import Foundation
import AppKit
import CryptoKit
import Darwin

public enum EnvironmentPhase: String, Codable, CaseIterable, Sendable {
    case requirementsChecking
    case rosettaRequired
    case runtimeDownloading
    case runtimeVerifying
    case runtimeInstalling
    case prefixCreating
    case graphicsInstalling
    case steamDownloading
    case steamInstalling
    case steamNativeLogin
    case steamUpdating
    case steamLaunching
    case validatingInstallation
    case steamReady
    case failedRecoverable
    case failedFatal
}

public enum GraphicsBackend: String, Codable, CaseIterable, Sendable {
    case wineD3D

    public var displayName: String { "Built-in compatibility graphics" }
    public var supportedAPIs: [String] { ["Direct3D 9", "Direct3D 10", "Direct3D 11"] }
}

public struct RuntimeManifest: Codable, Equatable, Sendable {
    public let identifier: String
    public let version: String
    public let upstreamURL: URL
    public let sha256: String
    public let expectedSize: Int64
    public let architecture: String
    public let minimumMacOS: String
    public let relativeExecutablePath: String
    public let license: String
    public let sourceURL: URL
    public let includedComponents: [String]
    public let validatedAt: Date
    public let bundleDirectoryName: String

    public init(identifier: String, version: String, upstreamURL: URL, sha256: String, expectedSize: Int64, architecture: String, minimumMacOS: String, relativeExecutablePath: String, license: String, sourceURL: URL, includedComponents: [String], validatedAt: Date, bundleDirectoryName: String) {
        self.identifier = identifier; self.version = version; self.upstreamURL = upstreamURL; self.sha256 = sha256; self.expectedSize = expectedSize; self.architecture = architecture; self.minimumMacOS = minimumMacOS; self.relativeExecutablePath = relativeExecutablePath; self.license = license; self.sourceURL = sourceURL; self.includedComponents = includedComponents; self.validatedAt = validatedAt; self.bundleDirectoryName = bundleDirectoryName
    }
}

public struct RuntimeComponentManifest: Codable, Equatable, Sendable {
    public let identifier: String
    public let version: String
    public let upstreamURL: URL
    public let sha256: String
    public let expectedSize: Int64?
    public let license: String
    public let sourceURL: URL
    public let installScope: String

    public init(identifier: String, version: String, upstreamURL: URL, sha256: String, expectedSize: Int64?, license: String, sourceURL: URL, installScope: String) {
        self.identifier = identifier; self.version = version; self.upstreamURL = upstreamURL; self.sha256 = sha256; self.expectedSize = expectedSize; self.license = license; self.sourceURL = sourceURL; self.installScope = installScope
    }
}

public enum FreeRuntimeCatalog {
    public static let wine = RuntimeManifest(
        identifier: "wine-staging-gcenx-osx64",
        version: "11.15",
        upstreamURL: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.15/wine-staging-11.15-osx64.tar.xz")!,
        sha256: "a8c50d0e14fb7982a21506287e1e41e1990fe77c74fa2a32da7dbcf7b21de1e2",
        expectedSize: 193_561_920,
        architecture: "x86_64 via Rosetta 2",
        minimumMacOS: "13.0",
        relativeExecutablePath: "Contents/Resources/wine/bin/wine",
        license: "Wine LGPL-2.1-or-later; upstream packaging license must be reviewed before commercial bundling",
        sourceURL: URL(string: "https://gitlab.winehq.org/wine/wine")!,
        includedComponents: ["Wine Staging", "Wine Mono 11.2.0", "Wine Gecko 2.47.4", "WineD3D"],
        validatedAt: ISO8601DateFormatter().date(from: "2026-08-08T20:31:36Z") ?? Date(),
        bundleDirectoryName: "Wine Staging.app"
    )

    public static let gstreamer = RuntimeComponentManifest(
        identifier: "gstreamer-macos-universal-runtime",
        version: "1.28.5",
        upstreamURL: URL(string: "https://gstreamer.freedesktop.org/data/pkg/macos/1.28.5/gstreamer-1.0-1.28.5-universal.pkg")!,
        sha256: "0a8fc7a1cf8d7bac833ca0ebe2fd196a199c2465e810cd5b1e4b4f720c258f43",
        expectedSize: 146_000_000,
        license: "LGPL-2.1-or-later and component-specific permissive licenses; see GStreamer notices",
        sourceURL: URL(string: "https://gitlab.freedesktop.org/gstreamer/gstreamer")!,
        installScope: "private Portside Runtime/Dependencies/GStreamer.framework"
    )

    public static let graphics = GraphicsBackend.wineD3D
}

public enum WineRuntimePolicy {
    public static let debug = "-all"
    public static let dllOverrides = "winedbg.exe=d;mscoree,mshtml="
}

public enum WineProcessEnvironment {
    #if DEBUG
    public static var defaultWineDebug: String {
        ProcessInfo.processInfo.environment["PORTSIDE_DIAGNOSTIC_WINEDEBUG"] ?? WineRuntimePolicy.debug
    }
    #else
    public static let defaultWineDebug = WineRuntimePolicy.debug
    #endif

    public static func make(
        runtimeExecutable: URL,
        prefix: URL,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        wineDebug: String = WineProcessEnvironment.defaultWineDebug
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["WINEPREFIX"] = prefix.path
        environment["WINEARCH"] = "win64"
        environment["WINEDLLOVERRIDES"] = WineRuntimePolicy.dllOverrides
        environment["WINEDEBUG"] = wineDebug
        environment["PATH"] = prepend(runtimeExecutable.deletingLastPathComponent().path, to: baseEnvironment["PATH"])
        environment["DYLD_FRAMEWORK_PATH"] = prepend(
            GStreamerManager.frameworkURL.deletingLastPathComponent().path,
            to: baseEnvironment["DYLD_FRAMEWORK_PATH"]
        )
        environment["GST_PLUGIN_PATH"] = prepend(
            GStreamerManager.frameworkURL.appendingPathComponent("Versions/1.0/lib/gstreamer-1.0").path,
            to: baseEnvironment["GST_PLUGIN_PATH"]
        )
        return environment
    }

    private static func prepend(_ value: String, to existing: String?) -> String {
        guard let existing, !existing.isEmpty else { return value }
        let entries = existing.split(separator: ":").map(String.init)
        guard !entries.contains(value) else { return existing }
        return ([value] + entries).joined(separator: ":")
    }
}

public struct InstalledRuntimeRecord: Codable, Equatable, Sendable {
    public let manifest: RuntimeManifest
    public let installedPath: URL
    public let executablePath: URL
    public let graphicsBackend: GraphicsBackend
    public let installedAt: Date
    public let gstreamerInstalled: Bool

    public init(manifest: RuntimeManifest, installedPath: URL, executablePath: URL, graphicsBackend: GraphicsBackend, installedAt: Date, gstreamerInstalled: Bool) {
        self.manifest = manifest; self.installedPath = installedPath; self.executablePath = executablePath; self.graphicsBackend = graphicsBackend; self.installedAt = installedAt; self.gstreamerInstalled = gstreamerInstalled
    }
}

