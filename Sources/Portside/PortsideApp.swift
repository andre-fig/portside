import SwiftUI
import AppKit
import PortsideCore
import Sentry

@main
struct PortsideApp: App {
    @StateObject private var model = PortsideModel()

    init() {
        SentrySDK.start { options in
            options.dsn = "https://5aa6a3d7a22bd8bb4b718bc2d6cfaac7@o4511935178080256.ingest.us.sentry.io/4511935182405632"
            options.debug = false
            options.sendDefaultPii = true
            options.tracesSampleRate = 1.0
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutPortsideButton() }
        }
    }
}

@MainActor
final class PortsideModel: ObservableObject {
    @Published var state: EnvironmentState
    @Published var requirements: SystemRequirements
    @Published var setupStep: SetupStep = .welcome
    @Published var progress: Double = 0
    @Published var message = ""
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published var didExportReport = false

    let store = EnvironmentStore()
    let logger = PortsideLogger()
    let runtimeProvider = FreeWineRuntimeProvider()
    let supervisor = ProcessSupervisor()
    let steamMonitor = SteamReadinessMonitor()

    enum SetupStep: String { case welcome, checking, rosettaRequired, preparing, downloading, installing, ready, failed }

    init() {
        try? store.prepareDirectories()
        state = store.load()
        requirements = SystemRequirements()
        if state.setupCompleted && state.steamInstalled && (state.runtimeRecord != nil || state.runtime != nil) {
            setupStep = .ready
        }
    }

    func setUp() {
        guard !isWorking else { return }
        isWorking = true; errorMessage = nil; progress = 0; setupStep = .checking; message = "Preparando o Portside…"
        let started = Date()
        if state.phase == .failedRecoverable { state.retryCount += 1 }
        state.lastError = nil; state.lastErrorCode = nil; state.lastProcessType = nil; state.lastExitCode = nil
        Task {
            do {
                logger.write("Starting Portside setup")
                updateProgress(0, phase: .requirementsChecking)
                try requirements.validate()
                let rosetta = await RosettaManager.status()
                guard rosetta.installed else {
                    state.phase = .rosettaRequired; persistState(); setupStep = .rosettaRequired; message = "Rosetta is required and is provided by macOS."; isWorking = false; return
                }
                setupStep = .preparing; updateProgress(0.08, phase: .graphicsInstalling)
                try store.prepareDirectories()
                let result = try await runtimeProvider.install { [weak self] value, phase in
                    Task { @MainActor in
                        self?.updateProgress(value, phase: phase)
                    }
                }
                state.runtimeRecord = result.record
                state.runtime = RuntimeDescriptor(name: result.record.manifest.identifier, version: result.record.manifest.version, executablePath: result.record.executablePath.path, redistributable: false, licenseNote: result.record.manifest.license)
                let existingSteam = SteamInstaller.locateInstalledExecutable()
                if existingSteam == nil {
                    setupStep = .downloading
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
                updateProgress(0.88, phase: .steamUpdating)
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
                SentrySDK.capture(error: error)
                state.phase = .failedRecoverable
                state.lastError = error.localizedDescription
                state.lastErrorCode = errorCode(for: error)
                if let pipelineError = error as? RuntimePipelineError, case .processFailed(_, let exitCode) = pipelineError {
                    state.lastExitCode = exitCode
                }
                state.lastSetupDuration = Date().timeIntervalSince(started)
                persistState()
                setupStep = .failed
                errorMessage = error.localizedDescription
                message = "Não foi possível concluir a preparação."
                logger.write(error.localizedDescription, level: .error)
            }
            isWorking = false
        }
    }

    func installRosetta() {
        guard !isWorking else { return }
        isWorking = true; message = "Requesting Rosetta from macOS…"
        Task {
            do {
                let result = try await RosettaManager.install()
                guard result.status == 0, (await RosettaManager.status()).installed else { throw RuntimePipelineError.rosettaUnavailable }
                setupStep = .checking; isWorking = false; setUp()
            } catch {
                isWorking = false; setupStep = .failed; errorMessage = "macOS could not install Rosetta. Use Software Update, then try again."; logger.write(error.localizedDescription, level: .error)
                SentrySDK.capture(error: error)
            }
        }
    }

    func launchSteam() {
        guard !isWorking else { return }
        isWorking = true; errorMessage = nil; message = "Preparando o Portside…"
        Task {
            do {
                try requirements.validate()
                guard (await RosettaManager.status()).installed else { throw RuntimePipelineError.rosettaUnavailable }
                let storedSteamExecutable = state.steamExecutablePath.map(URL.init(fileURLWithPath:))
                guard let steamExecutable = (storedSteamExecutable.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }) ?? SteamInstaller.locateInstalledExecutable() else {
                    throw PortsideError.processLaunchFailed("Steam is not installed yet. Run Set Up Portside first.")
                }
                guard FileManager.default.isExecutableFile(atPath: state.runtimeRecord?.executablePath.path ?? state.runtime?.executablePath ?? ""),
                      FileManager.default.fileExists(atPath: PortsidePaths.steamPrefix.appendingPathComponent("system.reg").path) else {
                    throw PortsideError.runtimeUnavailable
                }
                state.steamExecutablePath = steamExecutable.path
                state.phase = .steamLaunching; persistState(); message = "Abrindo a Steam…"
                try await openSteamAndWait(executable: steamExecutable)
                message = "Tudo pronto"; NSApp.hide(nil)
            } catch {
                if supervisor.isRunning { supervisor.requestStop() }
                SentrySDK.capture(error: error)
                errorMessage = error.localizedDescription
                state.phase = .failedRecoverable; state.lastError = error.localizedDescription; state.lastErrorCode = errorCode(for: error); persistState()
                logger.write(error.localizedDescription, level: .error)
                NSApp.unhide(nil)
            }
            isWorking = false
        }
    }

