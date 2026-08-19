import Foundation
import AppKit
import Darwin
import PortsideCore

/// The Portside launcher delegates prefix creation, winetricks and the final
/// executable handoff to the official Sikarugir wrapper. It never invokes Wine
/// directly and never passes Portside-specific Steam login flags.
@MainActor
final class SteamProcessLauncher {
    private let logger = PortsideLogger(logFileName: "steam-launch.log")
    private let runner: ProcessRunning

    init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    func installSteam(using wrapper: URL) async throws -> ProcessResult {
        let specification = try SikarugirSteamFlow.installationSpec(wrapper: wrapper)
        logger.write("Starting official Sikarugir WSS-winetricks steam flow")
        let result = try await runner.run(specification, logger: logger)
        guard result.status == 0 else {
            throw PortsideError.processFailed("official winetricks steam", result.status)
        }
        return result
    }

    func launch(wrapper: URL) async throws -> NSRunningApplication? {
        guard FileManager.default.fileExists(atPath: wrapper.path) else {
            throw PortsideError.runtimeUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: wrapper, configuration: configuration) { application, error in
                if let error {
                    continuation.resume(throwing: PortsideError.processLaunchFailed("Sikarugir wrapper could not be opened: \(error.localizedDescription)"))
                } else {
                    continuation.resume(returning: application)
                }
            }
        }
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
        logger.write("Requested termination of \(pids.count) managed Sikarugir processes")
    }
}
