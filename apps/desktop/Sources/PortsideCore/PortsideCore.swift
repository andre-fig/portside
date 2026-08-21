import Foundation
import CryptoKit

/// All Portside-owned state is kept below this root. Runtime components are
/// downloaded into these directories; the active prefix and game library are
/// kept separate from replaceable runtime versions.
public enum PortsidePaths {
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Portside", isDirectory: true)
    }

    public static var runtime: URL { root.appendingPathComponent("Runtime", isDirectory: true) }
    public static var wrappers: URL { root.appendingPathComponent("Wrappers", isDirectory: true) }
    public static var prefixes: URL { root.appendingPathComponent("Prefixes", isDirectory: true) }
    public static var steamLibrary: URL { root.appendingPathComponent("SteamLibrary", isDirectory: true) }
    public static var cache: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public static var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public static var diagnostics: URL { root.appendingPathComponent("Diagnostics", isDirectory: true) }
    public static var profiles: URL { root.appendingPathComponent("Profiles", isDirectory: true) }
    public static var manifests: URL { root.appendingPathComponent("Manifests", isDirectory: true) }
    public static var runtimeManifest: URL { manifests.appendingPathComponent("runtime-manifest.json") }
    public static var runtimeManifestETag: URL { manifests.appendingPathComponent("runtime-manifest.etag") }
    public static var runtimePending: URL { runtime.appendingPathComponent("Pending", isDirectory: true) }

    // Compatibility aliases for callers from the previous release.
    public static var downloads: URL { cache.appendingPathComponent("Downloads", isDirectory: true) }
    public static var backups: URL { diagnostics.appendingPathComponent("Backups", isDirectory: true) }
    public static var prefix: URL { prefixes }
    public static var steamPrefix: URL { prefixes.appendingPathComponent("PortsideBaseline", isDirectory: true) }
    public static var prefixRuntimeMetadata: URL { steamPrefix.appendingPathComponent(".portside-runtime.json") }
    public static var baselineWrapper: URL { wrappers.appendingPathComponent("PortsideBaseline.app", isDirectory: true) }

    public static var allDirectories: [URL] {
        [root, runtime, runtimePending, wrappers, prefixes, steamLibrary, cache, downloads, logs, diagnostics, profiles, manifests]
    }
}

public enum PortsideError: LocalizedError, Equatable {
    case unsupportedArchitecture(String)
    case unsupportedOperatingSystem(String)
    case insufficientStorage(required: Int64, available: Int64)
    case rosettaUnavailable
    case runtimeUnavailable
    case invalidArtifact(String)
    case checksumMismatch(expected: String, actual: String)
    case processLaunchFailed(String)
    case processTimedOut(String)
    case processFailed(String, Int32)
    case invalidPath

    public var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture: return "Portside requires an Apple silicon Mac."
        case .unsupportedOperatingSystem(let version): return "macOS \(version) is not supported by this build."
        case .insufficientStorage(let required, let available):
            return "Portside needs at least \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)); only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available."
        case .rosettaUnavailable: return "Rosetta 2 is required to prepare the gaming environment."
        case .runtimeUnavailable: return "The Portside gaming environment is not installed."
        case .invalidArtifact(let reason): return "The Portside runtime could not be verified: \(reason)"
        case .checksumMismatch(let expected, let actual): return "Checksum mismatch (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case .processLaunchFailed(let reason), .processTimedOut(let reason): return reason
        case .processFailed(let process, let status): return "\(process) exited with status \(status)."
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
    public var runtimeRecord: PortsideRuntimeRecord?
    public var runtimeManifestVersion: String?
    public var phase: EnvironmentPhase?
    public var wrapperPath: String?
    public var prefixPath: String?
    public var steamExecutablePath: String?
    public var lastReadiness: SteamReadinessReport?
    public var lastError: String?
    public var retryCount = 0
    public var lastErrorCode: String?
    public var lastExitCode: Int32?
    public var lastSetupDuration: TimeInterval?
    public var lastUpdated: Date?

    public init() {}
}

/// Context deliberately contains only allow-listed, non-identifying values.
public struct DiagnosticContext: Sendable, Equatable {
    public var stage: String?
    public var errorCode: String?
    public var portsideVersion: String
    public var portsideBuild: String
    public var macOSVersion: String?
    public var architecture: String?
    public var runtimeVersion: String?
    public var templateVersion: String?
    public var engineVersion: String?
    public var renderer: String?
    public var appID: String?
    public var executableArchitecture: String?
    public var graphicsAPI: String?
    public var launchAttempt: Int?
    public var fallbackIndex: Int?
    public var exitCode: Int32?
    public var windowDetected: Bool?
    public var rollbackPerformed: Bool?
    public var processStarted: Bool?
    public var webHelperStarted: Bool?
    public var interfaceVerification: String?
    public var msyncEnabled: Bool?
    public var esyncEnabled: Bool?

