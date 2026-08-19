import XCTest
@testable import PortsideCore

final class PortsideCoreTests: XCTestCase {
    func testGoldenBaselineMatchesValidatedOfficialConfiguration() {
        let configuration = SikarugirBaselineConfiguration.golden
        XCTAssertEqual(SikarugirBaselineConfiguration.creatorVersion, "1.0.1")
        XCTAssertEqual(SikarugirBaselineConfiguration.templateVersion, "1.0.11")
        XCTAssertEqual(SikarugirBaselineConfiguration.engineName, "WS12WineSikarugir10.0_6")
        XCTAssertEqual(configuration.renderer, .wineD3D)
        XCTAssertTrue(configuration.msync)
        XCTAssertTrue(configuration.esync)
        XCTAssertEqual(configuration.programFlags, "")
        XCTAssertEqual(configuration.wineDebug, "-plugplay,+loaddll")
        XCTAssertEqual(configuration.environment["D3DMETAL"], "0")
        XCTAssertEqual(configuration.environment["DXMT"], "0")
        XCTAssertEqual(configuration.environment["DXVK"], "0")
    }

    func testOfficialCatalogUsesPinnedHTTPSArtifactsAndChecksums() throws {
        for artifact in SikarugirOfficialCatalog.all {
            try SikarugirArtifactValidator.validate(artifact)
            XCTAssertEqual(artifact.sha256.count, 64)
            XCTAssertTrue(artifact.url.absoluteString.contains("Sikarugir-App"))
        }
        XCTAssertEqual(SikarugirOfficialCatalog.engine.sha256, SikarugirBaselineConfiguration.engineArchiveSHA256)
        XCTAssertEqual(SikarugirOfficialCatalog.template.sha256, SikarugirBaselineConfiguration.templateArchiveSHA256)
    }

    func testLatestStableEngineParsingIsNaturalAndExcludesBattleNetVariant() {
        let list = """
        WS12WineSikarugir10.0
        WS12WineSikarugir10.0_4
        WS12WineSikarugir10.0-battle.net
        WS12WineSikarugir10.0_6
        WS12WineCX24.0.7_7
        """
        XCTAssertEqual(SikarugirUpdateService.latestStableEngine(in: list), "WS12WineSikarugir10.0_6")
    }

    func testUpdateChecksAtMostOncePerDay() {
        let now = Date()
        XCTAssertTrue(SikarugirUpdateService.shouldCheck(lastCheck: nil, now: now))
        XCTAssertFalse(SikarugirUpdateService.shouldCheck(lastCheck: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(SikarugirUpdateService.shouldCheck(lastCheck: now.addingTimeInterval(-86_401), now: now))
    }

    func testWrapperConfigurationDoesNotEnableAlternativeRenderers() throws {
        let values = SikarugirWrapperConfiguration().plistValues()
        XCTAssertEqual(values["Program Name and Path"] as? String, "/Program Files (x86)/Steam/steam.exe")
        XCTAssertEqual(values["Program Flags"] as? String, "")
        XCTAssertEqual(values["D3DMETAL"] as? Int, 0)
        XCTAssertEqual(values["DXMT"] as? Int, 0)
        XCTAssertEqual(values["DXVK"] as? Int, 0)
        XCTAssertNil(values["NSMicrophoneUsageDescription"])
        XCTAssertThrowsError(try SikarugirBaselineConfiguration(renderer: .dxvk))
    }

    func testSteamInstallUsesOfficialWinetricksVerbAndNoCustomSteamFlags() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let launcher = root.appendingPathComponent("Contents/MacOS/Sikarugir")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: launcher.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = try SikarugirSteamFlow.installationSpec(wrapper: root)
        XCTAssertEqual(spec.arguments, ["WSS-winetricks", "steam"])
        XCTAssertFalse(spec.arguments.joined(separator: " ").contains("cef"))
        XCTAssertFalse(spec.arguments.contains { $0.contains("noreactlogin") || $0.contains("allosarches") })
    }

    func testCleanLaunchUsesTheWrapperExecutableWithoutDirectWineOrSteamArguments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let launcher = root.appendingPathComponent("Contents/MacOS/Sikarugir")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: launcher.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = try SikarugirSteamFlow.cleanLaunchSpec(wrapper: root)
        XCTAssertEqual(spec.arguments, [])
        XCTAssertEqual(spec.executable, launcher)
    }

    func testArchiveTraversalAndIntegrityAreRejected() throws {
        XCTAssertTrue(SafeArchiveExtractor.isSafeRelativePath("Template.app/Contents/Info.plist"))
        XCTAssertFalse(SafeArchiveExtractor.isSafeRelativePath("../../Library/LaunchAgents/unsafe"))
        XCTAssertFalse(SafeArchiveExtractor.isSafeRelativePath("/absolute"))
        XCTAssertThrowsError(try SafeArchiveExtractor.validateListing("safe/file\n../../unsafe\n"))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("safe".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try IntegrityVerifier.verify(url: file, expectedSHA256: String(repeating: "0", count: 64)))
    }

