import Foundation
import CryptoKit

public enum PortsidePaths {
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Portside", isDirectory: true)
    }

    public static var runtime: URL { root.appendingPathComponent("Runtime", isDirectory: true) }
    public static var prefixes: URL { root.appendingPathComponent("Prefixes", isDirectory: true) }
    public static var steamPrefix: URL { prefixes.appendingPathComponent("Steam", isDirectory: true) }
    public static var profiles: URL { root.appendingPathComponent("Profiles", isDirectory: true) }
    public static var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public static var cache: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public static var downloads: URL { root.appendingPathComponent("Downloads", isDirectory: true) }
    public static var diagnostics: URL { root.appendingPathComponent("Diagnostics", isDirectory: true) }

    public static var allDirectories: [URL] {
        [root, runtime, prefixes, steamPrefix, profiles, logs, cache, downloads, diagnostics]
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
    public var lastError: String?
    public var lastUpdated: Date?

    public init() {}
}

public final class EnvironmentStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let stateURL: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.stateURL = PortsidePaths.root.appendingPathComponent("environment.json")
    }

    public func prepareDirectories() throws {
        for directory in PortsidePaths.allDirectories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
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

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.logURL = PortsidePaths.logs.appendingPathComponent("portside.log")
    }

    public func write(_ message: String, level: Level = .info) {
        lock.lock(); defer { lock.unlock() }
        try? fileManager.createDirectory(at: PortsidePaths.logs, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue.uppercased())] \(Self.sanitize(message))\n"
        if let data = line.data(using: .utf8) {
            if fileManager.fileExists(atPath: logURL.path), let handle = try? FileHandle(forWritingTo: logURL) {
                _ = try? handle.seekToEnd(); _ = try? handle.write(contentsOf: data); _ = try? handle.close()
            } else { try? data.write(to: logURL, options: .atomic) }
        }
        rotateIfNeeded()
    }

    public func read() -> String { (try? String(contentsOf: logURL, encoding: .utf8)) ?? "No Portside log entries yet." }

    public static func sanitize(_ value: String) -> String {
        var result = value
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
        return result
    }

    private func rotateIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber, size.int64Value > 2_000_000 else { return }
        let rotated = PortsidePaths.logs.appendingPathComponent("portside.log.1")
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

    public init(fileManager: FileManager = .default, logger: PortsideLogger = PortsideLogger()) {
        self.fileManager = fileManager
        self.logger = logger
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        super.init()
    }

    public func download(from source: URL, to destination: URL, progress: ProgressHandler? = nil) async throws -> DownloadResult {
        guard source.scheme == "https", source.host != nil else { throw PortsideError.steamInstallerUnavailable }
        var request = URLRequest(url: source)
        request.timeoutInterval = 120
        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PortsideError.steamInstallerUnavailable
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        let digest = SHA256.hash(data: try Data(contentsOf: destination)).map { String(format: "%02x", $0) }.joined()
        let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        progress?(1)
        logger.write("Downloaded official Steam installer (\(bytes) bytes, sha256 \(digest))")
        return DownloadResult(url: destination, sha256: digest, bytes: bytes)
    }
}

public enum SteamInstaller {
    public static let officialURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!
    public static var localURL: URL { PortsidePaths.downloads.appendingPathComponent("SteamSetup.exe") }

    public static func download(using downloader: SecureDownloader = SecureDownloader(), progress: SecureDownloader.ProgressHandler? = nil) async throws -> DownloadResult {
        try await downloader.download(from: officialURL, to: localURL, progress: progress)
    }

    public static func install(using runtime: RuntimeDescriptor, logger: PortsideLogger = PortsideLogger()) async throws {
        guard let runtimePath = runtime.executablePath,
              FileManager.default.isExecutableFile(atPath: runtimePath),
              FileManager.default.fileExists(atPath: localURL.path) else { throw PortsideError.runtimeUnavailable }
        try FileManager.default.createDirectory(at: PortsidePaths.steamPrefix, withIntermediateDirectories: true)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: runtimePath)
        task.arguments = [localURL.path]
        task.environment = ["WINEPREFIX": PortsidePaths.steamPrefix.path]
        try task.run()
        await withCheckedContinuation { continuation in
            task.terminationHandler = { _ in continuation.resume() }
        }
        logger.write("Steam installer exited with code \(task.terminationStatus)")
        guard task.terminationStatus == 0 else {
            throw PortsideError.processLaunchFailed("Steam installation did not complete. See Support for diagnostics.")
        }
    }
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

    public init(logger: PortsideLogger = PortsideLogger()) { self.logger = logger }

    public var isRunning: Bool { process?.isRunning == true }

    public func launchSteam(state: EnvironmentState) throws {
        guard let runtimePath = state.runtime?.executablePath, FileManager.default.isExecutableFile(atPath: runtimePath) else {
            throw PortsideError.runtimeUnavailable
        }
        let steamExecutable = PortsidePaths.steamPrefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/Steam.exe")
        guard FileManager.default.fileExists(atPath: steamExecutable.path) else {
            throw PortsideError.processLaunchFailed("Steam is not installed yet. Run Set Up Portside first.")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: runtimePath)
        // Fixed argument list: no shell and no remote metadata is interpolated here.
        task.arguments = [steamExecutable.path]
        task.environment = ["WINEPREFIX": PortsidePaths.steamPrefix.path]
        do { try task.run(); process = task; logger.write("Steam process started") }
        catch { throw PortsideError.processLaunchFailed("Steam could not be started. See Support for diagnostics.") }
    }

    public func requestStop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        logger.write("Steam process termination requested")
    }
}

public struct CompatibilityProfile: Codable, Equatable, Sendable {
    public var appID: String
    public var name: String
    public var runtimeVersion: String?
    public var graphicsNotes: String?
    public var knownIssues: [String]
    public var classification: String
    public var lastTested: Date?

    public init(appID: String, name: String, runtimeVersion: String? = nil, graphicsNotes: String? = nil, knownIssues: [String] = [], classification: String = "Not tested", lastTested: Date? = nil) {
        self.appID = appID; self.name = name; self.runtimeVersion = runtimeVersion; self.graphicsNotes = graphicsNotes; self.knownIssues = knownIssues; self.classification = classification; self.lastTested = lastTested
    }
}

public final class ProfileStore: @unchecked Sendable {
    private let fileManager: FileManager
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func save(_ profile: CompatibilityProfile) throws {
        try fileManager.createDirectory(at: PortsidePaths.profiles, withIntermediateDirectories: true)
        guard profile.appID.allSatisfy(\.isNumber), !profile.appID.isEmpty, profile.appID.count <= 20 else { throw PortsideError.invalidPath }
        let url = PortsidePaths.profiles.appendingPathComponent("\(profile.appID).json")
        try JSONEncoder.portside.encode(profile).write(to: url, options: .atomic)
    }

    public func load(appID: String) -> CompatibilityProfile? {
        guard appID.allSatisfy(\.isNumber), appID.count <= 20 else { return nil }
        let url = PortsidePaths.profiles.appendingPathComponent("\(appID).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.portside.decode(CompatibilityProfile.self, from: data)
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
        Steam state: \(state.steamInstalled ? "installed" : "not installed")
        Environment state: \(state.setupCompleted ? "ready" : "not configured")

        Recent Portside log:
        \(logger.read())
        """
        try PortsideLogger.sanitize(contents).write(to: reportURL, atomically: true, encoding: .utf8)
        return reportURL
    }
}

private extension JSONEncoder {
    static var portside: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
private extension JSONDecoder {
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
