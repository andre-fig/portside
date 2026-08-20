import XCTest
import CryptoKit
@testable import PortsideCore

final class PortsideCoreTests: XCTestCase {
    func testGoldenBaselineMatchesPortsideConfiguration() {
        let configuration = PortsideRuntimeConfiguration.golden
        XCTAssertEqual(PortsideRuntimeConfiguration.creatorVersion, "Portside")
        XCTAssertEqual(PortsideRuntimeConfiguration.templateVersion, "Portside wrapper 1")
        XCTAssertEqual(PortsideRuntimeConfiguration.engineName, "PortsideWineEngine")
        XCTAssertEqual(configuration.renderer, .wineD3D)
        XCTAssertTrue(configuration.msync)
        XCTAssertTrue(configuration.esync)
        XCTAssertEqual(configuration.programFlags, "")
        XCTAssertEqual(configuration.wineDebug, "-plugplay,+loaddll")
        XCTAssertEqual(configuration.environment["D3DMETAL"], "0")
        XCTAssertEqual(configuration.environment["DXMT"], "0")
        XCTAssertEqual(configuration.environment["DXVK"], "0")
    }

    func testRuntimeCatalogRequiresPortsideComponents() {
        XCTAssertEqual(PortsideRuntimeCatalog.requiredComponents, ["wrapper", "engine", "winetricks"])
        XCTAssertEqual(PortsideRuntimeCatalog.wrapperName, "PortsideBaseline.app")
    }

    func testUpdateChecksAtMostOncePerDay() {
        let now = Date()
        XCTAssertTrue(PortsideUpdateService.shouldCheck(lastCheck: nil, now: now))
        XCTAssertFalse(PortsideUpdateService.shouldCheck(lastCheck: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(PortsideUpdateService.shouldCheck(lastCheck: now.addingTimeInterval(-86_401), now: now))
    }

    func testWrapperConfigurationDoesNotEnableAlternativeRenderers() throws {
        XCTAssertEqual(PortsideRuntimeCatalog.steamExecutable, "C:\\Program Files (x86)\\Steam\\steam.exe")
        XCTAssertEqual(PortsideRuntimeConfiguration.golden.environment["D3DMETAL"], "0")
        XCTAssertEqual(PortsideRuntimeConfiguration.golden.environment["DXMT"], "0")
        XCTAssertEqual(PortsideRuntimeConfiguration.golden.environment["DXVK"], "0")
        XCTAssertThrowsError(try PortsideRuntimeConfiguration(renderer: .dxvk))
    }

    func testSteamInstallUsesPortsideWinetricksVerbAndNoCustomSteamFlags() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let launcher = root.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: launcher.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = try PortsideSteamFlow.installationSpec(wrapper: root)
        XCTAssertEqual(spec.arguments, ["--winetricks", "steam"])
        XCTAssertFalse(spec.arguments.joined(separator: " ").contains("cef"))
        XCTAssertFalse(spec.arguments.contains { $0.contains("noreactlogin") || $0.contains("allosarches") })
    }

    func testCleanLaunchUsesThePortsideHostWithoutDirectWineOrSteamArguments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let launcher = root.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: launcher.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = try PortsideSteamFlow.cleanLaunchSpec(wrapper: root)
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
        XCTAssertFalse(PortsideLogger.sanitize("C:\\users\\andrefigueiredo\\AppData\\Local").contains("andrefigueiredo"))
    }

    func testDiagnosticsAllowOnlyNonSensitiveFields() {
        let context = DiagnosticContext(renderer: "wineD3D", appID: "3139440", msyncEnabled: true, esyncEnabled: true)
        XCTAssertEqual(context.fields["app_id"], "3139440")
        XCTAssertNil(context.fields["password"])
        XCTAssertFalse(context.fields.keys.contains { $0.localizedCaseInsensitiveContains("token") })
    }

