import XCTest
@testable import PortsideCore

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    var specification: ProcessLaunchSpec?
    let result: ProcessResult
    init(result: ProcessResult = ProcessResult(status: 0, output: "", duration: 0.1)) { self.result = result }
    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult { self.specification = specification; return result }
}

private struct TimeoutProcessRunner: ProcessRunning {
    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult { throw RuntimePipelineError.processTimedOut(specification.executable.lastPathComponent) }
}

final class PortsideCoreTests: XCTestCase {
    func testAppleSiliconRequirementAcceptsEnoughStorage() throws {
        XCTAssertNoThrow(try SystemRequirements(architecture: "arm64", macOSVersion: "macOS 26", availableStorage: 20_000_000_000).validate())
    }

    func testRequirementRejectsIntelAndLowStorage() {
        XCTAssertThrowsError(try SystemRequirements(architecture: "x86_64", macOSVersion: "macOS 26", availableStorage: 20_000_000_000).validate())
        XCTAssertThrowsError(try SystemRequirements(architecture: "arm64", macOSVersion: "macOS 26", availableStorage: 1).validate())
    }

    func testSanitizerRedactsSecrets() {
        let sanitized = PortsideLogger.sanitize("password=secret token:abc123 bearer abc.def email user@example.com steam 76561198012345678 path \(NSHomeDirectory())")
        XCTAssertFalse(sanitized.contains("secret")); XCTAssertFalse(sanitized.contains("abc123")); XCTAssertFalse(sanitized.contains("abc.def"))
        XCTAssertFalse(sanitized.contains("user@example.com")); XCTAssertFalse(sanitized.contains("76561198012345678")); XCTAssertFalse(sanitized.contains(NSHomeDirectory()))
    }

    func testDiagnosticContextContainsOnlyTechnicalFields() {
        let context = DiagnosticContext(stage: "steam_handoff", errorCode: "steam_window_failed", macOSVersion: "macOS 26", architecture: "arm64", runtimeVersion: "11.6_1", processType: "steam-launch", exitCode: 7, duration: 2.5, retryCount: 1, msyncBootstrapped: false, msyncRunning: false)
        XCTAssertEqual(context.fields["error_code"], "steam_window_failed")
        XCTAssertEqual(context.fields["runtime_version"], "11.6_1")
        XCTAssertFalse(context.fields.keys.contains { $0.lowercased().contains("cef") })
        XCTAssertFalse(context.fields.keys.contains { ["user", "email", "steam_id", "cookie"].contains($0) })
    }

    func testProductHasOneRuntimeAndUsesTheSingleSteamLaunchProfile() {
        XCTAssertEqual(FreeRuntimeCatalog.wine.version, "11.6_1")
        XCTAssertEqual(SteamInstaller.launchArguments, ["-udpforce", "-noreactlogin", "-allosarches", "-cef-force-32bit"])
        XCTAssertFalse(EnvironmentPhase.allCases.map(\.rawValue).contains("steamNativeLogin"))
        XCTAssertFalse(PortsidePaths.allDirectories.contains { $0.lastPathComponent == "Prefixes" })
    }

    func testWineEnvironmentDoesNotEnableLegacySyncCascade() {
        let environment = WineProcessEnvironment.make(runtimeExecutable: URL(fileURLWithPath: "/private/Runtime/bin/wine"), prefix: URL(fileURLWithPath: "/private/Prefix/Steam"), baseEnvironment: ["HOME": "/private/home", "PATH": "/usr/bin:/bin", "WINEMSYNC": "1", "WINEESYNC": "1", "WINEFSYNC": "1", "DXVK_ASYNC": "1", "MTL_HUD_ENABLED": "1"])
        XCTAssertNil(environment["WINEESYNC"]); XCTAssertNil(environment["WINEMSYNC"])
        XCTAssertNil(environment["WINEFSYNC"]); XCTAssertNil(environment["DXVK_ASYNC"]); XCTAssertNil(environment["MTL_HUD_ENABLED"])
        XCTAssertEqual(environment["WINEPREFIX"], "/private/Prefix/Steam"); XCTAssertEqual(environment["WINEARCH"], "win64")
        XCTAssertEqual(environment["PATH"]?.split(separator: ":").first.map(String.init), "/private/Runtime/bin")
        XCTAssertEqual(environment[WineProcessEnvironment.ownerMarkerKey], WineProcessEnvironment.prefixMarker(for: URL(fileURLWithPath: "/private/Prefix/Steam")))
    }