    private func friendlyMessage(for phase: EnvironmentPhase) -> String {
        switch phase {
        case .requirementsChecking: return "Preparando o Portside…"
        case .rosettaRequired: return "Preparando o Portside…"
        case .runtimeDownloading: return "Baixando componentes"
        case .runtimeVerifying, .runtimeInstalling, .prefixCreating, .graphicsInstalling: return "Preparando o ambiente"
        case .steamDownloading, .steamInstalling: return "Instalando a Steam"
        case .steamUpdating: return "Atualizando a Steam"
        case .steamLaunching, .validatingInstallation, .steamReady: return "Tudo pronto"
        case .failedRecoverable, .failedFatal: return "Não foi possível concluir a preparação."
        }
    }

    private func updateProgress(_ value: Double, phase: EnvironmentPhase) {
        if let currentPhase = state.phase, phaseRank(phase) < phaseRank(currentPhase), value < progress { return }
        state.phase = phase
        progress = max(progress, min(1, value))
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
        case .failedRecoverable, .failedFatal: return 99
        }
    }

    private func errorCode(for error: Error) -> String {
        if let pipelineError = error as? RuntimePipelineError {
            return String(describing: pipelineError).split(separator: "(").first.map(String.init) ?? "runtime_error"
        }
        if let portsideError = error as? PortsideError {
            return String(describing: portsideError).split(separator: "(").first.map(String.init) ?? "portside_error"
        }
        return String(describing: type(of: error))
    }

    private func openSteamAndWait(executable: URL) async throws {
        state.lastProcessType = "steam-launch"
        state.phase = .steamLaunching; persistState()
        guard let runtimePath = state.runtimeRecord?.executablePath ?? state.runtime?.executablePath.map(URL.init(fileURLWithPath:)) else {
            throw PortsideError.runtimeUnavailable
        }
        let policyResult = try await WinePrefixManager.configureSilentCrashHandling(runtimeExecutable: runtimePath, prefix: PortsidePaths.steamPrefix, logger: logger)
        guard policyResult.status == 0 else { throw RuntimePipelineError.processFailed("Wine crash-dialog configuration", policyResult.status) }
        try supervisor.launchSteam(state: state)
        let status = await steamMonitor.waitForSteam(executable: executable)
        state.lastSteamStatus = status
        guard status == .windowVisible else {
            throw PortsideError.processLaunchFailed("Steam started but its window did not appear before the timeout.")
        }
        state.phase = .steamReady; state.setupCompleted = true; state.lastError = nil; persistState()
        NSApp.hide(nil)
    }

    private func persistState() {
        state.lastUpdated = Date()
        try? store.save(state)
    }

    func stopSteam() {
        supervisor.requestStop(); message = "Steam was asked to close safely."
    }

    func repair() {
        state.setupCompleted = false
        state.steamInstalled = SteamInstaller.locateInstalledExecutable() != nil
        setupStep = .checking
        setUp()
    }

    func exportReport() {
        do {
            let url = try DiagnosticReport.create(state: state, requirements: requirements, logger: logger)
            didExportReport = true
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            SentrySDK.capture(error: error)
            errorMessage = "Could not export the diagnostic report."
        }
    }

    func openStorage() { NSWorkspace.shared.open(PortsidePaths.root) }

    func clearCache() {
        do {
            try FileManager.default.removeItem(at: PortsidePaths.cache)
            try FileManager.default.createDirectory(at: PortsidePaths.cache, withIntermediateDirectories: true)
            message = "Download cache cleared. Installed games were preserved."
        } catch {
            SentrySDK.capture(error: error)
            errorMessage = "Could not clear the download cache."
        }
    }

    func reset() {
        do {
            try FileManager.default.removeItem(at: PortsidePaths.root)
            state = EnvironmentState(); setupStep = .welcome; message = "Portside was reset. Installed Steam and game files were removed."; errorMessage = nil
        } catch {
            SentrySDK.capture(error: error)
            errorMessage = "Could not reset Portside."
        }
    }
}