public enum RuntimePipelineError: LocalizedError, Equatable {
    case checksumMismatch(expected: String, actual: String)
    case unexpectedArchiveEntry(String)
    case archiveExtractionFailed(String)
    case runtimeStructureInvalid
    case rosettaUnavailable
    case gstreamerInstallFailed(Int32, String)
    case processFailed(String, Int32)
    case processTimedOut(String)

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch: return "A downloaded compatibility component failed integrity verification."
        case .unexpectedArchiveEntry: return "A compatibility archive contained an unsafe path and was rejected."
        case .archiveExtractionFailed: return "The compatibility component could not be extracted safely."
        case .runtimeStructureInvalid: return "The downloaded runtime did not contain the expected executable."
        case .rosettaUnavailable: return "Rosetta is required to run this x86-64 compatibility runtime."
        case .gstreamerInstallFailed: return "The audio/video support component could not be installed."
        case .processFailed(let process, _): return "The \(process) process did not complete successfully."
        case .processTimedOut(let process): return "The \(process) process timed out."
        }
    }
}

public enum IntegrityVerifier {
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(url: URL, expectedSHA256: String, expectedSize: Int64? = nil) throws {
        if let expectedSize, expectedSize > 0, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size != expectedSize { throw RuntimePipelineError.checksumMismatch(expected: expectedSHA256, actual: "size:\(size)") }
        let actual = try sha256(of: url)
        guard actual.lowercased() == expectedSHA256.lowercased() else { throw RuntimePipelineError.checksumMismatch(expected: expectedSHA256, actual: actual) }
    }
}

public enum AtomicInstaller {
    public static func installDirectory(from staged: URL, to destination: URL, fileManager: FileManager = .default) throws {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let backup = parent.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        let hadDestination = fileManager.fileExists(atPath: destination.path)
        if hadDestination { try fileManager.moveItem(at: destination, to: backup) }
        do {
            try fileManager.moveItem(at: staged, to: destination)
            if hadDestination { try? fileManager.removeItem(at: backup) }
        } catch {
            if hadDestination, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: destination)
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }
}

public struct ProcessResult: Sendable, Equatable {
    public let status: Int32
    public let output: String
    public let duration: TimeInterval
}

public struct ProcessLaunchSpec: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?
    public let timeout: TimeInterval?

    public init(executable: URL, arguments: [String] = [], environment: [String: String] = [:], workingDirectory: URL? = nil, timeout: TimeInterval? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult
}

public enum DirectProcess {
    public static func run(specification: ProcessLaunchSpec, logger: PortsideLogger = PortsideLogger(), logOutput: Bool = true) async throws -> ProcessResult {
        let task = Process()
        task.executableURL = specification.executable
        task.arguments = specification.arguments
        task.environment = specification.environment
        task.currentDirectoryURL = specification.workingDirectory
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("portside-process-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        task.standardOutput = outputHandle; task.standardError = outputHandle
        let started = Date()
        do { try task.run() } catch { throw RuntimePipelineError.processFailed(specification.executable.lastPathComponent, -1) }
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    task.terminationHandler = { _ in continuation.resume() }
                }
                return true
            }
            if let timeout = specification.timeout {
                group.addTask {
                    try? await Task.sleep(for: .seconds(timeout))
                    return false
                }
            }
            let result = await group.next() ?? true
            group.cancelAll()
            return result
        }
        if !finished {
            task.terminate()
            try? await Task.sleep(for: .milliseconds(100))
            try? outputHandle.close()
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            try? FileManager.default.removeItem(at: outputURL)
            if logOutput {
                logger.write("\(specification.executable.lastPathComponent) timed out, output=\(String(data: data, encoding: .utf8) ?? "")", level: .error)
            }
            throw RuntimePipelineError.processTimedOut(specification.executable.lastPathComponent)
        }
        try? outputHandle.close()
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        try? FileManager.default.removeItem(at: outputURL)
        let output = String(data: data, encoding: .utf8) ?? ""
        let duration = Date().timeIntervalSince(started)
        if logOutput {
            logger.write("\(specification.executable.lastPathComponent) exited with \(task.terminationStatus), duration \(String(format: "%.2f", duration))s, output=\(output)")
        }
        return ProcessResult(status: task.terminationStatus, output: output, duration: duration)
    }

    public static func run(executable: URL, arguments: [String], environment: [String: String] = [:], logger: PortsideLogger = PortsideLogger(), logOutput: Bool = true) async throws -> ProcessResult {
        try await run(specification: ProcessLaunchSpec(executable: executable, arguments: arguments, environment: environment), logger: logger, logOutput: logOutput)
    }
}

public struct SystemProcessRunner: ProcessRunning, Sendable {
    public init() {}
    public func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger = PortsideLogger()) async throws -> ProcessResult {
        try await DirectProcess.run(specification: specification, logger: logger)
    }
}

public enum SafeArchiveExtractor {
    public static func extractTarXZ(_ archive: URL, to directory: URL, logger: PortsideLogger = PortsideLogger()) async throws {
        let list = try await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tvf", archive.path], logger: logger)
        guard list.status == 0 else { throw RuntimePipelineError.archiveExtractionFailed(list.output) }
        for entry in list.output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            guard !entry.hasPrefix("l") && !entry.hasPrefix("h") else { throw RuntimePipelineError.unexpectedArchiveEntry(entry) }
            let path = entry.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true).last.map(String.init) ?? entry
            guard isSafeRelativePath(path) else { throw RuntimePipelineError.unexpectedArchiveEntry(path) }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xJf", archive.path, "-C", directory.path], logger: logger)
        guard result.status == 0 else { throw RuntimePipelineError.archiveExtractionFailed(result.output) }
    }

    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        return path.split(separator: "/").allSatisfy { $0 != ".." && !$0.isEmpty }
    }
}

public struct RosettaStatus: Sendable, Equatable {
    public let installed: Bool
    public let validationOutput: String
    public init(installed: Bool, validationOutput: String) { self.installed = installed; self.validationOutput = validationOutput }
}

public enum RosettaManager {
    public static func status() async -> RosettaStatus {
        let result = try? await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/bin/arch"), arguments: ["-x86_64", "/usr/bin/true"])
        return RosettaStatus(installed: result?.status == 0, validationOutput: result?.output ?? "")
    }

    public static func install() async throws -> ProcessResult {
        try await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/sbin/softwareupdate"), arguments: ["--install-rosetta"])
    }
}

public enum GStreamerManager {
    public static var privateFrameworkURL: URL {
        PortsidePaths.runtime.appendingPathComponent("Dependencies/GStreamer.framework")
    }