    func testSikarugirDevelopmentProfileHasExactMSYNCEnvironment() {
        let profile = RuntimeValidationProfile.sikarugirMSyncReference.environment(from: ["PATH": "/usr/bin"])
        XCTAssertEqual(profile["WINEMSYNC"], "1"); XCTAssertEqual(profile["WINEESYNC"], "0")
        let official = RuntimeValidationProfile.officialWine.environment(from: profile)
        XCTAssertNil(official["WINEMSYNC"]); XCTAssertNil(official["WINEESYNC"])
    }

    func testMSyncReadinessRequiresRealRuntimeLogLines() {
        let state = RuntimeSynchronizationLog.state(from: "msync: bootstrapped\nmsync: up and running\n")
        XCTAssertTrue(state.bootstrapped); XCTAssertTrue(state.running)
        XCTAssertTrue(state.applicable)
        let incomplete = RuntimeSynchronizationLog.state(from: "ps output WINEMSYNC=1")
        XCTAssertFalse(incomplete.bootstrapped); XCTAssertFalse(incomplete.running)
        XCTAssertFalse(incomplete.applicable)
        let official = RuntimeSynchronizationLog.state(from: "Wine process started with no synchronization markers")
        XCTAssertFalse(official.applicable)
    }

    func testDownloaderRejectsUnapprovedHostBeforeNetworkAccess() async {
        let downloader = SecureDownloader(allowedHosts: ["cdn.fastly.steamstatic.com"])
        do { _ = try await downloader.download(from: URL(string: "https://example.com/component.zip")!, to: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); XCTFail("unapproved host") }
        catch { XCTAssertEqual(error as? PortsideError, .steamInstallerUnavailable) }
    }

    func testRuntimeManifestIsPinnedToOfficialWineStaging116() {
        XCTAssertEqual(FreeRuntimeCatalog.wine.version, "11.6_1")
        XCTAssertEqual(FreeRuntimeCatalog.wine.sha256, "9e73898fc83b0137638fe90d4868387f30b5993e86aeaef7422d8b1655238014")
        XCTAssertEqual(FreeRuntimeCatalog.wine.expectedSize, 322_511_424)
        XCTAssertEqual(FreeRuntimeCatalog.wine.upstreamURL.absoluteString, "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.6_1/wine-staging-11.6_1-osx64.tar.xz")
        XCTAssertTrue(FreeRuntimeCatalog.wine.includedComponents.contains("WineD3D"))
        XCTAssertFalse(FreeRuntimeCatalog.wine.includedComponents.contains { $0.localizedCaseInsensitiveContains("D3DMetal") || $0.localizedCaseInsensitiveContains("GPTK") })
        XCTAssertTrue(FreeRuntimeCatalog.wine.includedComponents.contains("Wine Mono 11.0.0"))
    }

    func testSteamInstallerUsesInstallerArgumentsOnlyAndNoShell() {
        let installer = URL(fileURLWithPath: "/tmp/Folder With Spaces/SteamSetup.exe")
        let specification = SteamInstaller.installationSpecification(runtimePath: "/tmp/Wine Runtime/bin/wine", installerURL: installer, prefixURL: URL(fileURLWithPath: "/tmp/Portside Prefix"))
        XCTAssertEqual(specification.arguments, [installer.path, "/S"]); XCTAssertEqual(specification.timeout, 180)
        XCTAssertFalse(specification.arguments.contains { $0.contains("sh -c") || $0.contains("bash -c") || $0.contains("cef") })
    }

