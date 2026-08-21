import SwiftUI
import AppKit
import PortsideCore

@main
struct PortsideApp: App {
    @StateObject private var model: PortsideModel
    private let updateCoordinator: PortsideUpdateCoordinator

    init() {
        let updateCoordinator = PortsideUpdateCoordinator()
        self.updateCoordinator = updateCoordinator
        let model = PortsideModel(diagnostics: SentryDiagnosticsService())
        _model = StateObject(wrappedValue: model)
        Task { @MainActor in
            await updateCoordinator.waitForInitialCheck()
            model.startAutomatically()
        }
    }

    var body: some Scene {
        WindowGroup {
                RootView(model: model)
                .frame(width: 460, height: model.setupStep == .failed ? 320 : model.setupStep == .license ? 330 : 260)
        }
        .defaultSize(width: 460, height: 260)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About Portside") { NSApp.orderFrontStandardAboutPanel(nil) } }
        }
    }
}

@MainActor
final class PortsideModel: ObservableObject {
    @Published var state: EnvironmentState
    @Published var requirements = SystemRequirements()
    @Published var setupStep: SetupStep = .checking
    @Published var progress = 0.0
    @Published var progressIsIndeterminate = false
    @Published var message = "Preparing Portside…"
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published var showsInstaller = true
    @Published var didExportReport = false
    @Published var licenseKey = ""
    @Published var licenseMessage = "Enter the purchase key from your Portside order."

    enum SetupStep { case checking, license, rosettaRequired, downloading, installing, opening, ready, failed }

    private let store = EnvironmentStore()
    private let logger = PortsideLogger()
    private let updateService: PortsideUpdateService
    private let wrapperInstaller: PortsideRuntimeInstaller
    private let steamLauncher: SteamProcessLauncher
    private let readinessMonitor: SteamReadinessMonitor
    private let agentLauncher = PortsideAgentLauncher()
    private let diagnostics: DiagnosticsService
    private let licenseClient: PortsideLicenseClient?
    private let requiresCommercialLicense: Bool
    private var hasValidLicense = false
    private var startedAutomatically = false

    init(diagnostics: DiagnosticsService = NoopDiagnosticsService()) {
        self.diagnostics = diagnostics
        let backendConfiguration = PortsideBackendConfiguration.fromBundle()
        #if DEBUG
        self.requiresCommercialLicense = false
        #else
        self.requiresCommercialLicense = backendConfiguration.isConfigured
        #endif
        self.licenseClient = backendConfiguration.isConfigured ? PortsideLicenseClient(configuration: backendConfiguration) : nil
        self.updateService = PortsideUpdateService(
            logger: PortsideLogger(logFileName: "portside-update.log"),
            backendConfiguration: PortsideBackendConfiguration.fromBundle(),
            currentVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
        )
        self.wrapperInstaller = PortsideRuntimeInstaller(logger: PortsideLogger(logFileName: "runtime-install.log"))
        self.steamLauncher = SteamProcessLauncher()
        self.readinessMonitor = SteamReadinessMonitor()
        try? store.prepareDirectories()
        self.state = store.load()
    }

    func startAutomatically() {
        guard !startedAutomatically else { return }
        startedAutomatically = true
        diagnostics.breadcrumb("setup_started", context: context(stage: "startup"))
        if requiresCommercialLicense {
            prepareLicense()
        } else {
            continueAfterLicense()
        }
    }

    private func continueAfterLicense() {
        if let wrapperPath = state.wrapperPath.map(URL.init(fileURLWithPath:)),
           isValidWrapper(wrapperPath),
           state.setupCompleted {
            Task { @MainActor in
                do {
                    let prefix = URL(fileURLWithPath: state.prefixPath ?? PortsidePaths.steamPrefix.path)
                    if !isManagedSteamRunning(wrapper: wrapperPath, prefix: prefix),
                       let applied = try await updateService.applyPendingRuntime(using: wrapperInstaller) {
                        state.wrapperPath = applied.result.validation.wrapper.path
                        state.prefixPath = applied.result.validation.prefix.path
                        state.runtimeRecord = applied.result.runtimeRecord
                        state.runtimeManifestVersion = applied.manifest.manifestVersion
                        persist()
                    }
                } catch {
                    // A non-critical runtime update never prevents an existing
                    // working installation from opening. The pending copy stays
                    // on disk for retry and rollback remains available.
                    if (try? updateService.pendingRuntimeUpdate()?.manifest.critical) == true {
                        errorMessage = "We couldn't verify an important Portside update. Steam was not opened."
                        message = "Portside needs attention before Steam can open."
                        setupStep = .failed
                        showsInstaller = true
                        diagnostics.capture(error: error, context: context(stage: "critical_runtime_update", errorCode: "critical_runtime_update_failed"))
                        return
                    }
                    logger.write("runtime update was deferred: \(error.localizedDescription)", level: .warning)
                }
                showsInstaller = false
                message = "Steam is ready to play"
            }
        } else {
            setUp()
        }
    }

