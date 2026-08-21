import Foundation
import Darwin

/// Runs outside Portside.app so a background runtime download is not killed
/// when the launcher hides and exits after Steam becomes ready.
public final class PortsideRuntimeUpdateWorker: @unchecked Sendable {
    private let logger: PortsideLogger
    private let updateService: PortsideUpdateService
    private let lockURL = PortsidePaths.runtime.appendingPathComponent("runtime-update-worker.lock")
    private var lockDescriptor: Int32 = -1

    public init(logger: PortsideLogger = PortsideLogger(logFileName: "runtime-updates.log"), updateService: PortsideUpdateService? = nil) {
        self.logger = logger
        self.updateService = updateService ?? PortsideUpdateService(
            logger: logger,
            backendConfiguration: PortsideBackendConfiguration.fromBundle(),
            currentVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
        )
    }

    public func runForever() async {
        guard acquireLock() else { return }
        defer { releaseLock() }
        logger.write("runtime update service started")
        while !Task.isCancelled {
            do {
                _ = try await updateService.prepareRuntimeUpdate()
            } catch {
                // Offline operation is expected. Keep the current runtime and
                // retry later without surfacing a technical dialog to users.
                logger.write("runtime update check deferred: \(error.localizedDescription)", level: .warning)
            }
            try? await Task.sleep(nanoseconds: 900_000_000_000)
        }
    }

    private func acquireLock() -> Bool {
        do {
            try FileManager.default.createDirectory(at: PortsidePaths.runtime, withIntermediateDirectories: true)
        } catch {
            return false
        }
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            return false
        }
        lockDescriptor = descriptor
        return true
    }

    private func releaseLock() {
        guard lockDescriptor >= 0 else { return }
        flock(lockDescriptor, LOCK_UN)
        close(lockDescriptor)
        lockDescriptor = -1
    }
}
