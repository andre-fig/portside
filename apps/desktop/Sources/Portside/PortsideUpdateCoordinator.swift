import Foundation
import Sparkle
import PortsideCore

@MainActor
protocol PortsideSparkleUpdating: AnyObject {
    var automaticallyDownloadsUpdates: Bool { get }
    var sessionInProgress: Bool { get }
    var canCheckForUpdates: Bool { get }
    func start() throws
    func checkForUpdateInformation()
    func checkForUpdates()
}

extension SPUUpdater: PortsideSparkleUpdating {}

/// Owns Sparkle's asynchronous session for the entire app lifetime. Construction
/// is inert: bootstrap calls runInitialCheck only after installation is accepted.
@MainActor
final class PortsideUpdateCoordinator: NSObject, SPUUpdaterDelegate {
    var onPhaseChanged: ((PortsideAppUpdatePhase) -> Void)?
    private let bundle: Bundle
    private let isCommercialBuild: Bool
    private let logger = PortsideLogger(logFileName: "portside-update.log")
    private var updater: (any PortsideSparkleUpdating)?
    private var userDriver: PortsideInitialUpdateUserDriver?
    private var preflight: PortsideAppUpdatePreflight?
    private var pendingItem: SUAppcastItem?
    private var postponed = false
    private var writtenReceiptVersion: String?
    private var receiptFailure: String?
    private var explicitRetry = false
    private var minimumRelaunchVersion: String?
    private let makeUpdater: (Bundle, any SPUUserDriver, any SPUUpdaterDelegate) -> any PortsideSparkleUpdating
    private let receiptLocation: URL?
    private let checkTimeout: Duration

    init(
        isCommercialBuild: Bool = false,
        bundle: Bundle = .main,
        receiptURL: URL? = nil,
        checkTimeout: Duration = .seconds(20),
        makeUpdater: @escaping (Bundle, any SPUUserDriver, any SPUUpdaterDelegate) -> any PortsideSparkleUpdating = {
            SPUUpdater(hostBundle: $0, applicationBundle: $0, userDriver: $1, delegate: $2)
        }
    ) {
        self.bundle = bundle
        self.isCommercialBuild = isCommercialBuild
        self.receiptLocation = receiptURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Portside", isDirectory: true).appendingPathComponent("app-update-relaunch.json")
        self.checkTimeout = checkTimeout
        self.makeUpdater = makeUpdater
        super.init()
    }

    func runInitialCheck() async -> PortsideAppUpdateOutcome {
        if let preflight { return await preflight.run() }
        let session = PortsideAppUpdatePreflight(checkTimeout: checkTimeout, previousRelaunch: inspectRelaunchReceipt(), allowsRelaunchRetry: explicitRetry)
        explicitRetry = false
        preflight = session
        session.onPhaseChanged = { [weak self] phase in
            self?.logger.write("app_update_phase phase=\(phase.rawValue)")
            self?.onPhaseChanged?(phase)
        }
        session.onStartCheck = { [weak self] in self?.startImmediateCheck() }
        session.onStartInstallation = { [weak self] in
            guard let self else { return }
            self.logger.write("app_update_installation_started")
            // The silent information probe completed. This cycle uses Sparkle's
            // standard UI, and its driver honors the existing automatic policy.
            self.updater?.checkForUpdates()
        }
        let outcome = await session.run()
        log(outcome)
        return outcome
    }

    func retryInitialCheck() async -> PortsideAppUpdateOutcome {
        guard let preflight else { return await runInitialCheck() }
        guard let outcome = preflight.outcome else { return await preflight.run() }
        if case .relaunching = outcome { return outcome }
        guard updater?.sessionInProgress != true else {
            updater?.checkForUpdates()
            return .blocked(reason: "Complete the Portside update window before trying again.")
        }
        // An explicit retry is the only way to retry a failed relaunch of the
        // same build. A fresh process never automatically repeats that attempt.
        explicitRetry = true
        self.preflight = nil
        pendingItem = nil
        postponed = false
        writtenReceiptVersion = nil
        receiptFailure = nil
        return await runInitialCheck()
    }

    func checkForUpdates() {
        guard preflight?.outcome?.allowsBootstrap == true else {
            if updater?.canCheckForUpdates == true { updater?.checkForUpdates() }
            return
        }
        updater?.checkForUpdates()
    }

