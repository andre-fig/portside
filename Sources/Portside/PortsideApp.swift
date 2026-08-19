import SwiftUI
import AppKit
import PortsideCore

@main
struct PortsideApp: App {
    @StateObject private var model: PortsideModel

    init() {
        let diagnostics = SentryDiagnosticsService()
        let model = PortsideModel(diagnostics: diagnostics)
        _model = StateObject(wrappedValue: model)
        Task { @MainActor in model.startAutomatically() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(width: model.setupStep == .failed ? InstallerLayout.failureWidth : InstallerLayout.width,
                       height: model.setupStep == .failed ? InstallerLayout.failureContentHeight : InstallerLayout.contentHeight)
        }
        .defaultSize(width: InstallerLayout.width, height: InstallerLayout.contentHeight)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutPortsideButton() }
        }
    }
}

@MainActor
final class PortsideModel: ObservableObject {
    @Published var state: EnvironmentState
    @Published var requirements: SystemRequirements
    @Published var setupStep: SetupStep = .checking
    @Published var progress: Double = 0
    @Published var progressIsIndeterminate = false
    @Published var message = ""
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published var didExportReport = false
    @Published var showsInstaller = true

    let store = EnvironmentStore()
    let logger = PortsideLogger()
    let runtimeProvider = FreeWineRuntimeProvider()
    let steamMonitor = SteamReadinessMonitor()
    let steamProcessLauncher = SteamProcessLauncher()
    let diagnostics: DiagnosticsService
    private var didStartAutomatically = false
    private var handoffExitScheduled = false
    private var steamLaunchLock: SteamLaunchLock?
    private var lastReadinessReport: SteamReadinessReport?

    enum SetupStep: String { case checking, rosettaRequired, preparing, downloading, installing, ready, failed }

    init(diagnostics: DiagnosticsService = NoopDiagnosticsService()) {
        self.diagnostics = diagnostics
        try? store.prepareDirectories()
        state = store.load()
        requirements = SystemRequirements()
        showsInstaller = !(state.setupCompleted && state.steamInstalled && hasValidInstalledEnvironment)
    }

    func startAutomatically() {
        guard !didStartAutomatically else { return }
        didStartAutomatically = true
        if state.setupCompleted && state.steamInstalled && hasValidInstalledEnvironment {
            showsInstaller = false
            launchSteam()
        } else {
            showsInstaller = true
            setUp()
        }
    }

    private var hasValidInstalledEnvironment: Bool {
        let runtimeRecord = state.runtimeRecord
        let runtimePath = runtimeRecord?.executablePath.path ?? state.runtime?.executablePath ?? ""
        return runtimeRecord?.manifest.identifier == FreeRuntimeCatalog.wine.identifier
            && runtimeRecord?.manifest.version == FreeRuntimeCatalog.wine.version
            && FileManager.default.isExecutableFile(atPath: runtimePath)
            && FileManager.default.fileExists(atPath: PortsidePaths.steamPrefix.appendingPathComponent("system.reg").path)
            && PrefixRuntimeMetadata.load(prefix: PortsidePaths.steamPrefix)?.runtimeIdentifier == FreeRuntimeCatalog.wine.identifier
            && PrefixRuntimeMetadata.load(prefix: PortsidePaths.steamPrefix)?.runtimeVersion == FreeRuntimeCatalog.wine.version
            && SteamInstaller.locateInstalledExecutable() != nil
    }

