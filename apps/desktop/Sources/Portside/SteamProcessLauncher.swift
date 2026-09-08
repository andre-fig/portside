import Foundation
import AppKit
import Darwin
import PortsideCore

/// Opens the runtime's validated application entry point through LaunchServices.
/// The original Sikarugir launcher owns Steam; Portside's helper handles setup.
/// Legacy direct-Wine bundles retain their negotiated host receipt protocol.
@MainActor
final class SteamProcessLauncher {
    @MainActor final class Launch {
        let id: UUID
        let application: NSRunningApplication
        init(id: UUID, application: NSRunningApplication) { self.id = id; self.application = application }
        @MainActor var hasTerminated: Bool { application.isTerminated }
    }
    private let logger = PortsideLogger(logFileName: "steam-launch.log")
    private let runner: ProcessRunning

    init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    func installSteam(using wrapper: URL) async throws -> ProcessResult {
        let specification = try PortsideSteamFlow.installationSpec(wrapper: wrapper)
        logger.write("Starting Portside runtime Steam setup")
        let result = try await runner.run(specification, logger: logger)
        guard result.status == 0 else {
            throw PortsideError.processFailed("Portside runtime Steam setup", result.status)
        }
        return result
    }

    func launch(wrapper: URL) async throws -> Launch {
        guard FileManager.default.fileExists(atPath: wrapper.path) else {
            throw PortsideError.runtimeUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let id = UUID()
        // Sikarugir remains the real app entry point. Receipt arguments belong
        // only to the legacy host and must never become upstream program flags.
        _ = try PortsideBundleComponents.runtimeLauncher(in: wrapper)
        configuration.arguments = try PortsideSteamFlow.launchArguments(wrapper: wrapper, launchID: id)
        let application: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            // AppKit invokes this completion handler on a concurrent queue.
            // Give it an explicitly nonisolated function type so Swift does
            // not insert a MainActor precondition into Launch Services' own
            // callback path. The suspended @MainActor task resumes on its
            // actor after the continuation is completed.
            let completionHandler: @Sendable (NSRunningApplication?, (any Error)?) -> Void = { application, error in
                if let error {
                    continuation.resume(throwing: PortsideError.processLaunchFailed("Portside runtime could not be opened: \(error.localizedDescription)"))
                } else if let application {
                    continuation.resume(returning: application)
                } else {
                    continuation.resume(throwing: PortsideError.processLaunchFailed("Portside runtime did not start."))
                }
            }
            NSWorkspace.shared.openApplication(at: wrapper, configuration: configuration, completionHandler: completionHandler)
        }
        return Launch(id: id, application: application)
    }

    func stopManagedProcesses(wrapper: URL, prefix: URL) {
        let monitor = SteamReadinessMonitor(logger: logger)
        let snapshots = monitor.captureProcessSnapshot()
        var managed = SteamProcessOwnership.managedPIDs(in: snapshots, wrapper: wrapper, prefix: prefix)
        managed.formUnion(SteamProcessOwnership.fileBackedManagedPIDs(in: snapshots, wrapper: wrapper, prefix: prefix))
        let pids = managed.map { $0 }
        for pid in Set(pids) where pid > 1 && pid != getpid() {
            _ = kill(pid, SIGTERM)
        }
        logger.write("Requested termination of \(pids.count) managed Portside processes")
    }
}
