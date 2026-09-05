import XCTest
import Sparkle
import PortsideCore
@testable import Portside

@MainActor
final class PortsideUpdateCoordinatorTests: XCTestCase {
    func testFirstLaunchWithoutRuntimeOrSteamStartsSparkleAndImmediatelyProbes() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        XCTAssertEqual(fake.starts, 0, "Constructing the coordinator must remain inert until location validation")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Runtime").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Steam").path))
        var events: [String] = []
        fake.onProbe = {
            events.append("app_update_check")
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        }
        let outcome = await coordinator.runInitialCheck()
        if outcome.allowsBootstrap { events.append("runtime_download") }
        XCTAssertEqual(fake.starts, 1)
        XCTAssertEqual(fake.probes, 1)
        XCTAssertEqual(fake.installChecks, 0)
        XCTAssertEqual(outcome, .noUpdate)
        XCTAssertEqual(events, ["app_update_check", "runtime_download"])
    }

    func testLaunchProbeDoesNotDependOnAutomaticDownloadsPreference() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fake = FakeSparkleUpdater()
        fake.automaticallyDownloadsUpdates = false
        let coordinator = fixture.coordinator(fake: fake)
        fake.onProbe = {
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)))
        }
        let outcome = await coordinator.runInitialCheck()
        XCTAssertEqual(outcome, .noUpdate)
        XCTAssertEqual(fake.probes, 1)
    }

    func testConcurrentInitialCallsCannotStartDuplicateSparkleCycles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        let first = Task { await coordinator.runInitialCheck() }
        let second = Task { await coordinator.runInitialCheck() }
        while fake.probes == 0 { await Task.yield() }
        fake.sessionInProgress = false
        coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        let outcomes = await [first.value, second.value]
        XCTAssertEqual(outcomes, [.noUpdate, .noUpdate])
        XCTAssertEqual(fake.starts, 1)
        XCTAssertEqual(fake.probes, 1)
    }

    func testOfflineFeedIsRecoverableAndDoesNotStartInstallation() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        fake.onProbe = {
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: URLError(.notConnectedToInternet))
        }
        let outcome = await coordinator.runInitialCheck()
        XCTAssertTrue(outcome.allowsBootstrap)
        XCTAssertEqual(fake.installChecks, 0)
    }

    func testTimedOutProbeCannotInstallFromLateSparkleCallback() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake, timeout: .milliseconds(5))
        let outcome = await coordinator.runInitialCheck()
        XCTAssertTrue(outcome.allowsBootstrap)
        fake.sessionInProgress = false
        coordinator.updater(fixture.nativeUpdater, didFindValidUpdate: fixture.item(version: "2"))
        coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        XCTAssertEqual(fake.installChecks, 0)
    }

    func testAvailableUpdateMustRelaunchBeforeRuntimeIsPermitted() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        let item = fixture.item(version: "2")
        var events: [String] = []
        fake.onProbe = {
            events.append("app_update_check")
            coordinator.updater(fixture.nativeUpdater, didFindValidUpdate: item)
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        }
        fake.onInstall = {
            events.append("app_update_install")
            coordinator.updater(fixture.nativeUpdater, didFindValidUpdate: item)
            coordinator.updater(fixture.nativeUpdater, willInstallUpdate: item)
            coordinator.updaterWillRelaunchApplication(fixture.nativeUpdater)
        }
        let outcome = await coordinator.runInitialCheck()
        if outcome.allowsBootstrap { events.append("runtime_download") }
        XCTAssertEqual(outcome, .relaunching)
        XCTAssertEqual(events, ["app_update_check", "app_update_install"])
        XCTAssertEqual(fake.installChecks, 1)
        let receipt = try JSONDecoder().decode(PortsideAppUpdateRelaunchReceipt.self, from: Data(contentsOf: fixture.receiptURL))
        XCTAssertEqual(receipt.expectedVersion, "2")
        XCTAssertEqual(receipt.sourceVersion, "1")
    }

    func testFailedRelaunchChecksFeedButDoesNotRepeatInstallationUntilExplicitRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try JSONEncoder().encode(PortsideAppUpdateRelaunchReceipt(sourceVersion: "1", expectedVersion: "2")).write(to: fixture.receiptURL)
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        let item = fixture.item(version: "2")
        fake.onProbe = {
            coordinator.updater(fixture.nativeUpdater, didFindValidUpdate: item)
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        }
        let failed = await coordinator.runInitialCheck()
        XCTAssertFalse(failed.allowsBootstrap)
        XCTAssertEqual(fake.probes, 1)
        XCTAssertEqual(fake.installChecks, 0)
        fake.onInstall = {
            coordinator.updater(fixture.nativeUpdater, willInstallUpdate: item)
            coordinator.updaterWillRelaunchApplication(fixture.nativeUpdater)
        }
        let retried = await coordinator.retryInitialCheck()
        XCTAssertEqual(retried, .relaunching)
        XCTAssertEqual(fake.installChecks, 1)
        XCTAssertEqual(fake.probes, 2)
    }

    func testUpdatedRelaunchVerifiesExpectedBuildAndPerformsFreshProbe() async throws {
        let fixture = try Fixture(version: "2")
        defer { fixture.cleanUp() }
        try JSONEncoder().encode(PortsideAppUpdateRelaunchReceipt(sourceVersion: "1", expectedVersion: "2")).write(to: fixture.receiptURL)
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        fake.onProbe = {
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        }
        let outcome = await coordinator.runInitialCheck()
        XCTAssertEqual(outcome, .updated(version: "2"))
        XCTAssertEqual(fake.probes, 1)
        XCTAssertEqual(fake.installChecks, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.receiptURL.path))
    }

    func testExplicitRetryWithNoUpdateOrOfflineFeedCannotReleaseOldVersion() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try JSONEncoder().encode(PortsideAppUpdateRelaunchReceipt(sourceVersion: "1", expectedVersion: "3")).write(to: fixture.receiptURL)
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        fake.onProbe = {
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        }
        let failed = await coordinator.runInitialCheck()
        let noUpdateRetry = await coordinator.retryInitialCheck()
        XCTAssertFalse(failed.allowsBootstrap)
        XCTAssertFalse(noUpdateRetry.allowsBootstrap)
        fake.onProbe = {
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: URLError(.notConnectedToInternet))
        }
        let offlineRetry = await coordinator.retryInitialCheck()
        XCTAssertFalse(offlineRetry.allowsBootstrap)
        XCTAssertThrowsError(try coordinator.updater(fixture.nativeUpdater, shouldProceedWithUpdate: fixture.item(version: "2"), updateCheck: .updates))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.receiptURL.path))
    }

    func testExplicitRetryAfterSuccessfulProbeChecksFeedAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        fake.onProbe = {
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: nil)
        }
        let first = await coordinator.runInitialCheck()
        let retried = await coordinator.retryInitialCheck()
        XCTAssertEqual(first, .noUpdate)
        XCTAssertEqual(retried, .noUpdate)
        XCTAssertEqual(fake.starts, 1)
        XCTAssertEqual(fake.probes, 2)
    }

    func testCriticalAppcastItemCannotBeHiddenByPriorSkippedVersion() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fake = FakeSparkleUpdater()
        let coordinator = fixture.coordinator(fake: fake)
        fake.onProbe = {
            coordinator.observeAppcastItems([fixture.item(version: "2", critical: true)])
            fake.sessionInProgress = false
            // A background Sparkle probe reports no update if the item had
            // previously been skipped while it was still a normal update.
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updateInformation, error: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)))
        }
        fake.onInstall = {
            fake.sessionInProgress = false
            coordinator.updater(fixture.nativeUpdater, didFinishUpdateCycleFor: .updates, error: nil)
        }
        let outcome = await coordinator.runInitialCheck()
        XCTAssertEqual(fake.installChecks, 1)
        XCTAssertFalse(outcome.allowsBootstrap)
    }

    func testSparkleDelegateSelectorsAreActuallyImplemented() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let coordinator = fixture.coordinator(fake: FakeSparkleUpdater())
        XCTAssertTrue(coordinator.responds(to: #selector(SPUUpdaterDelegate.updater(_:didFinishUpdateCycleFor:error:))))
        XCTAssertTrue(coordinator.responds(to: #selector(SPUUpdaterDelegate.updater(_:mayPerform:))))
        XCTAssertTrue(coordinator.responds(to: #selector(SPUUpdaterDelegate.updater(_:shouldProceedWithUpdate:updateCheck:))))
        XCTAssertTrue(coordinator.responds(to: #selector(SPUUpdaterDelegate.updaterWillRelaunchApplication(_:))))
    }

    func testNormalAutomaticUpdateInstallsSilentlyAndWritesReceiptBeforeRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let standard = RecordingStandardUserDriver(hostBundle: fixture.bundle, delegate: nil)
        let driver = PortsideInitialUpdateUserDriver(standard: standard)
        driver.isInitialInstallation = { true }
        driver.shouldAutomaticallyInstall = { true }
        var receiptWrites = 0
        driver.prepareInstallation = { receiptWrites += 1; return true }
        var choices: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: fixture.item(version: "2"), state: try fixture.state(stage: .notDownloaded)) { choices.append($0) }
        driver.showDownloadInitiated(cancellation: {})
        XCTAssertEqual(standard.offers, 0)
        XCTAssertEqual(standard.downloadWindows, 0)
        XCTAssertEqual(choices, [.install])
        driver.showReady { choices.append($0) }
        XCTAssertEqual(receiptWrites, 1)
        XCTAssertEqual(choices, [.install, .install])
        XCTAssertEqual(standard.readyWindows, 0)
    }

    func testCriticalAutomaticUpdateUsesStandardSparkleProgress() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let standard = RecordingStandardUserDriver(hostBundle: fixture.bundle, delegate: nil)
        let driver = PortsideInitialUpdateUserDriver(standard: standard)
        driver.isInitialInstallation = { true }
        driver.shouldAutomaticallyInstall = { true }
        driver.prepareInstallation = { true }
        let item = fixture.item(version: "2", critical: true)
        XCTAssertTrue(item.isCriticalUpdate)
        var choice: SPUUserUpdateChoice?
        driver.showUpdateFound(with: item, state: try fixture.state(stage: .notDownloaded)) { choice = $0 }
        driver.showDownloadInitiated(cancellation: {})
        XCTAssertEqual(choice, .install)
        XCTAssertEqual(standard.downloadWindows, 1)
    }

    func testDisabledAutomaticPolicyRequiresStandardConfirmation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let standard = RecordingStandardUserDriver(hostBundle: fixture.bundle, delegate: nil)
        let driver = PortsideInitialUpdateUserDriver(standard: standard)
        driver.isInitialInstallation = { true }
        driver.shouldAutomaticallyInstall = { false }
        var choice: SPUUserUpdateChoice?
        driver.showUpdateFound(with: fixture.item(version: "2"), state: try fixture.state(stage: .notDownloaded)) { choice = $0 }
        XCTAssertEqual(standard.offers, 1)
        XCTAssertNil(choice)
        standard.offerReply?(.dismiss)
        XCTAssertEqual(choice, .dismiss)
    }

    func testAutomaticPolicyDoesNotSilentlyAcceptMajorOrInformationalUpgrade() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let standard = RecordingStandardUserDriver(hostBundle: fixture.bundle, delegate: nil)
        let driver = PortsideInitialUpdateUserDriver(standard: standard)
        driver.isInitialInstallation = { true }
        driver.shouldAutomaticallyInstall = { true }
        let major = fixture.item(version: "2", minimumAutoUpdateVersion: "2")
        XCTAssertTrue(major.isMajorUpgrade)
        driver.showUpdateFound(with: major, state: try fixture.state(stage: .notDownloaded)) { _ in XCTFail("Major upgrade needs standard confirmation") }
        let information = fixture.item(version: "2", informationOnly: true)
        XCTAssertTrue(information.isInformationOnlyUpdate)
        driver.showUpdateFound(with: information, state: try fixture.state(stage: .notDownloaded)) { _ in XCTFail("Informational update cannot automatically install") }
        XCTAssertEqual(standard.offers, 2)
    }

    func testFailedReceiptCancelsInstallationBeforeAutomaticRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let standard = RecordingStandardUserDriver(hostBundle: fixture.bundle, delegate: nil)
        let driver = PortsideInitialUpdateUserDriver(standard: standard)
        driver.isInitialInstallation = { true }
        driver.shouldAutomaticallyInstall = { true }
        driver.prepareInstallation = { false }
        var choices: [SPUUserUpdateChoice] = []
        driver.showUpdateFound(with: fixture.item(version: "2"), state: try fixture.state(stage: .notDownloaded)) { choices.append($0) }
        driver.showReady { choices.append($0) }
        XCTAssertEqual(choices, [.install, .skip])
    }

    func testLaterScheduledUpdatesKeepStandardSparklePolicy() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let standard = RecordingStandardUserDriver(hostBundle: fixture.bundle, delegate: nil)
        let driver = PortsideInitialUpdateUserDriver(standard: standard)
        driver.isInitialInstallation = { false }
        driver.shouldAutomaticallyInstall = { true }
        driver.showUpdateFound(with: fixture.item(version: "2"), state: try fixture.state(stage: .notDownloaded)) { _ in XCTFail("Scheduled updates must remain controlled by Sparkle") }
        XCTAssertEqual(standard.offers, 1)
    }
}

