import Foundation
import XCTest
@testable import PortsideRuntimeHost

final class SikarugirIntegrationTests: XCTestCase {
    func testSteamCannotAccidentallyUseTheMaintenanceHostAsAProxy() throws {
        let result = try runFixture(launcher: "exit 23", wine: "exit 91")
        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.receipt["phase"] as? String, "executionFailed")
    }

    func testSteamInstallationUsesTheSikarugirWinetricksEntryPoint() throws {
        let launcher = "[ $# -eq 2 ] && [ \"$1\" = WSS-winetricks ] && [ \"$2\" = steam ] || exit 90\nexit 0"
        XCTAssertEqual(try runFixture(launcher: launcher, wine: "exit 91", arguments: ["--winetricks", "-q", "steam"]).status, 0)
    }

    func testExistingPrefixPreparationPreservesMarkerAndDoesNotApplyWine11CEFPolicy() throws {
        let wine = #"""
        [ "$1" = wineboot.exe ] && [ "$2" = -u ] && [ "$3" = -r ] && [ $# -eq 3 ] || exit 90
        [ "$(cat "$WINEPREFIX/preservation-marker")" = preserve ] || exit 91
        case "$WINEDLLOVERRIDES" in *mscoree,mshtml=*) ;; *) exit 92 ;; esac
        exit 0
        """#
        XCTAssertEqual(try runFixture(launcher: "exit 94", wine: wine, arguments: ["--create-prefix"]).status, 0)
    }

    func testNewPrefixWaitsForRegistryFilesWrittenAfterWinebootExit() throws {
        let wine = #"""
        (sleep 1; for name in system.reg user.reg userdef.reg; do printf registry > "$WINEPREFIX/$name"; done) >/dev/null 2>&1 &
        exit 0
        """#
        XCTAssertEqual(try runFixture(launcher: "exit 94", wine: wine, arguments: ["--create-prefix"], freshPrefix: true).status, 0)
    }

    func testComponentSetupDoesNotInheritPreparationAddonDeferral() throws {
        let launcher = "[ -z \"$WINEDLLOVERRIDES\" ] || exit 90\nexit 0"
        XCTAssertEqual(try runFixture(launcher: launcher, wine: "exit 91", arguments: ["--winetricks", "steam"]).status, 0)
    }

    func testMissingSDKOrEscapingLauncherCannotFallBackToWine() throws {
        for invalid in ["missing-sdk", "escaping-launcher"] {
            let result = try runFixture(launcher: "exit 0", wine: "exit 91", invalid: invalid)
            XCTAssertEqual(result.status, 1)
            XCTAssertEqual(result.receipt["phase"] as? String, "executionFailed")
            XCTAssertFalse(result.log.contains("starting Sikarugir"))
        }
    }

    func testUnknownIntegrationDoesNotSilentlyUseDirectWine() throws {
        let result = try runFixture(launcher: "exit 0", wine: "exit 91", invalid: "unknown-integration")
        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.receipt["phase"] as? String, "executionFailed")
    }

    private func runFixture(launcher: String, wine: String, arguments: [String] = [], invalid: String? = nil, freshPrefix: Bool = false) throws -> (status: Int32, receipt: [String: Any], log: String) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("PortsideSikarugirTests-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("Runtime.app")
        func script(_ path: URL, _ body: String) throws {
            try manager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: path)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        let executable = wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let builtHost = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("PortsideRuntimeHost")
        try manager.copyItem(at: builtHost, to: executable)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Sikarugir", "CFBundleIdentifier": "com.portside.runtime", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: wrapper.appendingPathComponent("Contents/Info.plist"))
        let config = wrapper.appendingPathComponent("Contents/Resources/portside-runtime.json")
        try manager.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let integration = invalid == "unknown-integration" ? "unknown" : "sikarugir"
        let configuration: [String: Any] = ["integration": integration, "version": "1.2.3", "wineRelativePath": "Contents/SharedSupport/wine", "prefixRelativePath": "Contents/SharedSupport/prefix", "winetricksRelativePath": "Contents/SharedSupport/winetricks", "steamExecutable": "steam.exe", "wineDebug": "-all", "environment": [:]]
        try JSONSerialization.data(withJSONObject: configuration).write(to: config)
        let launcherURL = wrapper.appendingPathComponent("Contents/MacOS/Sikarugir")
        if invalid == "escaping-launcher" {
            let outside = root.appendingPathComponent("UnrelatedLauncher")
            try script(outside, launcher)
            try manager.createSymbolicLink(at: launcherURL, withDestinationURL: outside)
        } else { try script(launcherURL, launcher) }
        if invalid != "missing-sdk" {
            try script(wrapper.appendingPathComponent("Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk"), "exit 0")
        }
        let wineURL = wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wine")
        try script(wineURL, wine)
        try manager.createSymbolicLink(at: wineURL.deletingLastPathComponent().appendingPathComponent("wineboot"), withDestinationURL: wineURL)
        let prefix = root.appendingPathComponent("ExternalPrefix")
        try manager.createDirectory(at: prefix, withIntermediateDirectories: true)
        if !freshPrefix {
            for name in ["system.reg", "user.reg", "userdef.reg"] { try Data("registry".utf8).write(to: prefix.appendingPathComponent(name)) }
        }
        let marker = prefix.appendingPathComponent("preservation-marker")
        try Data("preserve".utf8).write(to: marker)
        try manager.createSymbolicLink(at: wrapper.appendingPathComponent("Contents/SharedSupport/prefix"), withDestinationURL: prefix)
        let home = root.appendingPathComponent("Home")
        let id = UUID()
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--launch-id", id.uuidString] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": home.path, "CFFIXED_USER_HOME": home.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "preserve")
        if freshPrefix {
            for name in ["system.reg", "user.reg", "userdef.reg"] { XCTAssertTrue(manager.fileExists(atPath: prefix.appendingPathComponent(name).path)) }
        }
        let logs = home.appendingPathComponent("Library/Application Support/Portside/Logs")
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: logs.appendingPathComponent("RuntimeLaunches/\(id.uuidString).json"))) as? [String: Any])
        return (process.terminationStatus, receipt, try String(contentsOf: logs.appendingPathComponent("runtime-host.log"), encoding: .utf8))
    }
}