    public static var frameworkURL: URL {
        FileManager.default.fileExists(atPath: privateFrameworkURL.path) ? privateFrameworkURL : URL(fileURLWithPath: "/Library/Frameworks/GStreamer.framework")
    }
    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: privateFrameworkURL.appendingPathComponent("Versions/1.0/lib/libgstreamer-1.0.0.dylib").path) }

    public static func install(using downloader: SecureDownloader = SecureDownloader(), logger: PortsideLogger = PortsideLogger()) async throws {
        let pkgURL = PortsidePaths.downloads.appendingPathComponent("gstreamer-\(FreeRuntimeCatalog.gstreamer.version).pkg")
        if !FileManager.default.fileExists(atPath: pkgURL.path) {
            _ = try await downloader.download(from: FreeRuntimeCatalog.gstreamer.upstreamURL, to: pkgURL)
        }
        do {
            try IntegrityVerifier.verify(url: pkgURL, expectedSHA256: FreeRuntimeCatalog.gstreamer.sha256, expectedSize: FreeRuntimeCatalog.gstreamer.expectedSize)
        } catch {
            try? FileManager.default.removeItem(at: pkgURL)
            throw error
        }
        let temporary = PortsidePaths.runtime.appendingPathComponent(".gstreamer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result = try await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/sbin/pkgutil"), arguments: ["--expand-full", pkgURL.path, temporary.path], logger: logger)
        guard result.status == 0 else { throw RuntimePipelineError.gstreamerInstallFailed(result.status, result.output) }
        let destination = privateFrameworkURL
        try? FileManager.default.removeItem(at: destination)
        let versionedRoot = destination.appendingPathComponent("Versions/1.0", isDirectory: true)
        try FileManager.default.createDirectory(at: versionedRoot, withIntermediateDirectories: true)
        let payloads = FileManager.default.enumerator(at: temporary, includingPropertiesForKeys: [.isDirectoryKey])?.compactMap { $0 as? URL }.filter { $0.lastPathComponent == "Payload" } ?? []
        guard !payloads.isEmpty else { throw RuntimePipelineError.gstreamerInstallFailed(-1, "GStreamer package payloads not found") }
        for payload in payloads { try mergeContents(from: payload, to: versionedRoot) }
        let versions = destination.appendingPathComponent("Versions", isDirectory: true)
        try? FileManager.default.createSymbolicLink(at: versions.appendingPathComponent("Current"), withDestinationURL: URL(fileURLWithPath: "1.0"))
        guard isInstalled else { throw RuntimePipelineError.gstreamerInstallFailed(-1, "GStreamer framework failed validation") }
    }

    private static func mergeContents(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let children = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])
        for child in children {
            let target = destination.appendingPathComponent(child.lastPathComponent)
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory { try mergeContents(from: child, to: target) }
            else if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: child, to: target) }
        }
    }
}

public enum WinePrefixManager {
    public static func ensureWindows10(runtimeExecutable: URL, prefix: URL, logger: PortsideLogger = PortsideLogger()) async throws -> ProcessResult {
        let current = try await runWineCfgVersion(runtimeExecutable: runtimeExecutable, prefix: prefix, logger: logger)
        if current.status == 0, current.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "win10" {
            return current
        }
        let environment = runtimeEnvironment(runtimeExecutable: runtimeExecutable, prefix: prefix)
        let configured = try await DirectProcess.run(
            executable: runtimeExecutable,
            arguments: ["winecfg", "-v", "win10"],
            environment: environment,
            logger: logger
        )
        guard configured.status == 0 else { return configured }
        let validated = try await runWineCfgVersion(runtimeExecutable: runtimeExecutable, prefix: prefix, logger: logger)
        guard validated.status == 0,
              validated.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "win10" else {
            return ProcessResult(status: 1, output: "Wine prefix Windows version validation failed", duration: validated.duration)
        }
        return validated
    }

    public static func configureSilentCrashHandling(runtimeExecutable: URL, prefix: URL, logger: PortsideLogger = PortsideLogger()) async throws -> ProcessResult {
        let environment = runtimeEnvironment(runtimeExecutable: runtimeExecutable, prefix: prefix)
        return try await DirectProcess.run(
            executable: runtimeExecutable,
            arguments: ["reg.exe", "ADD", "HKCU\\Software\\Wine\\WineDbg", "/v", "ShowCrashDialog", "/t", "REG_DWORD", "/d", "0", "/f"],
            environment: environment,
            logger: logger
        )
    }

    private static func runWineCfgVersion(runtimeExecutable: URL, prefix: URL, logger: PortsideLogger) async throws -> ProcessResult {
        try await DirectProcess.run(
            executable: runtimeExecutable,
            arguments: ["winecfg", "-v"],
            environment: runtimeEnvironment(runtimeExecutable: runtimeExecutable, prefix: prefix),
            logger: logger
        )
    }

    private static func runtimeEnvironment(runtimeExecutable: URL, prefix: URL) -> [String: String] {
        WineProcessEnvironment.make(runtimeExecutable: runtimeExecutable, prefix: prefix)
    }
}

public struct RuntimeInstallResult: Sendable, Equatable {
    public let record: InstalledRuntimeRecord
    public let prefixURL: URL
}

public final class FreeWineRuntimeProvider: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (Double, EnvironmentPhase) -> Void
    private let fileManager: FileManager
    private let logger: PortsideLogger
    private let downloader: SecureDownloader

    public init(fileManager: FileManager = .default, logger: PortsideLogger = PortsideLogger(), downloader: SecureDownloader? = nil) {
        self.fileManager = fileManager; self.logger = logger; self.downloader = downloader ?? SecureDownloader(fileManager: fileManager, logger: logger)
    }

    public func install(progress: ProgressHandler? = nil) async throws -> RuntimeInstallResult {
        let manifest = FreeRuntimeCatalog.wine
        let rosetta = await RosettaManager.status()
        guard rosetta.installed else { throw RuntimePipelineError.rosettaUnavailable }
        try fileManager.createDirectory(at: PortsidePaths.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: PortsidePaths.downloads, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: PortsidePaths.runtime, withIntermediateDirectories: true)
        if !GStreamerManager.isInstalled {
            progress?(0.03, .graphicsInstalling)
            logger.write("GStreamer runtime is not installed; requesting the official system installer")
            try await GStreamerManager.install(using: downloader, logger: logger)
        }
        progress?(0.05, .runtimeDownloading)
        let archive = PortsidePaths.downloads.appendingPathComponent("\(manifest.identifier)-\(manifest.version).tar.xz")
        if !fileManager.fileExists(atPath: archive.path) {
            _ = try await downloader.download(from: manifest.upstreamURL, to: archive) { value in
                progress?(0.05 + (value * 0.28), .runtimeDownloading)
            }
        }
        progress?(0.35, .runtimeVerifying)
        do {
            try IntegrityVerifier.verify(url: archive, expectedSHA256: manifest.sha256, expectedSize: manifest.expectedSize)
        } catch {
            try? fileManager.removeItem(at: archive)
            throw error
        }
        progress?(0.45, .runtimeInstalling)
        let installedRoot = PortsidePaths.runtime.appendingPathComponent(manifest.version, isDirectory: true)
        let executable = installedRoot.appendingPathComponent(manifest.relativeExecutablePath)
        if !fileManager.isExecutableFile(atPath: executable.path) {
            let temporary = PortsidePaths.runtime.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            do {
                try await SafeArchiveExtractor.extractTarXZ(archive, to: temporary, logger: logger)
                let extracted = temporary.appendingPathComponent(manifest.bundleDirectoryName)
                guard fileManager.isExecutableFile(atPath: extracted.appendingPathComponent("Contents/Resources/wine/bin/wine").path) else { throw RuntimePipelineError.runtimeStructureInvalid }
                try AtomicInstaller.installDirectory(from: extracted, to: installedRoot, fileManager: fileManager)
                try? fileManager.removeItem(at: temporary)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        }
        let finalExecutable = installedRoot.appendingPathComponent(manifest.relativeExecutablePath)
        guard fileManager.isExecutableFile(atPath: finalExecutable.path) else { throw RuntimePipelineError.runtimeStructureInvalid }
        progress?(0.8, .prefixCreating)
        let prefix = PortsidePaths.steamPrefix
        try fileManager.createDirectory(at: prefix, withIntermediateDirectories: true)
        let environment = WineProcessEnvironment.make(runtimeExecutable: finalExecutable, prefix: prefix)
        let wineboot = installedRoot.appendingPathComponent("Contents/Resources/wine/bin/wineboot")
        if !fileManager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) {
            let result = try await DirectProcess.run(executable: wineboot, arguments: ["-u"], environment: environment, logger: logger)
            guard result.status == 0 else { throw RuntimePipelineError.processFailed("prefix initialization", result.status) }
        }
        let registryResult = try await WinePrefixManager.configureSilentCrashHandling(runtimeExecutable: finalExecutable, prefix: prefix, logger: logger)
        guard registryResult.status == 0 else { throw RuntimePipelineError.processFailed("Wine crash-dialog configuration", registryResult.status) }
        progress?(1, .steamInstalling)
        let record = InstalledRuntimeRecord(manifest: manifest, installedPath: installedRoot, executablePath: finalExecutable, graphicsBackend: FreeRuntimeCatalog.graphics, installedAt: Date(), gstreamerInstalled: GStreamerManager.isInstalled)
        let recordURL = installedRoot.appendingPathComponent("portside-runtime.json")
        try JSONEncoder.portside.encode(record).write(to: recordURL, options: .atomic)
        return RuntimeInstallResult(record: record, prefixURL: prefix)
    }
}

