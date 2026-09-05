import Darwin
import Foundation

public enum PortsideRuntimeActivityError: LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "Portside could not coordinate its update. Check access to your Application Support folder and try again."
    }
}

/// Serializes foreground app-update/bootstrap work with background runtime
/// preparation across processes. The empty file is not persisted progress:
/// macOS releases the advisory lock when its owning process exits or crashes.
public final class PortsideRuntimeActivityLease: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    public static func acquire() async throws -> PortsideRuntimeActivityLease {
        try await acquire(at: PortsidePaths.root.appendingPathComponent(".runtime-activity.lock"))
    }

    static func acquire(at url: URL, pollInterval: Duration = .milliseconds(100)) async throws -> PortsideRuntimeActivityLease {
        try Task.checkCancellation()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { throw PortsideRuntimeActivityError.unavailable }
        // Do not follow a substituted lock symlink or let child processes keep
        // the parent's lease alive after it exits.
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw PortsideRuntimeActivityError.unavailable }
        var returnedLease = false
        defer { if !returnedLease { close(descriptor) } }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_nlink == 1 else { throw PortsideRuntimeActivityError.unavailable }
        while true {
            try Task.checkCancellation()
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                try Task.checkCancellation()
                returnedLease = true
                return PortsideRuntimeActivityLease(descriptor: descriptor)
            }
            guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else {
                throw PortsideRuntimeActivityError.unavailable
            }
            // Only the short nonblocking flock call is synchronous. Waiting
            // never blocks the MainActor or prevents task cancellation.
            try await Task.sleep(for: pollInterval)
        }
    }

    public func release() {
        lock.withLock {
            guard descriptor >= 0 else { return }
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }

    deinit { release() }
}