    func testRendererFallbacksAreOrderedAndMutuallyExclusive() {
        let x64 = GameExecutableInfo(architecture: "x86_64", graphicsAPI: "DirectX 11")
        XCTAssertEqual(GameCompatibilityService.renderer(for: x64), [.dxmt, .wineD3D])
        let x86 = GameExecutableInfo(architecture: "x86", graphicsAPI: "DirectX 11")
        XCTAssertEqual(GameCompatibilityService.renderer(for: x86), [.dxmt, .wineD3D])
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

    func testLocalBuildDisablesAppUpdatesUntilProductionValuesAreInjected() {
        XCTAssertFalse(PortsideAppUpdateConfiguration.isConfigured(feed: "", publicKey: ""))
        XCTAssertFalse(PortsideAppUpdateConfiguration.isConfigured(feed: "https://example.invalid/appcast.xml", publicKey: "public"))
        XCTAssertTrue(PortsideAppUpdateConfiguration.isConfigured(feed: "https://updates.portside.test/v1/appcast.xml", publicKey: "public"))
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

    func testSignedRuntimeManifestAndMinimumVersionAreValidated() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        var unsigned: [String: Any] = [
            "schemaVersion": 1,
            "channel": "staging",
            "manifestVersion": "1.0.0",
            "minimumPortsideVersion": "0.1.0",
            "publishedAt": "2026-08-19T00:00:00Z",
            "builtBy": "Portside",
            "buildId": "test-build",
            "buildStatus": "staging",
            "components": ["wrapper", "engine", "winetricks"].map { name in [
                "id": name,
                "component": name,
                "version": "1.0.0",
                "downloadURL": "https://downloads.portside.test/\(name).tar.xz",
                "sha256": String(repeating: "a", count: 64),
                "size": 10,
                "critical": false,
                "rollbackVersion": NSNull(),
                "builtBy": "Portside",
                "sourcePath": "vendor/\(name)",
                "sourceCommit": String(repeating: "b", count: 40),
                "sourceSnapshotChecksum": String(repeating: "c", count: 64),
                "license": "LGPL-2.1-or-later"
            ]},
            "rendererDefaults": ["renderer": "wineD3D"],
            "compatibilityRules": [],
            "critical": false,
            "rollbackVersion": NSNull(),
            "signatureKeyId": "manifest-1",
            "signature": NSNull()
        ]
        let unsignedData = try JSONSerialization.data(withJSONObject: unsigned, options: [.sortedKeys])
        let signature = try signingKey.signature(for: unsignedData).base64EncodedString()
        unsigned["signature"] = signature
        let data = try JSONSerialization.data(withJSONObject: unsigned, options: [.sortedKeys])
        let manifest = try PortsideManifestVerifier.verify(data, publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(), expectedKeyID: "manifest-1", currentVersion: "0.1.0", allowedHosts: ["downloads.portside.test"])
        XCTAssertEqual(manifest.components.count, 3)
        XCTAssertThrowsError(try PortsideManifestVerifier.verify(data, publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(), expectedKeyID: "manifest-1", expectedChannel: "production", currentVersion: "0.1.0", allowedHosts: ["downloads.portside.test"]))
        XCTAssertThrowsError(try PortsideManifestVerifier.verify(data, publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(), expectedKeyID: "manifest-1", currentVersion: "0.0.9", allowedHosts: ["downloads.portside.test"]))
    }

    func testLicenseTokenAcceptsOnlyTheConfiguredSignature() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let header = Data("{\"alg\":\"EdDSA\",\"typ\":\"PORTSIDE-LICENSE\"}".utf8).base64EncodedString()
        let payload = Data("{\"licenseId\":\"lic-1\",\"deviceId\":\"dev-1\",\"plan\":\"standard\",\"issuedAt\":4102444800,\"expiresAt\":4103654400,\"offlineUntil\":4103654400,\"keyId\":\"license-1\"}".utf8).base64EncodedString()
        let input = "\(header).\(payload)"
        let signatureData = try signingKey.signature(for: Data(input.utf8))
        let token = "\(input).\(signatureData.base64EncodedString())"
        XCTAssertEqual(try PortsideLicenseClient.verifyLocal(token: token, publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(), expectedKeyID: "license-1").deviceId, "dev-1")
        var invalidSignature = signatureData
        invalidSignature[0] ^= 0x01
        XCTAssertThrowsError(try PortsideLicenseClient.verifyLocal(token: "\(input).\(invalidSignature.base64EncodedString())", publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(), expectedKeyID: "license-1"))
    }

