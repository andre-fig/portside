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
    let supervisor = ProcessSupervisor()
    let steamMonitor = SteamReadinessMonitor()
    let diagnostics: DiagnosticsService
    private var didStartAutomatically = false

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
            NSApp.hide(nil)
            launchSteam()
        } else {
            showsInstaller = true
            setUp()
        }
    }

    private var hasValidInstalledEnvironment: Bool {
        let runtimePath = state.runtimeRecord?.executablePath.path ?? state.runtime?.executablePath ?? ""
        return FileManager.default.isExecutableFile(atPath: runtimePath)
            && FileManager.default.fileExists(atPath: PortsidePaths.steamPrefix.appendingPathComponent("system.reg").path)
            && SteamInstaller.locateInstalledExecutable() != nil
    }

    func setUp() {
        guard !isWorking else { return }
        showsInstaller = true
        isWorking = true; errorMessage = nil; progress = 0; progressIsIndeterminate = false; setupStep = .checking; message = "Checking your Mac…"
        let started = Date()
        if state.phase == .failedRecoverable { state.retryCount += 1 }
        state.lastError = nil; state.lastErrorCode = nil; state.lastProcessType = nil; state.lastExitCode = nil
        Task {
            do {
                diagnostics.breadcrumb("setup_started", context: diagnosticContext(stage: "checking_requirements"))
                logger.write("Starting Portside setup")
                updateProgress(0, phase: .requirementsChecking)
                try requirements.validate()
                diagnostics.breadcrumb("requirements_checked", context: diagnosticContext(stage: "checking_requirements"))
                if !(await RosettaManager.status()).installed {
                    state.phase = .rosettaRequired; persistState(); setupStep = .rosettaRequired; message = "Preparing Rosetta…"; progressIsIndeterminate = true
                    let result = try await RosettaManager.install()
                    guard result.status == 0, (await RosettaManager.status()).installed else { throw RuntimePipelineError.rosettaUnavailable }
                }
                setupStep = .preparing; updateProgress(0.08, phase: .graphicsInstalling)
                try store.prepareDirectories()
                diagnostics.breadcrumb("runtime_download_started", context: diagnosticContext(stage: "runtime"))
                let result = try await runtimeProvider.install { [weak self] value, phase in
                    Task { @MainActor in
                        self?.updateProgress(value, phase: phase)
                    }
                }
                state.runtimeRecord = result.record
                state.runtime = RuntimeDescriptor(name: result.record.manifest.identifier, version: result.record.manifest.version, executablePath: result.record.executablePath.path, redistributable: false, licenseNote: result.record.manifest.license)
                diagnostics.breadcrumb("runtime_verified", context: diagnosticContext(stage: "runtime", runtimeVersion: result.record.manifest.version))
                diagnostics.breadcrumb("prefix_created", context: diagnosticContext(stage: "prefix", runtimeVersion: result.record.manifest.version))
                let existingSteam = SteamInstaller.locateInstalledExecutable()
                if existingSteam == nil {
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
                updateProgress(0.92, phase: .validatingInstallation)
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
                guard windows10Result.status == 0 else { throw RuntimePipelineError.processFailed("Windows 10 prefix configuration", windows10Result.status) }
                updateProgress(0.88, phase: .steamUpdating)
                diagnostics.breadcrumb("steam_update_started", context: diagnosticContext(stage: "steam_update"))
                if !steamMonitor.bootstrapComplete(prefix: PortsidePaths.steamPrefix) {
                    state.lastProcessType = "steam-bootstrap"
                    try supervisor.launchSteam(state: state, arguments: SteamInstaller.bootstrapArguments)
                    guard await steamMonitor.waitForBootstrap(prefix: PortsidePaths.steamPrefix) else {
                        throw PortsideError.processLaunchFailed("Steam bootstrap did not complete before the timeout.")
                    }
                    supervisor.requestStop()
                }
                updateProgress(0.96, phase: .validatingInstallation)
                try await openSteamAndWait(executable: steamExecutable)
                state.lastSetupDuration = Date().timeIntervalSince(started)
                setupStep = .ready; updateProgress(1, phase: .steamReady)
                logger.write("Setup completed")
            } catch {
                if supervisor.isRunning { supervisor.requestStop() }
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
                diagnostics.capture(error: error, context: diagnosticContext(stage: "failed", errorCode: errorCode(for: error), duration: Date().timeIntervalSince(started)))
            }
            isWorking = false
        }
    }

    func installRosetta() {
        guard !isWorking else { return }
        isWorking = true; message = "Preparing Rosetta…"
        Task {
            do {
                let result = try await RosettaManager.install()
                guard result.status == 0, (await RosettaManager.status()).installed else { throw RuntimePipelineError.rosettaUnavailable }
                setupStep = .checking; isWorking = false; setUp()
            } catch {
                isWorking = false; setupStep = .failed; errorMessage = "Could not complete setup."; logger.write(error.localizedDescription, level: .error)
                diagnostics.capture(error: error, context: diagnosticContext(stage: "rosetta", errorCode: errorCode(for: error)))
            }
        }
    }

    func launchSteam() {
        guard !isWorking else { return }
        isWorking = true; errorMessage = nil; message = "Preparing Portside…"
        Task {
            do {
                try requirements.validate()
                guard (await RosettaManager.status()).installed else { throw RuntimePipelineError.rosettaUnavailable }
                let storedSteamExecutable = state.steamExecutablePath.map(URL.init(fileURLWithPath:))
                guard let steamExecutable = (storedSteamExecutable.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }) ?? SteamInstaller.locateInstalledExecutable() else {
                    throw PortsideError.processLaunchFailed("Steam is not installed yet.")
                }
                guard FileManager.default.isExecutableFile(atPath: state.runtimeRecord?.executablePath.path ?? state.runtime?.executablePath ?? ""),
                      FileManager.default.fileExists(atPath: PortsidePaths.steamPrefix.appendingPathComponent("system.reg").path) else {
                    throw PortsideError.runtimeUnavailable
                }
                state.steamExecutablePath = steamExecutable.path
                state.phase = .steamLaunching; persistState(); message = "Opening Steam…"
                try await openSteamAndWait(executable: steamExecutable)
                showsInstaller = false
                message = "Ready"; NSApp.hide(nil)
            } catch {
                if supervisor.isRunning { supervisor.requestStop() }
                errorMessage = "Could not complete setup."
                setupStep = .failed
                state.phase = .failedRecoverable; state.lastError = PortsideLogger.sanitize(error.localizedDescription); state.lastErrorCode = errorCode(for: error); persistState()
                logger.write(error.localizedDescription, level: .error)
                diagnostics.capture(error: error, context: diagnosticContext(stage: "launch", errorCode: errorCode(for: error)))
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

    private func setIndeterminate(_ value: Bool) {
        progressIsIndeterminate = value
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
            case .processLaunchFailed: return "steam_launch_failed"
            case .invalidPath: return "permission_denied"
            }
        }
        return "portside_error"
    }

    private func diagnosticContext(stage: String? = nil, errorCode: String? = nil, runtimeVersion: String? = nil, duration: TimeInterval? = nil, cefStrategy: String? = nil, webhelperRestartCount: Int? = nil) -> DiagnosticContext {
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
            cefStrategy: cefStrategy,
            webhelperRestartCount: webhelperRestartCount
        )
    }

    private func openSteamAndWait(executable: URL) async throws {
        state.lastProcessType = "steam-launch"
        state.phase = .steamLaunching; message = friendlyMessage(for: .steamLaunching); persistState()
        guard let runtimePath = state.runtimeRecord?.executablePath ?? state.runtime?.executablePath.map(URL.init(fileURLWithPath:)) else {
            throw PortsideError.runtimeUnavailable
        }
        diagnostics.breadcrumb("steam_launch_requested", context: diagnosticContext(stage: "launching_steam"))
        setIndeterminate(true)
        if let runtimeRoot = state.runtimeRecord?.installedPath {
            try? WineRuntimeBranding.apply(to: runtimeRoot)
        }
        let policyResult = try await WinePrefixManager.configureSilentCrashHandling(runtimeExecutable: runtimePath, prefix: PortsidePaths.steamPrefix, logger: logger)
        guard policyResult.status == 0 else { throw RuntimePipelineError.processFailed("Wine crash-dialog configuration", policyResult.status) }
        let windows10Result = try await WinePrefixManager.ensureWindows10(runtimeExecutable: runtimePath, prefix: PortsidePaths.steamPrefix, logger: logger)
        guard windows10Result.status == 0 else { throw RuntimePipelineError.processFailed("Windows 10 prefix configuration", windows10Result.status) }
        await stopLegacySteamIfNeeded(runtimePath: runtimePath)
        if await steamMonitor.activateVisibleSteamWindow() {
            state.lastSteamStatus = .windowVisible
            state.phase = .steamReady; state.setupCompleted = true; state.lastError = nil; persistState()
            NSApp.hide(nil)
            return
        }
        if await steamMonitor.isSteamProcessRunning() {
            logger.write("Stopping an existing Steam process before opening the UI")
            await steamMonitor.stopSteam(runtimeExecutable: runtimePath, prefix: PortsidePaths.steamPrefix)
            guard await steamMonitor.waitForSteamToStop() else {
                throw PortsideError.processLaunchFailed("Steam could not be restarted after its update.")
            }
        }
        let strategies = SteamInstaller.uiLaunchConfigurations
        var lastReport: SteamReadinessReport?
        for (index, strategy) in strategies.enumerated() {
            if index > 0 {
                if let previous = lastReport, previous.logAnalysis.cacheCorruptionLikely {
                    let backups = try SteamHTMLCacheRecovery.renameHTMLCache(prefix: PortsidePaths.steamPrefix, logger: logger)
                    if !backups.isEmpty {
                        diagnostics.event("steam_html_cache_recovery_attempted", context: diagnosticContext(stage: "cef_fallback", cefStrategy: strategy.identifier, webhelperRestartCount: previous.webhelperRestartCount))
                    }
                }
                if supervisor.isRunning { supervisor.requestStop() }
                await steamMonitor.stopSteam(runtimeExecutable: runtimePath, prefix: PortsidePaths.steamPrefix)
                _ = await steamMonitor.waitForSteamToStop(timeout: 10)
            }
            diagnostics.event("steam_started", context: diagnosticContext(stage: "launching_steam", cefStrategy: strategy.identifier))
            try supervisor.launchSteam(state: state, arguments: strategy.arguments)
            let report = await steamMonitor.waitForSteamReport(executable: executable, prefix: PortsidePaths.steamPrefix, strategy: strategy)
            lastReport = report
            state.lastSteamStatus = report.status
            if let exitCode = report.webhelperExitCode { state.lastExitCode = exitCode }
            let reportContext = diagnosticContext(stage: "steam_readiness", duration: report.webhelperStableDuration, cefStrategy: strategy.identifier, webhelperRestartCount: report.webhelperRestartCount)
            if report.webhelperStarted { diagnostics.event("steamwebhelper_started", context: reportContext) }
            if report.webhelperExitCode != nil {
                diagnostics.event("steamwebhelper_exit_code", context: reportContext)
            }
            if report.webhelperRestartCount >= 3 { diagnostics.event("steamwebhelper_crash_loop", context: reportContext) }
            if report.windowDetected { diagnostics.event("steam_window_detected", context: reportContext) }
            if report.status == .windowVisible || report.status == .ready {
                state.phase = .steamReady; state.setupCompleted = true; state.lastError = nil; persistState()
                NSApp.hide(nil)
                return
            }
            if report.windowDetected { diagnostics.event("steam_login_ui_unverified", context: reportContext) }
            logger.write("CEF strategy \(strategy.identifier) did not produce a verified Steam UI: status=\(report.status.rawValue), webhelper_started=\(report.webhelperStarted), restarts=\(report.webhelperRestartCount), stable_seconds=\(String(format: "%.2f", report.webhelperStableDuration))", level: .warning)
            diagnostics.event(report.webhelperStarted ? "steam_cef_initialization_failed" : "steam_webhelper_not_started", context: reportContext)
        }
        diagnostics.event("steamwebhelper_timeout", context: diagnosticContext(stage: "steam_readiness", cefStrategy: lastReport?.cefStrategy, webhelperRestartCount: lastReport?.webhelperRestartCount))
        throw PortsideError.processLaunchFailed("Steam started but its interface could not be verified.")
    }

    private func stopLegacySteamIfNeeded(runtimePath: URL) async {
        let legacyPrefix = PortsidePaths.legacyPrefixes.appendingPathComponent("Steam", isDirectory: true)
        let legacyExecutable = legacyPrefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
        guard FileManager.default.fileExists(atPath: legacyExecutable.path) else { return }
        logger.write("Stopping Steam from the legacy prefix before opening the managed prefix")
        await steamMonitor.stopSteam(runtimeExecutable: runtimePath, prefix: legacyPrefix)
    }

    private func persistState() {
        state.lastUpdated = Date()
        try? store.save(state)
    }

    func stopSteam() {
        supervisor.requestStop(); message = "Steam was asked to close safely."
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
            state = EnvironmentState(); setupStep = .checking; message = "Portside was reset."; errorMessage = nil
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
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            WindowConfigurator(
                contentSize: model.setupStep == .failed
                    ? CGSize(width: InstallerLayout.failureWidth, height: InstallerLayout.failureContentHeight)
                    : CGSize(width: InstallerLayout.width, height: InstallerLayout.contentHeight),
                isVisible: model.showsInstaller
            )
                .frame(width: 0, height: 0)
        }
    }
}

private enum InstallerLayout {
    static let width: CGFloat = 520
    static let contentHeight: CGFloat = 306
    static let failureWidth: CGFloat = 620
    static let failureContentHeight: CGFloat = 386
}

struct InstallerHeader: View {
    @ObservedObject var model: PortsideModel

    var body: some View {
        HStack(spacing: 12) {
            PortsideLogoView(size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.setupCompleted ? "Portside" : "Portside Installer")
                    .font(.headline)
                Text(model.state.setupCompleted && model.setupStep == .failed ? "Steam could not be opened" : "Preparing Steam for your Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
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
        private var desiredSize = CGSize(width: 520, height: 300)
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
            lastSize = contentSize
            lastVisibility = isVisible
            window.title = "Portside Installer"
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
            if isVisible { window.makeKeyAndOrderFront(nil) } else { window.orderOut(nil) }
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
        }.padding(28).frame(width: InstallerLayout.width, height: 251)
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
        }.padding(28).frame(width: InstallerLayout.failureWidth, height: 331)
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