    public init(stage: String? = nil, errorCode: String? = nil, portsideVersion: String = "0.1.0", portsideBuild: String = "1", macOSVersion: String? = nil, architecture: String? = nil, runtimeVersion: String? = nil, templateVersion: String? = nil, engineVersion: String? = nil, renderer: String? = nil, appID: String? = nil, executableArchitecture: String? = nil, graphicsAPI: String? = nil, launchAttempt: Int? = nil, fallbackIndex: Int? = nil, exitCode: Int32? = nil, windowDetected: Bool? = nil, rollbackPerformed: Bool? = nil, processStarted: Bool? = nil, webHelperStarted: Bool? = nil, interfaceVerification: String? = nil, msyncEnabled: Bool? = nil, esyncEnabled: Bool? = nil) {
        self.stage = stage
        self.errorCode = errorCode
        self.portsideVersion = portsideVersion
        self.portsideBuild = portsideBuild
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.runtimeVersion = runtimeVersion
        self.templateVersion = templateVersion
        self.engineVersion = engineVersion
        self.renderer = renderer
        self.appID = appID
        self.executableArchitecture = executableArchitecture
        self.graphicsAPI = graphicsAPI
        self.launchAttempt = launchAttempt
        self.fallbackIndex = fallbackIndex
        self.exitCode = exitCode
        self.windowDetected = windowDetected
        self.rollbackPerformed = rollbackPerformed
        self.processStarted = processStarted
        self.webHelperStarted = webHelperStarted
        self.interfaceVerification = interfaceVerification
        self.msyncEnabled = msyncEnabled
        self.esyncEnabled = esyncEnabled
    }

    public var fields: [String: String] {
        var result = ["portside_version": portsideVersion, "portside_build": portsideBuild]
        let values: [(String, String?)] = [
            ("stage", stage), ("error_code", errorCode), ("macos_version", macOSVersion), ("architecture", architecture),
            ("runtime_version", runtimeVersion), ("template_version", templateVersion), ("engine_version", engineVersion),
            ("renderer", renderer), ("app_id", appID), ("executable_architecture", executableArchitecture), ("graphics_api", graphicsAPI),
            ("launch_attempt", launchAttempt.map(String.init)), ("fallback_index", fallbackIndex.map(String.init)),
            ("exit_code", exitCode.map(String.init)), ("window_detected", windowDetected.map(String.init)),
            ("rollback_performed", rollbackPerformed.map(String.init)), ("process_started", processStarted.map(String.init)),
            ("webhelper_started", webHelperStarted.map(String.init)), ("interface_verification", interfaceVerification),
            ("msync_enabled", msyncEnabled.map(String.init)), ("esync_enabled", esyncEnabled.map(String.init))
        ]
        for (key, value) in values where value != nil { result[key] = value! }
        return result
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
        try JSONEncoder.portside.encode(state).write(to: stateURL, options: .atomic)
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
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] [\(level.rawValue)] \(Self.sanitize(message))\n"
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(at: PortsidePaths.logs, withIntermediateDirectories: true)
            if let size = try? fileManager.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber, size.int64Value > 4 * 1024 * 1024 {
                let rotated = logURL.appendingPathExtension("1")
                try? fileManager.removeItem(at: rotated)
                try? fileManager.moveItem(at: logURL, to: rotated)
            }
            if !fileManager.fileExists(atPath: logURL.path) { fileManager.createFile(atPath: logURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            // Diagnostics must never break the launcher.
        }
    }

    public static func sanitize(_ value: String) -> String {
        var result = value.replacingOccurrences(of: NSHomeDirectory(), with: "$USER_HOME")
        if let windowsUser = try? NSRegularExpression(pattern: "(?i)C:\\\\users\\\\[^\\\\\\s]+") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = windowsUser.stringByReplacingMatches(in: result, range: range, withTemplate: "C:\\\\users\\\\<user>")
        }
        let patterns = [
            "(?i)(password|passwd|token|cookie|sessionid|steamid|auth)\\s*[=:]\\s*[^\\s,;]+",
            "(?i)(-steamid|--steamid)\\s+[^\\s]+"
        ]
        for pattern in patterns {
            if let expression = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "$1=<redacted>")
            }
        }
        return result
    }

    public func contents() -> String { (try? String(contentsOf: logURL)) ?? "" }
}

public struct DownloadResult: Sendable, Equatable {
    public let url: URL
    public let bytes: Int64
    public let sha256: String
    public init(url: URL, bytes: Int64, sha256: String) { self.url = url; self.bytes = bytes; self.sha256 = sha256 }
}

