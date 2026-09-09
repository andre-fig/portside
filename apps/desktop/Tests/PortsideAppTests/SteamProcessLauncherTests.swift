import AppKit
import XCTest
import PortsideCore
@testable import Portside

@MainActor
final class SteamProcessLauncherTests: XCTestCase {
    func testReplacementRefreshesRegistrationAndDropsLegacyArguments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PortsideLaunchTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("Runtime.app")
        let infoURL = wrapper.appendingPathComponent("Contents/Info.plist")
        let resource = wrapper.appendingPathComponent("Contents/Resources/portside-runtime.json")
        try write("fixture", to: wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost"), executable: true)
        var info: [String: Any] = ["CFBundleIdentifier": "com.portside.runtime", "CFBundlePackageType": "APPL", "CFBundleExecutable": "PortsideRuntimeHost"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        try write(#"{"launchDiagnosticsVersion":1}"#, to: resource)
        let cached = try XCTUnwrap(Bundle(url: wrapper))
        XCTAssertEqual(cached.executableURL?.lastPathComponent, "PortsideRuntimeHost")
        let id = UUID()
        var registrations = 0
        let register: (URL, Bool) -> OSStatus = { url, force in
            XCTAssertEqual(url, wrapper)
            XCTAssertTrue(force)
            registrations += 1
            return 0
        }
        let legacy = try SteamProcessLauncher.openConfiguration(wrapper: wrapper, launchID: id, register: register)
        XCTAssertEqual(legacy.arguments, ["--launch-id", id.uuidString])

        info["CFBundleExecutable"] = "Sikarugir"
        info["Program Name and Path"] = "/Program Files (x86)/Steam/steam.exe"
        info["Program Flags"] = ""
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL, options: .atomic)
        try write(#"{"integration":"sikarugir","launchDiagnosticsVersion":1}"#, to: resource)
        try write("fixture", to: wrapper.appendingPathComponent("Contents/MacOS/Sikarugir"), executable: true)
        try write("fixture", to: wrapper.appendingPathComponent("Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk"), executable: true)
        let prefix = root.appendingPathComponent("Prefix")
        for name in ["system.reg", "user.reg", "userdef.reg", "drive_c/Program Files (x86)/Steam/steam.exe"] {
            try write("fixture", to: prefix.appendingPathComponent(name))
        }
        let link = wrapper.appendingPathComponent("Contents/SharedSupport/prefix")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: prefix)
        let current = try SteamProcessLauncher.openConfiguration(wrapper: wrapper, launchID: id, register: register)
        XCTAssertTrue(current.arguments.isEmpty)
        XCTAssertTrue(current.activates)
        XCTAssertEqual(registrations, 2)
        XCTAssertThrowsError(try SteamProcessLauncher.openConfiguration(wrapper: wrapper, launchID: id, register: { _, _ in -50 }))

        try FileManager.default.removeItem(at: PortsideSteamFlow.steamExecutable(prefix: prefix))
        XCTAssertThrowsError(try SteamProcessLauncher.openConfiguration(wrapper: wrapper, launchID: id, register: register))
        XCTAssertEqual(registrations, 2, "Incomplete setup must fail before registration or opening")
        withExtendedLifetime(cached) {}
    }

    private func write(_ text: String, to url: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }
}