    private func startImmediateCheck() {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard PortsideAppUpdateConfiguration.isConfigured(feed: feed, publicKey: key),
              let feedURL = feed.flatMap(URL.init(string:)), feedURL.scheme == "https",
              let key, Data(base64Encoded: key)?.count == 32 else {
            logger.write("app_update_check_unavailable reason=missing_or_invalid_configuration", level: .warning)
            preflight?.unavailable(reason: "Portside is missing its update configuration. Please install a valid copy of Portside.", commercial: isCommercialBuild)
            return
        }
        do {
            if updater == nil {
                let standard = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
                let driver = PortsideInitialUpdateUserDriver(standard: standard)
                driver.isInitialInstallation = { [weak self] in self?.isInitialInstallation == true }
                driver.shouldAutomaticallyInstall = { [weak self] in self?.updater?.automaticallyDownloadsUpdates == true }
                driver.prepareInstallation = { [weak self] in self?.prepareRelaunchReceipt() == true }
                driver.didPostpone = { [weak self] in self?.postponed = true }
                userDriver = driver
                let updater = makeUpdater(bundle, driver, self)
                self.updater = updater
                try updater.start()
            }
            logger.write("app_update_check_started trigger=launch mode=immediate_probe")
            // Deliberately independent of runtime, Steam, previous launch state,
            // and the user's preference for future scheduled checks. A probe
            // never installs, so a late response after timeout cannot race setup.
            updater?.checkForUpdateInformation()
        } catch {
            logger.write("app_update_start_failed code=\((error as NSError).code)", level: .error)
            preflight?.unavailable(reason: "Portside could not start its updater. Please install a valid copy of Portside.", commercial: isCommercialBuild)
        }
    }