    func setUp() {
        guard !isWorking else { return }
        showsInstaller = true
        isWorking = true
        errorMessage = nil
        progress = 0
        progressIsIndeterminate = false
        setupStep = .checking
        message = "Checking your Mac…"
        lastReadinessReport = nil
        let started = Date()
        if state.phase == .failedRecoverable { state.retryCount += 1 }
        state.lastError = nil
        state.lastErrorCode = nil
        state.lastProcessType = nil
        state.lastExitCode = nil

        Task {
            do {
                diagnostics.breadcrumb("setup_started", context: diagnosticContext(stage: "checking_requirements"))
                logger.write("Starting Portside setup")
                updateProgress(0, phase: .requirementsChecking)
                try requirements.validate()
                diagnostics.breadcrumb("requirements_checked", context: diagnosticContext(stage: "checking_requirements"))

                if !(await RosettaManager.status()).installed {
                    state.phase = .rosettaRequired
                    persistState()
                    setupStep = .rosettaRequired
                    message = "Preparing Rosetta…"
                    progressIsIndeterminate = true
                    let result = try await RosettaManager.install()
                    guard result.status == 0, (await RosettaManager.status()).installed else {
                        throw RuntimePipelineError.rosettaUnavailable
                    }
                }

                setupStep = .preparing
                updateProgress(0.08, phase: .graphicsInstalling)
                try store.prepareDirectories()
                await stopManagedSteamIfNeeded()
                diagnostics.breadcrumb("runtime_download_started", context: diagnosticContext(stage: "runtime"))
                let result = try await runtimeProvider.install { [weak self] value, phase in
                    Task { @MainActor in self?.updateProgress(value, phase: phase) }
                }
                state.runtimeRecord = result.record
                state.runtime = RuntimeDescriptor(
                    name: result.record.manifest.identifier,
                    version: result.record.manifest.version,
                    executablePath: result.record.executablePath.path,
                    redistributable: false,
                    licenseNote: result.record.manifest.license
                )
                diagnostics.breadcrumb("runtime_verified", context: diagnosticContext(stage: "runtime", runtimeVersion: result.record.manifest.version))
                diagnostics.breadcrumb("prefix_created", context: diagnosticContext(stage: "prefix", runtimeVersion: result.record.manifest.version))

                if SteamInstaller.locateInstalledExecutable() == nil {
                    setupStep = .downloading
                    diagnostics.breadcrumb("steam_install_started", context: diagnosticContext(stage: "steam_download"))
                    _ = try await SteamInstaller.download { [weak self] value in
                        Task { @MainActor in self?.updateProgress(0.72 + (value * 0.08), phase: .steamDownloading) }
                    }
                    setupStep = .installing
                    state.lastProcessType = "steam-installer"
                    updateProgress(0.84, phase: .steamInstalling)
                    try await SteamInstaller.install(using: state.runtime!, logger: logger)
                }

                guard let steamExecutable = SteamInstaller.locateInstalledExecutable() else {
                    throw PortsideError.processLaunchFailed("Steam installer finished without creating steam.exe.")
                }
                state.steamExecutablePath = steamExecutable.path
                state.steamInstalled = true
                state.setupCompleted = false
                guard let runtimePath = state.runtimeRecord?.executablePath ?? state.runtime?.executablePath.map(URL.init(fileURLWithPath:)) else {
                    throw PortsideError.runtimeUnavailable
                }
                let windows10Result = try await WinePrefixManager.ensureWindows10(runtimeExecutable: runtimePath, prefix: PortsidePaths.steamPrefix, logger: logger)
                guard windows10Result.status == 0 else {
                    throw RuntimePipelineError.processFailed("Windows 10 prefix configuration", windows10Result.status)
                }
                updateProgress(0.96, phase: .validatingInstallation)
                let launchOutcome = try await openSteamAndWait(executable: steamExecutable)
                if launchOutcome == .alreadyCoordinated {
                    isWorking = false
                    showsInstaller = false
                    terminateAfterHandOff()
                    return
                }
                state.lastSetupDuration = Date().timeIntervalSince(started)
                setupStep = .ready
                updateProgress(1, phase: .steamProcessHandoffComplete)
                logger.write("Setup completed")
                terminateAfterHandOff()
            } catch {
                await stopManagedSteamIfNeeded()
                state.phase = .failedRecoverable
                state.lastError = PortsideLogger.sanitize(error.localizedDescription)
                state.lastErrorCode = errorCode(for: error)
                if let pipelineError = error as? RuntimePipelineError, case .processFailed(_, let exitCode) = pipelineError {
                    state.lastExitCode = exitCode
                }
                state.lastSetupDuration = Date().timeIntervalSince(started)
                persistState()
                setupStep = .failed
                errorMessage = "Could not complete setup."
                message = "Could not complete setup."
                logger.write(error.localizedDescription, level: .error)
                diagnostics.capture(error: error, context: diagnosticContext(
                    stage: "failed",
                    errorCode: errorCode(for: error),
                    duration: Date().timeIntervalSince(started),
                    report: lastReadinessReport
                ))
            }
            isWorking = false
        }
    }

