import Foundation
import CryptoKit

public enum PortsidePaths {
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Portside", isDirectory: true)
    }

    public static var runtime: URL { root.appendingPathComponent("Runtime", isDirectory: true) }
    public static var prefix: URL { root.appendingPathComponent("Prefix", isDirectory: true) }
    public static var steamPrefix: URL { prefix.appendingPathComponent("Steam", isDirectory: true) }
    public static var legacyPrefixes: URL { root.appendingPathComponent("Prefixes", isDirectory: true) }
    public static var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public static var cache: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public static var downloads: URL { root.appendingPathComponent("Downloads", isDirectory: true) }
    public static var diagnostics: URL { root.appendingPathComponent("Diagnostics", isDirectory: true) }
    public static var launchers: URL { root.appendingPathComponent("Launchers", isDirectory: true) }

    public static var allDirectories: [URL] {
        [root, runtime, prefix, steamPrefix, logs, cache, downloads, diagnostics, launchers]
    }
}

public enum PortsideError: LocalizedError, Equatable {
    case unsupportedArchitecture(String)
    case unsupportedOperatingSystem(String)
    case insufficientStorage(required: Int64, available: Int64)
    case runtimeUnavailable
    case steamInstallerUnavailable
    case processLaunchFailed(String)
    case invalidPath

    public var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture: return "Portside requires an Apple silicon Mac."
        case .unsupportedOperatingSystem(let version): return "macOS \(version) is not supported by this build."
        case .insufficientStorage(let required, let available):
            return "Portside needs at least \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)); only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available."
        case .runtimeUnavailable: return "No authorized Windows compatibility runtime was found."
        case .steamInstallerUnavailable: return "The official Steam installer could not be downloaded."
        case .processLaunchFailed(let reason): return reason
        case .invalidPath: return "The selected path is not safe for Portside."
        }
    }
}

public struct SystemRequirements: Equatable, Sendable {
    public let architecture: String
    public let macOSVersion: String
    public let availableStorage: Int64
    public let isAppleSilicon: Bool
    public let meetsMinimum: Bool

    public init() {
        self.init(
            architecture: ProcessInfo.processInfo.machineArchitecture,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            availableStorage: Self.currentAvailableStorage()
        )
    }

    public init(architecture: String, macOSVersion: String, availableStorage: Int64) {
        self.architecture = architecture
        self.macOSVersion = macOSVersion
        self.availableStorage = availableStorage
        self.isAppleSilicon = architecture == "arm64"
        self.meetsMinimum = self.isAppleSilicon && availableStorage >= 12_000_000_000
    }

    public func validate() throws {
        guard isAppleSilicon else { throw PortsideError.unsupportedArchitecture(architecture) }
        guard availableStorage >= 12_000_000_000 else {
            throw PortsideError.insufficientStorage(required: 12_000_000_000, available: availableStorage)
        }
    }

    public static func currentAvailableStorage() -> Int64 {
        (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
    }
}

public struct RuntimeDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let executablePath: String?
    public let redistributable: Bool
    public let licenseNote: String

    public init(name: String, version: String, executablePath: String?, redistributable: Bool, licenseNote: String) {
        self.name = name
        self.version = version
        self.executablePath = executablePath
        self.redistributable = redistributable
        self.licenseNote = licenseNote
    }
}

public struct EnvironmentState: Codable, Equatable, Sendable {
    public var setupCompleted = false
    public var steamInstalled = false
    public var runtime: RuntimeDescriptor?
    public var runtimeRecord: InstalledRuntimeRecord?
    public var phase: EnvironmentPhase?
    public var steamExecutablePath: String?
    public var lastSteamStatus: SteamProcessStatus?
    public var lastError: String?
    public var retryCount = 0
    public var lastErrorCode: String?
    public var lastProcessType: String?
    public var lastExitCode: Int32?
    public var lastSetupDuration: TimeInterval?
    public var lastUpdated: Date?

    public init() {}
}

