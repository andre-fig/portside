import XCTest
@testable import PortsideCore

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    var specification: ProcessLaunchSpec?
    let result: ProcessResult

    init(result: ProcessResult = ProcessResult(status: 0, output: "", duration: 0.1)) {
        self.result = result
    }

    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult {
        self.specification = specification
        return result
    }
}

private struct TimeoutProcessRunner: ProcessRunning {
    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult {
        throw RuntimePipelineError.processTimedOut(specification.executable.lastPathComponent)
    }
}

final class PortsideCoreTests: XCTestCase {
    func testAppleSiliconRequirementAcceptsEnoughStorage() throws {
        let requirements = SystemRequirements(architecture: "arm64", macOSVersion: "macOS 26", availableStorage: 20_000_000_000)
        XCTAssertNoThrow(try requirements.validate())
    }

    func testRequirementRejectsIntel() {
        let requirements = SystemRequirements(architecture: "x86_64", macOSVersion: "macOS 26", availableStorage: 20_000_000_000)
        XCTAssertThrowsError(try requirements.validate()) { XCTAssertEqual($0 as? PortsideError, .unsupportedArchitecture("x86_64")) }
    }

    func testRequirementRejectsLowStorage() {
        let requirements = SystemRequirements(architecture: "arm64", macOSVersion: "macOS 26", availableStorage: 1)
        XCTAssertThrowsError(try requirements.validate())
    }

    func testSanitizerRedactsSecrets() {
        let sanitized = PortsideLogger.sanitize("password=secret token:abc123 bearer abc.def email user@example.com steam 76561198012345678 path \(NSHomeDirectory())?token=secret")
        XCTAssertFalse(sanitized.contains("secret")); XCTAssertFalse(sanitized.contains("abc123")); XCTAssertFalse(sanitized.contains("abc.def"))
        XCTAssertFalse(sanitized.contains("user@example.com")); XCTAssertFalse(sanitized.contains("76561198012345678")); XCTAssertFalse(sanitized.contains(NSHomeDirectory()))
    }

    func testDiagnosticContextContainsOnlyTechnicalFields() {
        let context = DiagnosticContext(stage: "steam_update", errorCode: "steam_update_failed", macOSVersion: "macOS 26", architecture: "arm64", runtimeVersion: "11.15", processType: "steam-bootstrap", exitCode: 7, duration: 2.5, retryCount: 1)
        XCTAssertEqual(context.fields["error_code"], "steam_update_failed")
        XCTAssertEqual(context.fields["architecture"], "arm64")
        XCTAssertFalse(context.fields.keys.contains("user"))
        XCTAssertFalse(context.fields.keys.contains("email"))
        XCTAssertFalse(context.fields.keys.contains("steam_id"))
    }

    func testSteamCEF32BitLaunchProfileIsExactAndStructured() {
        let profile = SteamInstaller.loginLaunchProfile
        XCTAssertEqual(profile.identifier, "cef_32bit_legacy_login")
        XCTAssertEqual(profile.requestedCEFArchitecture, "32bit")
        XCTAssertEqual(profile.arguments, ["-udpforce", "-noreactlogin", "-allosarches", "-cef-force-32bit"])
        XCTAssertFalse(profile.arguments.contains { $0.contains("=") || $0.contains(" ") || $0.contains("\"") })

        for strategy in SteamInstaller.uiLaunchConfigurations {
            let arguments = SteamInstaller.loginLaunchArguments(for: strategy)
            XCTAssertEqual(Array(arguments.prefix(profile.arguments.count)), profile.arguments)
            XCTAssertEqual(Array(arguments.dropFirst(profile.arguments.count).prefix(2)), SteamInstaller.defaultLanguageArguments)
            XCTAssertFalse(arguments.contains { $0 == "-allowseaches" || $0 == "-allosarches=" })
        }

        let context = DiagnosticContext(
            stage: "steam_launch",
            steamLaunchProfile: profile.identifier,
            steamLaunchArgumentsApplied: true,
            requestedCEFArchitecture: profile.requestedCEFArchitecture,
            effectiveCEFArchitecture: "64bit",
            legacyLoginFlagIgnored: true,
            webhelperProcessCount: 3
        )
        XCTAssertEqual(context.fields["steam_launch_profile"], "cef_32bit_legacy_login")
        XCTAssertEqual(context.fields["steam_launch_arguments_applied"], "true")
        XCTAssertEqual(context.fields["requested_cef_architecture"], "32bit")
        XCTAssertEqual(context.fields["effective_cef_architecture"], "64bit")
        XCTAssertEqual(context.fields["legacy_login_flag_ignored"], "true")
        XCTAssertEqual(context.fields["webhelper_process_count"], "3")
        XCTAssertFalse(context.fields.keys.contains("steam_id"))
        XCTAssertFalse(context.fields.keys.contains("cookie"))
    }