    func installRosetta() {
        guard !isWorking else { return }
        isWorking = true
        message = "Preparing Rosetta…"
        Task {
            do {
                let result = try await RosettaManager.install()
                guard result.status == 0, (await RosettaManager.status()).installed else {
                    throw RuntimePipelineError.rosettaUnavailable
                }
                setupStep = .checking
                isWorking = false
                setUp()
            } catch {
                isWorking = false
                setupStep = .failed
                errorMessage = "Could not complete setup."
                logger.write(error.localizedDescription, level: .error)
                diagnostics.capture(error: error, context: diagnosticContext(stage: "rosetta", errorCode: errorCode(for: error)))
            }
        }
    }

    func launchSteam() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        message = "Preparing Portside…"
        lastReadinessReport = nil
        let started = Date()

        Task {
            do {
                try requirements.validate()
                guard (await RosettaManager.status()).installed else { throw RuntimePipelineError.rosettaUnavailable }
                let storedSteamExecutable = state.steamExecutablePath.map(URL.init(fileURLWithPath:))
                guard let steamExecutable = (storedSteamExecutable.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }) ?? SteamInstaller.locateInstalledExecutable() else {
                    throw PortsideError.processLaunchFailed("Steam is not installed yet.")
                }
                guard hasValidInstalledEnvironment,
                      let runtimePath = state.runtimeRecord?.executablePath else {
                    throw PortsideError.runtimeUnavailable
                }
                state.steamExecutablePath = steamExecutable.path
                state.phase = .steamLaunching
                persistState()
                message = "Opening Steam…"
                let launchOutcome = try await openSteamAndWait(executable: steamExecutable, runtimePath: runtimePath)
                if launchOutcome == .alreadyCoordinated {
                    isWorking = false
                    showsInstaller = false
                    terminateAfterHandOff()
                    return
                }
                state.lastSetupDuration = Date().timeIntervalSince(started)
                showsInstaller = false
                message = "Ready"
                terminateAfterHandOff()
            } catch {
                state.setupCompleted = false
                state.lastSetupDuration = Date().timeIntervalSince(started)
                errorMessage = "Could not complete setup."
                setupStep = .failed
                state.phase = .failedRecoverable
                state.lastError = PortsideLogger.sanitize(error.localizedDescription)
                state.lastErrorCode = errorCode(for: error)
                persistState()
                logger.write(error.localizedDescription, level: .error)
                diagnostics.capture(error: error, context: diagnosticContext(
                    stage: "launch",
                    errorCode: errorCode(for: error),
                    duration: Date().timeIntervalSince(started),
                    report: lastReadinessReport
                ))
                showsInstaller = true
                NSApp.unhide(nil)
            }
            isWorking = false
        }
    }

    private func friendlyMessage(for phase: EnvironmentPhase) -> String {
        switch phase {
        case .requirementsChecking: return "Checking your Mac…"
        case .rosettaRequired: return "Preparing Rosetta…"
        case .runtimeDownloading, .runtimeVerifying: return "Downloading required components…"
        case .runtimeInstalling, .prefixCreating, .graphicsInstalling: return "Preparing the game environment…"
        case .steamDownloading, .steamInstalling: return "Installing Steam…"
        case .steamUpdating: return "Updating Steam…"
        case .steamLaunching: return "Opening Steam…"
        case .validatingInstallation: return "Finishing…"
        case .steamReady: return "Ready"
        case .steamProcessHandoffComplete: return "Steam process handoff complete"
        case .failedRecoverable, .failedFatal: return "Could not complete setup."
        }
    }

    private func updateProgress(_ value: Double, phase: EnvironmentPhase) {
        if let currentPhase = state.phase, phaseRank(phase) < phaseRank(currentPhase), value < progress { return }
        state.phase = phase
        progress = max(progress, min(1, value))
        progressIsIndeterminate = false
        message = friendlyMessage(for: phase)
        persistState()
    }

    private func phaseRank(_ phase: EnvironmentPhase) -> Int {
        switch phase {
        case .requirementsChecking: return 0
        case .rosettaRequired: return 1
        case .graphicsInstalling: return 2
        case .runtimeDownloading: return 3
        case .runtimeVerifying: return 4
        case .runtimeInstalling: return 5
        case .prefixCreating: return 6
        case .steamDownloading: return 7
        case .steamInstalling: return 8
        case .steamUpdating: return 9
        case .steamLaunching: return 10
        case .validatingInstallation: return 11
        case .steamReady: return 12
        case .steamProcessHandoffComplete: return 13
        case .failedRecoverable, .failedFatal: return 99
        }
    }

    private func errorCode(for error: Error) -> String {
        if let pipelineError = error as? RuntimePipelineError {
            switch pipelineError {
            case .checksumMismatch: return "runtime_checksum_failed"
            case .unexpectedArchiveEntry, .archiveExtractionFailed, .runtimeStructureInvalid: return "runtime_extraction_failed"
            case .rosettaUnavailable: return "rosetta_unavailable"
            case .gstreamerInstallFailed: return "gstreamer_setup_failed"
            case .processTimedOut: return "setup_timeout"
            case .runtimeMigrationFailed: return "runtime_migration_failed"
            case .snapshotInsufficientSpace: return "runtime_snapshot_space_failed"
            case .processFailed(let process, _):
                let normalized = process.lowercased()
                if normalized.contains("steam installer") { return "steam_install_failed" }
                if normalized.contains("prefix") { return "prefix_creation_failed" }
                if normalized.contains("steam") { return "steam_update_failed" }
                return "child_process_exited"
            }
        }
        if let portsideError = error as? PortsideError {
            switch portsideError {
            case .unsupportedArchitecture, .unsupportedOperatingSystem, .insufficientStorage: return "requirements_check_failed"
            case .runtimeUnavailable: return "runtime_download_failed"
            case .steamInstallerUnavailable: return "steam_download_failed"
            case .processLaunchFailed(let reason):
                let normalized = reason.lowercased()
                if normalized.contains("window") || normalized.contains("handoff") { return "steam_window_failed" }
                return "steam_launch_failed"
            case .invalidPath: return "permission_denied"
            }
        }
        return "portside_error"
    }

    private func diagnosticContext(stage: String? = nil, errorCode: String? = nil, runtimeVersion: String? = nil, duration: TimeInterval? = nil, report: SteamReadinessReport? = nil) -> DiagnosticContext {
        DiagnosticContext(
            stage: stage,
            errorCode: errorCode,
            macOSVersion: requirements.macOSVersion,
            architecture: requirements.architecture,
            runtimeName: state.runtime?.name,
            runtimeVersion: runtimeVersion ?? state.runtime?.version,
            graphicsBackend: state.runtimeRecord?.graphicsBackend.rawValue,
            processType: state.lastProcessType,
            exitCode: state.lastExitCode,
            duration: duration ?? state.lastSetupDuration,
            retryCount: state.retryCount,
            webhelperRestartCount: report?.webhelperRestartCount,
            webhelperStarted: report?.webhelperStarted,
            webhelperExitCode: report?.webhelperExitCode,
            windowDetected: report?.windowDetected,
            webhelperProcessCount: report?.webhelperProcessCount,
            processStarted: report?.processStarted,
            processHandoffComplete: report?.processHandoffComplete,
            interfaceVerification: report?.interfaceVerification.rawValue,
            msyncApplicable: report?.runtimeSynchronization.applicable,
            msyncBootstrapped: report?.runtimeSynchronization.bootstrapped,
            msyncRunning: report?.runtimeSynchronization.running
        )
    }

    private enum SteamOpenOutcome: Equatable {
        case ready
        case alreadyCoordinated
    }

    private func openSteamAndWait(executable: URL, runtimePath: URL? = nil) async throws -> SteamOpenOutcome {
        let runtimePath = runtimePath ?? state.runtimeRecord?.executablePath
        guard let runtimePath else { throw PortsideError.runtimeUnavailable }
        guard steamLaunchLock == nil else {
            logger.write("Steam launch is already being coordinated by this Portside instance")
            return .alreadyCoordinated
        }
        guard let launchLock = SteamLaunchLock.acquire() else {
            logger.write("Another Portside instance is already launching Steam; no duplicate Wine process will be created", level: .warning)
            return .alreadyCoordinated
        }
        steamLaunchLock = launchLock
        defer { steamLaunchLock = nil }

        state.lastProcessType = "steam-launch"
        state.phase = .steamLaunching
        message = friendlyMessage(for: .steamLaunching)
        persistState()
        diagnostics.breadcrumb("steam_launch_requested", context: diagnosticContext(stage: "launching_steam"))
        progressIsIndeterminate = true

        await stopManagedSteamIfNeeded()
        guard await steamProcessLauncher.waitForExit(timeout: 10) else {
            throw PortsideError.processLaunchFailed("The previous managed Steam launcher could not be closed safely.")
        }

        let existingWebhelperLines = await steamMonitor.captureWebhelperLines()
        logger.write("Launching steam.exe with cef_32bit_legacy_login arguments")
        _ = try await steamProcessLauncher.launch(
            runtimePath: runtimePath,
            prefix: PortsidePaths.steamPrefix,
            steamExecutable: executable,
            arguments: SteamInstaller.launchArguments
        )
        diagnostics.breadcrumb("steam_started", context: diagnosticContext(stage: "steam_process_started"))

        let report = await steamMonitor.waitForSteamHandoff(prefix: PortsidePaths.steamPrefix, baselineWebhelperLines: existingWebhelperLines)
        lastReadinessReport = report
        logger.write("steamwebhelper_process_count=\(report.webhelperProcessCount)")
        guard report.status == .processHandoffComplete else {
            diagnostics.event("steam_handoff_failed", context: diagnosticContext(stage: "steam_handoff", errorCode: "steam_\(report.status.rawValue)", report: report))
            throw PortsideError.processLaunchFailed("Steam process handoff could not be completed.")
        }
        diagnostics.event("steam_process_handoff_complete", context: diagnosticContext(stage: "steam_handoff", report: report))
        state.phase = .steamProcessHandoffComplete
        state.setupCompleted = true
        state.lastSteamStatus = .processHandoffComplete
        state.lastError = nil
        persistState()
        showsInstaller = false
        return .ready
    }

    private func stopManagedSteamIfNeeded() async {
        guard let runtimePath = state.runtimeRecord?.executablePath ?? state.runtime?.executablePath.map(URL.init(fileURLWithPath:)),
              FileManager.default.isExecutableFile(atPath: runtimePath.path) else { return }
        if await steamMonitor.isSteamProcessRunning(prefix: PortsidePaths.steamPrefix) {
            logger.write("Stopping the existing Portside Steam process before continuing")
            await steamMonitor.stopSteam(runtimeExecutable: runtimePath, prefix: PortsidePaths.steamPrefix)
            _ = await steamMonitor.waitForSteamToStop(prefix: PortsidePaths.steamPrefix, timeout: 20)
        }
        _ = await steamProcessLauncher.waitForExit(timeout: 10)
    }

    private func terminateAfterHandOff() {
        guard !handoffExitScheduled else { return }
        handoffExitScheduled = true
        logger.write("Steam handoff completed; closing Portside")
        NSApp.hide(nil)
        DispatchQueue.main.async {
            NSApp.terminate(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if NSApp.isRunning { NSApp.terminate(nil) }
            }
        }
    }

    private func persistState() {
        state.lastUpdated = Date()
        try? store.save(state)
    }

    func stopSteam() {
        Task {
            guard let runtimePath = state.runtimeRecord?.executablePath else { return }
            await steamMonitor.stopSteam(runtimeExecutable: runtimePath, prefix: PortsidePaths.steamPrefix)
            message = "Steam was asked to close safely."
        }
    }

    func repair() {
        diagnostics.breadcrumb("repair_requested", context: diagnosticContext(stage: "repair"))
        state.setupCompleted = false
        state.steamInstalled = SteamInstaller.locateInstalledExecutable() != nil
        showsInstaller = true
        setupStep = .checking
        setUp()
    }

    func exportReport() {
        do {
            let url = try DiagnosticReport.create(state: state, requirements: requirements, logger: logger)
            didExportReport = true
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = "Could not export the diagnostic report."
            diagnostics.capture(error: error, context: diagnosticContext(stage: "diagnostic_report", errorCode: "diagnostic_report_failed"))
        }
    }

    func openStorage() { NSWorkspace.shared.open(PortsidePaths.root) }

    func clearCache() {
        do {
            try FileManager.default.removeItem(at: PortsidePaths.cache)
            try FileManager.default.createDirectory(at: PortsidePaths.cache, withIntermediateDirectories: true)
            message = "Download cache cleared. Installed games were preserved."
        } catch {
            errorMessage = "Could not clear the download cache."
            diagnostics.capture(error: error, context: diagnosticContext(stage: "cache", errorCode: "permission_denied"))
        }
    }

    func reset() {
        do {
            try FileManager.default.removeItem(at: PortsidePaths.root)
            state = EnvironmentState()
            setupStep = .checking
            message = "Portside was reset."
            errorMessage = nil
        } catch {
            errorMessage = "Could not reset Portside."
            diagnostics.capture(error: error, context: diagnosticContext(stage: "reset", errorCode: "permission_denied"))
        }
    }
}