public struct DiagnosticContext: Sendable, Equatable {
    public var stage: String?
    public var errorCode: String?
    public var portsideVersion: String
    public var portsideBuild: String
    public var macOSVersion: String?
    public var architecture: String?
    public var runtimeName: String?
    public var runtimeVersion: String?
    public var graphicsBackend: String?
    public var processType: String?
    public var exitCode: Int32?
    public var duration: TimeInterval?
    public var retryCount: Int
    public var cefStrategy: String?
    public var cefFailureCategory: String?
    public var webhelperRestartCount: Int?
    public var webhelperStarted: Bool?
    public var webhelperExitCode: Int32?
    public var rendererMode: String?
    public var gpuProcessStatus: String?
    public var windowDetected: Bool?
    public var browserReadyDetected: Bool?
    public var windowVisualState: String?
    public var cacheRecoveryAttempted: Bool?
    public var steamVersion: String?
    public var steamLaunchProfile: String?
    public var steamLaunchArgumentsApplied: Bool?
    public var requestedCEFArchitecture: String?
    public var effectiveCEFArchitecture: String?
    public var legacyLoginFlagIgnored: Bool?
    public var webhelperProcessCount: Int?

    public init(
        stage: String? = nil,
        errorCode: String? = nil,
        portsideVersion: String = "0.1.0",
        portsideBuild: String = "1",
        macOSVersion: String? = nil,
        architecture: String? = nil,
        runtimeName: String? = nil,
        runtimeVersion: String? = nil,
        graphicsBackend: String? = nil,
        processType: String? = nil,
        exitCode: Int32? = nil,
        duration: TimeInterval? = nil,
        retryCount: Int = 0,
        cefStrategy: String? = nil,
        cefFailureCategory: String? = nil,
        webhelperRestartCount: Int? = nil,
        webhelperStarted: Bool? = nil,
        webhelperExitCode: Int32? = nil,
        rendererMode: String? = nil,
        gpuProcessStatus: String? = nil,
        windowDetected: Bool? = nil,
        browserReadyDetected: Bool? = nil,
        windowVisualState: String? = nil,
        cacheRecoveryAttempted: Bool? = nil,
        steamVersion: String? = nil,
        steamLaunchProfile: String? = nil,
        steamLaunchArgumentsApplied: Bool? = nil,
        requestedCEFArchitecture: String? = nil,
        effectiveCEFArchitecture: String? = nil,
        legacyLoginFlagIgnored: Bool? = nil,
        webhelperProcessCount: Int? = nil
    ) {
        self.stage = stage; self.errorCode = errorCode; self.portsideVersion = portsideVersion; self.portsideBuild = portsideBuild
        self.macOSVersion = macOSVersion; self.architecture = architecture; self.runtimeName = runtimeName; self.runtimeVersion = runtimeVersion
        self.graphicsBackend = graphicsBackend; self.processType = processType; self.exitCode = exitCode; self.duration = duration; self.retryCount = retryCount
        self.cefStrategy = cefStrategy; self.cefFailureCategory = cefFailureCategory; self.webhelperRestartCount = webhelperRestartCount
        self.webhelperStarted = webhelperStarted; self.webhelperExitCode = webhelperExitCode; self.rendererMode = rendererMode
        self.gpuProcessStatus = gpuProcessStatus; self.windowDetected = windowDetected; self.browserReadyDetected = browserReadyDetected
        self.windowVisualState = windowVisualState; self.cacheRecoveryAttempted = cacheRecoveryAttempted; self.steamVersion = steamVersion
        self.steamLaunchProfile = steamLaunchProfile; self.steamLaunchArgumentsApplied = steamLaunchArgumentsApplied
        self.requestedCEFArchitecture = requestedCEFArchitecture; self.effectiveCEFArchitecture = effectiveCEFArchitecture
        self.legacyLoginFlagIgnored = legacyLoginFlagIgnored; self.webhelperProcessCount = webhelperProcessCount
    }

