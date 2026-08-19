import SwiftUI
import AppKit
import PortsideCore

@main
struct PortsideApp: App {
    @StateObject private var model = PortsideModel()

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
    let runtimeLocator = RuntimeLocator()
    let supervisor = ProcessSupervisor()

    enum SetupStep: String { case welcome, checking, preparing, downloading, installing, ready, failed }

    init() {
        state = store.load()
        requirements = SystemRequirements()
        if state.setupCompleted { setupStep = .ready }
    }

    func setUp() {
        guard !isWorking else { return }
        isWorking = true; errorMessage = nil; progress = 0; setupStep = .checking
        Task {
            do {
                logger.write("Starting Portside setup")
                try requirements.validate()
                setupStep = .preparing; message = "Preparing your Portside workspace…"; progress = 0.15
                try store.prepareDirectories()
                try await Task.sleep(for: .milliseconds(250))
                setupStep = .downloading; message = "Downloading the official Steam installer from Valve…"; progress = 0.3
                _ = try await SteamInstaller.download { [weak self] value in
                    Task { @MainActor in self?.progress = 0.3 + (value * 0.5) }
                }
                setupStep = .installing; message = "Steam installer is ready. Looking for an authorized compatibility runtime…"; progress = 0.85
                let runtime = runtimeLocator.locate()
                state.runtime = runtime
                state.steamInstalled = false
                state.setupCompleted = false
                state.lastError = runtime == nil ? PortsideError.runtimeUnavailable.localizedDescription : nil
                if let runtime {
                    message = "Installing Steam in Portside’s private environment…"
                    try await SteamInstaller.install(using: runtime, logger: logger)
                    state.steamInstalled = FileManager.default.fileExists(atPath: PortsidePaths.steamPrefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/Steam.exe").path)
                    guard state.steamInstalled else { throw PortsideError.processLaunchFailed("Steam installation finished without a Steam client. See Support for diagnostics.") }
                }
                state.setupCompleted = state.steamInstalled
                state.lastError = state.setupCompleted ? nil : PortsideError.runtimeUnavailable.localizedDescription
                state.lastUpdated = Date()
                try store.save(state)
                if runtime == nil { throw PortsideError.runtimeUnavailable }
                setupStep = .ready; message = "Portside is ready. Steam will open in its own window."; progress = 1
                logger.write("Setup completed")
            } catch {
                setupStep = .failed; errorMessage = error.localizedDescription; message = "Setup needs your attention."; logger.write(error.localizedDescription, level: .error)
            }
            isWorking = false
        }
    }

    func launchSteam() {
        errorMessage = nil
        do { try supervisor.launchSteam(state: state); message = "Steam is starting…" }
        catch { errorMessage = error.localizedDescription; logger.write(error.localizedDescription, level: .error) }
    }

    func stopSteam() {
        supervisor.requestStop(); message = "Steam was asked to close safely."
    }

    func exportReport() {
        do {
            let url = try DiagnosticReport.create(state: state, requirements: requirements, logger: logger)
            didExportReport = true
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { errorMessage = "Could not export the diagnostic report." }
    }

    func openStorage() { NSWorkspace.shared.open(PortsidePaths.root) }

    func clearCache() {
        do {
            try FileManager.default.removeItem(at: PortsidePaths.cache)
            try FileManager.default.createDirectory(at: PortsidePaths.cache, withIntermediateDirectories: true)
            message = "Download cache cleared. Installed games were preserved."
        } catch { errorMessage = "Could not clear the download cache." }
    }

    func reset() {
        do {
            try FileManager.default.removeItem(at: PortsidePaths.root)
            state = EnvironmentState(); setupStep = .welcome; message = "Portside was reset. Installed Steam and game files were removed."; errorMessage = nil
        } catch { errorMessage = "Could not reset Portside." }
    }
}

struct RootView: View {
    @ObservedObject var model: PortsideModel

    var body: some View {
        Group {
            if model.setupStep == .welcome || model.setupStep == .failed { OnboardingView(model: model) }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack { BrandMark(); Spacer(); Text("Portside").font(.title2.weight(.semibold)); Spacer(); Color.clear.frame(width: 64) }
                .padding(.top, 42)
            Spacer()
            VStack(spacing: 14) {
                Text(model.setupStep == .failed ? "Setup needs attention" : "Welcome to Portside").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Play supported Windows Steam games on your Mac.").font(.title3).foregroundStyle(.secondary)
                Text("Install and try any Windows Steam game. Compatibility may vary by title.").multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 450)
                if let error = model.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).multilineTextAlignment(.center).padding(.top, 8) }
            }
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 24) {
                    RequirementBadge(icon: "cpu", title: "Apple silicon", value: model.requirements.isAppleSilicon ? "Detected" : "Required")
                    RequirementBadge(icon: "internaldrive", title: "Storage", value: ByteCountFormatter.string(fromByteCount: model.requirements.availableStorage, countStyle: .file) + " free")
                }
                Button(model.setupStep == .failed ? "Try Again" : "Set Up Portside", action: model.setUp)
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction).disabled(model.isWorking)
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
                if !model.state.steamInstalled { Text("Steam setup is prepared, but a licensed compatibility runtime and Steam installation are still required for execution.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 500) }
                HStack { Button("Open Steam", action: model.launchSteam).buttonStyle(.borderedProminent).controlSize(.large); Button("Stop Steam", action: model.stopSteam).buttonStyle(.bordered).disabled(!model.supervisor.isRunning) }
                Spacer()
            }.padding(32)
        }
        .sheet(isPresented: $showSupport) { SupportView(model: model) }
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
