import Foundation

public enum PortsideAppUpdatePhase: String, Sendable, Equatable {
    case checking, installing, relaunching
}

/// Only a terminal outcome can release the runtime/Steam bootstrap gate.
public enum PortsideAppUpdateOutcome: Sendable, Equatable {
    case noUpdate
    case updated(version: String)
    case recoverableFailure(reason: String)
    case blocked(reason: String)
    case relaunching

    public var allowsBootstrap: Bool {
        switch self {
        case .noUpdate, .updated, .recoverableFailure: return true
        case .blocked, .relaunching: return false
        }
    }
}

/// A receipt is written only when Sparkle is about to commit an installation.
/// It records an expectation, never a persisted in-progress bootstrap state.
public struct PortsideAppUpdateRelaunchReceipt: Codable, Sendable, Equatable {
    public let sourceVersion: String
    public let expectedVersion: String
    public let createdAt: Date

    public init(sourceVersion: String, expectedVersion: String, createdAt: Date = Date()) {
        self.sourceVersion = sourceVersion
        self.expectedVersion = expectedVersion
        self.createdAt = createdAt
    }

    public func validate(currentVersion: String, compare: (String, String) -> ComparisonResult) -> PortsideAppUpdateOutcome {
        guard !expectedVersion.isEmpty, expectedVersion.count <= 128,
              expectedVersion.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              compare(expectedVersion, sourceVersion) == .orderedDescending else {
            return .blocked(reason: "Portside could not verify the previous update. Please try updating again.")
        }
        guard compare(currentVersion, expectedVersion) != .orderedAscending else {
            return .blocked(reason: "The previous Portside update did not finish. Please try updating again before opening Steam.")
        }
        return .updated(version: currentVersion)
    }
}

/// Testable lifecycle independent of Sparkle, runtime files, Steam, or setup state.
/// The initial probe cannot install anything. Its timeout can therefore safely
/// release a valid app while ignoring late probe callbacks.
@MainActor
public final class PortsideAppUpdatePreflight {
    public var onStartCheck: (() -> Void)?
    public var onStartInstallation: (() -> Void)?
    public var onPhaseChanged: ((PortsideAppUpdatePhase) -> Void)?
    public private(set) var outcome: PortsideAppUpdateOutcome?
    public private(set) var phase: PortsideAppUpdatePhase = .checking
    public private(set) var expectedVersion: String?
    public private(set) var requiresUpdate = false
    public private(set) var hasStarted = false
    private var checkFinished = false
    private var installationFinished = false
    private var waiters: [CheckedContinuation<PortsideAppUpdateOutcome, Never>] = []
    private var checkTimeoutTask: Task<Void, Never>?
    private var installationTimeoutTask: Task<Void, Never>?
    private let checkTimeout: Duration
    private let installationTimeout: Duration
    private let previousRelaunch: PortsideAppUpdateOutcome?
    private let allowsRelaunchRetry: Bool

    public init(checkTimeout: Duration = .seconds(20), installationTimeout: Duration = .seconds(600), previousRelaunch: PortsideAppUpdateOutcome? = nil, allowsRelaunchRetry: Bool = false) {
        self.checkTimeout = checkTimeout
        self.installationTimeout = installationTimeout
        self.previousRelaunch = previousRelaunch
        self.allowsRelaunchRetry = allowsRelaunchRetry
    }

    public func run() async -> PortsideAppUpdateOutcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard !hasStarted else { return }
            hasStarted = true
            onPhaseChanged?(.checking)
            checkTimeoutTask = Task { [weak self, checkTimeout] in
                do { try await Task.sleep(for: checkTimeout) } catch { return }
                self?.checkTimedOut()
            }
            onStartCheck?()
        }
    }

    public func foundUpdate(version: String, critical: Bool) {
        guard outcome == nil else { return }
        expectedVersion = version
        requiresUpdate = requiresUpdate || critical
    }

    public func checkCompleted(errorReason: String? = nil) {
        guard hasStarted, !checkFinished, outcome == nil else { return }
        checkFinished = true
        checkTimeoutTask?.cancel()
        if let previousRelaunch, !previousRelaunch.allowsBootstrap, !(allowsRelaunchRetry && expectedVersion != nil) {
            finish(previousRelaunch)
        } else if expectedVersion != nil {
            phase = .installing
            onPhaseChanged?(.installing)
            installationTimeoutTask = Task { [weak self, installationTimeout] in
                do { try await Task.sleep(for: installationTimeout) } catch { return }
                self?.installationTimedOut()
            }
            onStartInstallation?()
        } else if let errorReason {
            finish(.recoverableFailure(reason: errorReason))
        } else {
            finish(previousRelaunch ?? .noUpdate)
        }
    }

    public func unavailable(reason: String, commercial: Bool) {
        guard outcome == nil else { return }
        if let previousRelaunch, !previousRelaunch.allowsBootstrap { finish(previousRelaunch); return }
        finish(commercial ? .blocked(reason: reason) : .recoverableFailure(reason: reason))
    }

    public func checkTimedOut() {
        guard hasStarted, !checkFinished, outcome == nil else { return }
        checkFinished = true
        if let previousRelaunch, !previousRelaunch.allowsBootstrap {
            finish(previousRelaunch)
        } else if requiresUpdate {
            finish(.blocked(reason: "A required Portside update must finish before Steam can open. Please try updating again."))
        } else {
            finish(.recoverableFailure(reason: "The Portside update check timed out. The installed version can still be used."))
        }
    }

    /// Called only when the actual installation cycle has ended; discovering or
    /// downloading an update alone must never be mistaken for installation.
    public func installationCompleted(errorReason: String? = nil, postponed: Bool = false) {
        guard phase == .installing, !installationFinished, outcome == nil else { return }
        installationFinished = true
        if let previousRelaunch, !previousRelaunch.allowsBootstrap {
            finish(previousRelaunch)
        } else if requiresUpdate {
            finish(.blocked(reason: "A required Portside update must finish before Steam can open. Please try updating again."))
        } else if let errorReason {
            finish(.recoverableFailure(reason: errorReason))
        } else if postponed {
            finish(.recoverableFailure(reason: "The Portside update was postponed."))
        } else {
            // A successful Sparkle cycle may only have staged an update for quit.
            finish(.blocked(reason: "Portside has not finished installing its update. Please try updating again."))
        }
    }

    public func installationTimedOut() {
        guard phase == .installing, outcome == nil else { return }
        finish(.blocked(reason: "The Portside update has not finished. Complete the update window or try again after it closes."))
    }

    public func willRelaunch() {
        guard phase == .installing, outcome == nil else { return }
        phase = .relaunching
        onPhaseChanged?(.relaunching)
        finish(.relaunching)
    }

    private func finish(_ result: PortsideAppUpdateOutcome) {
        guard outcome == nil else { return }
        outcome = result
        checkTimeoutTask?.cancel()
        installationTimeoutTask?.cancel()
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: result) }
    }
}
