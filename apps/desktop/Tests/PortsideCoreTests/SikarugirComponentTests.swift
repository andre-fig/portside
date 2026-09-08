import Foundation
import XCTest
@testable import PortsideCore

final class SikarugirComponentTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("PortsideSikarugirComponents-\(UUID())")
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testOriginalLauncherAndMaintenanceHelperHaveSeparateRoles() throws {
        let wrapper = try fixture()
        let launcher = try PortsideBundleComponents.runtimeLauncher(in: wrapper)
        XCTAssertEqual(launcher.lastPathComponent, "launcher")
        XCTAssertEqual(launcher.resolvingSymlinksInPath().lastPathComponent, "Sikarugir")
        XCTAssertEqual(try PortsideBundleComponents.runtimeHost(in: wrapper).lastPathComponent, "PortsideRuntimeHost")
        XCTAssertEqual(try PortsideSteamFlow.cleanLaunchSpec(wrapper: wrapper).executable, launcher)
        XCTAssertEqual(try PortsideSteamFlow.prefixCreationSpec(wrapper: wrapper).executable.lastPathComponent, "PortsideRuntimeHost")
        XCTAssertEqual(try PortsideSteamFlow.installationSpec(wrapper: wrapper).executable.lastPathComponent, "PortsideRuntimeHost")
        XCTAssertEqual(try PortsideRuntimeValidator.validate(wrapper: wrapper).launcher, launcher)
    }

    func testReceiptArgumentsNeverReachSikarugirEvenWithLegacyCapabilityMarker() throws {
        let wrapper = try fixture()
        XCTAssertEqual(try PortsideSteamFlow.launchArguments(wrapper: wrapper, launchID: UUID()), [])
    }

    func testMissingMaintenanceHelperCannotFallBackToOriginalLauncher() throws {
        let wrapper = try fixture()
        try FileManager.default.removeItem(at: wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost"))
        XCTAssertThrowsError(try PortsideSteamFlow.prefixCreationSpec(wrapper: wrapper))
    }

    func testMissingOrEscapingSDKIsRejected() throws {
        let wrapper = try fixture()
        let sdk = wrapper.appendingPathComponent("Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk")
        try FileManager.default.removeItem(at: sdk)
        XCTAssertThrowsError(try PortsideBundleComponents.runtimeLauncher(in: wrapper))
        let outside = root.appendingPathComponent("UnrelatedSDK")
        try executable(outside)
        try FileManager.default.createSymbolicLink(at: sdk, withDestinationURL: outside)
        XCTAssertThrowsError(try PortsideBundleComponents.runtimeLauncher(in: wrapper))
    }

    func testMaintenanceHostCannotReplaceSikarugirApplicationEntryPoint() throws {
        let wrapper = try fixture(primary: "PortsideRuntimeHost")
        XCTAssertThrowsError(try PortsideBundleComponents.runtimeLauncher(in: wrapper))
    }

    func testUnknownAndMalformedIntegrationCannotFallBackToLegacyHost() throws {
        let wrapper = try fixture()
        let resource = wrapper.appendingPathComponent("Contents/Resources/portside-runtime.json")
        for contents in [#"{"integration":"unknown"}"#, "broken-json"] {
            try Data(contents.utf8).write(to: resource)
            XCTAssertThrowsError(try PortsideBundleComponents.runtimeHost(in: wrapper))
        }
    }

    func testConfigurationSymlinkIsRejected() throws {
        let wrapper = try fixture()
        let resource = wrapper.appendingPathComponent("Contents/Resources/portside-runtime.json")
        let outside = root.appendingPathComponent("UnrelatedConfig")
        try FileManager.default.moveItem(at: resource, to: outside)
        try FileManager.default.createSymbolicLink(at: resource, withDestinationURL: outside)
        XCTAssertThrowsError(try PortsideBundleComponents.runtimeHost(in: wrapper))
    }

    private func executable(_ path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }

    private func fixture(primary: String = "launcher") throws -> URL {
        let wrapper = root.appendingPathComponent("Runtime.app")
        let original = wrapper.appendingPathComponent("Contents/MacOS/Sikarugir")
        try executable(original)
        try executable(wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost"))
        try executable(wrapper.appendingPathComponent("Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk"))
        try FileManager.default.createSymbolicLink(at: wrapper.appendingPathComponent("Contents/MacOS/launcher"), withDestinationURL: original)
        let info: [String: Any] = ["CFBundleExecutable": primary, "CFBundleIdentifier": "com.portside.runtime", "CFBundlePackageType": "APPL", "PortsideRuntime": true, "PortsideRenderer": "WineD3D", "PortsideD3DMetal": 0, "PortsideDXMT": 0, "PortsideDXVK": 0]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: wrapper.appendingPathComponent("Contents/Info.plist"))
        let resource = wrapper.appendingPathComponent("Contents/Resources/portside-runtime.json")
        try FileManager.default.createDirectory(at: resource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"integration":"sikarugir","launchDiagnosticsVersion":1}"#.utf8).write(to: resource)
        let engine = wrapper.appendingPathComponent("Contents/SharedSupport/wine")
        try executable(engine.appendingPathComponent("bin/wine"))
        try FileManager.default.createDirectory(at: engine.appendingPathComponent("share/wine"), withIntermediateDirectories: true)
        try Data("Wine Sikarugir fixture".utf8).write(to: engine.appendingPathComponent("version"))
        try FileManager.default.createDirectory(at: wrapper.appendingPathComponent("Contents/SharedSupport/prefix"), withIntermediateDirectories: true)
        return wrapper
    }
}