@MainActor
private final class FakeSparkleUpdater: PortsideSparkleUpdating {
    var automaticallyDownloadsUpdates = true
    var sessionInProgress = false
    var canCheckForUpdates: Bool { !sessionInProgress }
    var starts = 0
    var probes = 0
    var installChecks = 0
    var onProbe: (() -> Void)?
    var onInstall: (() -> Void)?
    func start() throws { starts += 1 }
    func checkForUpdateInformation() { probes += 1; sessionInProgress = true; onProbe?() }
    func checkForUpdates() { installChecks += 1; sessionInProgress = true; onInstall?() }
}

@MainActor
private struct Fixture {
    let root: URL
    let bundle: Bundle
    let nativeUpdater: SPUUpdater
    var receiptURL: URL { root.appendingPathComponent("receipt.json") }

    init(version: String = "1") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Portside-update-tests-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = root.appendingPathComponent("Portside.app", isDirectory: true)
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.portside.tests.\(UUID().uuidString)",
            "CFBundleName": "Portside", "CFBundlePackageType": "APPL", "CFBundleVersion": version,
            "SUFeedURL": "https://updates.example.com/appcast.xml", "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
            "SUEnableAutomaticChecks": false, "SUAutomaticallyUpdate": true
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        bundle = try XCTUnwrap(Bundle(url: bundleURL))
        nativeUpdater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil), delegate: nil)
    }

    func coordinator(fake: FakeSparkleUpdater, timeout: Duration = .seconds(20)) -> PortsideUpdateCoordinator {
        PortsideUpdateCoordinator(isCommercialBuild: true, bundle: bundle, receiptURL: receiptURL, checkTimeout: timeout, makeUpdater: { _, _, _ in fake })
    }

    func item(version: String, critical: Bool = false, minimumAutoUpdateVersion: String? = nil, informationOnly: Bool = false) -> SUAppcastItem {
        // Sparkle's public fixture initializer is deprecated for OS-dependent
        // fields; these tests use only its stable build number and enclosure.
        var dictionary: [String: Any] = ["enclosure": ["url": "https://updates.example.com/Portside.zip", "sparkle:version": version]]
        if critical { dictionary["sparkle:criticalUpdate"] = [String: String]() }
        if let minimumAutoUpdateVersion { dictionary["sparkle:minimumAutoupdateVersion"] = minimumAutoUpdateVersion }
        if informationOnly {
            dictionary = ["sparkle:version": version, "link": "https://updates.example.com/info"]
        }
        if minimumAutoUpdateVersion != nil { return MajorUpgradeAppcastItem(dictionary: dictionary)! }
        return SUAppcastItem(dictionary: dictionary)!
    }

    func state(stage: SPUUserUpdateStage) throws -> SPUUserUpdateState {
        // Exercise the public NSSecureCoding initializer with Sparkle 2.9.6's
        // serialized state keys; no private initializer or installer is invoked.
        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        archive.encode(stage.rawValue, forKey: "SPUUserUpdateStateStage")
        archive.encode(true, forKey: "SPUUserUpdateStateUserInitiated")
        archive.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
        return try XCTUnwrap(SPUUserUpdateState(coder: decoder))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private final class MajorUpgradeAppcastItem: SUAppcastItem, @unchecked Sendable {
    // Production Sparkle resolves this against the host version. The public
    // dictionary fixture initializer does not resolve OS/host-dependent state.
    override var isMajorUpgrade: Bool { true }
}

@MainActor
private final class RecordingStandardUserDriver: SPUStandardUserDriver {
    var offers = 0
    var downloadWindows = 0
    var readyWindows = 0
    var offerReply: ((SPUUserUpdateChoice) -> Void)?
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        offers += 1
        offerReply = reply
    }
    override func showDownloadInitiated(cancellation: @escaping () -> Void) { downloadWindows += 1 }
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { readyWindows += 1 }
}