    func testSteamLibraryScannerParsesAndTracksManagedInstallations() throws {
        let root = PortsidePaths.root.appendingPathComponent(".test-library-" + UUID().uuidString, isDirectory: true)
        let prefix = root.appendingPathComponent("Prefix", isDirectory: true)
        let steamLibrary = root.appendingPathComponent("Library", isDirectory: true)
        let steamApps = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        let gameDirectory = steamApps.appendingPathComponent("common/Example Game", isDirectory: true)
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        let folders = """
        "libraryfolders"
        {
            "0"
            {
                "path" "C:\\Program Files (x86)\\Steam"
                "apps"
                {
                    "304930" "123"
                }
            }
        }
        """
        try Data(folders.utf8).write(to: steamApps.appendingPathComponent("libraryfolders.vdf"))
        let manifestURL = steamApps.appendingPathComponent("appmanifest_304930.acf")
        func writeManifest(updated: String, size: String) throws {
            let manifest = """
            "AppState"
            {
                "appid" "304930"
                "name" "Example Game"
                "StateFlags" "4"
                "installdir" "Example Game"
                "LastUpdated" "\(updated)"
                "SizeOnDisk" "\(size)"
            }
            """
            try Data(manifest.utf8).write(to: manifestURL)
        }
        try writeManifest(updated: "100", size: "10")
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = SteamLibraryScanner(prefix: prefix, steamLibrary: steamLibrary)
        let first = try scanner.scan()
        XCTAssertEqual(first.snapshot.games.first?.appID, "304930")
        XCTAssertEqual(first.snapshot.games.first?.installDirectory, gameDirectory.standardizedFileURL)
        XCTAssertEqual(first.changes.count, 1)
        XCTAssertTrue(first.changes.first == .installed(first.snapshot.games[0]))

        try writeManifest(updated: "200", size: "20")
        let second = try scanner.scan(previous: first.snapshot)
        XCTAssertTrue(second.changes.contains { if case .updated = $0 { return true }; return false })

        try FileManager.default.removeItem(at: manifestURL)
        let third = try scanner.scan(previous: second.snapshot)
        XCTAssertTrue(third.changes.contains { if case .removed(let appID, _) = $0 { return appID == "304930" }; return false })
    }

