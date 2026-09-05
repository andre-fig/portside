import XCTest
import Darwin
@testable import Portside

final class PortsideRuntimeUpdaterMigrationTests: XCTestCase, @unchecked Sendable {
    func testOnlySameUserExactRuntimeUpdaterIsTerminated() async throws {
        let updater = process(pid: 100)
        let compatibility = process(pid: 101, arguments: ["--wrapper", "/temporary/wrapper"])
        let steam = process(pid: 102, name: "steam_osx", arguments: ["--runtime-updater"])
        let otherUser = process(pid: 103, user: 999)
        let extraArguments = process(pid: 104, arguments: ["--runtime-updater", "--wrapper", "/temporary/wrapper"])
        let unrelatedURL = URL(fileURLWithPath: "/temporary/Other.app/Contents/MacOS/PortsideAgent")
        let unrelated = PortsideRuntimeUpdaterProcess(pid: 105, user: 501, startedSeconds: 1000, startedMicroseconds: 50, executable: unrelatedURL, arguments: [unrelatedURL.path, "--runtime-updater"])
        let controller = FakeUpdaterProcesses(processes: [updater, compatibility, steam, otherUser, extraArguments, unrelated])
        let count = try await PortsideRuntimeUpdaterMigration.quiesce(controller: controller)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(controller.signalled, [100])
        XCTAssertEqual(controller.signatureChecks, [100])
    }

    func testInvalidSignatureNeverSignalsAndBlocksPreflight() async {
        let controller = FakeUpdaterProcesses(processes: [process(pid: 100)])
        controller.signatureValid = false
        do {
            _ = try await PortsideRuntimeUpdaterMigration.quiesce(controller: controller)
            XCTFail("Unverified updater must not remain active during preflight")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Portside could not pause its background updater. Close other Portside windows and try again.")
        }
        XCTAssertTrue(controller.signalled.isEmpty)
    }

    func testExitedOrReusedPIDIsNotSignalled() async throws {
        let controller = FakeUpdaterProcesses(processes: [process(pid: 100)])
        controller.alive.remove(100)
        let count = try await PortsideRuntimeUpdaterMigration.quiesce(controller: controller)
        XCTAssertEqual(count, 0)
        XCTAssertTrue(controller.signalled.isEmpty)
    }

    func testTerminationFailurePreventsPreflightWithoutForcedKill() async {
        let controller = FakeUpdaterProcesses(processes: [process(pid: 100)])
        controller.terminationFails = true
        do {
            _ = try await PortsideRuntimeUpdaterMigration.quiesce(controller: controller)
            XCTFail("An active legacy downloader must block preflight")
        } catch {}
        XCTAssertEqual(controller.signalled, [100])
        XCTAssertTrue(controller.alive.contains(100))
    }

    func testUnresponsiveUpdaterTimesOutWithoutSecondSignal() async {
        let controller = FakeUpdaterProcesses(processes: [process(pid: 100)])
        controller.exitsOnTermination = false
        do {
            _ = try await PortsideRuntimeUpdaterMigration.quiesce(controller: controller, timeout: .milliseconds(5))
            XCTFail("An active legacy downloader must block preflight")
        } catch {}
        XCTAssertEqual(controller.signalled, [100])
    }

    func testNoRuntimeUpdaterDoesNotRequireOrInspectSigningIdentity() async throws {
        let controller = FakeUpdaterProcesses(processes: [process(pid: 101, arguments: ["--wrapper", "/temporary/wrapper"])])
        let count = try await PortsideRuntimeUpdaterMigration.quiesce(controller: controller)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(controller.publisherReads, 0)
    }

    private func process(pid: pid_t, user: uid_t = 501, name: String = "PortsideAgent", arguments: [String] = ["--runtime-updater"]) -> PortsideRuntimeUpdaterProcess {
        let executable = URL(fileURLWithPath: "/temporary/Portside.app/Contents/Helpers/PortsideAgent.app/Contents/MacOS/\(name)")
        return PortsideRuntimeUpdaterProcess(pid: pid, user: user, startedSeconds: 1000, startedMicroseconds: 50, executable: executable, arguments: [executable.path] + arguments)
    }
}

/// Every test uses this in-memory controller. No real process is signalled.
private final class FakeUpdaterProcesses: PortsideRuntimeUpdaterProcessControlling, @unchecked Sendable {
    let currentUser: uid_t = 501
    let processes: [PortsideRuntimeUpdaterProcess]
    var signatureValid = true
    var terminationFails = false
    var exitsOnTermination = true
    var alive: Set<pid_t>
    var signalled: [pid_t] = []
    var signatureChecks: [pid_t] = []
    var publisherReads = 0
    init(processes: [PortsideRuntimeUpdaterProcess]) { self.processes = processes; alive = Set(processes.map(\.pid)) }
    func applicationPublisher() throws -> String { publisherReads += 1; return "TESTPUBLISHER" }
    func candidates() throws -> [PortsideRuntimeUpdaterProcess] { processes }
    func hasValidAgentSignature(_ process: PortsideRuntimeUpdaterProcess, publisher: String) -> Bool {
        signatureChecks.append(process.pid)
        return signatureValid && publisher == "TESTPUBLISHER"
    }
    func stillRunning(_ process: PortsideRuntimeUpdaterProcess) -> Bool { alive.contains(process.pid) }
    func terminate(_ process: PortsideRuntimeUpdaterProcess, publisher: String) throws {
        signalled.append(process.pid)
        if terminationFails { throw PortsideRuntimeUpdaterMigrationError.couldNotStop }
        if exitsOnTermination { alive.remove(process.pid) }
    }
}
