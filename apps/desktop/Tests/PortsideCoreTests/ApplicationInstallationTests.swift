import Darwin
import XCTest
@testable import PortsideCore

final class ApplicationInstallationTests: XCTestCase {
    func testCommercialDMGIsBlocked() {
        let result = assessment("/Volumes/Portside/Portside.app")
        XCTAssertTrue(result.requiresMove)
        XCTAssertEqual(result.reason, .diskImage)
    }

    func testCustomMountedDMGIsBlocked() {
        XCTAssertTrue(PortsideInstallationAssessment.evaluate(bundleURL: URL(fileURLWithPath: "/Applications/Portside.app"), isCommercialBuild: true, isReadOnly: false, isDiskImage: true).requiresMove)
    }

    func testAppTranslocationIsDetected() {
        XCTAssertEqual(assessment("/private/var/folders/test/AppTranslocation/id/d/Portside.app").reason, .appTranslocation)
    }

    func testReadOnlyBundleIsBlockedEvenInApplications() {
        let result = assessment("/Applications/Portside.app", readOnly: true)
        XCTAssertTrue(result.requiresMove)
        XCTAssertEqual(result.reason, .readOnlyBundle)
    }

    func testCommercialInstalledBundleCanContinue() {
        XCTAssertFalse(assessment("/Applications/Portside.app").requiresMove)
    }

    func testOtherApplicationLocationsAreBlocked() {
        for path in ["/Applications/Other.app", "/Applications/Portside copy.app", "/Users/test/Applications/Portside.app", "/tmp/Portside.app"] {
            XCTAssertTrue(assessment(path).requiresMove)
        }
    }

    func testDebugCanRunOutsideApplications() {
        XCTAssertFalse(PortsideInstallationAssessment.evaluate(bundleURL: URL(fileURLWithPath: "/Volumes/Portside/Portside.app"), isCommercialBuild: false, isReadOnly: true).requiresMove)
        #if DEBUG
        XCTAssertFalse(PortsideInstallationService.isCommercialBuild())
        #endif
    }

    func testNewerExistingReleaseOrBuildIsNeverReplaced() {
        XCTAssertThrowsError(try identity("1.0", build: "10").validateReplacement(of: identity("2.0", build: "9"))) { XCTAssertEqual($0 as? PortsideInstallationError, .newerInstallation) }
        XCTAssertThrowsError(try identity("2.0", build: "10").validateReplacement(of: identity("2.0", build: "11"))) { XCTAssertEqual($0 as? PortsideInstallationError, .newerInstallation) }
    }

    func testExistingPublisherMustMatch() {
        let other = PortsideSignedApplication(identifier: "com.portside.app", teamIdentifier: "OTHER", version: "1", buildVersion: "1", codeDirectoryHash: "a")
        XCTAssertThrowsError(try identity("2").validateReplacement(of: other)) { XCTAssertEqual($0 as? PortsideInstallationError, .differentPublisher) }
    }

