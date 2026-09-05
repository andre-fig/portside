import Foundation
import XCTest
@testable import PortsideRuntimeHost

final class BundleResolutionTests: XCTestCase {
    func testHostResolvesAppBundleInsteadOfContentsDirectory() throws {
        let root = try fixtureBundle()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let bundle = try XCTUnwrap(Bundle(url: root))
        XCTAssertEqual(try PortsideRuntimeHost.bundleURL(bundle: bundle).standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(bundle.executableURL?.lastPathComponent, "PortsideRuntimeHost")
    }

    func testHostResolvesResourcesAfterBundleMove() throws {
        let root = try fixtureBundle()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let moved = root.deletingLastPathComponent().appendingPathComponent("Renamed runtime.app")
        try FileManager.default.moveItem(at: root, to: moved)
        XCTAssertEqual(try PortsideRuntimeHost.loadConfiguration(bundle: moved).version, "1.2.3")
        XCTAssertEqual(try PortsideRuntimeHost.bundleURL(bundle: XCTUnwrap(Bundle(url: moved))).standardizedFileURL, moved.standardizedFileURL)
    }

    func testBundleDiagnosticContainsLocationExistenceSignatureAndRejection() throws {
        let root = try fixtureBundle()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let executable = try XCTUnwrap(Bundle(url: root)?.executableURL)
        let diagnostic = PortsideRuntimeHost.bundleRejectionDiagnostic(bundleURL: root, executable: executable, reason: "The runtime host executable resolves outside its bundle")
        XCTAssertTrue(diagnostic.contains("bundle_url=\(root.absoluteString)"))
        XCTAssertTrue(diagnostic.contains("helper_url=\(executable.absoluteString)"))
        XCTAssertTrue(diagnostic.contains("file_exists=true"))
        XCTAssertTrue(diagnostic.contains("signature=invalid:OSStatus="))
        XCTAssertTrue(diagnostic.contains("reason=The runtime host executable resolves outside its bundle"))
    }

    func testMissingExecutableDiagnosticAndPersonalPathsAreSanitized() {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads/PortsideBaseline.app")
        let missing = root.appendingPathComponent("Contents/MacOS/MissingHost")
        let diagnostic = PortsideRuntimeHost.bundleRejectionDiagnostic(bundleURL: root, executable: missing, reason: "The runtime host executable is missing")
        XCTAssertTrue(diagnostic.contains("file_exists=false"))
        XCTAssertTrue(diagnostic.contains("signature=unavailable:OSStatus="))
        XCTAssertFalse(diagnostic.contains(NSHomeDirectory()))
        XCTAssertTrue(diagnostic.contains("$USER_HOME"))
    }

    func testActualHostStartsFromMovedBundleWithUnrelatedWorkingDirectory() throws {
        let root = try fixtureBundle()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let builtHost = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("PortsideRuntimeHost")
        let executable = root.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: builtHost, to: executable)
        let engineWine = root.appendingPathComponent("Contents/SharedSupport/engine/bin/wine")
        try FileManager.default.createDirectory(at: engineWine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: engineWine, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        let moved = root.deletingLastPathComponent().appendingPathComponent("Moved runtime.app")
        try FileManager.default.moveItem(at: root, to: moved)

        // Foundation honors CFFIXED_USER_HOME. Keep the host's prefix and logs
        // inside this fixture, without touching any installed runtime or user log.
        let disposableHome = root.deletingLastPathComponent().appendingPathComponent("DisposableHome")
        let process = Process()
        process.executableURL = moved.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        process.arguments = ["--version"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": disposableHome.path, "CFFIXED_USER_HOME": disposableHome.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let log = try String(contentsOf: disposableHome.appendingPathComponent("Library/Application Support/Portside/Logs/runtime-host.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("finished version status=0"))
        XCTAssertFalse(log.contains("notInBundle"))
    }

    private func fixtureBundle() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PortsideHostTests-\(UUID().uuidString)").appendingPathComponent("PortsideBaseline.app")
        let executable = root.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "PortsideRuntimeHost", "CFBundleIdentifier": "com.portside.runtime", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: root.appendingPathComponent("Contents/Info.plist"))
        let resource = root.appendingPathComponent("Contents/Resources/portside-runtime.json")
        try FileManager.default.createDirectory(at: resource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":"1.2.3","wineRelativePath":"Contents/SharedSupport/engine","prefixRelativePath":"Contents/SharedSupport/prefix","winetricksRelativePath":"Contents/SharedSupport/winetricks/src/winetricks","steamExecutable":"steam.exe","wineDebug":"-all","environment":{}}"#.utf8).write(to: resource)
        return root
    }
}