    private var isInitialInstallation: Bool {
        preflight?.phase == .installing && preflight?.outcome == nil
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard let preflight, preflight.outcome == nil else { return }
        let expected = preflight.phase == .checking ? SPUUpdateCheck.updateInformation : .updates
        guard updateCheck == expected else {
            throw NSError(domain: "PortsideAppUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Portside is completing its initial update check."])
        }
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        if let minimumRelaunchVersion,
           SUStandardVersionComparator.default.compareVersion(updateItem.versionString, toVersion: minimumRelaunchVersion) == .orderedAscending {
            throw NSError(domain: "PortsideAppUpdate", code: 3, userInfo: [NSLocalizedDescriptionKey: "This update does not satisfy the version required by the previous Portside update. Please try again later."])
        }
        // The probe can finish after its deadline, but must never start a second
        // installation cycle. This also rejects unexpectedly late install offers.
        if updateCheck == .updates, preflight?.outcome != nil, preflight?.outcome?.allowsBootstrap != true {
            throw NSError(domain: "PortsideAppUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "The initial update session has ended. Please try updating again."])
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard preflight?.outcome == nil else { return }
        pendingItem = item
        preflight?.foundUpdate(version: item.versionString, critical: item.isCriticalUpdate)
        logger.write("app_update_found critical=\(item.isCriticalUpdate) feed_signature=\(item.signingValidationStatus.rawValue)")
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        observeAppcastItems(appcast.items)
    }

    func observeAppcastItems(_ items: [SUAppcastItem]) {
        guard preflight?.outcome == nil else { return }
        let currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        // Sparkle's background probe honors skipped versions. A build that was
        // previously skipped as normal may subsequently become critical. Inspect
        // Sparkle's parsed critical status before its skipped-version filtering,
        // then use the standard explicit update cycle to offer that update.
        for item in items where item.isCriticalUpdate {
            guard item.channel == nil, item.isMacOsUpdate, !item.isDeltaUpdate,
                  item.minimumUpdateVersionIsOK, item.minimumOperatingSystemVersionIsOK,
                  item.maximumOperatingSystemVersionIsOK, item.arm64HardwareRequirementIsOK else { continue }
            guard SUStandardVersionComparator.default.compareVersion(item.versionString, toVersion: currentVersion) == .orderedDescending else { continue }
            preflight?.foundUpdate(version: item.versionString, critical: true)
            logger.write("app_update_critical_requirement_found feed_signature=\(item.signingValidationStatus.rawValue)")
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard let preflight, preflight.outcome == nil else { return }
        let nsError = error as NSError?
        let noUpdate = nsError.map { $0.domain == SUSparkleErrorDomain && $0.code == SUError.noUpdateError.rawValue } ?? false
        let reason = (error == nil || noUpdate) ? nil : "Portside could not check or download its update. Please try again later."
        if let nsError, !noUpdate {
            // Error descriptions may contain feed query parameters. Only a code
            // is logged; all app-provided visible errors are fixed English text.
            logger.write("app_update_cycle_failed code=\(nsError.code)", level: .warning)
        }
        if updateCheck == .updateInformation {
            preflight.checkCompleted(errorReason: reason)
        } else {
            preflight.installationCompleted(errorReason: receiptFailure ?? reason, postponed: postponed)
        }
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        if choice != .install { postponed = true }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard isInitialInstallation else { return false }
        pendingItem = item
        guard prepareRelaunchReceipt() else { return true }
        immediateInstallHandler()
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        pendingItem = item
        _ = prepareRelaunchReceipt()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        guard receiptFailure == nil else { return }
        logger.write("app_update_relaunch_requested")
        preflight?.willRelaunch()
    }

    private var receiptURL: URL? {
        receiptLocation
    }

    private func prepareRelaunchReceipt() -> Bool {
        guard let pendingItem, let receiptURL else { return false }
        if writtenReceiptVersion == pendingItem.versionString { return true }
        do {
            let receipt = PortsideAppUpdateRelaunchReceipt(
                sourceVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                expectedVersion: pendingItem.versionString
            )
            try FileManager.default.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(receipt).write(to: receiptURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            writtenReceiptVersion = pendingItem.versionString
            logger.write("app_update_relaunch_receipt_saved")
            return true
        } catch {
            receiptFailure = "Portside could not save its update progress. Check available disk space and try again."
            preflight?.unavailable(reason: receiptFailure!, commercial: true)
            logger.write("app_update_receipt_failed code=\((error as NSError).code)", level: .error)
            return false
        }
    }

    private func inspectRelaunchReceipt() -> PortsideAppUpdateOutcome? {
        guard let receiptURL, FileManager.default.fileExists(atPath: receiptURL.path) else { return nil }
        do {
            let receipt = try JSONDecoder().decode(PortsideAppUpdateRelaunchReceipt.self, from: Data(contentsOf: receiptURL))
            let current = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            let outcome = receipt.validate(currentVersion: current) { SUStandardVersionComparator.default.compareVersion($0, toVersion: $1) }
            if outcome.allowsBootstrap {
                minimumRelaunchVersion = nil
                try FileManager.default.removeItem(at: receiptURL)
                logger.write("app_update_relaunch_verified")
                return outcome
            }
            minimumRelaunchVersion = receipt.expectedVersion
            logger.write("app_update_relaunch_unverified automatic_retry=blocked", level: .error)
            return outcome
        } catch {
            return .blocked(reason: "Portside could not verify the previous update. Please try updating again.")
        }
    }

    private func log(_ outcome: PortsideAppUpdateOutcome) {
        let result: String
        switch outcome {
        case .noUpdate: result = "no_update"
        case .updated: result = "updated_and_verified"
        case .recoverableFailure: result = "recoverable_failure"
        case .blocked: result = "blocked"
        case .relaunching: result = "relaunching"
        }
        logger.write("app_update_preflight_finished result=\(result) bootstrap_allowed=\(outcome.allowsBootstrap)")
    }
}

/// All visible UI remains Sparkle's standard UI. Only the silent probe and
/// already-authorized automatic installation are handled without extra screens.
@MainActor
final class PortsideInitialUpdateUserDriver: NSObject, SPUUserDriver {
    let standard: SPUStandardUserDriver
    var isInitialInstallation: (() -> Bool)?
    var shouldAutomaticallyInstall: (() -> Bool)?
    var prepareInstallation: (() -> Bool)?
    var didPostpone: (() -> Void)?
    private var automaticInstallation = false
    private var criticalUpdate = false
    private var shouldShowProgress: Bool { !automaticInstallation || criticalUpdate }

    init(standard: SPUStandardUserDriver) { self.standard = standard }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        if isInitialInstallation?() != true { standard.showUserInitiatedUpdateCheck(cancellation: cancellation) }
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        criticalUpdate = appcastItem.isCriticalUpdate
        automaticInstallation = isInitialInstallation?() == true && shouldAutomaticallyInstall?() == true && !appcastItem.isInformationOnlyUpdate && !appcastItem.isMajorUpgrade
        if automaticInstallation {
            if state.stage == .installing, prepareInstallation?() != true { reply(.skip); return }
            reply(.install)
        } else {
            standard.showUpdateFound(with: appcastItem, state: state) { [weak self] choice in
                guard let self else { reply(.dismiss); return }
                if choice != .install { self.didPostpone?() }
                if choice == .install, state.stage == .installing, self.prepareInstallation?() != true { reply(.skip); return }
                reply(choice)
            }
        }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { standard.showUpdateReleaseNotes(with: downloadData) }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { standard.showUpdateReleaseNotesFailedToDownloadWithError(error) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if isInitialInstallation?() == true { acknowledgement() } else { standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement) }
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { standard.showUpdaterError(error, acknowledgement: acknowledgement) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { if shouldShowProgress { standard.showDownloadInitiated(cancellation: cancellation) } }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { if shouldShowProgress { standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength) } }
    func showDownloadDidReceiveData(ofLength length: UInt64) { if shouldShowProgress { standard.showDownloadDidReceiveData(ofLength: length) } }
    func showDownloadDidStartExtractingUpdate() { if shouldShowProgress { standard.showDownloadDidStartExtractingUpdate() } }
    func showExtractionReceivedProgress(_ progress: Double) { if shouldShowProgress { standard.showExtractionReceivedProgress(progress) } }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if automaticInstallation {
            reply(prepareInstallation?() == true ? .install : .skip)
        } else {
            standard.showReady { [weak self] choice in
                guard let self else { reply(.skip); return }
                if choice != .install { self.didPostpone?() }
                if choice == .install, self.prepareInstallation?() != true { reply(.skip); return }
                reply(choice)
            }
        }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if shouldShowProgress { standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication) }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement) }
    func dismissUpdateInstallation() { automaticInstallation = false; standard.dismissUpdateInstallation() }
    func showUpdateInFocus() { standard.showUpdateInFocus() }
}