public struct SteamCEFLogFinding: Sendable, Equatable {
    public let category: String
    public let timestamp: String?
    public let line: String

    public init(category: String, timestamp: String? = nil, line: String) {
        self.category = category
        self.timestamp = timestamp
        self.line = line
    }
}

public struct SteamCEFLogBaseline: Sendable, Equatable {
    public let offsets: [String: Int64]

    public init(offsets: [String: Int64]) {
        self.offsets = offsets
    }
}

public struct SteamCEFLogAnalysis: Sendable, Equatable {
    public let filesRead: [String]
    public let findings: [SteamCEFLogFinding]
    public let failureCategories: [String]
    public let webhelperRestartCount: Int
    public let webhelperExitCode: Int32?
    public let cacheCorruptionLikely: Bool
    public let browserReadyDetected: Bool
    public let contentWindowEvidence: Bool
    public let rendererMode: String?
    public let gpuProcessStatus: String?
    public let steamVersion: String?
    public let effectiveCEFArchitecture: String?

    public init(
        filesRead: [String],
        findings: [SteamCEFLogFinding],
        failureCategories: [String] = [],
        webhelperRestartCount: Int,
        webhelperExitCode: Int32? = nil,
        cacheCorruptionLikely: Bool,
        browserReadyDetected: Bool = false,
        contentWindowEvidence: Bool = false,
        rendererMode: String? = nil,
        gpuProcessStatus: String? = nil,
        steamVersion: String? = nil,
        effectiveCEFArchitecture: String? = nil
    ) {
        self.filesRead = filesRead; self.findings = findings; self.failureCategories = failureCategories
        self.webhelperRestartCount = webhelperRestartCount; self.webhelperExitCode = webhelperExitCode
        self.cacheCorruptionLikely = cacheCorruptionLikely; self.browserReadyDetected = browserReadyDetected
        self.contentWindowEvidence = contentWindowEvidence; self.rendererMode = rendererMode
        self.gpuProcessStatus = gpuProcessStatus; self.steamVersion = steamVersion
        self.effectiveCEFArchitecture = effectiveCEFArchitecture
    }

    public var hasStrongUIEvidence: Bool {
        let blocking = Set([
            "cef_gpu_initialization_failed", "cef_angle_failed", "cef_compositor_failed", "cef_renderer_failed",
            "cef_webhelper_crash_loop", "cef_cache_failure", "cef_cache_failed", "cef_dependency_missing",
            "cef_resources_not_loaded", "cef_sandbox_failure", "cef_network_failure", "cef_network_failed",
            "cef_certificate_failure", "cef_certificate_failed"
        ])
        return browserReadyDetected && contentWindowEvidence && failureCategories.allSatisfy { !blocking.contains($0) }
    }
}

public enum SteamCEFLogAnalyzer {
    public static let logFilenames = [
        "webhelper_gpu.txt", "cef_log.txt", "steamui_html.txt", "webhelper.txt",
        "bootstrap_log.txt", "console_log.txt", "connection_log.txt"
    ]