struct RootView: View {
    @ObservedObject var model: PortsideModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            if model.showsInstaller {
                VStack(spacing: 0) {
                    InstallerHeader(model: model)
                    Divider()
                    if model.setupStep == .failed { FailureView(model: model) }
                    else { SetupProgressView(model: model) }
                }
                .ignoresSafeArea(.container, edges: .top)
            } else {
                ReadyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            WindowConfigurator(
                contentSize: model.setupStep == .failed
                    ? CGSize(width: InstallerLayout.failureWidth, height: InstallerLayout.failureContentHeight)
                    : CGSize(width: InstallerLayout.width, height: InstallerLayout.contentHeight),
                isVisible: true
            )
                .frame(width: 0, height: 0)
        }
    }
}

struct ReadyView: View {
    var body: some View {
        VStack(spacing: 12) {
            PortsideLogoView(size: 54)
            Text("Portside")
                .font(.title2.weight(.semibold))
            Text("Steam is ready")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(width: InstallerLayout.width, height: InstallerLayout.contentHeight)
    }
}

private enum InstallerLayout {
    static let width: CGFloat = 460
    static let contentHeight: CGFloat = 276
    static let failureWidth: CGFloat = 560
    static let failureContentHeight: CGFloat = 350
    static let headerHeight: CGFloat = 56
    static let progressContentHeight = contentHeight - headerHeight - 1
    static let failureContentBodyHeight = failureContentHeight - headerHeight - 1
}

struct InstallerHeader: View {
    @ObservedObject var model: PortsideModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PortsideLogoView(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Portside")
                    .font(.headline)
                Text(model.state.setupCompleted && model.setupStep == .failed ? "Steam could not be opened" : "Preparing Steam for your Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .frame(height: InstallerLayout.headerHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    let contentSize: CGSize
    let isVisible: Bool

    func makeNSView(context: Context) -> ConfiguringView { ConfiguringView() }

    func updateNSView(_ nsView: ConfiguringView, context: Context) {
        nsView.apply(contentSize: contentSize, isVisible: isVisible)
    }

    final class ConfiguringView: NSView {
        private var lastSize: CGSize?
        private var lastVisibility: Bool?
        private var desiredSize = CGSize(width: InstallerLayout.width, height: InstallerLayout.contentHeight)
        private var desiredVisibility = true

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply(contentSize: desiredSize, isVisible: desiredVisibility)
        }

        func apply(contentSize: CGSize, isVisible: Bool) {
            desiredSize = contentSize
            desiredVisibility = isVisible
            guard let window else { return }
            guard lastSize != contentSize || lastVisibility != isVisible else { return }
            let wasVisible = window.isVisible
            let sizeChanged = lastSize != contentSize
            let visibilityChanged = lastVisibility != isVisible
            lastSize = contentSize
            lastVisibility = isVisible
            window.title = "Portside"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.styleMask.remove(.resizable)
            window.styleMask.remove(.miniaturizable)
            window.styleMask.remove(.closable)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setContentSize(contentSize)
            let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
            window.minSize = frameSize
            window.maxSize = frameSize
            if isVisible {
                if sizeChanged || visibilityChanged || !wasVisible {
                    center(window)
                }
                if wasVisible { window.orderFront(nil) }
                else { window.makeKeyAndOrderFront(nil) }
                if sizeChanged || visibilityChanged || !wasVisible {
                    DispatchQueue.main.async { [weak self, weak window] in
                        guard let self, let window, window.isVisible else { return }
                        self.center(window)
                    }
                }
            } else {
                window.orderOut(nil)
            }
        }

        private func center(_ window: NSWindow) {
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }
            let visibleFrame = screen.visibleFrame
            let frame = window.frame
            let origin = NSPoint(
                x: visibleFrame.midX - (frame.width / 2),
                y: visibleFrame.midY - (frame.height / 2)
            )
            window.setFrameOrigin(origin)
        }
    }
}

struct SetupProgressView: View {
    @ObservedObject var model: PortsideModel
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(model.message.isEmpty ? "Preparing Portside…" : model.message).font(.title3.weight(.medium))
            if model.progressIsIndeterminate { ProgressView().frame(width: 360) }
            else { ProgressView(value: model.progress).frame(width: 360) }
            Spacer()
        }.padding(22).frame(width: InstallerLayout.width, height: InstallerLayout.progressContentHeight)
    }
}

struct FailureView: View {
    @ObservedObject var model: PortsideModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Could not complete setup.").font(.title3.weight(.medium))
            HStack(spacing: 12) {
                Button("Try Again") { model.repair() }.buttonStyle(.borderedProminent)
            }.disabled(model.isWorking)
            Spacer()
        }.padding(22).frame(width: InstallerLayout.failureWidth, height: InstallerLayout.failureContentBodyHeight)
    }
}

struct PortsideLogoView: View {
    var size: CGFloat = 96

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "PortsideLogo", withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "shippingbox.and.arrow.backward.fill").resizable().scaledToFit().padding(18)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Portside")
    }
}

struct AboutPortsideButton: View {
    var body: some View { Button("About Portside") { NSApp.orderFrontStandardAboutPanel(nil) } }
}
