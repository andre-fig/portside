import XCTest
import Sparkle
import PortsideCore
@testable import Portside

/// Opt-in integration evidence only: no model, runtime service, Steam process,
/// or installation request is ever started by this test.
@MainActor
final class PortsideInstalledSparkleProbeTests: XCTestCase {
    func testInstalledBundlePerformsRealSparkleProbeWithoutInstalling() async throws {
        guard let path = ProcessInfo.processInfo.environment["PORTSIDE_VALIDATION_APP_BUNDLE"] else {
            throw XCTSkip("Set PORTSIDE_VALIDATION_APP_BUNDLE explicitly to probe a signed validation app.")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path == "/Applications/Portside.app" else {
            throw XCTSkip("The real Sparkle probe is restricted to the installed /Applications/Portside.app bundle.")
        }
        _ = try PortsideApplicationSignature.validate(bundleURL: url)
        let bundle = try XCTUnwrap(Bundle(url: url))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Portside-real-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var adapter: ProbeOnlySparkleUpdater?
        let coordinator = PortsideUpdateCoordinator(isCommercialBuild: true, bundle: bundle, receiptURL: temporary.appendingPathComponent("receipt.json"), checkTimeout: .seconds(30)) { bundle, driver, delegate in
            let wrapper = ProbeOnlySparkleUpdater(bundle: bundle, driver: driver, delegate: delegate)
            adapter = wrapper
            return wrapper
        }
        let outcome = await coordinator.runInitialCheck()
        XCTAssertEqual(adapter?.probeCount, 1)
        XCTAssertEqual(adapter?.refusedInstallation, false, "The feed advanced; installation was refused by this test's adapter.")
        XCTAssertEqual(outcome, .noUpdate, "A real no-update response is required; offline or timeout is not proof.")
    }
}

@MainActor
private final class ProbeOnlySparkleUpdater: NSObject, PortsideSparkleUpdating, SPUUpdaterDelegate {
    private var updater: SPUUpdater!
    private weak var delegate: (any SPUUpdaterDelegate)?
    private var didStartProbe = false
    private(set) var probeCount = 0
    private(set) var refusedInstallation = false
    var automaticallyDownloadsUpdates: Bool { updater.automaticallyDownloadsUpdates }
    var sessionInProgress: Bool { updater.sessionInProgress }
    var canCheckForUpdates: Bool { updater.canCheckForUpdates }

    init(bundle: Bundle, driver: any SPUUserDriver, delegate: any SPUUpdaterDelegate) {
        self.delegate = delegate
        super.init()
        updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: self)
    }
    func start() throws { try updater.start() }
    func checkForUpdateInformation() { didStartProbe = true; probeCount += 1; updater.checkForUpdateInformation() }
    func checkForUpdates() {
        refusedInstallation = true
        let error = NSError(domain: "PortsideProbeValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Installation is disabled during this validation probe."])
        delegate?.updater?(updater, didFinishUpdateCycleFor: .updates, error: error)
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // A real SPUUpdater could schedule a background check of its own. This
        // validation adapter allows exactly the explicitly requested probe.
        guard didStartProbe, updateCheck == .updateInformation else {
            throw NSError(domain: "PortsideProbeValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Only the explicit validation probe is permitted."])
        }
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updateInformation else {
            throw NSError(domain: "PortsideProbeValidation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Installation is disabled during this validation probe."])
        }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { delegate?.updater?(updater, didFindValidUpdate: item) }
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) { delegate?.updater?(updater, didFinishLoading: appcast) }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        delegate?.updater?(updater, didFinishUpdateCycleFor: updateCheck, error: error)
    }
}
