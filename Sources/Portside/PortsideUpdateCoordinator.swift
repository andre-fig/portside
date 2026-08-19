import Foundation
import Sparkle

/// Sparkle is optional in local development until a Portside feed and public
/// EdDSA key are provisioned. Commercial bundles receive both at packaging
/// time; no private update key is ever read by the app.
@MainActor
final class PortsideUpdateCoordinator: NSObject {
    private let controller: SPUStandardUpdaterController?

    override init() {
        let feed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if feed.isEmpty || publicKey.isEmpty || feed.contains("example.invalid") {
            controller = nil
        } else {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        super.init()
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
