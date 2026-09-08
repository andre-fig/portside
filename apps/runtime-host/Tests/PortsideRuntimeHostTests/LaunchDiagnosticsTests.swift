import Foundation
import XCTest
@testable import PortsideRuntimeHost

final class LaunchDiagnosticsTests: XCTestCase {
    func testImmediateExitZeroAndNineRemainNormalExits() throws {
        for status in [0, 9] {
            let result = try runFixture(script: "#!/bin/sh\nexit \(status)\n")
            XCTAssertEqual(result.status, Int32(status))
            XCTAssertEqual(result.receipt["terminationStatus"] as? Int, status)
            XCTAssertEqual(result.receipt["terminationReason"] as? String, "exit")
            XCTAssertNil(result.receipt["signal"])
            XCTAssertTrue(result.log.contains("duration="))
            XCTAssertLessThan(result.receipt["duration"] as? Double ?? 90, 3)
        }
    }

    func testSignalNineIsNotExitNine() throws {
        let result = try runFixture(script: "#!/bin/sh\nkill -KILL $$\n")
        XCTAssertEqual(result.status, 137)
        XCTAssertEqual(result.receipt["terminationStatus"] as? Int, 9)
        XCTAssertEqual(result.receipt["terminationReason"] as? String, "uncaughtSignal")
        XCTAssertEqual(result.receipt["signal"] as? Int, 9)
        XCTAssertTrue(result.log.contains("terminationReason=uncaughtSignal signal=9"))
    }