    func testAtomicInstallKeepsExistingDestinationRecoverableOnFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staged = root.appendingPathComponent("staged")
        let destination = root.appendingPathComponent("Wrappers/PortsideBaseline.app")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: staged.appendingPathComponent("marker"))
        try Data("old".utf8).write(to: destination.appendingPathComponent("marker"))
        defer { try? FileManager.default.removeItem(at: root) }
        try AtomicInstaller.installDirectory(from: staged, to: destination)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker")), "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Wrappers/.previous-").deletingLastPathComponent().path))
    }

    func testDiagnosticSanitizationRemovesSecretsAndHomePath() {
        let text = "token=abc123 steamid=76561198000000000 path=\(NSHomeDirectory())/Library"
        let sanitized = PortsideLogger.sanitize(text)
        XCTAssertFalse(sanitized.contains("abc123"))
        XCTAssertFalse(sanitized.contains("76561198000000000"))
        XCTAssertTrue(sanitized.contains("$USER_HOME"))
    }

    func testDiagnosticsAllowOnlyNonSensitiveFields() {
        let context = DiagnosticContext(renderer: "wineD3D", appID: "3139440", msyncEnabled: true, esyncEnabled: true)
        XCTAssertEqual(context.fields["app_id"], "3139440")
        XCTAssertNil(context.fields["password"])
        XCTAssertFalse(context.fields.keys.contains { $0.localizedCaseInsensitiveContains("token") })
    }

    func testRendererFallbacksAreOrderedAndMutuallyExclusive() {
        let x64 = GameExecutableInfo(architecture: "x86_64", graphicsAPI: "DirectX 11")
        XCTAssertEqual(GameCompatibilityService.renderer(for: x64), [.d3dMetal, .dxmt, .dxvk, .wineD3D])
        let x86 = GameExecutableInfo(architecture: "x86", graphicsAPI: "DirectX 11")
        XCTAssertEqual(GameCompatibilityService.renderer(for: x86), [.dxvk, .wineD3D])
        XCTAssertTrue(GameCompatibilityService.mutuallyExclusive(.wineD3D, environment: ["D3DMETAL": "0", "DXMT": "0", "DXVK": "0"]))
        XCTAssertFalse(GameCompatibilityService.mutuallyExclusive(.wineD3D, environment: ["D3DMETAL": "1", "DXMT": "1"]))
    }

    func testPEArchitectureAndGraphicsDetection() throws {
        var data = Data(repeating: 0, count: 512)
        data[0] = 0x4d; data[1] = 0x5a
        data[0x3c] = 0x80
        data[0x80] = 0x50; data[0x81] = 0x45
        data[0x84] = 0x4c; data[0x85] = 0x01 // x86
        data.append(contentsOf: Data("d3d9.dll".utf8))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".exe")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let info = try GameCompatibilityService.detectExecutable(at: file)
        XCTAssertEqual(info.architecture, "x86")
        XCTAssertEqual(info.graphicsAPI, "DirectX 9")
    }

    func testReadinessDoesNotClaimVisualSuccessFromProcessesAlone() {
        let report = SteamReadinessReport(state: .processRunningWithoutWindow, processStarted: true, webHelperStarted: true, windowDetected: false, processRunningWithoutWindow: true)
        XCTAssertTrue(report.processStarted)
        XCTAssertTrue(report.webHelperStarted)
        XCTAssertFalse(report.windowDetected)
        XCTAssertFalse(report.uiReady)
        XCTAssertEqual(report.interfaceVerification, .notVerified)
    }

    func testNativeSteamSnapshotIsNotOwnedByPortside() {
        let wrapper = URL(fileURLWithPath: "/private/Portside/Wrappers/PortsideBaseline.app")
        XCTAssertFalse(SteamProcessOwnership.isManaged(snapshotLine: "steam.exe -silent", wrapper: wrapper))
        XCTAssertTrue(SteamProcessOwnership.isManaged(snapshotLine: "\(wrapper.path)/Contents/SharedSupport/prefix/drive_c/steam.exe", wrapper: wrapper))
    }

    func testEnvironmentStateRoundTrips() throws {
        var state = EnvironmentState()
        state.setupCompleted = true
        state.phase = .steamReady
        state.lastReadiness = SteamReadinessReport(state: .visibleButUnverified, processStarted: true, webHelperStarted: true, windowDetected: true, visibleButUnverified: true)
        let data = try JSONEncoder.portside.encode(state)
        let restored = try JSONDecoder.portside.decode(EnvironmentState.self, from: data)
        XCTAssertEqual(restored, state)
    }

    func testCompatibilityManifestStoresGunZAppIDWithoutAccountData() throws {
        let entry = GameCompatibilityEntry(appID: "3139440", executable: "GunZ.exe", architecture: "x86", graphicsAPI: "DirectX 9", preferredRenderer: .wineD3D)
        let manifest = GameCompatibilityManifest(entries: [entry])
        let data = try JSONEncoder.portside.encode(manifest)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("3139440"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("token"))
    }
}