    func testUnsignedBundleFailsSignatureValidation() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try PortsideApplicationSignature.validate(bundleURL: root)) { XCTAssertEqual($0 as? PortsideInstallationError, .invalidSignature) }
    }

    @MainActor func testMoveValidatesInstalledCopyThenReopensBeforeSchedulingEjection() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("2"))
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        try await service.moveToApplicationsAndReopen { installer.events.append("opening") }
        XCTAssertEqual(installer.events, ["validateSource", "install", "validateInstalled", "opening", "reopen", "scheduleEjection"])
    }

    @MainActor func testOpenInstalledApplicationRetriesLaunchWithoutCopyingAgain() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"), existing: identity("2"))
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        try await service.openInstalledApplication()
        XCTAssertEqual(installer.events, ["validateSource", "validateInstalled", "reopen", "scheduleEjection"])
    }

    @MainActor func testOpenInstalledApplicationRejectsAnUntrustedReplacement() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"), existing: identity("2"))
        installer.invalidInstalledSignature = true
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        do { try await service.openInstalledApplication(); XCTFail("Invalid application was reopened") }
        catch { XCTAssertEqual(error as? PortsideInstallationError, .invalidSignature) }
        XCTAssertFalse(installer.events.contains("reopen"))
        XCTAssertFalse(installer.events.contains("install"))
    }

    @MainActor func testNewerInstallationOpensAutomaticallyWithoutCopying() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"), existing: identity("2"))
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        try await service.moveToApplicationsAndReopen { installer.events.append("opening") }
        XCTAssertEqual(installer.events, ["validateSource", "validateInstalled", "opening", "validateSource", "validateInstalled", "reopen", "scheduleEjection"])
    }

    @MainActor func testAutomaticOpeningSelectsOnlyTrustedNewerInstalledVersions() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("2"))
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        XCTAssertFalse(try service.hasNewerInstalledApplication())
        for version in ["1", "2"] {
            installer.existing = identity(version)
            XCTAssertFalse(try service.hasNewerInstalledApplication())
        }
        installer.existing = identity("3")
        XCTAssertTrue(try service.hasNewerInstalledApplication())
        installer.existing = identity("2", build: "3")
        XCTAssertTrue(try service.hasNewerInstalledApplication())
        installer.existing = identity("3", build: "1")
        XCTAssertThrowsError(try service.hasNewerInstalledApplication())
        installer.existing = PortsideSignedApplication(identifier: "com.portside.app", teamIdentifier: "OTHER", version: "3", buildVersion: "3", codeDirectoryHash: "other")
        XCTAssertThrowsError(try service.hasNewerInstalledApplication())
        installer.existing = identity("3")
        installer.invalidInstalledSignature = true
        XCTAssertThrowsError(try service.hasNewerInstalledApplication())
        XCTAssertFalse(installer.events.contains("install"))
        XCTAssertFalse(installer.events.contains("reopen"))
    }

    @MainActor func testNewerInstalledCopyOpeningFailureDoesNotCopyOrEject() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"), existing: identity("2"))
        installer.reopenFailure = true
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        do { try await service.moveToApplicationsAndReopen(); XCTFail("Opening failure was ignored") }
        catch { XCTAssertEqual(error as? PortsideInstallationError, .reopenFailed) }
        XCTAssertFalse(installer.events.contains("install"))
        XCTAssertFalse(installer.events.contains("scheduleEjection"))
    }

    @MainActor func testNewerVersionArrivingDuringInstallIsRevalidatedAndOpened() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"))
        installer.replacementDuringInstall = identity("2")
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        try await service.moveToApplicationsAndReopen()
        XCTAssertEqual(installer.existing, identity("2"))
        XCTAssertEqual(installer.events, ["validateSource", "install", "validateSource", "validateInstalled", "reopen", "scheduleEjection"])
    }

    @MainActor func testAutomaticOpenRechecksDestinationAfterOpeningCallback() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"), existing: identity("2"))
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        do {
            try await service.moveToApplicationsAndReopen { installer.invalidInstalledSignature = true }
            XCTFail("Changed destination was opened")
        } catch { XCTAssertEqual(error as? PortsideInstallationError, .invalidSignature) }
        XCTAssertFalse(installer.events.contains("reopen"))
        XCTAssertFalse(installer.events.contains("scheduleEjection"))
    }

    @MainActor func testCopyPermissionFailureDoesNotRelaunch() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"))
        installer.failure = .permissionDenied
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        do { try await service.moveToApplicationsAndReopen(); XCTFail("Permission failure was ignored") }
        catch { XCTAssertEqual(error as? PortsideInstallationError, .permissionDenied) }
        XCTAssertFalse(installer.events.contains("reopen"))
        XCTAssertFalse(installer.events.contains("scheduleEjection"))
    }

    @MainActor func testInstalledSignatureFailureDoesNotRelaunch() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"))
        installer.invalidInstalledSignature = true
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        do { try await service.moveToApplicationsAndReopen(); XCTFail("Invalid copy was opened") }
        catch { XCTAssertEqual(error as? PortsideInstallationError, .invalidSignature) }
        XCTAssertFalse(installer.events.contains("reopen"))
    }

    @MainActor func testReopenFailureNeverSchedulesEjection() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"))
        installer.reopenFailure = true
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        do { try await service.moveToApplicationsAndReopen(); XCTFail("Reopen failure was ignored") }
        catch { XCTAssertEqual(error as? PortsideInstallationError, .reopenFailed) }
        XCTAssertFalse(installer.events.contains("scheduleEjection"))
    }

    @MainActor func testRepeatedMoveDoesNotStartDuplicateInstallations() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = InstallationMock(identity: identity("1"))
        installer.suspendInstall = true
        let service = PortsideInstallationService(bundle: try XCTUnwrap(Bundle(url: root)), installer: installer)
        let first = Task { try await service.moveToApplicationsAndReopen() }
        while installer.installContinuation == nil { await Task.yield() }
        do { try await service.moveToApplicationsAndReopen(); XCTFail("Duplicate installation started") }
        catch { XCTAssertEqual(error as? PortsideInstallationError, .alreadyMoving) }
        installer.installContinuation?.resume()
        try await first.value
        XCTAssertEqual(installer.events.filter { $0 == "install" }.count, 1)
    }

    func testTransactionReplacesOlderBundleAtomicallyAndRetainsOriginalAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Portside.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("2".utf8).write(to: source.appendingPathComponent("version"))
        try Data("1".utf8).write(to: destination.appendingPathComponent("version"))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "version")
        XCTAssertEqual(try PortsideInstallationTransaction.run(executable: URL(fileURLWithPath: "/usr/bin/xattr"), arguments: ["-w", "com.portside.test", "preserved", source.path]), 0)
        let validate: (URL) throws -> PortsideSignedApplication = { url in
            self.identity(try String(contentsOf: url.appendingPathComponent("version"), encoding: .utf8))
        }
        try PortsideInstallationTransaction.perform(source: source, destination: destination, identity: identity("2"), owner: getuid(), group: getgid(), assess: { _ in }, validate: validate)
        XCTAssertEqual(try validate(destination).version, "2")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("link").path), "version")
        let previous = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".Portside-Previous-") })
        XCTAssertEqual(try validate(previous).version, "1")
        XCTAssertEqual(try PortsideInstallationTransaction.run(executable: URL(fileURLWithPath: "/usr/bin/xattr"), arguments: ["-p", "com.portside.test", destination.path]), 0)
        XCTAssertEqual(try validate(source).version, "2")
    }

    func testTransactionRejectsBadStagedSignatureWithoutChangingExistingApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Portside.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("original".utf8).write(to: destination.appendingPathComponent("marker"))
        XCTAssertThrowsError(try PortsideInstallationTransaction.perform(source: source, destination: destination, identity: identity("2"), owner: getuid(), group: getgid(), assess: { _ in }, validate: { url in
            if url == destination { return self.identity("1") }
            throw PortsideInstallationError.invalidSignature
        })) { XCTAssertEqual($0 as? PortsideInstallationError, .invalidSignature) }
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8), "original")
    }

    func testNewInstallationNeverOverwritesAnAppCreatedDuringCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Portside.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try PortsideInstallationTransaction.perform(source: source, destination: destination, identity: identity("2"), owner: getuid(), group: getgid(), assess: { _ in }, validate: { _ in
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try Data("concurrent installation".utf8).write(to: destination.appendingPathComponent("marker"))
            return self.identity("2")
        })) { XCTAssertEqual($0 as? PortsideInstallationError, .installationChanged) }
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8), "concurrent installation")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Portside.app").path))
    }

    func testTransactionRejectsNewerExistingBundleBeforeCopying() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Portside.app")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("newer installation".utf8).write(to: destination.appendingPathComponent("marker"))
        XCTAssertThrowsError(try PortsideInstallationTransaction.perform(source: source, destination: destination, identity: identity("1"), owner: getuid(), group: getgid(), assess: { _ in }, validate: { _ in self.identity("2") })) { XCTAssertEqual($0 as? PortsideInstallationError, .newerInstallation) }
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8), "newer installation")
    }

    func testRealPermissionFailureIsActionableAndPreservesDestination() throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission checks require an unprivileged test process") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Applications/Portside.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.deletingLastPathComponent().path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.deletingLastPathComponent().path)
        XCTAssertThrowsError(try PortsideInstallationTransaction.perform(source: source, destination: destination, identity: identity("1"), owner: getuid(), group: getgid(), assess: { _ in }, validate: { _ in self.identity("1") })) { XCTAssertEqual($0 as? PortsideInstallationError, .permissionDenied) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testAuthorizationPreservesSpecificValidationStatusWithoutExposingOSMessages() throws {
        XCTAssertEqual(try PortsideInstallationTransaction.runAuthorization(appleScript: "return 65"), 65)
        XCTAssertEqual(PortsideInstallationError.from(exitStatus: 65), .invalidSignature)
        XCTAssertEqual(try PortsideInstallationTransaction.runAuthorization(appleScript: "return -128"), 77)
    }

    func testShellEscapingDoesNotExecuteSourcePathContents() {
        XCTAssertEqual(PortsideInstallationTransaction.shellQuote("/tmp/Portside's $(touch nope) `echo nope`.app"), "'/tmp/Portside'\\''s $(touch nope) `echo nope`.app'")
    }

    func testInstallationErrorsUseEnglishActionableText() {
        let errors: [PortsideInstallationError] = [.permissionDenied, .invalidSignature, .invalidBundle, .differentPublisher, .newerInstallation, .installationChanged, .copyFailed, .helperUnavailable, .reopenFailed, .alreadyMoving]
        XCTAssertTrue(errors.allSatisfy { $0.errorDescription?.isEmpty == false })
        XCTAssertTrue(PortsideInstallationError.permissionDenied.localizedDescription.contains("Permission"))
        XCTAssertTrue(PortsideInstallationError.newerInstallation.localizedDescription.contains("newer version"))
        XCTAssertTrue(PortsideInstallationError.invalidSignature.localizedDescription.contains("signature"))
    }

    private func assessment(_ path: String, readOnly: Bool = false) -> PortsideInstallationAssessment {
        .evaluate(bundleURL: URL(fileURLWithPath: path), isCommercialBuild: true, isReadOnly: readOnly)
    }

    private func identity(_ version: String, build: String? = nil) -> PortsideSignedApplication {
        PortsideSignedApplication(identifier: "com.portside.app", teamIdentifier: "TEST", version: version, buildVersion: build ?? version, codeDirectoryHash: version)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("app")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.portside.app", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "CFBundleExecutable": "Portside"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: root.appendingPathComponent("Contents/Info.plist"))
        return root
    }
}

