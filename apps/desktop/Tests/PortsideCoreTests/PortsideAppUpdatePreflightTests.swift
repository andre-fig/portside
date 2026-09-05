import XCTest
@testable import PortsideCore

@MainActor
final class PortsideAppUpdatePreflightTests: XCTestCase {
    func testNoUpdateCompletesAllWaitersAndStartsOnlyOneProbe() async {
        let session = PortsideAppUpdatePreflight()
        var checks = 0
        session.onStartCheck = { checks += 1 }
        let first = Task { await session.run() }
        let second = Task { await session.run() }
        await Task.yield()
        XCTAssertNil(session.outcome)
        session.checkCompleted()
        let outcomes = await [first.value, second.value]
        XCTAssertEqual(outcomes, [.noUpdate, .noUpdate])
        XCTAssertEqual(checks, 1)
        let repeated = await session.run()
        XCTAssertEqual(repeated, .noUpdate)
        XCTAssertEqual(checks, 1)
    }

    func testAvailableUpdateStartsOneInstallationBeforeBootstrapCanProceed() async {
        let session = PortsideAppUpdatePreflight()
        var installations = 0
        session.onStartCheck = {
            session.foundUpdate(version: "2", critical: false)
            session.checkCompleted()
            session.checkCompleted()
        }
        session.onStartInstallation = { installations += 1 }
        let task = Task { await session.run() }
        await Task.yield()
        XCTAssertEqual(session.phase, .installing)
        XCTAssertNil(session.outcome)
        XCTAssertEqual(installations, 1)
        session.willRelaunch()
        session.willRelaunch()
        let outcome = await task.value
        XCTAssertEqual(outcome, .relaunching)
        XCTAssertFalse(outcome.allowsBootstrap)
    }

    func testRequiredUpdateCannotBeSkippedToOpenSteam() async {
        let session = PortsideAppUpdatePreflight()
        session.onStartCheck = {
            session.foundUpdate(version: "2", critical: true)
            session.checkCompleted()
        }
        session.onStartInstallation = { session.installationCompleted(postponed: true) }
        let outcome = await session.run()
        XCTAssertFalse(outcome.allowsBootstrap)
        guard case .blocked = outcome else { return XCTFail("A required update must block bootstrap") }
    }

    func testNormalUpdateMayBePostponedWhenConfirmationIsRequired() async {
        let session = PortsideAppUpdatePreflight()
        session.onStartCheck = {
            session.foundUpdate(version: "2", critical: false)
            session.checkCompleted()
        }
        session.onStartInstallation = { session.installationCompleted(postponed: true) }
        let outcome = await session.run()
        XCTAssertTrue(outcome.allowsBootstrap)
    }

    func testFinishedCycleWithoutRelaunchIsNotSuccessfulInstallation() async {
        let session = PortsideAppUpdatePreflight()
        session.onStartCheck = {
            session.foundUpdate(version: "2", critical: false)
            session.checkCompleted()
        }
        session.onStartInstallation = { session.installationCompleted() }
        let outcome = await session.run()
        XCTAssertFalse(outcome.allowsBootstrap)
    }

    func testOfflineFeedDoesNotBlockValidInstalledVersion() async {
        let session = PortsideAppUpdatePreflight()
        session.onStartCheck = { session.checkCompleted(errorReason: "The update feed is temporarily unavailable.") }
        let outcome = await session.run()
        XCTAssertEqual(outcome, .recoverableFailure(reason: "The update feed is temporarily unavailable."))
        XCTAssertTrue(outcome.allowsBootstrap)
    }

    func testTimeoutDoesNotBlockValidVersionAndLateCallbackCannotInstall() async {
        let session = PortsideAppUpdatePreflight(checkTimeout: .milliseconds(5))
        var installations = 0
        session.onStartCheck = {}
        session.onStartInstallation = { installations += 1 }
        let outcome = await session.run()
        XCTAssertTrue(outcome.allowsBootstrap)
        session.foundUpdate(version: "2", critical: true)
        session.checkCompleted()
        XCTAssertEqual(installations, 0)
        XCTAssertEqual(session.outcome, outcome)
    }

    func testKnownRequiredUpdateCannotBecomeRecoverableOnProbeTimeout() async {
        let session = PortsideAppUpdatePreflight()
        session.onStartCheck = {
            session.foundUpdate(version: "2", critical: true)
            session.checkTimedOut()
        }
        let outcome = await session.run()
        XCTAssertFalse(outcome.allowsBootstrap)
    }