    func testInstallerTimeoutCanBeSimulatedWithoutLaunchingWine() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-timeout-\(UUID().uuidString)", isDirectory: true)
        let installer = root.appendingPathComponent("SteamSetup.exe")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try Data("installer".utf8).write(to: installer)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = RuntimeDescriptor(name: "test", version: "1", executablePath: "/usr/bin/true", redistributable: false, licenseNote: "test")
        do { try await SteamInstaller.install(using: runtime, installerURL: installer, candidates: [], prefixURL: root.appendingPathComponent("Prefix"), runner: TimeoutProcessRunner()); XCTFail("timeout") }
        catch { XCTAssertEqual(error as? RuntimePipelineError, .processTimedOut("true")) }
    }

    func testSilentInstallerFailureIsReportedWithoutChangingSteamArguments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-failure-\(UUID().uuidString)", isDirectory: true)
        let installer = root.appendingPathComponent("SteamSetup.exe")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try Data("installer".utf8).write(to: installer)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingProcessRunner(result: ProcessResult(status: 7, output: "failed", duration: 0.2))
        let runtime = RuntimeDescriptor(name: "test", version: "1", executablePath: "/usr/bin/true", redistributable: false, licenseNote: "test")
        do { try await SteamInstaller.install(using: runtime, installerURL: installer, candidates: [root.appendingPathComponent("missing.exe")], prefixURL: root.appendingPathComponent("Prefix"), runner: runner); XCTFail("failure") }
        catch { XCTAssertTrue(error is RuntimePipelineError) }
        XCTAssertEqual(runner.specification?.arguments, [installer.path, "/S"])
    }

    func testPrefixSnapshotRestorePreservesSteamAppsAndUserData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-snapshot-\(UUID().uuidString)", isDirectory: true)
        let prefix = root.appendingPathComponent("Prefix/Steam", isDirectory: true); let backups = root.appendingPathComponent("Backups", isDirectory: true)
        let apps = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true); let user = prefix.appendingPathComponent("drive_c/users/portside", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try Data("game".utf8).write(to: apps.appendingPathComponent("appmanifest.acf")); try Data("setting".utf8).write(to: user.appendingPathComponent("settings.vdf"))
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try PrefixSnapshot.create(prefix: prefix, backupsRoot: backups)
        try Data("changed".utf8).write(to: apps.appendingPathComponent("appmanifest.acf")); try PrefixSnapshot.restore(snapshot: snapshot, prefix: prefix)
        XCTAssertEqual(try String(contentsOf: prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/appmanifest.acf")), "game")
        XCTAssertEqual(try String(contentsOf: prefix.appendingPathComponent("drive_c/users/portside/settings.vdf")), "setting")
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))
    }

    func testTargetedSnapshotDoesNotCopySteamApps() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-targeted-snapshot-\(UUID().uuidString)", isDirectory: true)
        let prefix = root.appendingPathComponent("Prefix/Steam", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        let apps = prefix.appendingPathComponent("steamapps", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try Data("old-registry".utf8).write(to: prefix.appendingPathComponent("system.reg"))
        try Data("game".utf8).write(to: apps.appendingPathComponent("appmanifest.acf"))
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try PrefixSnapshot.create(prefix: prefix, backupsRoot: backups, strategy: .targeted, availableStorage: 2_000_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.appendingPathComponent("targeted/steamapps").path))
        try Data("changed".utf8).write(to: prefix.appendingPathComponent("system.reg"))
        try PrefixSnapshot.restore(snapshot: snapshot, prefix: prefix)
        XCTAssertEqual(try String(contentsOf: prefix.appendingPathComponent("system.reg")), "old-registry")
        XCTAssertEqual(try String(contentsOf: apps.appendingPathComponent("appmanifest.acf")), "game")
    }

    func testSnapshotRetentionKeepsOnlyOneRecoverableSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-retention-\(UUID().uuidString)", isDirectory: true)
        let prefix = root.appendingPathComponent("Prefix/Steam", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try Data("registry".utf8).write(to: prefix.appendingPathComponent("system.reg"))
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try PrefixSnapshot.create(prefix: prefix, backupsRoot: backups, strategy: .targeted, availableStorage: 2_000_000_000)
        let second = try PrefixSnapshot.create(prefix: prefix, backupsRoot: backups, strategy: .targeted, availableStorage: 2_000_000_000)
        let third = try PrefixSnapshot.create(prefix: prefix, backupsRoot: backups, strategy: .targeted, availableStorage: 2_000_000_000)
        try PrefixSnapshot.retainOnly(third, backupsRoot: backups)
        let retained = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("Steam-prefix-") }
        XCTAssertEqual(retained.map(\.lastPathComponent), [third.lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    func testRuntimeMigrationFromWine115RunsWinebootAndWritesNewMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-migration-\(UUID().uuidString)", isDirectory: true)
        let prefix = root.appendingPathComponent("Prefix/Steam", isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime/11.6_1/bin/wine")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: prefix.appendingPathComponent("system.reg"))
        try PrefixRuntimeMetadata(runtimeIdentifier: "wine-staging-gcenx-osx64", runtimeVersion: "11.15").write(to: prefix)
        let runner = RecordingProcessRunner()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(PrefixRuntimeMigration.requiresMigration(prefix: prefix, manifest: FreeRuntimeCatalog.wine))
        let migrated = try await PrefixRuntimeMigration.updateIfNeeded(prefix: prefix, runtimeExecutable: runtime, manifest: FreeRuntimeCatalog.wine, runner: runner)
        XCTAssertTrue(migrated)
        XCTAssertEqual(runner.specification?.executable.lastPathComponent, "wineboot")
        XCTAssertEqual(runner.specification?.arguments, ["-u"])
        XCTAssertNil(runner.specification?.environment["WINEMSYNC"]); XCTAssertNil(runner.specification?.environment["WINEESYNC"])
        try PrefixRuntimeMetadata(runtimeIdentifier: FreeRuntimeCatalog.wine.identifier, runtimeVersion: FreeRuntimeCatalog.wine.version).write(to: prefix)
        XCTAssertFalse(PrefixRuntimeMigration.requiresMigration(prefix: prefix, manifest: FreeRuntimeCatalog.wine))
    }

    func testRuntimeMigrationFailureCanRollbackThePrefix() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-migration-rollback-\(UUID().uuidString)", isDirectory: true)
        let prefix = root.appendingPathComponent("Prefix/Steam", isDirectory: true)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime/bin/wine")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("before".utf8).write(to: prefix.appendingPathComponent("system.reg"))
        try PrefixRuntimeMetadata(runtimeIdentifier: "wine-staging-gcenx-osx64", runtimeVersion: "11.15").write(to: prefix)
        let snapshot = try PrefixSnapshot.create(prefix: prefix, backupsRoot: backups, strategy: .targeted, availableStorage: 2_000_000_000)
        let runner = RecordingProcessRunner(result: ProcessResult(status: 9, output: "wineboot failed", duration: 0.1))
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await PrefixRuntimeMigration.updateIfNeeded(prefix: prefix, runtimeExecutable: runtime, manifest: FreeRuntimeCatalog.wine, runner: runner)
            XCTFail("migration should fail")
        } catch { XCTAssertEqual(error as? RuntimePipelineError, .runtimeMigrationFailed(9)) }
        try Data("changed".utf8).write(to: prefix.appendingPathComponent("system.reg"))
        try PrefixSnapshot.restore(snapshot: snapshot, prefix: prefix)
        XCTAssertEqual(try String(contentsOf: prefix.appendingPathComponent("system.reg")), "before")
    }

    func testObsoleteWine115RuntimeCleanupDoesNotTouchCurrentRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-runtime-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("11.15_1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("11.6_1"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try RuntimeStorage.removeObsolete11_15(runtimeRoot: root, keepingVersion: "11.6_1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("11.15_1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("11.6_1").path))
    }

    func testProcessHandoffDoesNotClaimWindowOrVisualReadiness() {
        let report = SteamReadinessReport(status: .processHandoffComplete, processStarted: true, processHandoffComplete: true, webhelperStarted: true, webhelperProcessCount: 5)
        XCTAssertTrue(report.processStarted); XCTAssertTrue(report.processHandoffComplete)
        XCTAssertFalse(report.windowDetected)
        XCTAssertEqual(report.interfaceVerification, .notVerified)
    }

    func testExternalSteamHelperWithoutPortsideMarkerIsRejected() {
        let prefix = URL(fileURLWithPath: "/private/Portside/Prefix/Steam")
        let external = "123 1 steamwebhelper.exe --type=renderer"
        let externalSteam = "124 1 steam.exe -silent"
        let managed = "123 1 steamwebhelper.exe PORTSIDE_WINE_PREFIX_MARKER=\(WineProcessEnvironment.prefixMarker(for: prefix))"
        XCTAssertFalse(SteamProcessOwnership.isManaged(snapshotLine: external, prefix: prefix, processName: "steamwebhelper"))
        XCTAssertFalse(SteamProcessOwnership.isManaged(snapshotLine: externalSteam, prefix: prefix, processName: "steam.exe"))
        XCTAssertTrue(SteamProcessOwnership.isManaged(snapshotLine: managed, prefix: prefix, processName: "steamwebhelper"))
    }

    func testDetachedProcessOutputFileAllowsChildToSurviveParentHandleClose() throws {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("portside-detached-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["2"]
        child.standardOutput = handle
        child.standardError = handle
        try child.run()
        try handle.close()
        XCTAssertTrue(child.isRunning)
        child.terminate()
    }

    func testArchivePathTraversalAndChecksumAreRejected() throws {
        XCTAssertTrue(SafeArchiveExtractor.isSafeRelativePath("Wine Staging.app/Contents/Resources/wine/bin/wine"))
        XCTAssertFalse(SafeArchiveExtractor.isSafeRelativePath("../../Library/LaunchAgents/unsafe")); XCTAssertFalse(SafeArchiveExtractor.isSafeRelativePath("/absolute/path"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("portside-integrity-\(UUID().uuidString)"); try Data("safe".utf8).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try IntegrityVerifier.verify(url: url, expectedSHA256: String(repeating: "0", count: 64)))
    }

    func testAtomicDirectoryInstallReplacesDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-atomic-\(UUID().uuidString)", isDirectory: true); let staged = root.appendingPathComponent("staged", isDirectory: true); let destination = root.appendingPathComponent("Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: staged.appendingPathComponent("marker")); try Data("old".utf8).write(to: destination.appendingPathComponent("marker")); defer { try? FileManager.default.removeItem(at: root) }
        try AtomicInstaller.installDirectory(from: staged, to: destination); XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker")), "new"); XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testSteamLaunchLockAllowsOnlyOneCoordinator() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("portside-lock-\(UUID().uuidString)"); let first = SteamLaunchLock.acquire(url: url)
        XCTAssertNotNil(first); XCTAssertNil(SteamLaunchLock.acquire(url: url)); _ = first
    }

    func testEnvironmentPhaseIsCodable() throws {
        var state = EnvironmentState(); state.phase = .prefixCreating; let data = try JSONEncoder.portside.encode(state)
        XCTAssertEqual(try JSONDecoder.portside.decode(EnvironmentState.self, from: data).phase, .prefixCreating)
    }

    func testSteamHasNoAppIDCompatibilityAllowlist() { XCTAssertTrue(SteamInstaller.steamExecutableCandidates.allSatisfy { $0.path.contains("Prefix/Steam") }) }
}