    public var fields: [String: String] {
        var values: [String: String] = [
            "portside_version": portsideVersion,
            "portside_build": portsideBuild,
            "retry_count": String(retryCount)
        ]
        let optionalValues: [(String, String?)] = [
            ("stage", stage), ("error_code", errorCode), ("macos_version", macOSVersion), ("architecture", architecture),
            ("runtime_name", runtimeName), ("runtime_version", runtimeVersion), ("graphics_backend", graphicsBackend),
            ("process_type", processType), ("exit_code", exitCode.map(String.init)), ("duration", duration.map { String(format: "%.2f", $0) }),
            ("cef_strategy", cefStrategy), ("cef_failure_category", cefFailureCategory),
            ("webhelper_restart_count", webhelperRestartCount.map(String.init)),
            ("webhelper_started", webhelperStarted.map(String.init)), ("webhelper_exit_code", webhelperExitCode.map(String.init)),
            ("renderer_mode", rendererMode), ("gpu_process_status", gpuProcessStatus),
            ("window_detected", windowDetected.map(String.init)), ("browser_ready", browserReadyDetected.map(String.init)),
            ("browser_ready_detected", browserReadyDetected.map(String.init)),
            ("window_visual_state", windowVisualState),
            ("cache_recovery_attempted", cacheRecoveryAttempted.map(String.init)), ("steam_version", steamVersion),
            ("steam_launch_profile", steamLaunchProfile), ("steam_launch_arguments_applied", steamLaunchArgumentsApplied.map(String.init)),
            ("requested_cef_architecture", requestedCEFArchitecture), ("effective_cef_architecture", effectiveCEFArchitecture),
            ("legacy_login_flag_ignored", legacyLoginFlagIgnored.map(String.init)), ("webhelper_process_count", webhelperProcessCount.map(String.init)),
        ]
        for (key, value) in optionalValues where value != nil { values[key] = value! }
        return values
    }
}

public protocol DiagnosticsService: Sendable {
    func breadcrumb(_ name: String, context: DiagnosticContext)
    func event(_ name: String, context: DiagnosticContext)
    func capture(error: Error, context: DiagnosticContext)
}

public struct NoopDiagnosticsService: DiagnosticsService {
    public init() {}
    public func breadcrumb(_ name: String, context: DiagnosticContext) {}
    public func event(_ name: String, context: DiagnosticContext) {}
    public func capture(error: Error, context: DiagnosticContext) {}
}

public final class EnvironmentStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let stateURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.stateURL = PortsidePaths.root.appendingPathComponent("environment.json")
    }

    public func prepareDirectories() throws {
        for directory in [PortsidePaths.root, PortsidePaths.runtime, PortsidePaths.logs, PortsidePaths.cache, PortsidePaths.downloads, PortsidePaths.diagnostics] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: PortsidePaths.prefix.path),
           fileManager.fileExists(atPath: PortsidePaths.legacyPrefixes.path) {
            try fileManager.moveItem(at: PortsidePaths.legacyPrefixes, to: PortsidePaths.prefix)
        }
        try fileManager.createDirectory(at: PortsidePaths.prefix, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: PortsidePaths.steamPrefix, withIntermediateDirectories: true)
    }

    public func load() -> EnvironmentState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder.portside.decode(EnvironmentState.self, from: data) else { return EnvironmentState() }
        return state
    }

    public func save(_ state: EnvironmentState) throws {
        try prepareDirectories()
        let data = try JSONEncoder.portside.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }
}

public final class PortsideLogger: @unchecked Sendable {
    public enum Level: String, Sendable { case info, warning, error }
    private let fileManager: FileManager
    private let logURL: URL
    private let lock = NSLock()

    public init(fileManager: FileManager = .default, logFileName: String = "portside.log") {
        self.fileManager = fileManager
        self.logURL = PortsidePaths.logs.appendingPathComponent(logFileName)
    }

    public func write(_ message: String, level: Level = .info) {
        lock.lock(); defer { lock.unlock() }
        try? fileManager.createDirectory(at: PortsidePaths.logs, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let sanitized = String(Self.sanitize(message).prefix(8_000))
        let line = "[\(timestamp)] [\(level.rawValue.uppercased())] \(sanitized)\n"
        if let data = line.data(using: .utf8) {
            if fileManager.fileExists(atPath: logURL.path), let handle = try? FileHandle(forWritingTo: logURL) {
                _ = try? handle.seekToEnd(); _ = try? handle.write(contentsOf: data); _ = try? handle.close()
            } else { try? data.write(to: logURL, options: .atomic) }
        }
        rotateIfNeeded()
    }

    public func read() -> String {
        guard let contents = try? String(contentsOf: logURL, encoding: .utf8) else { return "No Portside log entries yet." }
        return String(Self.sanitize(contents).suffix(128_000))
    }

    public static func sanitize(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        result = result.replacingOccurrences(of: #"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, with: "[EMAIL_REDACTED]", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?<!\d)\d{17}(?!\d)"#, with: "[STEAM_ID_REDACTED]", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)(https?://[^\s?]+)(\?[^\s]+)?"#, with: "$1?[REDACTED_QUERY]", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"(?i)(password|passwd|token|cookie|authorization|secret)\s*[:=]\s*[^\s,;]+"#,
            with: "$1=[REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)bearer\s+[A-Za-z0-9._-]+"#,
            with: "bearer [REDACTED]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: #"(?i)(WINEPREFIX|HOME|USER|USERNAME|SENTRY_AUTH_TOKEN)\s*=\s*[^\s,;]+"#, with: "$1=[REDACTED]", options: .regularExpression)
        return result
    }

    private func rotateIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber, size.int64Value > 512_000 else { return }
        let rotated = logURL.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotated)
        try? fileManager.moveItem(at: logURL, to: rotated)
    }
}