    public static func captureBaseline(prefix: URL, fileManager: FileManager = .default) -> SteamCEFLogBaseline {
        let roots = [
            prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true),
            prefix.appendingPathComponent("drive_c/Program Files/Steam", isDirectory: true)
        ]
        var offsets: [String: Int64] = [:]
        for root in roots {
            for filename in logFilenames {
                let url = root.appendingPathComponent("logs", isDirectory: true).appendingPathComponent(filename)
                if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                    offsets[url.path] = Int64(size)
                }
            }
        }
        return SteamCEFLogBaseline(offsets: offsets)
    }

    public static func analyze(prefix: URL, fileManager: FileManager = .default, minimumModificationDate: Date? = nil, baseline: SteamCEFLogBaseline? = nil) -> SteamCEFLogAnalysis {
        let steamRoots = [
            prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true),
            prefix.appendingPathComponent("drive_c/Program Files/Steam", isDirectory: true)
        ]
        var filesRead: [String] = []
        var findings: [SteamCEFLogFinding] = []
        var failureCategories = Set<String>()
        var restartCount = 0
        var webhelperExitCode: Int32?
        var cacheCorruptionLikely = false
        var browserReadyDetected = false
        var contentWindowSignals = Set<String>()
        var contentWindowEvidence = false
        var rendererMode: String?
        var gpuProcessStatus: String?
        var steamVersion: String?
        var effectiveCEFArchitecture: String?

        for root in steamRoots {
            for filename in logFilenames {
                let url = root.appendingPathComponent("logs", isDirectory: true).appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: url.path), let content = readTail(of: url, fileManager: fileManager, startingOffset: baseline?.offsets[url.path]) else { continue }
                if baseline == nil, let minimumModificationDate,
                   let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modified < minimumModificationDate {
                    continue
                }
                filesRead.append(filename)
                for rawLine in content.split(whereSeparator: \.isNewline).map(String.init) {
                    let lowercased = rawLine.lowercased()
                    if lowercased.contains("restart webhelper process") { restartCount += 1 }
                    if lowercased.contains("webhelper"), lowercased.contains("exit") {
                        let candidate = rawLine.split(whereSeparator: { !$0.isNumber && $0 != "-" }).last.flatMap { Int32($0) }
                        webhelperExitCode = candidate ?? webhelperExitCode
                    }
                    if lowercased.contains("browserready") { browserReadyDetected = true }
                    if let signal = ["createresponse", "getdesiredsteamuiwindows", "popuphtmlwindow", "created browser window", "created window"].first(where: lowercased.contains) {
                        contentWindowSignals.insert(signal)
                    }
                    if lowercased.contains("client version") {
                        if let version = rawLine.split(separator: ":", maxSplits: 1).last {
                            steamVersion = String(PortsideLogger.sanitize(String(version).trimmingCharacters(in: .whitespacesAndNewlines)).prefix(80))
                        }
                    }
                    if lowercased.contains("cef.win32") || lowercased.contains("cef win32") || lowercased.contains("32-bit cef") {
                        effectiveCEFArchitecture = "32bit"
                    } else if lowercased.contains("cef.win64") || lowercased.contains("cef win64") || lowercased.contains("64-bit cef") {
                        effectiveCEFArchitecture = "64bit"
                    }
                    if lowercased.contains("disabling gpu acceleration") || lowercased.contains("software rendering") {
                        rendererMode = "software"; gpuProcessStatus = "disabled"
                    } else if lowercased.contains("swiftshader") {
                        rendererMode = "swiftshader"
                    } else if lowercased.contains("use-gl=angle") || lowercased.contains("angle") {
                        rendererMode = "angle"
                    } else if lowercased.contains("d3d11") {
                        rendererMode = "d3d11"
                    } else if lowercased.contains("opengl") {
                        rendererMode = "opengl"
                    } else if lowercased.contains("vulkan") {
                        rendererMode = "vulkan"
                    } else if lowercased.contains("gpu acceleration") {
                        rendererMode = "gpu"
                    }
                    if lowercased.contains("gpu process started") && gpuProcessStatus == nil { gpuProcessStatus = "started" }
                    if lowercased.contains("gpu process crashed") || lowercased.contains("gpu process exited") || lowercased.contains("failed to initialize gpu") || lowercased.contains("gpu initialization failed") || lowercased.contains("gpu process launch failed") {
                        failureCategories.insert("cef_gpu_initialization_failed"); gpuProcessStatus = "failed"
                    }
                    let angleFailure = (lowercased.contains("angle") || lowercased.contains("eglcreatecontext") || lowercased.contains("renderer11.cpp") || lowercased.contains("dxgi"))
                        && ["error", "failed", "unable", "unsupported"].contains(where: lowercased.contains)
                    if angleFailure { failureCategories.insert("cef_angle_failed") }
                    let compositorFailure = (lowercased.contains("compositor") || lowercased.contains("context lost")) && ["error", "failed", "crashed", "lost", "unable", "disabled"].contains(where: lowercased.contains)
                    if compositorFailure { failureCategories.insert("cef_compositor_failed") }
                    if lowercased.contains("renderer") && (lowercased.contains("crash") || lowercased.contains("failed") || lowercased.contains("exited")) {
                        failureCategories.insert("cef_renderer_failed")
                    }
                    if lowercased.contains("cache") && (lowercased.contains("corrupt") || lowercased.contains("failed") || lowercased.contains("invalid") || lowercased.contains("access denied") || lowercased.contains("loading cache")) {
                        failureCategories.insert("cef_cache_failure"); failureCategories.insert("cef_cache_failed"); cacheCorruptionLikely = true
                    }
                    if ["err_connection", "err_name_not_resolved", "err_network_changed", "wsalookupservicebegin failed", "network error", "http error"].contains(where: lowercased.contains) {
                        failureCategories.insert("cef_network_failure"); failureCategories.insert("cef_network_failed")
                    }
                    if ["err_cert", "certificate verification failed", "crl - verification failed", "certificate error"].contains(where: lowercased.contains) {
                        failureCategories.insert("cef_certificate_failure"); failureCategories.insert("cef_certificate_failed")
                    }
                    if ["missing dll", "could not load", "module not found", "dependency missing"].contains(where: lowercased.contains) {
                        failureCategories.insert("cef_dependency_missing")
                    }
                    if ["failed to load resource", "resource load failed"].contains(where: lowercased.contains) {
                        failureCategories.insert("cef_resources_not_loaded")
                    }
                    if lowercased.contains("sandbox") && ["failed", "error", "denied", "unable"].contains(where: lowercased.contains) {
                        failureCategories.insert("cef_sandbox_failure")
                    }
                    let matches = failureCategories.filter { category in
                        switch category {
                        case "cef_gpu_initialization_failed": return lowercased.contains("gpu") || lowercased.contains("context lost")
                        case "cef_angle_failed": return lowercased.contains("angle") || lowercased.contains("eglcreatecontext") || lowercased.contains("dxgi")
                        case "cef_compositor_failed": return lowercased.contains("compositor") || lowercased.contains("context lost")
                        case "cef_renderer_failed": return lowercased.contains("renderer")
                        case "cef_cache_failure", "cef_cache_failed": return lowercased.contains("cache")
                        case "cef_network_failure", "cef_network_failed": return ["err_connection", "err_name_not_resolved", "err_network_changed", "wsalookupservicebegin failed", "network error", "http error"].contains(where: lowercased.contains)
                        case "cef_certificate_failure", "cef_certificate_failed": return ["err_cert", "certificate", "crl - verification failed"].contains(where: lowercased.contains)
                        case "cef_dependency_missing": return ["missing dll", "could not load", "module not found", "dependency missing"].contains(where: lowercased.contains)
                        case "cef_resources_not_loaded": return ["failed to load resource", "resource load failed"].contains(where: lowercased.contains)
                        case "cef_sandbox_failure": return lowercased.contains("sandbox")
                        default: return false
                        }
                    }.sorted()
                    guard !matches.isEmpty else { continue }
                    let safeLine = String(PortsideLogger.sanitize(rawLine).prefix(500))
                    let timestamp = rawLine.first == "[" ? rawLine.split(separator: "]", maxSplits: 1).first.map { String($0.dropFirst()) } : nil
                    for category in matches {
                        findings.append(SteamCEFLogFinding(category: category, timestamp: timestamp, line: safeLine))
                        if findings.count >= 24 { break }
                    }
                    if findings.count >= 24 { break }
                }
                if findings.count >= 24 { break }
            }
            if findings.count >= 24 { break }
        }
        if restartCount >= 3 { failureCategories.insert("cef_webhelper_crash_loop") }
        contentWindowEvidence = contentWindowSignals.count >= 2
        if !browserReadyDetected || !contentWindowEvidence { failureCategories.insert("cef_ui_unverified") }
        return SteamCEFLogAnalysis(
            filesRead: Array(Set(filesRead)).sorted(), findings: findings,
            failureCategories: failureCategories.sorted(), webhelperRestartCount: restartCount,
            webhelperExitCode: webhelperExitCode, cacheCorruptionLikely: cacheCorruptionLikely,
            browserReadyDetected: browserReadyDetected, contentWindowEvidence: contentWindowEvidence,
            rendererMode: rendererMode, gpuProcessStatus: gpuProcessStatus, steamVersion: steamVersion,
            effectiveCEFArchitecture: effectiveCEFArchitecture
        )
    }

    private static func readTail(of url: URL, fileManager: FileManager, startingOffset: Int64? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = Int64((try? handle.seekToEnd()) ?? 0)
        if let startingOffset, fileSize <= startingOffset { return nil }
        let minimumOffset = max(Int64(0), min(fileSize, startingOffset ?? 0))
        let offset = fileSize > minimumOffset + 64 * 1024 ? fileSize - 64 * 1024 : minimumOffset
        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public enum SteamWindowVisualState: String, Codable, Sendable {
    case unavailable
    case black
    case rendered
}

public enum SteamWindowPixelAnalyzer {
    /// Classifies sampled window pixels without treating a dark Steam theme as a blank window.
    /// A window is considered black only when its content is almost uniformly near zero.
    public static func classify(
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int,
        alphaFirst: Bool = false,
        data: [UInt8]
    ) -> SteamWindowVisualState {
        guard width > 0, height > 0, bytesPerPixel >= 3, bytesPerRow > 0 else { return .unavailable }
        let colorOffset = alphaFirst && bytesPerPixel >= 4 ? 1 : 0
        guard colorOffset + 2 < bytesPerPixel else { return .unavailable }

        let sampleStepX = max(1, width / 16)
        let sampleStepY = max(1, height / 12)
        let contentStartY = height > 160 ? min(height - 1, height / 10) : 0
        var samples = 0
        var darkSamples = 0
        var brightSamples = 0
        var totalLuminance = 0.0

        for y in stride(from: contentStartY, to: height, by: sampleStepY) {
            for x in stride(from: 0, to: width, by: sampleStepX) {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel) + colorOffset
                guard offset + 2 < data.count else { continue }
                let red = Double(data[offset])
                let green = Double(data[offset + 1])
                let blue = Double(data[offset + 2])
                let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                samples += 1
                totalLuminance += luminance
                if max(red, green, blue) <= 12 { darkSamples += 1 }
                if max(red, green, blue) >= 32 { brightSamples += 1 }
            }
        }

        guard samples > 0 else { return .unavailable }
        let meanLuminance = totalLuminance / Double(samples)
        let brightFraction = Double(brightSamples) / Double(samples)
        if meanLuminance < 18 && brightFraction < 0.025 {
            return .black
        }
        if darkSamples < samples || meanLuminance >= 18 || brightFraction >= 0.025 {
            return .rendered
        }
        return .unavailable
    }

    /// Pixel classification is available only for bytes supplied by a caller.
    /// Portside deliberately does not capture another application's window or the
    /// display, because those CoreGraphics APIs require Screen Recording access.
}

