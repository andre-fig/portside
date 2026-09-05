import XCTest
@testable import PortsideCore

final class PortsideBootstrapTests: XCTestCase {
    func testEveryFreshProcessRequiresLocationAndAppCheckWithoutRuntimeOrSteamState() {
        var bootstrap = PortsideBootstrap()
        XCTAssertEqual(bootstrap.state, .checkingInstallationLocation)
        XCTAssertFalse(bootstrap.advance(to: .installingRuntime))
        XCTAssertFalse(bootstrap.advance(to: .launchingSteam))
        XCTAssertTrue(bootstrap.confirmInstallation())
        XCTAssertEqual(bootstrap.state, .checkingAppUpdate)
        XCTAssertFalse(bootstrap.advance(to: .checkingRuntime))
        XCTAssertFalse(bootstrap.advance(to: .installingRuntime))
        XCTAssertFalse(bootstrap.advance(to: .checkingSteam))
        XCTAssertFalse(bootstrap.advance(to: .launchingSteam))
    }

    func testCompletedPreflightPermitsOrderedBootstrapExactlyOnce() {
        var bootstrap = PortsideBootstrap()
        XCTAssertTrue(bootstrap.confirmInstallation())
        XCTAssertTrue(bootstrap.finishAppUpdate(allowsBootstrap: true))
        XCTAssertFalse(bootstrap.finishAppUpdate(allowsBootstrap: true))
        XCTAssertEqual(bootstrap.state, .checkingRuntime)
        XCTAssertFalse(bootstrap.advance(to: .launchingSteam))
        XCTAssertTrue(bootstrap.advance(to: .installingRuntime))
        XCTAssertFalse(bootstrap.advance(to: .installingRuntime))
        XCTAssertTrue(bootstrap.advance(to: .checkingSteam))
        XCTAssertFalse(bootstrap.advance(to: .checkingSteam))
        XCTAssertTrue(bootstrap.advance(to: .launchingSteam))
        XCTAssertFalse(bootstrap.advance(to: .launchingSteam))
        XCTAssertTrue(bootstrap.advance(to: .ready))
    }

    func testMandatoryUpdateCannotStartRuntimeOrSteamBeforeRelaunch() {
        var bootstrap = PortsideBootstrap()
        XCTAssertTrue(bootstrap.confirmInstallation())
        XCTAssertTrue(bootstrap.advance(to: .installingAppUpdate))
        XCTAssertFalse(bootstrap.advance(to: .installingAppUpdate))
        XCTAssertFalse(bootstrap.advance(to: .installingRuntime))
        XCTAssertFalse(bootstrap.advance(to: .launchingSteam))
        XCTAssertTrue(bootstrap.advance(to: .relaunching))
        XCTAssertFalse(bootstrap.finishAppUpdate(allowsBootstrap: true))
        XCTAssertFalse(bootstrap.advance(to: .checkingRuntime))
        XCTAssertFalse(bootstrap.retry())
        // Nothing persists a transient phase. The next process starts afresh.
        XCTAssertEqual(PortsideBootstrap().state, .checkingInstallationLocation)
    }

    func testBlockedBuildCannotOpenSteamAndRetryRequiresBothGatesAgain() {
        var bootstrap = PortsideBootstrap()
        XCTAssertTrue(bootstrap.confirmInstallation())
        XCTAssertTrue(bootstrap.finishAppUpdate(allowsBootstrap: false))
        XCTAssertEqual(bootstrap.state, .failed)
        XCTAssertFalse(bootstrap.advance(to: .checkingRuntime))
        XCTAssertFalse(bootstrap.advance(to: .launchingSteam))
        XCTAssertFalse(bootstrap.finishAppUpdate(allowsBootstrap: true))
        XCTAssertTrue(bootstrap.retry())
        XCTAssertFalse(bootstrap.installationConfirmed)
        XCTAssertFalse(bootstrap.appUpdateCompleted)
    }

    func testMoveOnlyRelaunchesAndNeverResumesOldProcess() {
        var bootstrap = PortsideBootstrap()
        XCTAssertTrue(bootstrap.advance(to: .movingToApplications))
        XCTAssertFalse(bootstrap.advance(to: .movingToApplications))
        XCTAssertFalse(bootstrap.confirmInstallation())
        XCTAssertTrue(bootstrap.advance(to: .relaunching))
        XCTAssertFalse(bootstrap.advance(to: .checkingAppUpdate))
        XCTAssertFalse(bootstrap.finishAppUpdate(allowsBootstrap: true))
    }
}