public struct DownloadResult: Sendable, Equatable {
    public let url: URL
    public let sha256: String
    public let bytes: Int64
}

public final class SecureDownloader: NSObject, @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (Double) -> Void
    private let session: URLSession
    private let fileManager: FileManager
    private let logger: PortsideLogger
    private let allowedHosts: Set<String>

    public init(fileManager: FileManager = .default, logger: PortsideLogger = PortsideLogger(), allowedHosts: Set<String> = ["github.com", "gstreamer.freedesktop.org", "cdn.fastly.steamstatic.com"]) {
        self.fileManager = fileManager
        self.logger = logger
        self.allowedHosts = allowedHosts
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        super.init()
    }

    public static func progressFraction(received: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(received) / Double(total)))
    }

    public func download(from source: URL, to destination: URL, progress: ProgressHandler? = nil) async throws -> DownloadResult {
        guard source.scheme == "https", let host = source.host, allowedHosts.contains(host.lowercased()) else { throw PortsideError.steamInstallerUnavailable }
        var request = URLRequest(url: source)
        request.timeoutInterval = 120
        let partialURL = destination.appendingPathExtension("part")
        let existingBytes = (try? partialURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if existingBytes > 0 { request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range") }
        let (byteStream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PortsideError.steamInstallerUnavailable
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let append = http.statusCode == 206 && existingBytes > 0
        if !append { try? fileManager.removeItem(at: partialURL) }
        fileManager.createFile(atPath: partialURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: partialURL)
        if append { try handle.seekToEnd() }
        var received = append ? existingBytes : 0
        var buffer = Data()
        do {
            for try await byte in byteStream {
                buffer.append(byte); received += 1
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true)
                    if let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init), length > 0 { progress?(min(0.99, Self.progressFraction(received: received, total: append ? existingBytes + length : length))) }
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: partialURL, to: destination)
        let digest = SHA256.hash(data: try Data(contentsOf: destination)).map { String(format: "%02x", $0) }.joined()
        let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        progress?(1)
        logger.write("Downloaded \(source.lastPathComponent) (\(bytes) bytes, sha256 \(digest))")
        return DownloadResult(url: destination, sha256: digest, bytes: bytes)
    }
}

public enum SteamInstaller {
    public static let officialURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!
    public static let loginLaunchProfile = SteamLaunchProfile.cef32LegacyLogin
    public static let bootstrapArguments = loginLaunchProfile.arguments
    public static let defaultLanguageArguments = ["-language", "english"]
    public static let uiArguments = SteamLaunchConfiguration.normal.arguments
    public static let fallbackUIArguments = SteamLaunchConfiguration.fallback.arguments
    public static let uiLaunchConfigurations = [SteamLaunchConfiguration.normal, SteamLaunchConfiguration.disableGPU, SteamLaunchConfiguration.fallback]
    public static var localURL: URL { PortsidePaths.downloads.appendingPathComponent("SteamSetup.exe") }

    public static func loginLaunchArguments(for configuration: SteamLaunchConfiguration) -> [String] {
        loginLaunchProfile.arguments + defaultLanguageArguments + configuration.arguments
    }

    public static var steamExecutableCandidates: [URL] {
        [
            PortsidePaths.steamPrefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe"),
            PortsidePaths.steamPrefix.appendingPathComponent("drive_c/Program Files/Steam/steam.exe"),
            PortsidePaths.steamPrefix.appendingPathComponent("drive_c/steam/steam.exe")
        ]
    }

    public static func locateInstalledExecutable() -> URL? {
        validateInstalledExecutable(candidates: steamExecutableCandidates)
    }

    public static func validateInstalledExecutable(candidates: [URL], fileManager: FileManager = .default) -> URL? {
        candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    public static func installationArguments(for installerURL: URL = localURL) -> [String] {
        [installerURL.path, "/S"]
    }

    public static func installationSpecification(runtimePath: String, installerURL: URL = localURL, prefixURL: URL = PortsidePaths.steamPrefix) -> ProcessLaunchSpec {
        let runtimeURL = URL(fileURLWithPath: runtimePath)
        return ProcessLaunchSpec(
            executable: runtimeURL,
            arguments: installationArguments(for: installerURL),
            environment: WineProcessEnvironment.make(runtimeExecutable: runtimeURL, prefix: prefixURL),
            workingDirectory: prefixURL,
            timeout: 180
        )
    }

    public static func download(using downloader: SecureDownloader = SecureDownloader(), progress: SecureDownloader.ProgressHandler? = nil) async throws -> DownloadResult {
        let result = try await downloader.download(from: officialURL, to: localURL, progress: progress)
        guard result.bytes >= 1_000_000 else { throw PortsideError.steamInstallerUnavailable }
        return result
    }

    public static func install(using runtime: RuntimeDescriptor, installerURL: URL = localURL, candidates: [URL] = steamExecutableCandidates, prefixURL: URL = PortsidePaths.steamPrefix, logger: PortsideLogger = PortsideLogger(), runner: ProcessRunning = SystemProcessRunner()) async throws {
        guard let runtimePath = runtime.executablePath,
              FileManager.default.isExecutableFile(atPath: runtimePath),
              FileManager.default.fileExists(atPath: installerURL.path) else { throw PortsideError.runtimeUnavailable }
        try FileManager.default.createDirectory(at: prefixURL, withIntermediateDirectories: true)
        let result = try await runner.run(installationSpecification(runtimePath: runtimePath, installerURL: installerURL, prefixURL: prefixURL), logger: logger)
        guard result.status == 0 else {
            throw RuntimePipelineError.processFailed("Steam installer", result.status)
        }
        guard validateInstalledExecutable(candidates: candidates) != nil else {
            throw PortsideError.processLaunchFailed("Steam installer finished without creating steam.exe.")
        }
    }
}

public enum SteamNativeLoginState: String, Equatable, Sendable {
    case loggedIn
    case notLoggedIn
    case unavailable
}

public enum SteamNativeLoginMigrationError: LocalizedError, Equatable, Sendable {
    case missingSourceItem(String)
    case loginNotDetected
    case copyFailed
    case nativeSteamInstallationFailed
    case nativeSteamApplicationUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingSourceItem(let item): return "Native Steam login data is missing: \(item)."
        case .loginNotDetected: return "Native Steam login was not detected before the timeout."
        case .copyFailed: return "Native Steam login data could not be copied."
        case .nativeSteamInstallationFailed: return "The native Steam app could not be installed."
        case .nativeSteamApplicationUnavailable: return "The native Steam app could not be opened."
        }
    }
}