    func testExecErrorHasDomainCodeAndNoFalseTermination() throws {
        let result = try runFixture(script: "#!/missing-portside-test-interpreter\n")
        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.receipt["phase"] as? String, "executionFailed")
        XCTAssertNil(result.receipt["terminationStatus"])
        XCTAssertTrue((result.receipt["executionError"] as? String)?.contains("code=") == true)
    }

    func testArgumentsAndSensitiveChildOutputAreSanitized() throws {
        let command = PortsideRuntimeHost.Command(label: "configured program", executable: URL(fileURLWithPath: "/runtime/bin/wine"), arguments: ["/Volumes/Personal/Private Game.exe", "-login", "private-user", "private-password"])
        let diagnostic = PortsideRuntimeHost.diagnosticCommand(command)
        XCTAssertFalse(diagnostic.contains("Private Game"))
        XCTAssertFalse(diagnostic.contains("private-user"))
        XCTAssertFalse(diagnostic.contains("private-password"))
        let result = try runFixture(script: "#!/bin/sh\necho 'steam -login private-user private-password'\necho 'Authorization: Bearer secret-value'\nexit 3\n")
        XCTAssertFalse(result.log.contains("private-user"))
        XCTAssertFalse(result.log.contains("private-password"))
        XCTAssertFalse(result.log.contains("secret-value"))
        XCTAssertTrue(result.log.contains("executable=$RUNTIME/wine"))
    }

    func testSymlinkPrefixResolvesToDisposableExternalDirectory() throws {
        let result = try runFixture(script: "#!/bin/sh\n[ -d \"$WINEPREFIX\" ] || exit 7\ncase \"$WINEPREFIX\" in */ExternalPrefix) exit 0 ;; *) exit 8 ;; esac\n")
        XCTAssertEqual(result.status, 0)
    }

    func testOptionalAddonsAreDeferredOnlyDuringPrefixCreation() throws {
        let script = "#!/bin/sh\ncase \"$WINEDLLOVERRIDES\" in *mscoree,mshtml=*) exit 23 ;; *) exit 0 ;; esac\n"
        XCTAssertEqual(try runFixture(script: script, arguments: ["--create-prefix"]).status, 23)
        XCTAssertEqual(try runFixture(script: script).status, 0)
        XCTAssertEqual(try runFixture(script: script, arguments: ["--program", "cmd"]).status, 0)
    }

    func testPrefixPreparationConfiguresOnlyCEFWithoutInheritingAddonDeferral() throws {
        let script = #"""
        #!/bin/sh
        if [ "$1" = "-u" ]; then
            [ "$2" = "-r" ] || exit 13
            case "$WINEDLLOVERRIDES" in *mscoree,mshtml=*) exit 0 ;; *) exit 8 ;; esac
        fi
        [ -z "$WINEDLLOVERRIDES" ] || exit 9
        [ "$1" = reg ] && [ "$2" = add ] || exit 10
        [ "$3" = 'HKCU\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides' ] || exit 11
        [ "$5" = vulkan-1 ] && [ "$9" = native,builtin ] || exit 12
        exit 0
        """#
        XCTAssertEqual(try runFixture(script: script, arguments: ["--create-prefix"]).status, 0)
        let failing = "#!/bin/sh\n[ \"$1\" = -u ] && exit 0\nexit 7\n"
        XCTAssertEqual(try runFixture(script: failing, arguments: ["--create-prefix"]).status, 7)
    }

    func testTerminalReceiptDoesNotWaitForInheritedOutputEOF() throws {
        let result = try runFixture(script: "#!/bin/sh\n(/bin/sleep 1; echo child-output-preserved) &\nexit 9\n", inspectReceiptBeforeExit: true)
        XCTAssertEqual(result.status, 9)
        XCTAssertTrue(result.log.contains("child-output-preserved"))
        XCTAssertLessThan(result.receipt["duration"] as? Double ?? 90, 0.8)
    }

    func testOutputLimitCannotExposeTailOfTruncatedCredentialLine() throws {
        let result = try runFixture(script: "#!/bin/sh\n/usr/bin/awk 'BEGIN {printf \"password=\"; for (i=0; i<80000; i++) printf \"x\"; print \"private-tail\"}'\nexit 3\n")
        XCTAssertFalse(result.log.contains("private-tail"))
        XCTAssertLessThan(result.log.utf8.count, 65_536)
    }

    func testInheritedOutputHasDeadlineAndDoesNotSignalDetachedWriter() async throws {
        let capture = try LaunchOutputCapture(log: { _ in })
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The second write happens after the receiver has closed. A pipe would
        // kill this shell with SIGPIPE before it can return the expected status.
        process.arguments = ["-c", "sleep 1; printf late-output; exit 23"]
        process.standardOutput = capture.writer
        process.standardError = FileHandle.nullDevice
        try process.run()
        try capture.writer.close()
        let started = Date()
        _ = await capture.finish(gracePeriod: 0.1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 23)
    }

    func testReceiptRetentionProtectsRecentLaunchesAndUnrelatedEntries() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("PortsideRetentionTests-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        let receipts = root.appendingPathComponent("RuntimeLaunches")
        try manager.createDirectory(at: receipts, withIntermediateDirectories: true)
        let now = Date()
        func receipt(age: TimeInterval, id: UUID = UUID()) throws -> URL {
            let file = receipts.appendingPathComponent(id.uuidString + ".json")
            try Data("{}".utf8).write(to: file)
            try manager.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
            return file
        }
        let currentID = UUID()
        let current = try receipt(age: 9 * 86400, id: currentID)
        let expired = try receipt(age: 8 * 86400)
        let excess = try receipt(age: 6000)
        for i in 0..<100 { _ = try receipt(age: Double(600 + i)) }
        let recent = try receipt(age: 10)
        let marker = root.appendingPathComponent("preserved-prefix-marker")
        try Data("keep".utf8).write(to: marker)
        let link = receipts.appendingPathComponent(UUID().uuidString + ".json")
        try manager.createSymbolicLink(at: link, withDestinationURL: marker)
        let unrelated = receipts.appendingPathComponent("unrelated.json")
        try Data("keep".utf8).write(to: unrelated)
        let directory = receipts.appendingPathComponent(UUID().uuidString + ".json")
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        PortsideRuntimeHost.pruneReceipts(in: receipts, preserving: currentID, now: now)
        XCTAssertFalse(manager.fileExists(atPath: expired.path))
        XCTAssertFalse(manager.fileExists(atPath: excess.path))
        for file in [current, recent, marker, link, unrelated, directory] {
            XCTAssertTrue(manager.fileExists(atPath: file.path))
        }
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "keep")
    }

    private func runFixture(script: String, inspectReceiptBeforeExit: Bool = false, arguments: [String] = []) throws -> (status: Int32, receipt: [String: Any], log: String) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("PortsideLaunchTests-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("PortsideBaseline.app")
        let executable = wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let builtHost = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("PortsideRuntimeHost")
        try manager.copyItem(at: builtHost, to: executable)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "PortsideRuntimeHost", "CFBundleIdentifier": "com.portside.runtime", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: wrapper.appendingPathComponent("Contents/Info.plist"))
        let configuration = wrapper.appendingPathComponent("Contents/Resources/portside-runtime.json")
        try manager.createDirectory(at: configuration.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":"test","wineRelativePath":"Contents/SharedSupport/engine","prefixRelativePath":"Contents/SharedSupport/prefix","winetricksRelativePath":"unused","steamExecutable":"steam.exe","wineDebug":"-all","environment":{}}"#.utf8).write(to: configuration)
        let wine = wrapper.appendingPathComponent("Contents/SharedSupport/engine/bin/wine")
        try manager.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script.utf8).write(to: wine)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        try manager.createSymbolicLink(at: wine.deletingLastPathComponent().appendingPathComponent("wineboot"), withDestinationURL: wine)
        let prefix = root.appendingPathComponent("ExternalPrefix")
        try manager.createDirectory(at: prefix, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: wrapper.appendingPathComponent("Contents/SharedSupport/prefix"), withDestinationURL: prefix)
        let home = root.appendingPathComponent("Home")
        let id = UUID()
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--launch-id", id.uuidString] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": home.path, "CFFIXED_USER_HOME": home.path]
        try process.run()
        let logs = home.appendingPathComponent("Library/Application Support/Portside/Logs")
        let receiptURL = logs.appendingPathComponent("RuntimeLaunches/\(id.uuidString).json")
        if inspectReceiptBeforeExit {
            let deadline = Date().addingTimeInterval(3)
            var terminal = false
            while Date() < deadline && process.isRunning {
                if let data = try? Data(contentsOf: receiptURL),
                   let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], value["phase"] as? String == "terminated" {
                    terminal = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            XCTAssertTrue(terminal)
            XCTAssertTrue(process.isRunning, "Host must preserve the detached child's output after recording the Wine exit")
        }
        process.waitUntilExit()
        let data = try Data(contentsOf: receiptURL)
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(receipt["launchID"] as? String, id.uuidString)
        let log = try String(contentsOf: logs.appendingPathComponent("runtime-host.log"), encoding: .utf8)
        XCTAssertFalse(log.contains(home.path))
        return (process.terminationStatus, receipt, log)
    }
}