@MainActor private final class InstallationMock: PortsideApplicationInstalling {
    let identity: PortsideSignedApplication
    var existing: PortsideSignedApplication?
    var events: [String] = []
    var failure: PortsideInstallationError?
    var invalidInstalledSignature = false
    var reopenFailure = false
    var suspendInstall = false
    var replacementDuringInstall: PortsideSignedApplication?
    var installContinuation: CheckedContinuation<Void, Never>?

    init(identity: PortsideSignedApplication, existing: PortsideSignedApplication? = nil) {
        self.identity = identity
        self.existing = existing
    }
    func validate(_ url: URL) throws -> PortsideSignedApplication {
        if url == PortsideInstallationService.destination {
            events.append("validateInstalled")
            if invalidInstalledSignature { throw PortsideInstallationError.invalidSignature }
            return existing ?? identity
        }
        events.append("validateSource")
        return identity
    }
    func exists(_ url: URL) -> Bool { existing != nil }
    func install(source: URL, identity: PortsideSignedApplication) async throws {
        events.append("install")
        if let replacementDuringInstall {
            existing = replacementDuringInstall
            throw PortsideInstallationError.newerInstallation
        }
        if let failure { throw failure }
        if suspendInstall { await withCheckedContinuation { installContinuation = $0 } }
        existing = identity
    }
    func reopen(_ url: URL) async throws {
        events.append("reopen")
        if reopenFailure { throw PortsideInstallationError.reopenFailed }
    }
    func scheduleDiskImageEjection(source: URL, installed: URL) { events.append("scheduleEjection") }
}