    func testInstallationTimeoutNeverReleasesBootstrap() async {
        let session = PortsideAppUpdatePreflight(installationTimeout: .milliseconds(5))
        session.onStartCheck = {
            session.foundUpdate(version: "2", critical: false)
            session.checkCompleted()
        }
        let outcome = await session.run()
        XCTAssertFalse(outcome.allowsBootstrap)
        session.installationCompleted(errorReason: "The download failed.")
        XCTAssertEqual(session.outcome, outcome)
    }

    func testVerifiedRelaunchStillChecksAgainAndReportsUpdatedVersion() async {
        let session = PortsideAppUpdatePreflight(previousRelaunch: .updated(version: "2"))
        var checks = 0
        session.onStartCheck = { checks += 1; session.checkCompleted() }
        let outcome = await session.run()
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(outcome, .updated(version: "2"))
    }

    func testFailedRelaunchBlocksAutomaticRetryLoopEvenWhenOfferIsAvailable() async {
        let blocked = PortsideAppUpdateOutcome.blocked(reason: "The previous update did not finish. Please try updating again.")
        let session = PortsideAppUpdatePreflight(previousRelaunch: blocked)
        var installations = 0
        session.onStartCheck = {
            session.foundUpdate(version: "2", critical: true)
            session.checkCompleted()
        }
        session.onStartInstallation = { installations += 1 }
        let outcome = await session.run()
        XCTAssertEqual(outcome, blocked)
        XCTAssertEqual(installations, 0)
    }

    func testFailedRelaunchRemainsBlockedWhenFeedTimesOut() async {
        let blocked = PortsideAppUpdateOutcome.blocked(reason: "The previous update did not finish. Please try updating again.")
        let session = PortsideAppUpdatePreflight(previousRelaunch: blocked)
        session.onStartCheck = { session.checkTimedOut() }
        let outcome = await session.run()
        XCTAssertEqual(outcome, blocked)
    }

    func testExplicitRetryCannotBypassFailedRelaunchWithoutUpdate() async {
        let blocked = PortsideAppUpdateOutcome.blocked(reason: "The expected update has not been installed.")
        for failure in [nil, "The feed is offline."] {
            let session = PortsideAppUpdatePreflight(previousRelaunch: blocked, allowsRelaunchRetry: true)
            session.onStartCheck = { session.checkCompleted(errorReason: failure) }
            let outcome = await session.run()
            XCTAssertEqual(outcome, blocked)
        }
        let timedOut = PortsideAppUpdatePreflight(previousRelaunch: blocked, allowsRelaunchRetry: true)
        timedOut.onStartCheck = { timedOut.checkTimedOut() }
        let outcome = await timedOut.run()
        XCTAssertEqual(outcome, blocked)
    }

    func testExplicitRetryThatFailsInstallationStillRequiresExpectedVersion() async {
        let blocked = PortsideAppUpdateOutcome.blocked(reason: "The expected update has not been installed.")
        let session = PortsideAppUpdatePreflight(previousRelaunch: blocked, allowsRelaunchRetry: true)
        session.onStartCheck = { session.foundUpdate(version: "2", critical: false); session.checkCompleted() }
        session.onStartInstallation = { session.installationCompleted(errorReason: "The download failed.") }
        let outcome = await session.run()
        XCTAssertEqual(outcome, blocked)
    }

    func testRelaunchReceiptRequiresExpectedBuildAndAcceptsLaterBuild() {
        let receipt = PortsideAppUpdateRelaunchReceipt(sourceVersion: "1", expectedVersion: "2")
        let compare: (String, String) -> ComparisonResult = { $0.compare($1, options: .numeric) }
        XCTAssertFalse(receipt.validate(currentVersion: "1", compare: compare).allowsBootstrap)
        XCTAssertEqual(receipt.validate(currentVersion: "2", compare: compare), .updated(version: "2"))
        XCTAssertEqual(receipt.validate(currentVersion: "3", compare: compare), .updated(version: "3"))
        let stale = PortsideAppUpdateRelaunchReceipt(sourceVersion: "2", expectedVersion: "1")
        XCTAssertFalse(stale.validate(currentVersion: "2", compare: compare).allowsBootstrap)
    }

    func testPhaseCallbacksAreEnglishAndFollowOneInstallationSequence() async {
        let session = PortsideAppUpdatePreflight()
        var phases: [String] = []
        session.onPhaseChanged = { phases.append($0.rawValue) }
        session.onStartCheck = { session.foundUpdate(version: "2", critical: true); session.checkCompleted() }
        session.onStartInstallation = { session.willRelaunch() }
        _ = await session.run()
        XCTAssertEqual(phases, ["checking", "installing", "relaunching"])
    }
}