    func testPEScannerBuildsGeneralProfileWithUnityAndAntiCheatEvidence() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".exe")
        try makeFakePE(machine: 0x8664, strings: "d3d11.dll UnityPlayer.dll BattlEye launcher").write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let evidence = try PEImportScanner().scan(url: file)
        XCTAssertEqual(evidence.architecture, .x86_64)
        XCTAssertTrue(evidence.graphicsAPIs.contains(.directX11))
        XCTAssertTrue(evidence.engineHints.contains("unity"))
        XCTAssertTrue(evidence.antiCheatProviders.contains(.battlEye))
        let profile = CompatibilityProfileBuilder.build(appID: "304930", gameName: "Unturned", evidences: [evidence])
        XCTAssertEqual(profile.appID, "304930")
        XCTAssertEqual(profile.preferredRenderer, .dxmt)
        XCTAssertTrue(profile.fallbackRenderers.contains(.dxvk))
        XCTAssertEqual(profile.antiCheat.first?.provider, .battlEye)
        XCTAssertEqual(profile.antiCheat.first?.status, "informational")
    }

    func testRendererManagerKeepsTwoExecutablesIndependentAndRollsBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configURL = root.appendingPathComponent("renderer-configurations.json")
        let firstURL = root.appendingPathComponent("GameA.exe")
        let secondURL = root.appendingPathComponent("GameB.exe")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("save data".utf8).write(to: root.appendingPathComponent("save.dat"))
        defer { try? FileManager.default.removeItem(at: root) }
        let inventory = RuntimeComponentInventory(wrapper: root, renderers: [
            RendererProfile(renderer: .wineD3D, available: true),
            RendererProfile(renderer: .dxmt, available: true),
            RendererProfile(renderer: .dxvk, available: true)
        ])
        let manager = RendererManager(wrapper: root, prefix: root.appendingPathComponent("prefix"), configurationURL: configURL, executeRegistryChanges: false, inventory: inventory)
        let firstSnapshot = manager.snapshot(appID: "304930", executable: firstURL)
        let first = try await manager.apply(renderer: .dxmt, appID: "304930", executable: firstURL)
        let second = try await manager.apply(renderer: .dxvk, appID: "304930", executable: secondURL)
        let proof = RendererManager.isolationProof(first: first, second: second)
        XCTAssertTrue(proof.independent)
        XCTAssertEqual(manager.configuration(appID: "304930", executable: firstURL)?.renderer, .dxmt)
        XCTAssertEqual(manager.configuration(appID: "304930", executable: secondURL)?.renderer, .dxvk)
        try await manager.rollback(firstSnapshot)
        XCTAssertNil(manager.configuration(appID: "304930", executable: firstURL))
        XCTAssertEqual(manager.configuration(appID: "304930", executable: secondURL)?.renderer, .dxvk)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("save.dat")), "save data")
    }

    func testLaunchMonitorDistinguishesGraphicsAnticheatAndUnverifiedState() {
        let graphics = GameLaunchSignals(appID: "1", executable: "game.exe", renderer: .wineD3D, architecture: .x86_64, duration: 2, exitCode: 1, deviceCreationFailed: true)
        XCTAssertEqual(GameLaunchMonitor.classify(graphics), .graphicsInitializationFailed)
        let anticheat = GameLaunchSignals(appID: "304930", executable: "Unturned.exe", renderer: .wineD3D, architecture: .x86_64, duration: 5, exitCode: 1, anticheatDetected: true)
        XCTAssertEqual(GameLaunchMonitor.classify(anticheat), .anticheatUnsupported)
        let unverified = GameLaunchSignals(appID: "1", executable: "game.exe", renderer: .wineD3D, architecture: .x86, duration: 30, exitCode: 0, stable: true, visualStateVerified: false)
        let attempt = GameLaunchMonitor.attempt(from: unverified)
        XCTAssertEqual(attempt.result, .visualStateUnverified)
        XCTAssertTrue(attempt.visualStateUnverified)
    }

    func testAgentStopsOnlyWhenManagedSteamIsGone() {
        XCTAssertTrue(PortsideAgent.shouldContinue(steamManagedProcessCount: 1))
        XCTAssertFalse(PortsideAgent.shouldContinue(steamManagedProcessCount: 0))
    }

    func testFallbackPolicyAllowsOnlyOneOfflineGraphicsRetry() {
        let profile = GameCompatibilityProfile(appID: "1", gameName: "Game", executables: [ExecutableProfile(executablePath: "/Games/Game.exe", architecture: .x86_64, detectedAPIs: [.directX11], preferredRenderer: .wineD3D, fallbackRenderers: [.dxmt, .wineD3D])], preferredRenderer: .wineD3D, fallbackRenderers: [.dxmt])
        let decision = CompatibilityFallbackPolicy.nextRenderer(profile: profile, executable: "/Games/Game.exe", attempted: .wineD3D, result: .graphicsInitializationFailed, attemptsAlreadyMade: 0)
        XCTAssertEqual(decision?.renderer, .dxmt)
        XCTAssertNil(CompatibilityFallbackPolicy.nextRenderer(profile: profile, executable: "/Games/Game.exe", attempted: .wineD3D, result: .graphicsInitializationFailed, attemptsAlreadyMade: 1))
        XCTAssertNil(CompatibilityFallbackPolicy.nextRenderer(profile: profile, executable: "/Games/Game.exe", attempted: .wineD3D, result: .graphicsInitializationFailed, attemptsAlreadyMade: 0, onlineSession: true))
        let antiCheat = GameCompatibilityProfile(appID: "1", gameName: "Game", executables: [], preferredRenderer: .wineD3D, fallbackRenderers: [.dxmt], antiCheat: [AntiCheatProfile(provider: .battlEye)])
        XCTAssertNil(CompatibilityFallbackPolicy.nextRenderer(profile: antiCheat, executable: "Game.exe", attempted: .wineD3D, result: .graphicsInitializationFailed, attemptsAlreadyMade: 0))
    }

    private func makeFakePE(machine: UInt16, strings: String) -> Data {
        var data = Data(repeating: 0, count: 512)
        data[0] = 0x4d
        data[1] = 0x5a
        data[0x3c] = 0x80
        data[0x80] = 0x50
        data[0x81] = 0x45
        data[0x84] = UInt8(machine & 0xff)
        data[0x85] = UInt8(machine >> 8)
        data[0x94] = 0x02
        data[0x98] = 0x0b
        data[0x99] = 0x01
        data.append(contentsOf: Data(strings.utf8))
        return data
    }
}