    private func prepareLicense() {
        setupStep = .license
        showsInstaller = true
        guard let licenseClient else {
            licenseMessage = "Portside services are not available yet."
            diagnostics.capture(
                error: PortsideCommercialError.backendUnavailable,
                context: context(stage: "license_validation", errorCode: "license_service_unavailable")
            )
            return
        }
        Task { @MainActor in
            do {
                _ = try await licenseClient.validate()
                hasValidLicense = true
                continueAfterLicense()
            } catch {
                licenseMessage = "Activate Portside with the purchase key from your order."
                if case PortsideCommercialError.invalidLicenseToken = error {
                    return
                }
                let failureCode = errorCode(error)
                diagnostics.capture(
                    error: error,
                    context: context(stage: "license_validation", errorCode: failureCode)
                )
                logger.write(
                    "license_validation_failed code=\(failureCode) reason=\(PortsideLogger.sanitize(error.localizedDescription))",
                    level: .error
                )
            }
        }
    }

    func activateLicense() {
        guard !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let licenseClient else {
            licenseMessage = "Enter your purchase key to continue."
            return
        }
        isWorking = true
        licenseMessage = "Activating Portside…"
        Task { @MainActor in
            do {
                _ = try await licenseClient.activate(licenseKey: licenseKey)
                hasValidLicense = true
                licenseKey = ""
                licenseMessage = "Portside is activated."
                isWorking = false
                setUp()
            } catch {
                licenseMessage = "That purchase key could not be activated. Check it and try again."
                diagnostics.capture(error: error, context: context(stage: "license_activation", errorCode: "license_activation_failed"))
            }
            isWorking = false
        }
    }