struct RootView: View {
    @ObservedObject var model: PortsideModel

    var body: some View {
        Group {
            if model.setupStep == .welcome || model.setupStep == .failed || model.setupStep == .rosettaRequired { OnboardingView(model: model) }
            else if model.setupStep == .ready { DashboardView(model: model) }
            else { SetupProgressView(model: model) }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Reset Portside?", isPresented: .constant(false)) { Button("Cancel", role: .cancel) {} }
    }
}

struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "arrow.triangle.2.circlepath.icloud.fill").font(.system(size: 30, weight: .medium)).foregroundStyle(.white)
        }.frame(width: 64, height: 64)
    }
}

struct OnboardingView: View {
    @ObservedObject var model: PortsideModel
    @State private var showResetConfirmation = false
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack { BrandMark(); Spacer(); Text("Portside").font(.title2.weight(.semibold)); Spacer(); Color.clear.frame(width: 64) }
                .padding(.top, 42)
            Spacer()
            VStack(spacing: 14) {
                Text(model.setupStep == .failed ? "Não foi possível concluir a preparação." : model.setupStep == .rosettaRequired ? "Rosetta is required" : "Welcome to Portside").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Play supported Windows Steam games on your Mac.").font(.title3).foregroundStyle(.secondary)
                Text("Install and try any Windows Steam game. Compatibility may vary by title.").multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 450)
                if model.setupStep == .rosettaRequired { Text("Portside uses Apple’s official Rosetta component to run the fixed x86-64 Wine runtime. macOS may ask for administrator approval.").multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 470).padding(.top, 8) }
                if model.setupStep == .failed, showDetails, let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).multilineTextAlignment(.center).padding(.top, 8)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 24) {
                    RequirementBadge(icon: "cpu", title: "Apple silicon", value: model.requirements.isAppleSilicon ? "Detected" : "Required")
                    RequirementBadge(icon: "internaldrive", title: "Storage", value: ByteCountFormatter.string(fromByteCount: model.requirements.availableStorage, countStyle: .file) + " free")
                }
                if model.setupStep == .failed {
                    HStack(spacing: 12) {
                        Button("Tentar novamente") { model.setUp() }.buttonStyle(.borderedProminent)
                        Button("Reparar") { model.repair() }.buttonStyle(.bordered)
                        Button("Salvar diagnóstico") { model.exportReport() }.buttonStyle(.bordered)
                        Button(showDetails ? "Ocultar detalhes" : "Ver detalhes") { showDetails.toggle() }.buttonStyle(.bordered)
                    }.disabled(model.isWorking)
                } else {
                    Button {
                        if model.setupStep == .rosettaRequired { model.installRosetta() } else { model.setUp() }
                    } label: {
                        Text(model.setupStep == .rosettaRequired ? "Install Rosetta" : "Set Up Portside")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction).disabled(model.isWorking)
                }
                HStack(spacing: 18) {
                    Link("Privacy", destination: URL(string: "https://portside.example/privacy")!)
                    Link("Compatibility info", destination: URL(string: "https://portside.example/compatibility")!)
                }.font(.caption)
                Text("Portside is independent and is not affiliated with or endorsed by Valve Corporation. Steam is a trademark of Valve Corporation.")
                    .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 520)
            }.padding(.bottom, 28)
        }.padding(.horizontal, 64)
    }
}

