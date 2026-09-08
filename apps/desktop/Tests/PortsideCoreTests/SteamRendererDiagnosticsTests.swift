import Foundation
import XCTest
@testable import PortsideCore

final class SteamRendererDiagnosticsTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("PortsideRendererTests-\(UUID())")
    private var file: URL { root.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs/webhelper_gpu.txt") }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testHistoricalAndTransientErrorsDoNotFailCurrentLaunch() throws {
        try append("GPU process was unable to boot: GPU process crashed too many times with SwiftShader.", date: start.addingTimeInterval(-30))
        let reader = SteamRendererDiagnostics(prefix: root, started: start)
        try append("Exiting GPU process due to errors during initialization", date: start)
        XCTAssertNil(reader.currentFailure(now: start.addingTimeInterval(5)))
        try append("GPU process was unable to boot: failed", date: start)
        XCTAssertEqual(reader.currentFailure(now: start.addingTimeInterval(5)), .rendererInitializationFailed)
        try append("GPU process started: start count: 4", date: start.addingTimeInterval(6))
        XCTAssertNil(reader.currentFailure(now: start.addingTimeInterval(10)))
    }

    func testRotationRejectsOldReportAndAcceptsOnlyCurrentCompleteLines() throws {
        let reader = SteamRendererDiagnostics(prefix: root, started: start)
        try append("GPU process was unable to boot: failed", date: start.addingTimeInterval(-60))
        XCTAssertNil(reader.currentFailure(now: start.addingTimeInterval(5)))
        try FileManager.default.removeItem(at: file)
        try append("GPU process was unable to boot: failed", date: start, newline: false)
        XCTAssertNil(reader.currentFailure(now: start.addingTimeInterval(5)))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("\n".utf8)); try handle.close()
        XCTAssertEqual(reader.currentFailure(now: start.addingTimeInterval(5)), .rendererInitializationFailed)
        try append("[ GL implementation parts ]: (gl=egl-angle,angle=swiftshader)", date: start.addingTimeInterval(6))
        XCTAssertNil(reader.currentFailure(now: start.addingTimeInterval(10)))
    }

    func testSymlinkLogIsNotRead() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = root.appendingPathComponent("unrelated")
        try Data("preserve".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertNil(SteamRendererDiagnostics(prefix: root, started: start).currentFailure())
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "preserve")
    }

    func testWindowAndHelperCannotAuthorizeGraphicalHandoff() {
        let unverified = SteamReadinessReport(state: .visibleButUnverified, processStarted: true, webHelperStarted: true, windowDetected: true, visibleButUnverified: true)
        XCTAssertFalse(unverified.canCompleteGraphicalHandoff)
        let confirmed = SteamReadinessReport(state: .uiReady, processStarted: true, webHelperStarted: true, windowDetected: true, uiReady: true, interfaceVerification: .manualConfirmed)
        XCTAssertTrue(confirmed.canCompleteGraphicalHandoff)
        let failed = SteamReadinessReport(state: .uiReady, processStarted: true, webHelperStarted: true, windowDetected: true, uiReady: true, interfaceVerification: .manualConfirmed, failure: .rendererInitializationFailed)
        XCTAssertFalse(failed.canCompleteGraphicalHandoff)
    }

    func testCurrentRendererFailureWinsOverWindowDetection() async {
        let wrapper = root.appendingPathComponent("Runtime.app")
        let helper = ManagedProcessSnapshot(pid: 42, parentPID: 1, command: wrapper.path + "/steamwebhelper.exe")
        let monitor = SteamReadinessMonitor(logger: PortsideLogger(logDirectory: root.appendingPathComponent("Logs")), snapshots: { [helper] }, windowProbe: { _ in true })
        let report = await monitor.waitForSteamWindow(wrapper: wrapper, timeout: 0.1, rendererFailure: { .rendererInitializationFailed })
        XCTAssertEqual(report.failure, .rendererInitializationFailed)
        XCTAssertFalse(report.canCompleteGraphicalHandoff)
    }

    private func append(_ message: String, date: Date, newline: Bool = true) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let text = "[\(formatter.string(from: date))] \(message)" + (newline ? "\n" : "")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data(text.utf8)); try handle.close()
    }
}
