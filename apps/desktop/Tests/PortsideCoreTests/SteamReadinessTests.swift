import Foundation
import XCTest
@testable import PortsideCore

final class SteamReadinessTests: XCTestCase {
    private let wrapper = URL(fileURLWithPath: "/PortsideFixture/Runtime.app")
    private let logs = FileManager.default.temporaryDirectory.appendingPathComponent("PortsideReadinessTests-\(UUID().uuidString)")

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: logs.path) { try FileManager.default.removeItem(at: logs) }
    }

    func testImmediateNormalExitDoesNotWaitForWindowDeadline() async {
        let receipt = receipt(status: 0)
        let report = await monitor().waitForSteamWindow(wrapper: wrapper, timeout: 20, poll: 0.02, launchReceipt: { receipt })
        XCTAssertLessThan(report.duration, 3)
        XCTAssertFalse(report.processStarted)
        XCTAssertEqual(report.failure, .steamNotStarted)
        XCTAssertEqual(report.state, .failed)
        XCTAssertNotEqual(report.failure?.code, "steam_window_failed")
    }

    func testNonzeroExitAndSignalHaveDistinctErrors() async {
        for (reason, expected) in [("exit", SteamLaunchFailure.wineExited(9)), ("uncaughtSignal", .wineSignaled(9))] {
            let receipt = receipt(status: 9, reason: reason)
            let report = await monitor().waitForSteamWindow(wrapper: wrapper, timeout: 20, poll: 0.02, launchReceipt: { receipt })
            XCTAssertEqual(report.failure, expected)
            XCTAssertFalse(report.processStarted)
            XCTAssertLessThan(report.duration, 3)
            XCTAssertEqual(report.runtimeTermination?.terminationReason, reason)
        }
    }

    func testExecutionFailureAndLegacyHostTerminationReturnEarly() async {
        let failed = receipt(phase: "executionFailed")
        let report = await monitor().waitForSteamWindow(wrapper: wrapper, timeout: 20, poll: 0.02, launchReceipt: { failed })
        XCTAssertEqual(report.failure, .wineExecutionFailed)
        let legacy = await monitor().waitForSteamWindow(wrapper: wrapper, timeout: 20, poll: 0.02, hostTerminated: { true })
        XCTAssertEqual(legacy.failure, .steamNotStarted)
        XCTAssertLessThan(legacy.duration, 3)
    }

    func testRunningSteamWithoutWindowKeepsSeparateFailure() async {
        let steam = steamSnapshot()
        let report = await monitor(snapshots: [steam]).waitForSteamWindow(wrapper: wrapper, timeout: 0.05, poll: 0.01)
        XCTAssertTrue(report.processStarted)
        XCTAssertTrue(report.processRunningWithoutWindow)
        XCTAssertEqual(report.failure, .processWithoutWindow)
        XCTAssertEqual(report.failure?.code, "steam_window_failed")
    }

    func testOwnedWebHelperAloneStillProvesSteamProcessesStarted() async {
        let helper = ManagedProcessSnapshot(pid: 43, parentPID: 1, command: wrapper.path + "/steamwebhelper.exe")
        let report = await monitor(snapshots: [helper]).waitForSteamWindow(wrapper: wrapper, timeout: 0.05, poll: 0.01)
        XCTAssertTrue(report.processStarted)
        XCTAssertTrue(report.webHelperStarted)
        XCTAssertEqual(report.failure, .processWithoutWindow)
    }

    func testWindowWithoutHelperIsNotGraphicalReadiness() async {
        let report = await monitor(snapshots: [steamSnapshot()], window: true).waitForSteamWindow(wrapper: wrapper, timeout: 0.05, poll: 0.01)
        XCTAssertTrue(report.windowDetected)
        XCTAssertFalse(report.webHelperStarted)
        XCTAssertEqual(report.failure, .windowWithoutWebHelper)
        XCTAssertEqual(report.state, .windowWithoutWebHelper)
    }

    func testDetachedChildCanBecomeReadyAfterLoaderExits() async {
        let finished = receipt(status: 0)
        let steam = steamSnapshot()
        let helper = ManagedProcessSnapshot(pid: 43, parentPID: steam.pid, command: "steamwebhelper.exe")
        let report = await monitor(snapshots: [steam, helper], window: true).waitForSteamWindow(wrapper: wrapper, timeout: 0.1, launchReceipt: { finished })
        XCTAssertNil(report.failure)
        XCTAssertEqual(report.state, .visibleButUnverified)
        XCTAssertFalse(report.uiReady)
        XCTAssertEqual(report.interfaceVerification, .notVerified)
    }

    func testUnrelatedNewWineDoesNotMaskImmediateFailure() async {
        let unrelated = ManagedProcessSnapshot(pid: 82, parentPID: 1, command: "/AnotherRuntime/bin/wine steam.exe")
        let finished = receipt(status: 9, reason: "uncaughtSignal")
        let report = await monitor(snapshots: [unrelated]).waitForSteamWindow(wrapper: wrapper, timeout: 20, poll: 0.02, launchReceipt: { finished })
        XCTAssertEqual(report.failure, .wineSignaled(9))
        XCTAssertFalse(report.processStarted)
        XCTAssertLessThan(report.duration, 3)
    }

    func testSteamObservedThenGoneIsNotProcessWithoutWindow() async {
        let sequence = SnapshotSequence(first: [steamSnapshot()])
        let monitor = SteamReadinessMonitor(logger: PortsideLogger(logDirectory: logs), snapshots: { sequence.next() }, windowProbe: { _ in false })
        let finished = receipt(status: 0)
        let report = await monitor.waitForSteamWindow(wrapper: wrapper, timeout: 20, poll: 0.02, launchReceipt: { finished })
        XCTAssertTrue(report.processStarted)
        XCTAssertFalse(report.processRunningWithoutWindow)
        XCTAssertEqual(report.failure, .steamExitedBeforeReady)
    }

    func testReceiptRejectsAnotherAttemptAndPreservesOldReportDecoding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let value = receipt(status: 9)
        let requested = UUID()
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(requested.uuidString + ".json"))
        XCTAssertNil(RuntimeLaunchReceipt.read(launchID: requested, directory: directory))
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(value.launchID.uuidString + ".json"))
        XCTAssertEqual(RuntimeLaunchReceipt.read(launchID: value.launchID, directory: directory), value)
        let old = SteamReadinessReport(state: .failed, processStarted: false, webHelperStarted: false, windowDetected: false)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "failure")
        json.removeValue(forKey: "runtimeTermination")
        let decoded = try JSONDecoder().decode(SteamReadinessReport.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.failure)
    }

    func testOwnershipRecognizesCanonicalExternalPrefixThroughWrapperSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let actualPrefix = root.appendingPathComponent("Prefixes/Baseline")
        let link = root.appendingPathComponent("Runtime.app/Contents/SharedSupport/prefix")
        try FileManager.default.createDirectory(at: actualPrefix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actualPrefix)
        let process = ManagedProcessSnapshot(pid: 77, parentPID: 1, command: actualPrefix.resolvingSymlinksInPath().path + "/drive_c/Steam/steam.exe")
        XCTAssertEqual(SteamProcessOwnership.managedPIDs(in: [process], wrapper: root.appendingPathComponent("Runtime.app"), prefix: link), [77])
    }

    private func monitor(snapshots: [ManagedProcessSnapshot] = [], window: Bool = false) -> SteamReadinessMonitor {
        SteamReadinessMonitor(logger: PortsideLogger(logDirectory: logs), snapshots: { snapshots }, windowProbe: { _ in window })
    }

    private func steamSnapshot() -> ManagedProcessSnapshot {
        ManagedProcessSnapshot(pid: 42, parentPID: 1, command: wrapper.path + "/Contents/SharedSupport/engine/bin/wine steam.exe")
    }

    private func receipt(status: Int32? = nil, reason: String = "exit", phase: String = "terminated") -> RuntimeLaunchReceipt {
        RuntimeLaunchReceipt(schemaVersion: 1, launchID: UUID(), phase: phase, hostPID: 30, childPID: 31,
                             terminationStatus: status, terminationReason: status == nil ? nil : reason,
                             signal: reason == "uncaughtSignal" ? status : nil, duration: 0.01, executionError: nil)
    }
}

private final class SnapshotSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var first: [ManagedProcessSnapshot]
    init(first: [ManagedProcessSnapshot]) { self.first = first }
    func next() -> [ManagedProcessSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        let result = first
        first = []
        return result
    }
}