    func setUp() {
        guard !isWorking else { return }
        if requiresCommercialLicense && !hasValidLicense {
            prepareLicense()
            return
        }
        isWorking = true
        showsInstaller = true
        setupStep = .checking
        progress = 0
        errorMessage = nil
        let started = Date()
        Task { @MainActor in
            do {
                try requirements.validate()
                diagnostics.breadcrumb("requirements_checked", context: context(stage: "requirements"))
                if let oldWrapper = state.wrapperPath, let oldPrefix = state.prefixPath {
                    steamLauncher.stopManagedProcesses(wrapper: URL(fileURLWithPath: oldWrapper), prefix: URL(fileURLWithPath: oldPrefix))
                }
                if !(await RosettaManager.status()).installed {
                    setupStep = .rosettaRequired
                    message = "Preparing your gaming environment…"
                    progressIsIndeterminate = true
                    let result = try await RosettaManager.install(logger: logger)
                    guard result.status == 0, (await RosettaManager.status()).installed else { throw PortsideError.rosettaUnavailable }
                }

                setupStep = .downloading
                message = "Getting Portside ready for you…"
                progressIsIndeterminate = false
                diagnostics.breadcrumb("runtime_download_started", context: context(stage: "runtime_download"))
                let artifacts = try await updateService.downloadBaselineArtifacts { [weak self] value in
                    Task { @MainActor in self?.progress = 0.45 * value }
                }
                diagnostics.breadcrumb("runtime_verified", context: context(stage: "runtime_verified"))

                setupStep = .installing
                message = "Setting up your private Steam experience…"
                progress = 0.5
                let installed = try await wrapperInstaller.install(artifacts: artifacts)
                diagnostics.breadcrumb("prefix_created", context: context(stage: "prefix_installation"))
                state.wrapperPath = installed.validation.wrapper.path
                state.prefixPath = installed.validation.prefix.path
                state.runtimeRecord = installed.runtimeRecord
                state.runtimeManifestVersion = updateService.lastManifestVersion
                state.runtime = RuntimeDescriptor(
                    name: "Portside Wine Engine",
                    version: "Portside source build",
                    executablePath: installed.validation.launcher.path,
                    redistributable: true,
                    licenseNote: installed.runtimeRecord.manifest.license
                )
                state.phase = .prefixCreating
                persist()

                let steamExecutable = PortsideSteamFlow.steamExecutable(prefix: installed.validation.prefix)
                if !FileManager.default.fileExists(atPath: steamExecutable.path) {
                    message = "Installing Steam securely…"
                    diagnostics.breadcrumb("steam_install_started", context: context(stage: "steam_install"))
                    diagnostics.breadcrumb("steam_update_started", context: context(stage: "steam_update"))
                    let result = try await steamLauncher.installSteam(using: installed.validation.wrapper)
                    guard result.status == 0 else { throw PortsideError.processFailed("Portside runtime Steam setup", result.status) }
                }
                // The Windows PE file does not need a macOS executable bit;
                // its existence is the authoritative post-winetricks check.
                state.steamInstalled = FileManager.default.fileExists(atPath: steamExecutable.path)
                state.steamExecutablePath = steamExecutable.path
                guard state.steamInstalled else { throw PortsideError.invalidArtifact("steam.exe was not created by the Portside runtime setup") }

                // The official first run must be over before the clean second
                // opening. Only this wrapper/prefix may be terminated.
                steamLauncher.stopManagedProcesses(wrapper: installed.validation.wrapper, prefix: installed.validation.prefix)
                for _ in 0..<20 {
                    let snapshots = readinessMonitor.captureProcessSnapshot()
                    var managedPIDs = SteamProcessOwnership.managedPIDs(in: snapshots, wrapper: installed.validation.wrapper, prefix: installed.validation.prefix)
                    managedPIDs.formUnion(SteamProcessOwnership.fileBackedManagedPIDs(in: snapshots, wrapper: installed.validation.wrapper, prefix: installed.validation.prefix))
                    let managed = snapshots.filter { managedPIDs.contains($0.pid) }
                    if managed.isEmpty { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }

                setupStep = .opening
                message = "Starting Steam…"
                diagnostics.breadcrumb("steam_launch_requested", context: context(stage: "steam_launch"))
                state.phase = .steamLaunching
                persist()
                let baselinePIDs = Set(readinessMonitor.captureProcessSnapshot().map(\.pid))
                _ = try await steamLauncher.launch(wrapper: installed.validation.wrapper)
                let report = await readinessMonitor.waitForSteamWindow(wrapper: installed.validation.wrapper, baselinePIDs: baselinePIDs)
                state.lastReadiness = report
                guard report.windowDetected && report.webHelperStarted else {
                    throw PortsideError.processLaunchFailed("Steam processes started without a managed graphical window.")
                }
                agentLauncher.start(wrapper: installed.validation.wrapper, prefix: installed.validation.prefix)
                state.setupCompleted = true
                state.phase = .steamReady
                state.lastError = nil
                state.lastErrorCode = nil
                state.lastSetupDuration = Date().timeIntervalSince(started)
                persist()
                agentLauncher.startRuntimeUpdater()
                diagnostics.event("steam_window_detected", context: context(stage: "window_detected", report: report))
                progress = 1
                setupStep = .ready
                showsInstaller = false
                hideAfterSteamWindow()
            } catch {
                state.phase = .failedRecoverable
                state.lastError = PortsideLogger.sanitize(error.localizedDescription)
                state.lastErrorCode = errorCode(error)
                state.lastSetupDuration = Date().timeIntervalSince(started)
                persist()
                let userMessage = userFacingSetupFailure(error)
                errorMessage = userMessage
                message = userMessage
                let failureStage = setupStage
                let failureCode = errorCode(error)
                setupStep = .failed
                diagnostics.capture(error: error, context: context(stage: failureStage, errorCode: failureCode))
                logger.write("setup_failed stage=\(failureStage) code=\(failureCode) reason=\(PortsideLogger.sanitize(error.localizedDescription))", level: .error)
            }
            isWorking = false
        }
    }

    func installRosetta() { setUp() }

    func launchSteam() {
        guard !isWorking, let path = state.wrapperPath else { return }
        let wrapper = URL(fileURLWithPath: path)
        guard isValidWrapper(wrapper) else { setUp(); return }
        isWorking = true
        message = "Starting Steam…"
        Task { @MainActor in
            do {
                let baselinePIDs = Set(readinessMonitor.captureProcessSnapshot().map(\.pid))
                _ = try await steamLauncher.launch(wrapper: wrapper)
                let report = await readinessMonitor.waitForSteamWindow(wrapper: wrapper, baselinePIDs: baselinePIDs)
                state.lastReadiness = report
                guard report.windowDetected && report.webHelperStarted else { throw PortsideError.processLaunchFailed("Steam opened without a managed graphical window.") }
                agentLauncher.start(wrapper: wrapper, prefix: URL(fileURLWithPath: state.prefixPath ?? PortsidePaths.steamPrefix.path))
                state.setupCompleted = true
                state.phase = .steamReady
                state.lastError = nil
                state.lastErrorCode = nil
                persist()
                agentLauncher.startRuntimeUpdater()
                showsInstaller = false
                hideAfterSteamWindow()
            } catch {
                let userMessage = userFacingSetupFailure(error)
                errorMessage = userMessage
                message = userMessage
                setupStep = .failed
                showsInstaller = true
                let failureCode = errorCode(error)
                diagnostics.capture(error: error, context: context(stage: "steam_launch", errorCode: failureCode))
                logger.write("steam_launch_failed code=\(failureCode) reason=\(PortsideLogger.sanitize(error.localizedDescription))", level: .error)
            }
            isWorking = false
        }
    }

    func stopSteam() {
        guard let wrapper = state.wrapperPath, let prefix = state.prefixPath else { return }
        steamLauncher.stopManagedProcesses(wrapper: URL(fileURLWithPath: wrapper), prefix: URL(fileURLWithPath: prefix))
        message = "Steam is closing…"
    }

    func repair() { state.setupCompleted = false; setUp() }

    func exportReport() {
        do {
            let report = try DiagnosticReport.create(state: state, requirements: requirements, logger: logger)
            didExportReport = true
            NSWorkspace.shared.activateFileViewerSelecting([report])
        } catch { errorMessage = "We couldn't create the support report." }
    }

    func openStorage() { NSWorkspace.shared.open(PortsidePaths.root) }

    func clearCache() {
        try? FileManager.default.removeItem(at: PortsidePaths.cache)
        try? FileManager.default.createDirectory(at: PortsidePaths.cache, withIntermediateDirectories: true)
        message = "Temporary setup files were removed. Your games and Steam data are safe."
    }

    private func context(stage: String, errorCode: String? = nil, report: SteamReadinessReport? = nil) -> DiagnosticContext {
        let bundle = Bundle.main
        return DiagnosticContext(
            stage: stage,
            errorCode: errorCode,
            portsideVersion: (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0",
            portsideBuild: (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0",
            macOSVersion: requirements.macOSVersion,
            architecture: requirements.architecture,
            runtimeVersion: "Portside runtime",
            templateVersion: "Portside wrapper",
            engineVersion: "Portside Wine source build",
            renderer: "wineD3D",
            exitCode: state.lastExitCode,
            windowDetected: report?.windowDetected,
            processStarted: report?.processStarted,
            webHelperStarted: report?.webHelperStarted,
            interfaceVerification: report?.interfaceVerification.rawValue,
            msyncEnabled: true,
            esyncEnabled: true
        )
    }

    private func errorCode(_ error: Error) -> String {
        switch error {
        case PortsideError.unsupportedArchitecture: return "unsupported_architecture"
        case PortsideError.unsupportedOperatingSystem: return "unsupported_macos"
        case PortsideError.insufficientStorage: return "insufficient_storage"
        case PortsideError.rosettaUnavailable: return "rosetta_unavailable"
        case PortsideError.runtimeUnavailable: return "portside_runtime_unavailable"
        case PortsideError.invalidArtifact: return "runtime_artifact_invalid"
        case PortsideError.checksumMismatch: return "runtime_artifact_checksum_failed"
        case PortsideError.processTimedOut: return "runtime_process_timeout"
        case PortsideError.processFailed: return "runtime_process_failed"
        case PortsideError.processLaunchFailed: return "steam_window_failed"
        case PortsideError.invalidPath: return "invalid_runtime_path"
        case PortsideCommercialError.backendUnavailable: return "runtime_service_unavailable"
        case PortsideCommercialError.invalidManifest: return "runtime_manifest_invalid"
        case PortsideCommercialError.invalidSignature: return "runtime_manifest_signature_failed"
        case PortsideCommercialError.incompatibleVersion: return "runtime_version_incompatible"
        case PortsideCommercialError.unauthorizedURL: return "runtime_download_not_approved"
        case PortsideCommercialError.invalidLicenseToken: return "license_token_invalid"
        case PortsideCommercialError.keychainFailure: return "secure_storage_failed"
        case DecodingError.dataCorrupted: return "portside_data_corrupted"
        case DecodingError.keyNotFound: return "portside_data_field_missing"
        case DecodingError.typeMismatch: return "portside_data_type_invalid"
        case DecodingError.valueNotFound: return "portside_data_value_missing"
        default: return "portside_setup_failed"
        }
    }

    private var setupStage: String {
        switch setupStep {
        case .checking: return "requirements"
        case .license: return "license"
        case .rosettaRequired: return "macos_compatibility"
        case .downloading: return "runtime_download"
        case .installing: return "runtime_installation"
        case .opening: return "steam_launch"
        case .ready: return "ready"
        case .failed: return "failed"
        }
    }

    private func userFacingSetupFailure(_ error: Error) -> String {
        switch error {
        case PortsideError.unsupportedArchitecture:
            return "Portside works on Macs with Apple silicon."
        case PortsideError.unsupportedOperatingSystem:
            return "This macOS version is not supported by Portside."
        case PortsideError.insufficientStorage:
            return "There is not enough free space to finish the setup."
        case PortsideError.rosettaUnavailable:
            return "macOS could not prepare the compatibility components."
        case PortsideError.runtimeUnavailable:
            return "The Portside environment is not available yet. Please try again."
        case PortsideError.invalidArtifact, PortsideError.checksumMismatch,
             PortsideCommercialError.invalidManifest, PortsideCommercialError.invalidSignature:
            return "A Portside component could not be verified. Please try again."
        case PortsideCommercialError.backendUnavailable, PortsideCommercialError.unauthorizedURL:
            return "Portside could not download the required components. Check your connection and try again."
        case PortsideCommercialError.incompatibleVersion:
            return "This Portside version is no longer compatible. Please download the latest version."
        case DecodingError.dataCorrupted, DecodingError.keyNotFound,
             DecodingError.typeMismatch, DecodingError.valueNotFound:
            return "Portside could not finish refreshing your setup. Please try again."
        case PortsideError.processTimedOut:
            return "Steam took too long to finish preparing. Please try again."
        case PortsideError.processFailed:
            return "Steam could not finish preparing. Please try again."
        case PortsideError.processLaunchFailed:
            return "Steam started, but its window could not be opened. Please try again."
        default:
            return "Something interrupted the Portside setup. Please try again."
        }
    }

    private func persist() {
        state.lastUpdated = Date()
        try? store.save(state)
    }

    private func isValidWrapper(_ wrapper: URL) -> Bool {
        (try? PortsideRuntimeValidator.validate(wrapper: wrapper)) != nil
    }

    private func isManagedSteamRunning(wrapper: URL, prefix: URL) -> Bool {
        let snapshots = readinessMonitor.captureProcessSnapshot()
        var managed = SteamProcessOwnership.managedPIDs(in: snapshots, wrapper: wrapper, prefix: prefix)
        managed.formUnion(SteamProcessOwnership.fileBackedManagedPIDs(in: snapshots, wrapper: wrapper, prefix: prefix))
        return snapshots.contains { snapshot in
            managed.contains(snapshot.pid) &&
                (snapshot.command.localizedCaseInsensitiveContains("steam.exe") || snapshot.command.localizedCaseInsensitiveContains("steamwebhelper"))
        }
    }

    private func hideAfterSteamWindow() {
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if NSApp.isRunning { NSApp.terminate(nil) }
        }
    }
}

struct RootView: View {
    @ObservedObject var model: PortsideModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            if model.showsInstaller {
                VStack(spacing: 0) {
                    HStack {
                        PortsideLogoView(size: 34)
                        VStack(alignment: .leading) {
                            Text("Portside").font(.headline)
                            Text("Your private gaming environment").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .frame(height: 58)
                    Divider()
                    if model.setupStep == .license {
                        VStack(spacing: 14) {
                            Spacer()
                            Text("Activate Portside").font(.title3.weight(.medium))
                            Text(model.licenseMessage).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            TextField("Purchase key", text: $model.licenseKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 330)
                            Button("Activate") { model.activateLicense() }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isWorking)
                            Spacer()
                        }
                        .padding(.horizontal, 28)
                    } else if model.setupStep == .failed {
                        VStack(spacing: 16) {
                            Spacer()
                            Text(model.message).font(.title3.weight(.medium))
                            Button("Try Again") { model.repair() }.buttonStyle(.borderedProminent).disabled(model.isWorking)
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 20) {
                            Spacer()
                            Text(model.message).font(.title3.weight(.medium))
                            if model.progressIsIndeterminate { ProgressView().frame(width: 350) }
                            else { ProgressView(value: model.progress).frame(width: 350) }
                            Spacer()
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    PortsideLogoView(size: 54)
                    Text("Portside").font(.title2.weight(.semibold))
                    Text("Steam is ready to play").font(.subheadline).foregroundStyle(.secondary)
                    Button("Open Steam") { model.launchSteam() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct PortsideLogoView: View {
    let size: CGFloat
    var body: some View {
        if let url = Bundle.main.url(forResource: "PortsideLogo", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: "shippingbox.and.arrow.backward.fill").resizable().scaledToFit().padding(8).frame(width: size, height: size)
        }
    }
}