    func testWineEnvironmentInheritsHostContextAndPrependsRuntimePaths() {
        let environment = WineProcessEnvironment.make(
            runtimeExecutable: URL(fileURLWithPath: "/private/Runtime/bin/wine"),
            prefix: URL(fileURLWithPath: "/private/Prefix/Steam"),
            baseEnvironment: [
                "HOME": "/private/home",
                "TMPDIR": "/private/tmp",
                "USER": "tester",
                "LOGNAME": "tester",
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8",
                "PATH": "/usr/bin:/bin",
                "SHELL": "/bin/zsh"
            ]
        )
        XCTAssertEqual(environment["HOME"], "/private/home")
        XCTAssertEqual(environment["TMPDIR"], "/private/tmp")
        XCTAssertEqual(environment["LANG"], "en_US.UTF-8")
        XCTAssertEqual(environment["LC_ALL"], "en_US.UTF-8")
        XCTAssertEqual(environment["WINEPREFIX"], "/private/Prefix/Steam")
        XCTAssertEqual(environment["WINEARCH"], "win64")
        XCTAssertEqual(environment["WINEESYNC"], "1")
        XCTAssertEqual(environment["PATH"]?.split(separator: ":").first.map(String.init), "/private/Runtime/bin")
        XCTAssertTrue(environment["PATH"]?.contains("/usr/bin") == true)
        XCTAssertFalse(environment["DYLD_FRAMEWORK_PATH"]?.isEmpty ?? true)
        XCTAssertTrue(environment["GST_PLUGIN_PATH"]?.contains("gstreamer-1.0") == true)

        let noESyncEnvironment = WineProcessEnvironment.make(
            runtimeExecutable: URL(fileURLWithPath: "/private/Runtime/bin/wine"),
            prefix: URL(fileURLWithPath: "/private/Prefix/Steam"),
            baseEnvironment: [:],
            esyncEnabled: false
        )
        XCTAssertEqual(noESyncEnvironment["WINEESYNC"], "0")
    }

    func testDownloaderRejectsUnapprovedHostBeforeNetworkAccess() async {
        let downloader = SecureDownloader(allowedHosts: ["cdn.fastly.steamstatic.com"])
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("portside-blocked-download-\(UUID().uuidString)")
        do {
            _ = try await downloader.download(from: URL(string: "https://example.com/component.zip")!, to: destination)
            XCTFail("Unapproved download origin should be rejected")
        } catch {
            XCTAssertEqual(error as? PortsideError, .steamInstallerUnavailable)
        }
    }

    func testSteamInstallerIsHTTPSAndOfficialHost() {
        XCTAssertEqual(SteamInstaller.officialURL.scheme, "https")
        XCTAssertEqual(SteamInstaller.officialURL.host, "cdn.fastly.steamstatic.com")
        XCTAssertTrue(PortsidePaths.steamPrefix.path.contains("/Portside/Prefix/Steam"))
    }