public final class SteamLaunchLock: @unchecked Sendable {
    private let fileDescriptor: Int32
    public let url: URL

    private init(fileDescriptor: Int32, url: URL) {
        self.fileDescriptor = fileDescriptor
        self.url = url
    }

    public static func acquire(url: URL = PortsidePaths.root.appendingPathComponent("steam-launch.lock")) -> SteamLaunchLock? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        let owner = Data("pid=\(getpid())\n".utf8)
        ftruncate(descriptor, 0)
        owner.withUnsafeBytes { buffer in
            _ = Darwin.write(descriptor, buffer.baseAddress, owner.count)
        }
        return SteamLaunchLock(fileDescriptor: descriptor, url: url)
    }

    deinit {
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}

private struct SteamWindowSnapshot {
    let processIdentifier: pid_t
}

public struct SteamReadinessReport: Sendable, Equatable {
    public let status: SteamProcessStatus
    public let cefStrategy: String
    public let webhelperStarted: Bool
    public let webhelperExitCode: Int32?
    public let webhelperRestartCount: Int
    public let webhelperProcessCount: Int
    public let webhelperStableDuration: TimeInterval
    public let windowDetected: Bool
    public let cefArgumentsObserved: Bool
    public let browserReadyDetected: Bool
    public let rendererMode: String?
    public let gpuProcessStatus: String?
    public let windowVisualState: SteamWindowVisualState
    public let logAnalysis: SteamCEFLogAnalysis

    public init(
        status: SteamProcessStatus,
        cefStrategy: String,
        webhelperStarted: Bool,
        webhelperExitCode: Int32?,
        webhelperRestartCount: Int,
        webhelperProcessCount: Int = 0,
        webhelperStableDuration: TimeInterval,
        windowDetected: Bool,
        cefArgumentsObserved: Bool,
        browserReadyDetected: Bool,
        rendererMode: String?,
        gpuProcessStatus: String?,
        windowVisualState: SteamWindowVisualState = .unavailable,
        logAnalysis: SteamCEFLogAnalysis
    ) {
        self.status = status
        self.cefStrategy = cefStrategy
        self.webhelperStarted = webhelperStarted
        self.webhelperExitCode = webhelperExitCode
        self.webhelperRestartCount = webhelperRestartCount
        self.webhelperProcessCount = webhelperProcessCount
        self.webhelperStableDuration = webhelperStableDuration
        self.windowDetected = windowDetected
        self.cefArgumentsObserved = cefArgumentsObserved
        self.browserReadyDetected = browserReadyDetected
        self.rendererMode = rendererMode
        self.gpuProcessStatus = gpuProcessStatus
        self.windowVisualState = windowVisualState
        self.logAnalysis = logAnalysis
    }
}

