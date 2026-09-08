import Foundation
import XCTest
@testable import PortsideCore

final class PortsideBundleComponentsTests: XCTestCase {
    func testRuntimeHostUsesBundleExecutableMetadataFromRelocatedBundle() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original/PortsideBaseline.app")
        try createBundle(at: original, identifier: "com.portside.runtime", executable: "MetadataSelectedHost")
        let moved = root.appendingPathComponent("Different location/Runtime.app")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: moved)

        let executable = try PortsideBundleComponents.runtimeHost(in: moved)
        XCTAssertEqual(executable.standardizedFileURL, moved.appendingPathComponent("Contents/MacOS/MetadataSelectedHost").standardizedFileURL)
        XCTAssertFalse(executable.path.contains("original"))
    }

    func testEmbeddedAgentUsesNestedBundleMetadata() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Copied Portside.app")
        try createBundle(at: app, identifier: "com.portside.app", executable: "Portside")
        let helper = app.appendingPathComponent("Contents/Helpers/PortsideAgent.app")
        try createBundle(at: helper, identifier: "com.portside.agent", executable: "AgentExecutableFromMetadata")

        let result = try PortsideBundleComponents.agent(in: XCTUnwrap(Bundle(url: app)))
        XCTAssertEqual(result.lastPathComponent, "AgentExecutableFromMetadata")
        XCTAssertTrue(result.path.hasPrefix(app.path + "/"))
    }

    func testHelperSymlinkOutsideApplicationIsRejected() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Portside.app")
        let external = root.appendingPathComponent("OutsideAgent.app")
        try createBundle(at: app, identifier: "com.portside.app", executable: "Portside")
        try createBundle(at: external, identifier: "com.portside.agent", executable: "PortsideAgent")
        let helper = app.appendingPathComponent("Contents/Helpers/PortsideAgent.app")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: helper, withDestinationURL: external)

        XCTAssertThrowsError(try PortsideBundleComponents.agent(in: XCTUnwrap(Bundle(url: app)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("outside its containing bundle"))
        }
    }

    func testWrongHelperIdentityReportsExactRejectionAndSignatureResult() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("Wrong.app")
        try createBundle(at: wrapper, identifier: "unexpected.identifier", executable: "PortsideRuntimeHost")
        XCTAssertThrowsError(try PortsideBundleComponents.runtimeHost(in: wrapper)) { error in
            guard let error = error as? PortsideBundleComponentError else { return XCTFail("Expected component diagnostics") }
            XCTAssertTrue(error.diagnostic.contains("bundle_url="))
            XCTAssertTrue(error.diagnostic.contains("helper_url="))
            XCTAssertTrue(error.diagnostic.contains("file_exists=true"))
            XCTAssertTrue(error.diagnostic.contains("signature="))
            XCTAssertTrue(error.diagnostic.contains("reason=The helper bundle identifier does not match com.portside.runtime"))
        }
    }

    func testCachedRuntimeCannotHideReplacedInvalidMetadata() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("Runtime.app")
        try createBundle(at: wrapper, identifier: "com.portside.runtime", executable: "Host")
        let cached = try XCTUnwrap(Bundle(url: wrapper))
        XCTAssertEqual(cached.bundleIdentifier, "com.portside.runtime")
        _ = try PortsideBundleComponents.runtimeHost(in: wrapper)
        let info = wrapper.appendingPathComponent("Contents/Info.plist")
        for metadata in [
            ["CFBundleIdentifier": "unexpected.identifier", "CFBundleExecutable": "Host"],
            ["CFBundleIdentifier": "com.portside.runtime", "CFBundleExecutable": "../Host"],
            ["CFBundleIdentifier": "com.portside.runtime", "CFBundleExecutable": "MissingHost"]
        ] {
            try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: info, options: .atomic)
            XCTAssertThrowsError(try PortsideBundleComponents.runtimeHost(in: wrapper))
        }
        try Data("invalid plist".utf8).write(to: info)
        XCTAssertThrowsError(try PortsideBundleComponents.runtimeHost(in: wrapper))
        let external = root.appendingPathComponent("ExternalInfo.plist")
        try FileManager.default.moveItem(at: info, to: external)
        try FileManager.default.createSymbolicLink(at: info, withDestinationURL: external)
        XCTAssertThrowsError(try PortsideBundleComponents.runtimeHost(in: wrapper))
        withExtendedLifetime(cached) {}
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PortsideBundleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func createBundle(at url: URL, identifier: String, executable: String) throws {
        let binary = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleExecutable": executable, "CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"
        ], format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
    }
}