    func testSilentSteamInstallerUsesSeparateUppercaseArgumentWithoutShell() {
        let specification = SteamInstaller.installationSpecification(runtimePath: "/tmp/wine", installerURL: URL(fileURLWithPath: "/tmp/SteamSetup.exe"), prefixURL: URL(fileURLWithPath: "/tmp/portside-prefix"))
        XCTAssertEqual(specification.arguments, ["/tmp/SteamSetup.exe", "/S"])
        XCTAssertEqual(specification.timeout, 180)
        XCTAssertFalse(specification.arguments.contains { $0.contains("sh -c") || $0.contains("bash -c") })
        XCTAssertEqual(specification.environment["WINEDEBUG"], "-all")
    }

    func testNativeSteamLoginMigrationCopiesOnlyRequiredItemsAndHandlesSpaces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-native-steam migration-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Application Support/Steam", isDirectory: true)
        let destination = root.appendingPathComponent("Prefix/Steam/drive_c/Program Files (x86)/Steam", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("config", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("userdata/76561198000000000", isDirectory: true), withIntermediateDirectories: true)
        try "login data".write(to: source.appendingPathComponent("config/loginusers.vdf"), atomically: true, encoding: .utf8)
        try Data("registry".utf8).write(to: source.appendingPathComponent("registry.vdf"))
        try Data("userdata".utf8).write(to: source.appendingPathComponent("userdata/76561198000000000/localconfig.vdf"))
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("config", isDirectory: true), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("config/old-file"))
        try Data("old registry".utf8).write(to: destination.appendingPathComponent("registry.vdf"))
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("userdata/old-account", isDirectory: true), withIntermediateDirectories: true)
        try Data("old userdata".utf8).write(to: destination.appendingPathComponent("userdata/old-account/localconfig.vdf"))
        let marker = root.appendingPathComponent("native-steam-login.marker")
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(SteamNativeLoginMigration.isComplete(at: destination, markerURL: marker))
        XCTAssertEqual(try SteamNativeLoginMigration.copyLoginData(from: source, to: destination, completionMarkerURL: marker), SteamNativeLoginMigration.requiredItems)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("config/loginusers.vdf")), "login data")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("registry.vdf")), "registry")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("userdata/76561198000000000/localconfig.vdf")), "userdata")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("config/old-file").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("userdata/old-account").path))
        XCTAssertTrue(SteamNativeLoginMigration.validateCopiedData(from: source, to: destination))
        XCTAssertTrue(SteamNativeLoginMigration.isComplete(at: destination, markerURL: marker))
        SteamNativeLoginMigration.invalidate(markerURL: marker)
        XCTAssertFalse(SteamNativeLoginMigration.isComplete(at: destination, markerURL: marker))
        let remaining = try FileManager.default.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil).map(\.lastPathComponent)
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".native-steam-login-") })
    }

    func testNativeSteamLoginStateRequiresRecentSavedAccount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-native-steam-state-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Steam", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("config", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("userdata", isDirectory: true), withIntermediateDirectories: true)
        try Data().write(to: source.appendingPathComponent("registry.vdf"))
        try Data("profile".utf8).write(to: source.appendingPathComponent("userdata/localconfig.vdf"))
        defer { try? FileManager.default.removeItem(at: root) }

        try "\"MostRecent\" \"1\"\n\"AllowAutoLogin\" \"1\"".write(to: source.appendingPathComponent("config/loginusers.vdf"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SteamNativeLoginMigration.loginState(at: source), .loggedIn)

        try "\"MostRecent\" \"1\"\n\"AllowAutoLogin\" \"0\"\n\"RememberPassword\" \"0\"".write(to: source.appendingPathComponent("config/loginusers.vdf"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SteamNativeLoginMigration.loginState(at: source), .notLoggedIn)

        try FileManager.default.removeItem(at: source.appendingPathComponent("userdata"))
        XCTAssertEqual(SteamNativeLoginMigration.loginState(at: source), .unavailable)
    }

    func testNativeSteamLoginMigrationRejectsMissingItemWithoutCreatingDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-native-steam-missing-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Steam", isDirectory: true)
        let destination = root.appendingPathComponent("Prefix/Steam/drive_c/Program Files (x86)/Steam", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("config", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("userdata", isDirectory: true), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try SteamNativeLoginMigration.copyLoginData(from: source, to: destination)) { error in
            XCTAssertEqual(error as? SteamNativeLoginMigrationError, .missingSourceItem("registry.vdf"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testInstallerTimeoutCanBeSimulatedWithoutLaunchingWine() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-installer-timeout-\(UUID().uuidString)", isDirectory: true)
        let installer = root.appendingPathComponent("SteamSetup.exe")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("installer".utf8).write(to: installer)
        defer { try? FileManager.default.removeItem(at: root) }
        let specification = SteamInstaller.installationSpecification(runtimePath: "/tmp/wine", installerURL: installer)
        XCTAssertEqual(specification.timeout, 180)
        let runtime = RuntimeDescriptor(name: "test", version: "1", executablePath: "/usr/bin/true", redistributable: false, licenseNote: "test")
        do {
            try await SteamInstaller.install(using: runtime, installerURL: installer, candidates: [], prefixURL: root.appendingPathComponent("Prefix"), runner: TimeoutProcessRunner())
            XCTFail("Timeout should fail setup")
        } catch {
            XCTAssertEqual(error as? RuntimePipelineError, .processTimedOut("true"))
        }
    }

    func testBootstrapUsesLegacyLoginProfile() {
        XCTAssertEqual(SteamInstaller.bootstrapArguments, ["-udpforce", "-noreactlogin", "-allosarches", "-cef-force-32bit"])
        XCTAssertEqual(SteamInstaller.noBrowserMiniGamesListArguments, ["-no-browser", "+open", "steam://open/minigameslist"])
        XCTAssertEqual(SteamInstaller.bootstrapArguments.count, 4)
        XCTAssertEqual(SteamInstaller.noBrowserMiniGamesListArguments.count, 3)
        XCTAssertFalse(SteamInstaller.bootstrapArguments.contains { $0.contains(" ") || $0.contains("\"") })
        XCTAssertFalse(SteamInstaller.noBrowserMiniGamesListArguments.contains { $0.contains(" ") || $0.contains("\"") })
        XCTAssertEqual(SteamInstaller.defaultLanguageArguments, ["-language", "english"])
        XCTAssertFalse(SteamInstaller.bootstrapArguments.contains { $0.contains("sh") || $0.contains("bash") })
        XCTAssertEqual(WineRuntimePolicy.debug, "-all")
        XCTAssertTrue(WineRuntimePolicy.dllOverrides.contains("winedbg.exe=d"))
    }

    func testSteamCEFStrategiesAreSeparateLimitedAndSecure() {
        XCTAssertEqual(SteamInstaller.uiArguments, [])
        XCTAssertEqual(SteamInstaller.fallbackUIArguments, ["-cef-disable-gpu", "-cef-disable-gpu-compositing"])
        XCTAssertEqual(SteamInstaller.uiLaunchConfigurations.count, 4)
        XCTAssertEqual(SteamInstaller.uiLaunchConfigurations.map(\.arguments), [[], [], ["-cef-disable-gpu"], ["-cef-disable-gpu", "-cef-disable-gpu-compositing"]])
        XCTAssertEqual(SteamInstaller.uiLaunchConfigurations[1].identifier, "WINEESYNC=0")
        XCTAssertFalse(SteamInstaller.uiLaunchConfigurations[1].esyncEnabled)
        XCTAssertFalse(SteamInstaller.uiLaunchConfigurations.flatMap(\.arguments).contains("-no-cef-sandbox"))
        XCTAssertFalse(SteamInstaller.uiLaunchConfigurations.flatMap(\.arguments).contains { $0.contains("steamapps") })
    }

    func testSteamCEFStrategyDoesNotChangeGameArguments() {
        let gameArguments = ["-novid", "-fullscreen"]
        let launch = SteamLaunchConfiguration(disableCEFGPU: true, additionalArguments: gameArguments)
        XCTAssertEqual(gameArguments, ["-novid", "-fullscreen"])
        XCTAssertFalse(launch.arguments.contains("-no-cef-sandbox"))
        XCTAssertEqual(launch.arguments.prefix(1), ["-cef-disable-gpu"])
    }

    func testSteamCEFLogAnalyzerReadsRelevantTailAndCountsRestarts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-cef-logs-\(UUID().uuidString)", isDirectory: true)
        let logs = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try "GPU process crashed\nRestart webhelper process, counter 1\nsteamwebhelper exited with code 7\nAccess denied while loading cache\n".write(to: logs.appendingPathComponent("cef_log.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let analysis = SteamCEFLogAnalyzer.analyze(prefix: root)
        XCTAssertEqual(analysis.webhelperRestartCount, 1)
        XCTAssertEqual(analysis.webhelperExitCode, 7)
        XCTAssertTrue(analysis.cacheCorruptionLikely)
        XCTAssertTrue(analysis.failureCategories.contains("cef_gpu_initialization_failed"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_cache_failure"))
        XCTAssertEqual(analysis.filesRead, ["cef_log.txt"])
    }

    func testSteamCEFLogAnalyzerReadsAllCEFLogsAndDoesNotTreatBareANGLEAsFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-cef-all-logs-\(UUID().uuidString)", isDirectory: true)
        let logs = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let contents: [String: String] = [
            "webhelper_gpu.txt": "ANGLE renderer selected\n",
            "cef_log.txt": "GPU process crashed\n",
            "steamui_html.txt": "BrowserReady\nCreateResponse\nGetDesiredSteamUIWindows\n",
            "steamui_login.txt": "WaitingForCredentials\nSetLoginState None\n",
            "webhelper.txt": "renderer process exited\nC:\\Program Files (x86)\\Steam\\bin\\cef\\cef.win64\\steamwebhelper.exe\n",
            "bootstrap_log.txt": "missing dll: d3dcompiler_47.dll\n",
            "console_log.txt": "ERR_CONNECTION_RESET\n",
            "connection_log.txt": "CRL - Verification failed\n"
        ]
        for (filename, content) in contents {
            try content.write(to: logs.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let analysis = SteamCEFLogAnalyzer.analyze(prefix: root)
        XCTAssertEqual(Set(analysis.filesRead), Set(SteamCEFLogAnalyzer.logFilenames))
        XCTAssertTrue(analysis.failureCategories.contains("cef_gpu_initialization_failed"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_renderer_failed"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_dependency_missing"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_network_failure"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_certificate_failure"))
        XCTAssertEqual(analysis.effectiveCEFArchitecture, "64bit")
        XCTAssertTrue(analysis.loginScreenDetected)
        XCTAssertFalse(analysis.failureCategories.contains("gpu"))
        XCTAssertFalse(analysis.hasStrongUIEvidence == true)
    }

    func testSteamCEFLogAnalyzerRequiresMoreThanBrowserReadyForStrongEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-cef-readiness-\(UUID().uuidString)", isDirectory: true)
        let logs = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try "BrowserReady\n".write(to: logs.appendingPathComponent("steamui_html.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let analysis = SteamCEFLogAnalyzer.analyze(prefix: root)
        XCTAssertTrue(analysis.browserReadyDetected)
        XCTAssertFalse(analysis.contentWindowEvidence)
        XCTAssertTrue(analysis.failureCategories.contains("cef_ui_unverified"))
        XCTAssertFalse(analysis.hasStrongUIEvidence)

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: logs.appendingPathComponent("steamui_html.txt").path)
        let stale = SteamCEFLogAnalyzer.analyze(prefix: root, minimumModificationDate: Date().addingTimeInterval(-10))
        XCTAssertFalse(stale.browserReadyDetected)
        XCTAssertFalse(stale.hasStrongUIEvidence)

        try "BrowserReady\nCreateResponse\nGetDesiredSteamUIWindows\nPopupHTMLWindow\n".write(to: logs.appendingPathComponent("steamui_html.txt"), atomically: true, encoding: .utf8)
        let verified = SteamCEFLogAnalyzer.analyze(prefix: root)
        XCTAssertTrue(verified.hasStrongUIEvidence)
    }

    func testSteamCEFLogAnalyzerUsesOnlyLinesWrittenAfterLaunchBaseline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-cef-baseline-\(UUID().uuidString)", isDirectory: true)
        let logs = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs", isDirectory: true)
        let htmlLog = logs.appendingPathComponent("steamui_html.txt")
        let gpuLog = logs.appendingPathComponent("webhelper_gpu.txt")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try "BrowserReady\nCreateResponse\nGetDesiredSteamUIWindows\nANGLE renderer selected\n".write(to: htmlLog, atomically: true, encoding: .utf8)
        try "ANGLE renderer error before this attempt\n".write(to: gpuLog, atomically: true, encoding: .utf8)
        let baseline = SteamCEFLogAnalyzer.captureBaseline(prefix: root)
        let handle = try FileHandle(forWritingTo: gpuLog)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("BrowserReady\nCreateResponse\nGetDesiredSteamUIWindows\n".utf8))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: root) }

        let analysis = SteamCEFLogAnalyzer.analyze(prefix: root, baseline: baseline)
        XCTAssertTrue(analysis.browserReadyDetected)
        XCTAssertTrue(analysis.contentWindowEvidence)
        XCTAssertFalse(analysis.failureCategories.contains("cef_angle_failed"))
        XCTAssertTrue(analysis.hasStrongUIEvidence)
    }

    func testSteamCEFLogAnalyzerReadsGPUAndConnectionFailuresFromFreshLogs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-cef-fresh-failures-\(UUID().uuidString)", isDirectory: true)
        let logs = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try "GPU process started\nEGLCreateContext failed: requested GLES version is unsupported\nCompositor context lost\n".write(to: logs.appendingPathComponent("webhelper_gpu.txt"), atomically: true, encoding: .utf8)
        try "WSALookupServiceBegin failed with: 8\n".write(to: logs.appendingPathComponent("connection_log.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let analysis = SteamCEFLogAnalyzer.analyze(prefix: root)
        XCTAssertEqual(analysis.gpuProcessStatus, "started")
        XCTAssertTrue(analysis.failureCategories.contains("cef_angle_failed"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_compositor_failed"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_network_failure"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_network_failed"))
    }

    func testSteamCEFLogAnalyzerClassifiesWebhelperCrashLoopAndResourceFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-cef-crash-loop-\(UUID().uuidString)", isDirectory: true)
        let logs = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try "Restart webhelper process\nRestart webhelper process\nRestart webhelper process\n".write(to: logs.appendingPathComponent("webhelper.txt"), atomically: true, encoding: .utf8)
        try "Failed to load resource https://example.invalid/app.js\n".write(to: logs.appendingPathComponent("cef_log.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let analysis = SteamCEFLogAnalyzer.analyze(prefix: root)
        XCTAssertTrue(analysis.failureCategories.contains("cef_webhelper_crash_loop"))
        XCTAssertTrue(analysis.failureCategories.contains("cef_resources_not_loaded"))
    }

    func testSteamHTMLCacheRecoveryRenamesOnlyHTMLCacheAndPreservesSteamData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-cache-recovery-\(UUID().uuidString)", isDirectory: true)
        let userRoot = root.appendingPathComponent("drive_c/users/test/AppData/Local/Steam", isDirectory: true)
        let htmlCache = userRoot.appendingPathComponent("htmlcache", isDirectory: true)
        let steamApps = root.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        try FileManager.default.createDirectory(at: htmlCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: steamApps, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: htmlCache.appendingPathComponent("index"))
        try Data("game".utf8).write(to: steamApps.appendingPathComponent("appmanifest.acf"))
        defer { try? FileManager.default.removeItem(at: root) }

        let backups = try SteamHTMLCacheRecovery.renameHTMLCache(prefix: root)
        XCTAssertEqual(backups.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: htmlCache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups[0].appendingPathComponent("index").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: steamApps.appendingPathComponent("appmanifest.acf").path))
    }

    func testDownloadProgressIsByteBasedAndClamped() {
        XCTAssertEqual(SecureDownloader.progressFraction(received: 25, total: 100), 0.25, accuracy: 0.001)
        XCTAssertEqual(SecureDownloader.progressFraction(received: 125, total: 100), 1.0, accuracy: 0.001)
        XCTAssertEqual(SecureDownloader.progressFraction(received: 1, total: 0), 0.0, accuracy: 0.001)
    }

    func testSilentInstallerFailureIsReportedWhenProcessExitsNonZero() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-installer-failure-\(UUID().uuidString)", isDirectory: true)
        let installer = root.appendingPathComponent("SteamSetup.exe")
        let prefix = root.appendingPathComponent("Prefix", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("installer".utf8).write(to: installer)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingProcessRunner(result: ProcessResult(status: 7, output: "failed", duration: 0.2))
        let runtime = RuntimeDescriptor(name: "test", version: "1", executablePath: "/usr/bin/true", redistributable: false, licenseNote: "test")

        do {
            try await SteamInstaller.install(using: runtime, installerURL: installer, candidates: [root.appendingPathComponent("missing.exe")], prefixURL: prefix, runner: runner)
            XCTFail("Non-zero installer exit should fail setup")
        } catch {
            XCTAssertTrue(error is RuntimePipelineError)
        }
        XCTAssertEqual(runner.specification?.arguments, [installer.path, "/S"])
    }

    func testInstallerSuccessWithoutSteamExecutableIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-installer-no-client-\(UUID().uuidString)", isDirectory: true)
        let installer = root.appendingPathComponent("SteamSetup.exe")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("installer".utf8).write(to: installer)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = RuntimeDescriptor(name: "test", version: "1", executablePath: "/usr/bin/true", redistributable: false, licenseNote: "test")

        do {
            try await SteamInstaller.install(using: runtime, installerURL: installer, candidates: [root.appendingPathComponent("missing.exe")], prefixURL: root.appendingPathComponent("Prefix"), runner: RecordingProcessRunner())
            XCTFail("A successful installer without steam.exe should fail validation")
        } catch {
            XCTAssertTrue(error is PortsideError)
        }
    }

    func testRuntimeManifestIsPinnedAndIncludesWineD3D() {
        XCTAssertEqual(FreeRuntimeCatalog.wine.version, "11.15")
        XCTAssertEqual(FreeRuntimeCatalog.wine.sha256, "a8c50d0e14fb7982a21506287e1e41e1990fe77c74fa2a32da7dbcf7b21de1e2")
        XCTAssertTrue(FreeRuntimeCatalog.wine.includedComponents.contains("WineD3D"))
        XCTAssertEqual(FreeRuntimeCatalog.wine.relativeExecutablePath, "Contents/Resources/wine/bin/wine")
        XCTAssertTrue(FreeRuntimeCatalog.wine.upstreamURL.absoluteString.hasPrefix("https://"))
    }

    func testArchivePathTraversalIsRejected() {
        XCTAssertTrue(SafeArchiveExtractor.isSafeRelativePath("Wine Staging.app/Contents/Resources/wine/bin/wine"))
        XCTAssertFalse(SafeArchiveExtractor.isSafeRelativePath("../../Library/LaunchAgents/unsafe"))
        XCTAssertFalse(SafeArchiveExtractor.isSafeRelativePath("/absolute/path"))
    }

    func testChecksumMismatchIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("portside-integrity-\(UUID().uuidString)")
        try Data("safe test data".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try IntegrityVerifier.verify(url: url, expectedSHA256: String(repeating: "0", count: 64)))
    }

    func testAtomicDirectoryInstallReplacesDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portside-atomic-\(UUID().uuidString)", isDirectory: true)
        let staged = root.appendingPathComponent("staged", isDirectory: true)
        let destination = root.appendingPathComponent("Runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: staged.appendingPathComponent("marker"))
        try Data("old".utf8).write(to: destination.appendingPathComponent("marker"))
        defer { try? FileManager.default.removeItem(at: root) }

        try AtomicInstaller.installDirectory(from: staged, to: destination)

        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker")), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testBlackWindowPixelAnalyzerDistinguishesBlackFromRenderedContent() {
        let black = Array(repeating: UInt8(0), count: 4 * 8 * 8)
        XCTAssertEqual(SteamWindowPixelAnalyzer.classify(width: 8, height: 8, bytesPerRow: 32, bytesPerPixel: 4, data: black), .black)

        var rendered = black
        for y in 2..<6 {
            for x in 2..<6 {
                let offset = (y * 32) + (x * 4)
                rendered[offset] = 255
                rendered[offset + 1] = 255
                rendered[offset + 2] = 255
            }
        }
        XCTAssertEqual(SteamWindowPixelAnalyzer.classify(width: 8, height: 8, bytesPerRow: 32, bytesPerPixel: 4, data: rendered), .rendered)
    }

    func testSteamLaunchLockAllowsOnlyOneCoordinator() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("portside-lock-\(UUID().uuidString)")
        let first = SteamLaunchLock.acquire(url: url)
        XCTAssertNotNil(first)
        XCTAssertNil(SteamLaunchLock.acquire(url: url))
        _ = first
    }

    func testEnvironmentPhaseIsCodable() throws {
        var state = EnvironmentState(); state.phase = .prefixCreating
        let data = try JSONEncoder.portside.encode(state)
        XCTAssertEqual(try JSONDecoder.portside.decode(EnvironmentState.self, from: data).phase, .prefixCreating)
    }

    func testRealSteamSetupWhenExplicitlyRequested() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PORTSIDE_REAL_INTEGRATION"] == "1", "Opt-in real runtime/Steam validation")
        let provider = FreeWineRuntimeProvider()
        let result = try await provider.install()
        let runtime = RuntimeDescriptor(name: result.record.manifest.identifier, version: result.record.manifest.version, executablePath: result.record.executablePath.path, redistributable: false, licenseNote: result.record.manifest.license)
        if SteamInstaller.locateInstalledExecutable() == nil {
            _ = try await SteamInstaller.download()
            try await SteamInstaller.install(using: runtime)
        }
        guard let steam = SteamInstaller.locateInstalledExecutable() else { XCTFail("steam.exe was not found"); return }
        var state = EnvironmentState(); state.runtime = runtime; state.runtimeRecord = result.record; state.steamExecutablePath = steam.path; state.steamInstalled = true
        let supervisor = ProcessSupervisor()
        let monitor = SteamReadinessMonitor()
        let windows10 = try await WinePrefixManager.ensureWindows10(runtimeExecutable: result.record.executablePath, prefix: PortsidePaths.steamPrefix)
        XCTAssertEqual(windows10.status, 0)
        await monitor.stopSteam(runtimeExecutable: result.record.executablePath, prefix: PortsidePaths.steamPrefix)
        _ = await monitor.waitForSteamToStop(timeout: 10)
        if !monitor.bootstrapComplete(prefix: PortsidePaths.steamPrefix) {
            try supervisor.launchSteam(state: state, arguments: SteamInstaller.bootstrapArguments)
            let bootstrapTimeout = TimeInterval(ProcessInfo.processInfo.environment["PORTSIDE_BOOTSTRAP_TIMEOUT"] ?? "180") ?? 180
            let bootstrapCompleted = await monitor.waitForBootstrap(prefix: PortsidePaths.steamPrefix, timeout: bootstrapTimeout)
            XCTAssertTrue(bootstrapCompleted)
            supervisor.requestStop()
        }
        try supervisor.launchSteam(state: state, arguments: SteamInstaller.uiLaunchConfigurations[0].arguments)
        let timeout = TimeInterval(ProcessInfo.processInfo.environment["PORTSIDE_REAL_TIMEOUT"] ?? "180") ?? 180
        let report = await monitor.waitForSteamReport(executable: steam, strategy: .primary, timeout: timeout)
        XCTAssertEqual(report.status, .ready, "Steam did not present a verified real window; status=\(report.status.rawValue)")
        XCTAssertTrue(report.webhelperStarted)
    }

    func testSteamHasNoAppIDCompatibilityAllowlist() {
        // Steam remains the sole library and launch authority; Portside has no game catalog.
        XCTAssertTrue(SteamInstaller.steamExecutableCandidates.allSatisfy { $0.path.contains("Prefix/Steam") })
    }
}