public enum SteamHTMLCacheRecovery {
    public static func renameHTMLCache(prefix: URL, fileManager: FileManager = .default, logger: PortsideLogger = PortsideLogger()) throws -> [URL] {
        let usersRoot = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        guard let users = try? fileManager.contentsOfDirectory(at: usersRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var backups: [URL] = []
        for user in users where (try? user.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let cache = user.appendingPathComponent("AppData/Local/Steam/htmlcache", isDirectory: true)
            guard fileManager.fileExists(atPath: cache.path) else { continue }
            let backup = cache.deletingLastPathComponent().appendingPathComponent("htmlcache.portside-backup-\(UUID().uuidString)", isDirectory: true)
            try fileManager.moveItem(at: cache, to: backup)
            backups.append(backup)
            logger.write("Renamed Steam HTML cache for recovery: \(backup.path)")
            cleanupOldBackups(in: cache.deletingLastPathComponent(), fileManager: fileManager, logger: logger)
        }
        return backups
    }

    private static func cleanupOldBackups(in directory: URL, fileManager: FileManager, logger: PortsideLogger) {
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let backups = entries.filter { $0.lastPathComponent.hasPrefix("htmlcache.portside-backup-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                return (left ?? .distantPast) > (right ?? .distantPast)
            }
        let retentionCutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for (index, backup) in backups.enumerated() {
            let modified = (try? backup.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            guard index >= 2 || (modified.map { $0 < retentionCutoff } ?? false) else { continue }
            let oldBackup = backup
            try? fileManager.removeItem(at: oldBackup)
            logger.write("Removed expired Steam HTML cache backup", level: .info)
        }
    }
}

public enum SteamProcessStatus: String, Codable, Sendable {
    case notRunning, steamStarting, wineProcessRunning, steamProcessRunning, webhelperStarting, webhelperNotStarted, webhelperCrashLoop
    case windowDetected, blackWindow, windowNotVisible, uiUnverified, cefReady, ready
    case cefGPUFailed, cefRendererFailed, cefNetworkFailed, rendererFailed, resourcesNotLoaded, cefFailed, windowVisible, exitedUnexpectedly
}

public final class SteamReadinessMonitor: @unchecked Sendable {
    private let logger: PortsideLogger
    public init(logger: PortsideLogger = PortsideLogger()) { self.logger = logger }

    public func bootstrapComplete(prefix: URL) -> Bool {
        let markers = [
            prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/package/steam_client_win32.installed"),
            prefix.appendingPathComponent("drive_c/Program Files/Steam/package/steam_client_win32.installed")
        ]
        return markers.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func waitForBootstrap(prefix: URL, timeout: TimeInterval = 180) async -> Bool {
        let marker = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/package/steam_client_win32.installed")
        let alternateMarker = prefix.appendingPathComponent("drive_c/Program Files/Steam/package/steam_client_win32.installed")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshot = await processSnapshot()
            terminateWineDebuggersIfNeeded(in: snapshot, stage: "Steam bootstrap")
            let markerExists = FileManager.default.fileExists(atPath: marker.path) || FileManager.default.fileExists(atPath: alternateMarker.path)
            if markerExists && managedProcessSnapshot(snapshot, prefix: prefix, processNames: ["steam.exe", "steamwebhelper"]) {
                logger.write("Steam bootstrap marker detected")
                return true
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    public func waitForSteam(executable: URL, prefix: URL = PortsidePaths.steamPrefix, timeout: TimeInterval = 60) async -> SteamProcessStatus {
        await waitForSteamReport(executable: executable, prefix: prefix, timeout: timeout).status
    }

    public func waitForSteamReport(executable: URL, prefix: URL = PortsidePaths.steamPrefix, strategy: SteamLaunchConfiguration = .primary, timeout: TimeInterval = 60, attemptStartedAt: Date? = nil, logBaseline: SteamCEFLogBaseline? = nil) async -> SteamReadinessReport {
        let deadline = Date().addingTimeInterval(timeout)
        let attemptStartedAt = attemptStartedAt ?? Date()
        var sawSteam = false
        var webhelperWasRunning = false
        var webhelperStarted = false
        var webhelperRestartCount = 0
        var webhelperProcessCount = 0
        var webhelperStableSince: Date?
        var windowDetected = false
        var windowVisualState = SteamWindowVisualState.unavailable
        var cefArgumentsObserved = strategy.arguments.isEmpty
        var loggedUnverifiedWindow = false
        while Date() < deadline {
            let snapshot = await processSnapshot()
            terminateWineDebuggersIfNeeded(in: snapshot, stage: "Steam startup")
            let steamRunning = managedProcessSnapshot(snapshot, prefix: prefix, processNames: ["steam.exe", "steamwebhelper"])
            let webhelperRunning = managedProcessSnapshot(snapshot, prefix: prefix, processNames: ["steamwebhelper"])
            webhelperProcessCount = max(webhelperProcessCount, snapshot.split(whereSeparator: \.isNewline).filter { $0.contains("steamwebhelper") }.count)
            if steamRunning { sawSteam = true }
            if webhelperRunning && cefArgumentsReachedWebhelper(snapshot: snapshot, strategy: strategy) { cefArgumentsObserved = true }
            if webhelperRunning {
                if !webhelperWasRunning {
                    if webhelperStarted { webhelperRestartCount += 1 }
                    webhelperStarted = true
                    webhelperStableSince = Date()
                    logger.write("steamwebhelper_started")
                }
            } else if webhelperWasRunning {
                webhelperRestartCount += 1
                webhelperStableSince = nil
                logger.write("steamwebhelper_exited", level: .warning)
            }
            webhelperWasRunning = webhelperRunning
            if sawSteam, let window = visibleSteamWindow(processSnapshot: snapshot) {
                NSRunningApplication(processIdentifier: window.processIdentifier)?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                windowDetected = true
                // Window metadata is safe to inspect without Screen Recording
                // permission. Pixel inspection is intentionally unavailable.
                windowVisualState = .unavailable
                let stableSeconds = stableDuration(since: webhelperStableSince)
                let analysis = SteamCEFLogAnalyzer.analyze(prefix: prefix, minimumModificationDate: attemptStartedAt, baseline: logBaseline)
                let visualStateAllowsReadiness = windowVisualState != .black
                if webhelperWasRunning && webhelperStarted && stableSeconds >= 2 && cefArgumentsObserved && analysis.hasStrongUIEvidence && visualStateAllowsReadiness {
                    logger.write("Steam window detected and activated")
                    return SteamReadinessReport(status: .ready, cefStrategy: strategy.identifier, webhelperStarted: webhelperStarted, webhelperExitCode: analysis.webhelperExitCode, webhelperRestartCount: max(webhelperRestartCount, analysis.webhelperRestartCount), webhelperProcessCount: webhelperProcessCount, webhelperStableDuration: stableSeconds, windowDetected: windowDetected, cefArgumentsObserved: cefArgumentsObserved, browserReadyDetected: analysis.browserReadyDetected, rendererMode: analysis.rendererMode, gpuProcessStatus: analysis.gpuProcessStatus, windowVisualState: windowVisualState, logAnalysis: analysis)
                }
                if !loggedUnverifiedWindow {
                    logger.write("Steam window detected before webhelper UI verification", level: .warning)
                    loggedUnverifiedWindow = true
                }
            }
            if webhelperRestartCount >= 3 {
                logger.write("steamwebhelper_crash_loop", level: .error)
                break
            }
            if sawSteam { try? await Task.sleep(for: .milliseconds(750)); continue }
            if snapshot.contains(executable.lastPathComponent.lowercased()) { try? await Task.sleep(for: .milliseconds(750)); continue }
            try? await Task.sleep(for: .seconds(1))
        }
        let analysis = SteamCEFLogAnalyzer.analyze(prefix: prefix, minimumModificationDate: attemptStartedAt, baseline: logBaseline)
        let restartCount = max(webhelperRestartCount, analysis.webhelperRestartCount)
        let status: SteamProcessStatus
        if analysis.failureCategories.contains("cef_webhelper_crash_loop") || restartCount >= 3 {
            status = .webhelperCrashLoop
        } else if !sawSteam && !webhelperStarted {
            status = .notRunning
        } else if !webhelperStarted {
            status = .webhelperStarting
        } else if windowVisualState == .black {
            status = .blackWindow
        } else if analysis.failureCategories.contains("cef_renderer_failed") {
            status = .cefRendererFailed
        } else if analysis.failureCategories.contains(where: { $0 == "cef_network_failure" || $0 == "cef_network_failed" || $0 == "cef_certificate_failure" || $0 == "cef_certificate_failed" }) {
            status = .cefNetworkFailed
        } else if analysis.failureCategories.contains("cef_resources_not_loaded") {
            status = .resourcesNotLoaded
        } else if analysis.failureCategories.contains(where: { $0 == "cef_gpu_initialization_failed" || $0 == "cef_angle_failed" || $0 == "cef_compositor_failed" || $0 == "cef_sandbox_failure" || $0 == "cef_dependency_missing" || $0 == "cef_cache_failure" || $0 == "cef_cache_failed" }) {
            status = .cefGPUFailed
        } else if sawSteam && !windowDetected {
            status = .windowNotVisible
        } else if sawSteam || windowDetected || webhelperStarted {
            status = .uiUnverified
        } else {
            status = .exitedUnexpectedly
        }
        return SteamReadinessReport(status: status, cefStrategy: strategy.identifier, webhelperStarted: webhelperStarted, webhelperExitCode: analysis.webhelperExitCode, webhelperRestartCount: restartCount, webhelperProcessCount: webhelperProcessCount, webhelperStableDuration: stableDuration(since: webhelperStableSince), windowDetected: windowDetected, cefArgumentsObserved: cefArgumentsObserved, browserReadyDetected: analysis.browserReadyDetected, rendererMode: analysis.rendererMode, gpuProcessStatus: analysis.gpuProcessStatus, windowVisualState: windowVisualState, logAnalysis: analysis)
    }

    public func isSteamProcessRunning(prefix: URL = PortsidePaths.steamPrefix) async -> Bool {
        let snapshot = await processSnapshot()
        return managedProcessSnapshot(snapshot, prefix: prefix, processNames: ["steam.exe", "steamwebhelper"])
    }

    public func stopSteam(runtimeExecutable: URL, prefix: URL) async {
        let wineserver = runtimeExecutable.deletingLastPathComponent().appendingPathComponent("wineserver")
        guard FileManager.default.isExecutableFile(atPath: wineserver.path) else {
            logger.write("Could not locate wineserver while stopping Steam", level: .error)
            return
        }
        let killServer = Process()
        killServer.executableURL = wineserver
        killServer.arguments = ["-k"]
        killServer.environment = WineProcessEnvironment.make(runtimeExecutable: runtimeExecutable, prefix: prefix)
        killServer.standardOutput = FileHandle.nullDevice
        killServer.standardError = FileHandle.nullDevice
        try? killServer.run()
        try? await Task.sleep(for: .milliseconds(750))
        if killServer.isRunning {
            killServer.terminate()
            logger.write("wineserver -k exceeded the graceful stop window; continuing with managed process cleanup", level: .warning)
        }
        logger.write("Steam process tree termination requested for the managed prefix")
        await forceTerminateManagedSteamIfNeeded()
    }

    public func waitForSteamToStop(timeout: TimeInterval = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !(await isSteamProcessRunning(prefix: PortsidePaths.steamPrefix)) {
                logger.write("Steam process tree stopped")
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logger.write("Steam process tree did not stop before the timeout", level: .error)
        return false
    }

    private func stableDuration(since date: Date?) -> TimeInterval {
        guard let date else { return 0 }
        return max(0, Date().timeIntervalSince(date))
    }

    private func processSnapshot() async -> String {
        let result = try? await DirectProcess.run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-axo", "pid=,comm=,args="] , logger: logger, logOutput: false)
        return result?.output.lowercased() ?? ""
    }

    private func managedProcessSnapshot(_ snapshot: String, prefix: URL, processNames: [String]) -> Bool {
        let managedPrefix = prefix.path.lowercased()
        let lines = snapshot.split(whereSeparator: \.isNewline).map(String.init)
        if processNames == ["steamwebhelper"] {
            return lines.contains { $0.contains("steamwebhelper") }
        }
        if processNames == ["steam.exe", "steamwebhelper"] {
            return lines.contains { $0.contains(managedPrefix) && $0.contains("steam.exe") }
                || lines.contains { $0.contains("steamwebhelper") }
        }
        return lines.contains { text in
            text.contains(managedPrefix) && processNames.contains { text.contains($0) }
        }
    }

    private func cefArgumentsReachedWebhelper(snapshot: String, strategy: SteamLaunchConfiguration) -> Bool {
        guard !strategy.arguments.isEmpty else { return true }
        let webhelperLines = snapshot.split(whereSeparator: \.isNewline).map(String.init).filter { $0.contains("steamwebhelper") }
        guard !webhelperLines.isEmpty else { return false }
        return strategy.arguments.allSatisfy { argument in
            switch argument {
            case "-cef-disable-gpu":
                return webhelperLines.contains { $0.contains("-cef-disable-gpu") || $0.contains("--disable-gpu") }
            case "-cef-disable-gpu-compositing":
                return webhelperLines.contains { $0.contains("-cef-disable-gpu-compositing") || $0.contains("--disable-gpu-compositing") }
            default:
                return webhelperLines.contains { $0.contains(argument.lowercased()) }
            }
        }
    }

    private func terminateWineDebuggersIfNeeded(in snapshot: String, stage: String) {
        guard snapshot.contains("winedbg") else { return }
        logger.write("Wine debugger detected during \(stage); silent crash policy remains active", level: .warning)
    }

    public func activateVisibleSteamWindow(prefix: URL = PortsidePaths.steamPrefix) async -> Bool {
        let snapshot = await processSnapshot()
        guard managedProcessSnapshot(snapshot, prefix: prefix, processNames: ["steam.exe", "steamwebhelper"]) else { return false }
        guard let window = visibleSteamWindow(processSnapshot: snapshot) else { return false }
        logger.write("Existing Steam window activation requested; readiness remains unverified")
        NSRunningApplication(processIdentifier: window.processIdentifier)?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        return true
    }

    private func visibleSteamWindow(processSnapshot: String) -> SteamWindowSnapshot? {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.compactMap { window -> SteamWindowSnapshot? in
            let owner = (window[kCGWindowOwnerName as String] as? String)?.lowercased() ?? ""
            let name = (window[kCGWindowName as String] as? String)?.lowercased() ?? ""
            let steamTitle = ["steam", "login", "sign in", "update", "store", "library"].contains { name.contains($0) }
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber).map({ pid_t($0.intValue) }) else { return nil }
            let isOnscreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let bounds = window[kCGWindowBounds as String] as? [String: Any]
            let width = (bounds?["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds?["Height"] as? NSNumber)?.doubleValue ?? 0
            guard isOnscreen || (width >= 200 && height >= 120) else { return nil }
            let isSteamProcess = processSnapshot.split(whereSeparator: \.isNewline).contains { line in
                let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count == 3, Int32(String(fields[0])) == Int32(ownerPID) else { return false }
                let processArguments = String(fields[1...].joined(separator: " "))
                return processArguments.contains("steam.exe") || processArguments.contains("steamwebhelper")
            }
            guard owner.contains("steam") || steamTitle || (owner.contains("wine") && isSteamProcess) else { return nil }
            return SteamWindowSnapshot(
                processIdentifier: ownerPID
            )
        }.first
    }

    private func forceTerminateManagedSteamIfNeeded() async {
        let initialSnapshot = await processSnapshot()
        let pids = managedSteamProcessIdentifiers(snapshot: initialSnapshot)
        guard !pids.isEmpty else { return }
        for pid in pids {
            logger.write("Terminating managed Wine/Steam process pid=\(pid)", level: .warning)
            _ = kill(pid, SIGTERM)
        }
        try? await Task.sleep(for: .milliseconds(750))
        let remaining = managedSteamProcessIdentifiers(snapshot: await processSnapshot())
        for pid in remaining {
            logger.write("Force terminating managed Wine/Steam process pid=\(pid)", level: .error)
            _ = kill(pid, SIGKILL)
        }
    }

    private func managedSteamProcessIdentifiers(snapshot: String) -> [pid_t] {
        let lines = snapshot.split(whereSeparator: \.isNewline).map(String.init)
        return lines.compactMap { line in
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let pid = fields.first.flatMap({ pid_t($0) }), fields.count >= 3 else { return nil }
            let commandLine = String(fields[2...].joined(separator: " "))
            guard commandLine.contains("steam.exe") || commandLine.contains("steamwebhelper") else { return nil }
            return pid
        }
    }
}