public final class SecureDownloader: @unchecked Sendable {
    private let allowedHosts: Set<String>
    private let maxBytes: Int64
    private let session: URLSession

    public init(allowedHosts: Set<String> = [], maxBytes: Int64 = 2_147_483_648) {
        self.allowedHosts = allowedHosts
        self.maxBytes = maxBytes
        self.session = URLSession(configuration: .ephemeral, delegate: RedirectPolicy(allowedHosts: allowedHosts), delegateQueue: nil)
    }

    public func download(from source: URL, to destination: URL, expectedSHA256: String? = nil, expectedSize: Int64? = nil) async throws -> DownloadResult {
        guard source.scheme == "https", let host = source.host, allowedHosts.contains(host) else { throw PortsideError.invalidArtifact("unapproved download host") }
        let (data, response) = try await session.data(from: source)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw PortsideError.invalidArtifact("HTTP \(http.statusCode)") }
        if Int64(data.count) > maxBytes { throw PortsideError.invalidArtifact("download exceeds configured size limit") }
        if let expectedSize, Int64(data.count) != expectedSize { throw PortsideError.invalidArtifact("unexpected size") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let expectedSHA256, digest.lowercased() != expectedSHA256.lowercased() { throw PortsideError.checksumMismatch(expected: expectedSHA256, actual: digest) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return DownloadResult(url: destination, bytes: Int64(data.count), sha256: digest)
    }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
    private let allowedHosts: Set<String>
    init(allowedHosts: Set<String>) { self.allowedHosts = allowedHosts }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", let host = url.host, allowedHosts.contains(host) else { completionHandler(nil); return }
        completionHandler(request)
    }
}

public struct ProcessResult: Sendable, Equatable {
    public let status: Int32
    public let output: String
    public let duration: TimeInterval
    public init(status: Int32, output: String = "", duration: TimeInterval = 0) { self.status = status; self.output = output; self.duration = duration }
}

public struct ProcessLaunchSpec: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let currentDirectory: URL?
    public let timeout: TimeInterval

    public init(executable: URL, arguments: [String] = [], environment: [String: String] = [:], currentDirectory: URL? = nil, timeout: TimeInterval = 900) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.timeout = timeout
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult
}

public struct SystemProcessRunner: ProcessRunning, @unchecked Sendable {
    public init() {}

    public func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = specification.executable
        process.arguments = specification.arguments
        process.environment = specification.environment.isEmpty ? nil : specification.environment
        process.currentDirectoryURL = specification.currentDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let started = Date()
        do { try process.run() } catch { throw PortsideError.processLaunchFailed("Could not start \(specification.executable.lastPathComponent).") }
        let reader = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }
        while process.isRunning {
            if Date().timeIntervalSince(started) > specification.timeout {
                process.terminate()
                throw PortsideError.processTimedOut(specification.executable.lastPathComponent)
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let output = PortsideLogger.sanitize(String(data: await reader.value, encoding: .utf8) ?? "")
        if !output.isEmpty { logger.write(output) }
        return ProcessResult(status: process.terminationStatus, output: output, duration: Date().timeIntervalSince(started))
    }
}

public enum IntegrityVerifier {
    public static func sha256(url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(url: URL, expectedSHA256: String, expectedSize: Int64? = nil) throws {
        if let expectedSize {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            if actualSize != expectedSize { throw PortsideError.invalidArtifact("unexpected size") }
        }
        let actual = try sha256(url: url)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw PortsideError.checksumMismatch(expected: expectedSHA256, actual: actual)
        }
    }
}

public enum AtomicInstaller {
    public static func installDirectory(from staged: URL, to destination: URL, fileManager: FileManager = .default) throws {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let previous = parent.appendingPathComponent(".previous-\(UUID().uuidString)", isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.moveItem(at: destination, to: previous) }
        do {
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            if fileManager.fileExists(atPath: previous.path) { try? fileManager.moveItem(at: previous, to: destination) }
            throw error
        }
    }
}

public enum DiagnosticReport {
    public static func create(state: EnvironmentState, requirements: SystemRequirements, logger: PortsideLogger, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: PortsidePaths.diagnostics, withIntermediateDirectories: true)
        let url = PortsidePaths.diagnostics.appendingPathComponent("report-\(Int(Date().timeIntervalSince1970)).txt")
        let stateData = try JSONEncoder.portside.encode(state)
        let stateText = PortsideLogger.sanitize(String(data: stateData, encoding: .utf8) ?? "{}")
        let text = "Portside diagnostic report\narchitecture=\(requirements.architecture)\nmacOS=\(requirements.macOSVersion)\nstate=\(stateText)\nlogs=\n\(PortsideLogger.sanitize(logger.contents()))\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

public extension JSONEncoder {
    static var portside: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var portside: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
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