struct RequirementBadge: View {
    let icon: String; let title: String; let value: String
    var body: some View { HStack { Image(systemName: icon).foregroundStyle(.blue); VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout.weight(.medium)) } }.frame(width: 190, alignment: .leading) }
}

struct SetupProgressView: View {
    @ObservedObject var model: PortsideModel
    var body: some View {
        VStack(spacing: 26) {
            Spacer(); BrandMark()
            Text(model.message).font(.title3.weight(.medium))
            ProgressView(value: model.progress).frame(width: 360)
            Text("You can cancel safely by closing this window. No credentials are collected by Portside.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(40)
    }
}

struct DashboardView: View {
    @ObservedObject var model: PortsideModel
    @State private var showSupport = false
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack { BrandMark().scaleEffect(0.62).frame(width: 40, height: 40); Text("Portside").font(.title2.weight(.bold)); Spacer(); Button("Support") { showSupport = true }.buttonStyle(.bordered); Button { model.launchSteam() } label: { Label("Open Steam", systemImage: "play.fill") }.buttonStyle(.borderedProminent) }.padding(.horizontal, 28).padding(.vertical, 16)
            Divider()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "shippingbox.and.arrow.backward.fill").font(.system(size: 48)).foregroundStyle(.blue)
                Text("Your Steam library, now on Mac.").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Portside will open the official Steam for Windows client in a separate window. Your library, downloads, updates and authentication stay with Steam.").multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 510)
                if let error = model.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).multilineTextAlignment(.center) }
                if !model.state.steamInstalled { Text("Steam has not finished installing yet. Run setup to prepare the free compatibility components and the official Steam client.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 500) }
                HStack { Button("Open Steam", action: model.launchSteam).buttonStyle(.borderedProminent).controlSize(.large); Button("Stop Steam", action: model.stopSteam).buttonStyle(.bordered).disabled(!model.supervisor.isRunning) }
                Spacer()
            }.padding(32)
        }
        .sheet(isPresented: $showSupport) { SupportView(model: model) }
        .onAppear {
            if model.state.setupCompleted && model.state.steamInstalled && !model.supervisor.isRunning { model.launchSteam() }
        }
    }
}

struct SupportView: View {
    @ObservedObject var model: PortsideModel
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Support").font(.title.bold()); Spacer(); Button("Done") { dismiss() } }
            Form {
                Section("Environment") {
                    LabeledContent("Portside", value: "0.1.0 MVP")
                    LabeledContent("macOS", value: model.requirements.macOSVersion)
                    LabeledContent("Architecture", value: model.requirements.architecture)
                    LabeledContent("Runtime", value: model.state.runtime?.version ?? "Not detected")
                    LabeledContent("Steam", value: model.state.steamInstalled ? "Installed" : "Not installed")
                    LabeledContent("Storage", value: ByteCountFormatter.string(fromByteCount: model.requirements.availableStorage, countStyle: .file))
                }
                Section("Actions") {
                    Button("Check for Problems") { model.message = model.requirements.meetsMinimum ? "No basic system problems found." : "This Mac does not meet the minimum requirements." }
                    Button("Repair Steam Environment") { model.message = "Repair is safe to run after a failed setup; installed game files are preserved." }
                    Button("Export Diagnostic Report") { model.exportReport() }
                    Button("Open Storage Location") { model.openStorage() }
                    Button("Clear Download Cache") { model.clearCache() }
                    Button("Reset Portside", role: .destructive) { showResetConfirmation = true }
                }
            }
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary) }
        }.padding(24).frame(width: 520, height: 500)
        .confirmationDialog("Reset Portside?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset and remove Portside files", role: .destructive) { model.reset(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the Portside environment, Steam prefix, downloads, logs and installed games. Your Steam account is not deleted.") }
    }
}

struct AboutPortsideButton: View {
    var body: some View { Button("About Portside") { NSApp.orderFrontStandardAboutPanel(nil) } }
}
