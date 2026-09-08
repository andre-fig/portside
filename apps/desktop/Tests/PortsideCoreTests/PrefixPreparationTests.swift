import Foundation
import XCTest
@testable import PortsideCore

final class PrefixPreparationTests: XCTestCase {
    func testNewExistingAndInterruptedPrefixesUseControlledPreparation() async throws {
        for existing in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let wrapper = try makeWrapper(root)
            let prefix = root.appendingPathComponent("ExternalPrefix")
            let marker = prefix.appendingPathComponent("synthetic-save")
            if existing {
                try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
                try Data("preserve".utf8).write(to: marker)
            }
            let runner = PrefixRunner()
            let installer = PortsideRuntimeInstaller(runner: runner, logger: PortsideLogger(logDirectory: root.appendingPathComponent("Logs")))
            try await installer.preparePrefix(wrapper: wrapper, prefix: prefix)
            let calls = await runner.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.arguments, ["--create-prefix"])
            XCTAssertNil(calls.first?.environment["WINEDLLOVERRIDES"])
            XCTAssertEqual(wrapper.appendingPathComponent("Contents/SharedSupport/prefix").resolvingSymlinksInPath(), prefix.resolvingSymlinksInPath())
            if existing { XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "preserve") }
            // A failed/interrupted first preparation leaves a directory. Retry
            // must still run wineboot, instead of trusting directory existence.
            try await installer.preparePrefix(wrapper: wrapper, prefix: prefix)
            let retryCalls = await runner.calls
            XCTAssertEqual(retryCalls.count, 2)
            XCTAssertTrue(try PortsideSteamFlow.cleanLaunchSpec(wrapper: wrapper).arguments.isEmpty)
        }
    }

    func testPreparationFailurePreservesExistingDataAndPropagates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = try makeWrapper(root)
        let prefix = root.appendingPathComponent("ExternalPrefix")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let marker = prefix.appendingPathComponent("synthetic-save")
        try Data("preserve".utf8).write(to: marker)
        let installer = PortsideRuntimeInstaller(runner: PrefixRunner(status: 7), logger: PortsideLogger(logDirectory: root.appendingPathComponent("Logs")))
        do {
            try await installer.preparePrefix(wrapper: wrapper, prefix: prefix)
            XCTFail("A failed Wine update must block installation")
        } catch {
            XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "preserve")
        }
    }

    private func makeWrapper(_ root: URL) throws -> URL {
        let wrapper = root.appendingPathComponent("Runtime.app")
        let executable = wrapper.appendingPathComponent("Contents/MacOS/Host")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Host", "CFBundleIdentifier": "com.portside.runtime", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: wrapper.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.createDirectory(at: wrapper.appendingPathComponent("Contents/SharedSupport/prefix"), withIntermediateDirectories: true)
        return wrapper
    }
}

private actor PrefixRunner: ProcessRunning {
    var calls: [ProcessLaunchSpec] = []
    let status: Int32
    init(status: Int32 = 0) { self.status = status }
    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult {
        calls.append(specification)
        return ProcessResult(status: status)
    }
}
