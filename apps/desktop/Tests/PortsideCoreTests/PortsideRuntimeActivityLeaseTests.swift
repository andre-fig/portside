import XCTest
@testable import PortsideCore

private actor LeaseConcurrencyProbe {
    private(set) var active = 0
    private(set) var maximum = 0
    private(set) var completed = 0

    func enter() { active += 1; maximum = max(maximum, active) }
    func leave() { active -= 1; completed += 1 }
}

final class PortsideRuntimeActivityLeaseTests: XCTestCase, @unchecked Sendable {
    func testForegroundAndBackgroundHoldersNeverOverlap() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.lock")
        let foreground = try await PortsideRuntimeActivityLease.acquire(at: url)
        let probe = LeaseConcurrencyProbe()
        let tasks = (0..<6).map { _ in
            Task {
                let lease = try await PortsideRuntimeActivityLease.acquire(at: url, pollInterval: .milliseconds(5))
                defer { lease.release() }
                await probe.enter()
                try await Task.sleep(for: .milliseconds(10))
                await probe.leave()
            }
        }
        try await Task.sleep(for: .milliseconds(40))
        let startedBeforeRelease = await probe.maximum
        XCTAssertEqual(startedBeforeRelease, 0, "No runtime work starts while the foreground owns the preflight lease")
        foreground.release()
        for task in tasks { try await task.value }
        let maximum = await probe.maximum
        let completed = await probe.completed
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(completed, 6)
        XCTAssertEqual(try Data(contentsOf: url).count, 0, "A lease file contains no persisted bootstrap state")
    }

    func testCancelledWaiterDoesNotReleaseAnotherHolderOrLeaveAStaleLock() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.lock")
        let first = try await PortsideRuntimeActivityLease.acquire(at: url)
        let waiter = Task { try await PortsideRuntimeActivityLease.acquire(at: url, pollInterval: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(20))
        waiter.cancel()
        do { _ = try await waiter.value; XCTFail("A cancelled waiter acquired the lease") }
        catch { XCTAssertTrue(error is CancellationError) }
        let probe = LeaseConcurrencyProbe()
        let next = Task {
            let lease = try await PortsideRuntimeActivityLease.acquire(at: url, pollInterval: .milliseconds(5))
            defer { lease.release() }
            await probe.enter()
        }
        try await Task.sleep(for: .milliseconds(20))
        let waitingMaximum = await probe.maximum
        XCTAssertEqual(waitingMaximum, 0)
        first.release()
        first.release()
        try await next.value
        let final = try await PortsideRuntimeActivityLease.acquire(at: url)
        final.release()
    }

    func testDeinitializationAutomaticallyReleasesLease() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.lock")
        var lease: PortsideRuntimeActivityLease? = try await PortsideRuntimeActivityLease.acquire(at: url)
        XCTAssertNotNil(lease)
        lease = nil
        let next = try await PortsideRuntimeActivityLease.acquire(at: url)
        next.release()
    }

    func testProcessExitReleasesKernelLockWithoutDeletingLeaseFile() async throws {
        // macOS ships Perl; use its flock to hold the exact same kernel lock
        // in a separate process, then terminate it without an explicit unlock.
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else { throw XCTSkip("Perl is unavailable for this process-exit check") }
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.lock")
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", "$|=1; open(my $f, '>>', $ARGV[0]) or die; flock($f, 2) or die; print qq(locked\\n); sleep 30;", url.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let signal = output.fileHandleForReading.availableData
        XCTAssertEqual(String(decoding: signal, as: UTF8.self), "locked\n")
        let probe = LeaseConcurrencyProbe()
        let waiter = Task {
            let lease = try await PortsideRuntimeActivityLease.acquire(at: url, pollInterval: .milliseconds(5))
            defer { lease.release() }
            await probe.enter()
        }
        try await Task.sleep(for: .milliseconds(20))
        let beforeExit = await probe.maximum
        XCTAssertEqual(beforeExit, 0)
        process.terminate()
        try await waiter.value
        let afterExit = await probe.maximum
        XCTAssertEqual(afterExit, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testLockSymlinkIsRejectedWithoutChangingItsTarget() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("user-data")
        let link = directory.appendingPathComponent("activity.lock")
        try Data("untouched".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do { _ = try await PortsideRuntimeActivityLease.acquire(at: link); XCTFail("A substituted lock was accepted") }
        catch { XCTAssertTrue(error is PortsideRuntimeActivityError) }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "untouched")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("portside-lease-\(UUID().uuidString)", isDirectory: true)
    }
}
