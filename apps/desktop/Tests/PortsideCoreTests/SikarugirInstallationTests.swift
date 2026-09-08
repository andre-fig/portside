import CryptoKit
import Foundation
import XCTest
@testable import PortsideCore

final class SikarugirInstallationTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("PortsideInstallation-\(UUID())")
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testThreeArchivesInstallAndUpdateWithoutChangingWrapperMetadataOrPrefixData() async throws {
        let artifacts = try archives()
        let state = root.appendingPathComponent("State")
        let runner = InstallationRunner()
        let installer = PortsideRuntimeInstaller(runner: runner, logger: PortsideLogger(logDirectory: root.appendingPathComponent("Logs")), rootDirectory: state)
        let first = try await installer.install(artifacts: artifacts)
        let info = first.validation.wrapper.appendingPathComponent("Contents/Info.plist")
        XCTAssertEqual(try Data(contentsOf: info), try Data(contentsOf: root.appendingPathComponent("inputs/PortsideBaseline.app/Contents/Info.plist")))
        XCTAssertEqual(first.validation.launcher.lastPathComponent, "Sikarugir")
        XCTAssertEqual(try String(contentsOf: first.validation.wrapper.appendingPathComponent("Contents/SharedSupport/winetricks"), encoding: .utf8), "original script")
        let prefix = first.validation.prefix
        let marker = prefix.appendingPathComponent("synthetic-save")
        try Data("preserve".utf8).write(to: marker)
        let second = try await installer.install(artifacts: artifacts)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "preserve")
        XCTAssertEqual(second.validation.prefix.path, prefix.path)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: second.validation.wrapper.appendingPathComponent("Contents/SharedSupport/prefix").path), PortsideRuntimeCatalog.managedPrefixLink)
        XCTAssertEqual(try Data(contentsOf: info), try Data(contentsOf: root.appendingPathComponent("inputs/PortsideBaseline.app/Contents/Info.plist")))
        let calls = await runner.preparations
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls.allSatisfy { $0.executable.lastPathComponent == "PortsideRuntimeHost" && $0.arguments == ["--create-prefix"] && $0.environment["WINEDLLOVERRIDES"] == nil })
    }

    func testWrongPackagedPrefixLinkFailsBeforeReplacingInstalledWrapper() async throws {
        let artifacts = try archives(link: "../../../../Unrelated")
        try await assertRejectedWithoutReplacement(artifacts)
    }

    func testModifiedArchiveFailsBeforeExtractionAndReplacement() async throws {
        let artifacts = try archives()
        let file = try XCTUnwrap(artifacts.first?.value)
        var bytes = try Data(contentsOf: file)
        bytes[0] ^= 1
        try bytes.write(to: file)
        try await assertRejectedWithoutReplacement(artifacts)
    }

    func testIncompleteComponentSetCannotChangeInstalledWrapper() async throws {
        let artifacts = try archives().filter { $0.key.component != "engine" }
        try await assertRejectedWithoutReplacement(artifacts)
    }

    func testLegacyEmbeddedPrefixDataIsNotDeletedDuringPreparation() async throws {
        _ = try archives()
        let wrapper = root.appendingPathComponent("inputs/PortsideBaseline.app")
        try FileManager.default.removeItem(at: wrapper.appendingPathComponent("Contents/Resources/portside-runtime.json"))
        let prefix = wrapper.appendingPathComponent("Contents/SharedSupport/prefix")
        try FileManager.default.removeItem(at: prefix)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let marker = prefix.appendingPathComponent("synthetic-save")
        try Data("preserve".utf8).write(to: marker)
        let installer = PortsideRuntimeInstaller(runner: InstallationRunner(), logger: PortsideLogger(logDirectory: root.appendingPathComponent("Logs")), rootDirectory: root.appendingPathComponent("State"))
        do {
            try await installer.preparePrefix(wrapper: wrapper, prefix: root.appendingPathComponent("external"))
            XCTFail("Embedded data must not be removed")
        } catch {
            XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "preserve")
        }
    }

    private func assertRejectedWithoutReplacement(_ artifacts: [PortsideRuntimeArtifact: URL]) async throws {
        let state = root.appendingPathComponent("State")
        let wrapper = state.appendingPathComponent("Wrappers/PortsideBaseline.app")
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        let marker = wrapper.appendingPathComponent("preserve-old-wrapper")
        try Data("preserve".utf8).write(to: marker)
        let runner = InstallationRunner()
        let installer = PortsideRuntimeInstaller(runner: runner, logger: PortsideLogger(logDirectory: root.appendingPathComponent("Logs")), rootDirectory: state)
        do { _ = try await installer.install(artifacts: artifacts); XCTFail("Invalid archive set accepted") }
        catch { XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "preserve") }
        let calls = await runner.preparations
        XCTAssertTrue(calls.isEmpty)
    }

    private func archives(link: String = PortsideRuntimeCatalog.managedPrefixLink) throws -> [PortsideRuntimeArtifact: URL] {
        let inputs = root.appendingPathComponent("inputs")
        func write(_ path: String, _ data: Data, executable: Bool = false) throws {
            let file = inputs.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
            if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
        }
        for name in ["MacOS/Sikarugir", "MacOS/PortsideRuntimeHost", "Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk"] {
            try write("PortsideBaseline.app/Contents/" + name, Data("fixture".utf8), executable: true)
        }
        let info: [String: Any] = ["CFBundleExecutable": "Sikarugir", "CFBundleIdentifier": "com.portside.runtime", "CFBundlePackageType": "APPL", "PortsideRuntime": true, "PortsideRenderer": "WineD3D", "PortsideD3DMetal": 0, "PortsideDXMT": 0, "PortsideDXVK": 0, "Program Name and Path": "/Program Files (x86)/Steam/steam.exe", "Program Flags": "", "D3DMETAL": 0, "DXMT": 0, "DXVK": 0, "WINEMSYNC": 1, "WINEESYNC": 1]
        try write("PortsideBaseline.app/Contents/Info.plist", PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0))
        try write("PortsideBaseline.app/Contents/Resources/portside-runtime.json", Data(#"{"integration":"sikarugir"}"#.utf8))
        let shared = inputs.appendingPathComponent("PortsideBaseline.app/Contents/SharedSupport")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: shared.appendingPathComponent("prefix").path, withDestinationPath: link)
        try write("Engine/bin/wine", Data("original engine".utf8), executable: true)
        try write("Engine/share/wine/wine.inf", Data("fixture".utf8))
        try write("Engine/version", Data("Wine Sikarugir fixture".utf8))
        try write("Winetricks/src/winetricks", Data("original script".utf8), executable: true)
        var result: [PortsideRuntimeArtifact: URL] = [:]
        for (component, name) in [("wrapper", "PortsideBaseline.app"), ("engine", "Engine"), ("winetricks", "Winetricks")] {
            let archive = root.appendingPathComponent(component + ".tar.xz")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-cJf", archive.path, "--no-xattrs", "--no-acls", "-C", inputs.path, name]
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let bytes = try Data(contentsOf: archive)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            result[PortsideRuntimeArtifact(id: component, component: component, version: "0.1.36", url: URL(string: "https://portside.test/" + component)!, sha256: digest, expectedSize: Int64(bytes.count))] = archive
        }
        return result
    }
}

private actor InstallationRunner: ProcessRunning {
    var preparations: [ProcessLaunchSpec] = []
    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult {
        if specification.executable.lastPathComponent == "PortsideRuntimeHost" {
            preparations.append(specification)
            return ProcessResult(status: 0)
        }
        return try await SystemProcessRunner().run(specification, logger: logger)
    }
}
