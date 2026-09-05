import Foundation

public enum PortsideBootstrapState: String, Sendable, CaseIterable {
    case checkingInstallationLocation, movingToApplications, checkingAppUpdate
    case installingAppUpdate, relaunching, checkingRuntime, installingRuntime
    case checkingSteam, launchingSteam, ready, failed
}

/// An in-memory gate. Only the updater's version receipt survives a relaunch;
/// every process must confirm its own location and finish a fresh app check.
public struct PortsideBootstrap: Sendable {
    public private(set) var state: PortsideBootstrapState = .checkingInstallationLocation
    public private(set) var installationConfirmed = false
    public private(set) var appUpdateCompleted = false

    public init() {}

    @discardableResult
    public mutating func confirmInstallation() -> Bool {
        guard state == .checkingInstallationLocation else { return false }
        installationConfirmed = true
        state = .checkingAppUpdate
        return true
    }

    @discardableResult
    public mutating func finishAppUpdate(allowsBootstrap: Bool) -> Bool {
        guard installationConfirmed,
              [.checkingAppUpdate, .installingAppUpdate].contains(state) else { return false }
        appUpdateCompleted = allowsBootstrap
        state = allowsBootstrap ? .checkingRuntime : .failed
        return true
    }

    /// Claims a stage before starting any asynchronous work. Duplicate or late
    /// callbacks cannot claim the same stage or jump across the preflight.
    @discardableResult
    public mutating func advance(to next: PortsideBootstrapState) -> Bool {
        let allowed: [PortsideBootstrapState: Set<PortsideBootstrapState>] = [
            .checkingInstallationLocation: [.movingToApplications, .failed],
            .movingToApplications: [.relaunching, .failed],
            .checkingAppUpdate: [.installingAppUpdate, .relaunching, .failed],
            .installingAppUpdate: [.relaunching, .failed],
            .checkingRuntime: [.installingRuntime, .checkingSteam, .failed],
            .installingRuntime: [.checkingSteam, .failed],
            .checkingSteam: [.launchingSteam, .ready, .failed],
            .launchingSteam: [.ready, .failed],
            .ready: [.launchingSteam],
            .failed: [], .relaunching: []
        ]
        guard allowed[state, default: []].contains(next) else { return false }
        if [.checkingRuntime, .installingRuntime, .checkingSteam, .launchingSteam, .ready].contains(next) {
            guard installationConfirmed && appUpdateCompleted else { return false }
        }
        state = next
        return true
    }

    public mutating func retry() -> Bool {
        guard state == .failed else { return false }
        self = Self()
        return true
    }
}
