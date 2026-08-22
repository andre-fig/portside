import Foundation
import Sparkle
import PortsideCore

@MainActor
private final class PortsideSparkleDelegate: NSObject, SPUUpdaterDelegate {
    var didFinishUpdateCycle: ((Error?) -> Void)?

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        didFinishUpdateCycle?(error)
    }
}

/// Sparkle is optional in local development until a Portside feed and public
/// EdDSA key are provisioned. Commercial bundles receive both at packaging
/// time; no private update key is ever read by the app.
@MainActor
final class PortsideUpdateCoordinator: NSObject {
    private let controller: SPUStandardUpdaterController?
    private let delegate: PortsideSparkleDelegate?
    private let logger = PortsideLogger(logFileName: "portside-update.log")
    private var initialCheckFinished = false
    private var initialCheckWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        let feed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !PortsideAppUpdateConfiguration.isConfigured(feed: feed, publicKey: publicKey) {
            delegate = nil
            controller = nil
        } else {
            let delegate = PortsideSparkleDelegate()
            self.delegate = delegate
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
        }
        super.init()
        delegate?.didFinishUpdateCycle = { [weak self] error in self?.finishInitialCheck(error: error) }
        // Sparkle schedules regular checks from Info.plist. This one launch-time
        // check is intentionally limited to the moment immediately after the
        // updater starts, as required by Sparkle's programmatic setup guidance.
        if let updater = controller?.updater, updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        } else {
            logger.write("sparkle_update_check_skipped reason=automatic_checks_disabled")
            finishInitialCheck(error: nil)
        }
    }

    func waitForInitialCheck() async {
        guard !initialCheckFinished else { return }
        await withCheckedContinuation { continuation in
            initialCheckWaiters.append(continuation)
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private func finishInitialCheck(error: Error?) {
        guard !initialCheckFinished else { return }
        initialCheckFinished = true
        if let error {
            logger.write("sparkle_update_check_finished error=\(PortsideLogger.sanitize(error.localizedDescription))", level: .warning)
        } else {
            logger.write("sparkle_update_check_finished")
        }
        let waiters = initialCheckWaiters
        initialCheckWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
