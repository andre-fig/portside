import Foundation
import Sparkle
import PortsideCore

/// Sparkle is optional in local development until a Portside feed and public
/// EdDSA key are provisioned. Commercial bundles receive both at packaging
/// time; no private update key is ever read by the app.
@MainActor
final class PortsideUpdateCoordinator: NSObject {
    private let controller: SPUStandardUpdaterController?

    override init() {
        let feed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !PortsideAppUpdateConfiguration.isConfigured(feed: feed, publicKey: publicKey) {
            controller = nil
        } else {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        super.init()
        // Sparkle schedules regular checks from Info.plist. This one launch-time
        // check is intentionally limited to the moment immediately after the
        // updater starts, as required by Sparkle's programmatic setup guidance.
        if let updater = controller?.updater, updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

}