public enum SteamNativeLoginMigration {
    public static let requiredItems = ["config", "registry.vdf", "userdata"]

    public static var nativeSteamSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Steam", isDirectory: true)
    }

    public static var managedSteamDirectory: URL {
        PortsidePaths.steamPrefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    public static func isComplete(at destinationRoot: URL = managedSteamDirectory, fileManager: FileManager = .default) -> Bool {
        requiredItems.allSatisfy { fileManager.fileExists(atPath: destinationRoot.appendingPathComponent($0).path) }
    }

    public static func loginState(at sourceRoot: URL = nativeSteamSupportDirectory, fileManager: FileManager = .default) -> SteamNativeLoginState {
        guard requiredItems.allSatisfy({ fileManager.fileExists(atPath: sourceRoot.appendingPathComponent($0).path) }) else {
            return .unavailable
        }
        let loginUsersURL = sourceRoot.appendingPathComponent("config/loginusers.vdf")
        guard let contents = try? String(contentsOf: loginUsersURL, encoding: .utf8) else { return .notLoggedIn }
        let hasAutoLogin = contents.range(of: #"(?m)\"AllowAutoLogin\"\s+\"1\""#, options: .regularExpression) != nil
        let hasRememberedPassword = contents.range(of: #"(?m)\"RememberPassword\"\s+\"1\""#, options: .regularExpression) != nil
        let userDataDirectory = sourceRoot.appendingPathComponent("userdata", isDirectory: true)
        let userDataEntries = (try? fileManager.contentsOfDirectory(at: userDataDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let hasUserData = !userDataEntries.isEmpty
        return hasUserData && (hasAutoLogin || hasRememberedPassword) ? .loggedIn : .notLoggedIn
    }

    @discardableResult
    public static func copyLoginData(from sourceRoot: URL = nativeSteamSupportDirectory, to destinationRoot: URL = managedSteamDirectory, fileManager: FileManager = .default) throws -> [String] {
        for item in requiredItems where !fileManager.fileExists(atPath: sourceRoot.appendingPathComponent(item).path) {
            throw SteamNativeLoginMigrationError.missingSourceItem(item)
        }

        let stagingRoot = destinationRoot.deletingLastPathComponent()
            .appendingPathComponent(".native-steam-login-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            for item in requiredItems {
                try fileManager.copyItem(
                    at: sourceRoot.appendingPathComponent(item),
                    to: stagingRoot.appendingPathComponent(item)
                )
            }
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            for item in requiredItems {
                let destination = destinationRoot.appendingPathComponent(item)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: stagingRoot.appendingPathComponent(item), to: destination)
            }
            try? fileManager.removeItem(at: stagingRoot)
            return requiredItems
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            if error is SteamNativeLoginMigrationError { throw error }
            throw SteamNativeLoginMigrationError.copyFailed
        }
    }
}

public struct SteamLaunchProfile: Equatable, Sendable {
    public let identifier: String
    public let arguments: [String]
    public let requestedCEFArchitecture: String

    public init(identifier: String, arguments: [String], requestedCEFArchitecture: String) {
        self.identifier = identifier
        self.arguments = arguments
        self.requestedCEFArchitecture = requestedCEFArchitecture
    }

    public static let cef32LegacyLogin = SteamLaunchProfile(
        identifier: "cef_32bit_legacy_login",
        arguments: ["-udpforce", "-noreactlogin", "-allosarches", "-cef-force-32bit"],
        requestedCEFArchitecture: "32bit"
    )
}

public struct SteamLaunchConfiguration: Equatable, Sendable {
    public let disableCEFGPU: Bool
    public let disableCEFGPUCompositing: Bool
    public let additionalArguments: [String]

    public init(disableCEFGPU: Bool, disableCEFGPUCompositing: Bool = false, additionalArguments: [String] = []) {
        self.disableCEFGPU = disableCEFGPU
        self.disableCEFGPUCompositing = disableCEFGPUCompositing
        self.additionalArguments = additionalArguments
    }

    public var arguments: [String] {
        var result: [String] = []
        if disableCEFGPU { result.append("-cef-disable-gpu") }
        if disableCEFGPUCompositing { result.append("-cef-disable-gpu-compositing") }
        return result + additionalArguments
    }

    public var identifier: String {
        arguments.isEmpty ? "default" : arguments.joined(separator: " ")
    }

    public static let normal = SteamLaunchConfiguration(disableCEFGPU: false)
    public static let primary = normal
    public static let disableGPU = SteamLaunchConfiguration(disableCEFGPU: true)
    public static let fallback = SteamLaunchConfiguration(disableCEFGPU: true, disableCEFGPUCompositing: true)
}

public protocol RuntimeLocating {
    func locate() -> RuntimeDescriptor?
}

public struct RuntimeLocator: RuntimeLocating {
    public init() {}

    public func locate() -> RuntimeDescriptor? {
        // Proprietary runtimes are intentionally not bundled. A signed Portside build can
        // register an authorized provider here without changing the rest of the app.
        let candidates = [
            PortsidePaths.runtime.appendingPathComponent("bin/wine"),
            PortsidePaths.runtime.appendingPathComponent("bin/wine64")
        ]
        guard let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
        return RuntimeDescriptor(name: "Authorized compatibility runtime", version: "external", executablePath: candidate.path, redistributable: false, licenseNote: "Provided separately; verify commercial redistribution rights before shipping.")
    }
}

public final class ProcessSupervisor: @unchecked Sendable {
    public private(set) var process: Process?
    private let logger: PortsideLogger
    private var runtimeExecutablePath: URL?
    private var prefixURL: URL?
    private var outputPipe: Pipe?

    public init(logger: PortsideLogger = PortsideLogger()) { self.logger = logger }

    public var isRunning: Bool { process?.isRunning == true }

    public func launchSteam(state: EnvironmentState, arguments: [String] = []) throws {
        let runtimePath = state.runtimeRecord?.executablePath.path ?? state.runtime?.executablePath
        guard let runtimePath, FileManager.default.isExecutableFile(atPath: runtimePath) else {
            throw PortsideError.runtimeUnavailable
        }
        let storedSteamExecutable = state.steamExecutablePath.map(URL.init(fileURLWithPath:))
        let steamExecutable = (storedSteamExecutable.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }) ?? SteamInstaller.locateInstalledExecutable()
        guard let steamExecutable else {
            throw PortsideError.processLaunchFailed("Steam is not installed yet.")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: runtimePath)
        runtimeExecutablePath = URL(fileURLWithPath: runtimePath)
        prefixURL = PortsidePaths.steamPrefix
        // Fixed argument list: no shell and no remote metadata is interpolated here.
        task.arguments = [steamExecutable.path] + arguments
        task.environment = WineProcessEnvironment.make(
            runtimeExecutable: URL(fileURLWithPath: runtimePath),
            prefix: PortsidePaths.steamPrefix
        )
        let outputPipe = Pipe()
        self.outputPipe = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            self?.logger.write("steam_process_output: \(output)")
        }
        task.standardOutput = outputPipe
        task.standardError = outputPipe
        task.terminationHandler = { [weak self] _ in
            self?.outputPipe?.fileHandleForReading.readabilityHandler = nil
        }
        do { try task.run(); process = task; logger.write("Steam process started") }
        catch { throw PortsideError.processLaunchFailed("Steam could not be started.") }
    }

    public func requestStop() {
        if let process, process.isRunning {
            process.terminate()
            logger.write("Steam process termination requested")
        }
        guard let runtimeExecutablePath, let prefixURL else { return }
        let wineserver = runtimeExecutablePath.deletingLastPathComponent().appendingPathComponent("wineserver")
        guard FileManager.default.isExecutableFile(atPath: wineserver.path) else { return }
        let task = Process()
        task.executableURL = wineserver
        task.arguments = ["-k"]
        task.environment = WineProcessEnvironment.make(runtimeExecutable: runtimeExecutablePath, prefix: prefixURL)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        logger.write("Portside Wine process tree termination requested")
    }

    public func waitForStop(timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isRunning { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return !isRunning
    }
}

public enum DiagnosticReport {
    public static func create(state: EnvironmentState, requirements: SystemRequirements, logger: PortsideLogger = PortsideLogger()) throws -> URL {
        try FileManager.default.createDirectory(at: PortsidePaths.diagnostics, withIntermediateDirectories: true)
        let reportURL = PortsidePaths.diagnostics.appendingPathComponent("Portside-Diagnostic-\(Int(Date().timeIntervalSince1970)).txt")
        let runtime = state.runtime.map { "\($0.name) \($0.version)" } ?? "Not detected"
        let storage = ByteCountFormatter.string(fromByteCount: requirements.availableStorage, countStyle: .file)
        let contents = """
        Portside Diagnostic Report
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        Portside version: 0.1.0 MVP
        macOS: \(requirements.macOSVersion)
        Architecture: \(requirements.architecture)
        Available storage: \(storage)
        Runtime: \(runtime)
        Runtime path: \(state.runtimeRecord?.installedPath.path ?? "Not installed")
        Runtime checksum: \(state.runtimeRecord?.manifest.sha256 ?? "Not verified")
        Graphics backend: \(state.runtimeRecord?.graphicsBackend.rawValue ?? "Not configured")
        Setup phase: \(state.phase?.rawValue ?? "unknown")
        Steam state: \(state.steamInstalled ? "installed" : "not installed")
        Steam executable: \(state.steamExecutablePath ?? "Not found")
        Last Steam status: \(state.lastSteamStatus?.rawValue ?? "unknown")
        Setup stage: \(state.phase?.rawValue ?? "unknown")
        Error code: \(state.lastErrorCode ?? "none")
        Process type: \(state.lastProcessType ?? "none")
        Exit code: \(state.lastExitCode.map(String.init) ?? "none")
        Setup duration: \(state.lastSetupDuration.map { String(format: "%.2f", $0) } ?? "none")s
        Retry count: \(state.retryCount)
        Environment state: \(state.setupCompleted ? "ready" : "not configured")

        Recent Portside log:
        \(logger.read())
        """
        try PortsideLogger.sanitize(contents).write(to: reportURL, atomically: true, encoding: .utf8)
        return reportURL
    }
}

extension JSONEncoder {
    static var portside: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
extension JSONDecoder {
    static var portside: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}

private extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
