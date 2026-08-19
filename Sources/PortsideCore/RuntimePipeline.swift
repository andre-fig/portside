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
    case steamUpdating
    case steamLaunching
    case validatingInstallation
    case steamReady
    case steamProcessHandoffComplete
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
        version: "11.6_1",
        upstreamURL: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.6_1/wine-staging-11.6_1-osx64.tar.xz")!,
        sha256: "9e73898fc83b0137638fe90d4868387f30b5993e86aeaef7422d8b1655238014",
        expectedSize: 322_511_424,
        architecture: "x86_64 via Rosetta 2",
        minimumMacOS: "13.0",
        relativeExecutablePath: "Contents/Resources/wine/bin/wine",
        license: "Wine LGPL-2.1-or-later; upstream packaging license must be reviewed before commercial bundling",
        sourceURL: URL(string: "https://gitlab.winehq.org/wine/wine")!,
        includedComponents: ["Wine Staging", "Wine Mono 11.0.0", "Wine Gecko 2.47.4", "WineD3D"],
        validatedAt: ISO8601DateFormatter().date(from: "2026-08-19T00:00:00Z") ?? Date(),
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
    public static let ownerMarkerKey = "PORTSIDE_WINE_PREFIX_MARKER"
    public static let experimentalEnvironmentKeys: Set<String> = [
        "WINEMSYNC", "WINEESYNC", "WINEFSYNC", "WINEFSYNC_FUTEX",
        "DXVK_ASYNC", "DXVK_HUD", "DXVK_ENABLE_NVAPI", "MTL_HUD_ENABLED",
        "WINE_D3D_CONFIG", "WINE_FULLSCREEN_FSR", "STAGING_SHARED_MEMORY",
        "STAGING_WRITECOPY"
    ]
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
        for key in Self.experimentalEnvironmentKeys {
            environment.removeValue(forKey: key)
        }
        environment["WINEPREFIX"] = prefix.path
        environment["WINEARCH"] = "win64"
        environment["WINEDLLOVERRIDES"] = WineRuntimePolicy.dllOverrides
        environment["WINEDEBUG"] = wineDebug
        environment[Self.ownerMarkerKey] = Self.prefixMarker(for: prefix)
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

    public static func prefixMarker(for prefix: URL) -> String {
        let digest = SHA256.hash(data: Data(prefix.standardizedFileURL.path.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func prepend(_ value: String, to existing: String?) -> String {
        guard let existing, !existing.isEmpty else { return value }
        let entries = existing.split(separator: ":").map(String.init)
        guard !entries.contains(value) else { return existing }
        return ([value] + entries).joined(separator: ":")
    }
}

/// Development-only environment profiles used when comparing candidate runtimes.
/// The Sikarugir profile is intentionally not selected by the product runtime and
/// does not ship any Sikarugir binary or wrapper.
public enum RuntimeValidationProfile {
    case officialWine
    case sikarugirMSyncReference

    public func environment(from base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        switch self {
        case .officialWine:
            for key in WineProcessEnvironment.experimentalEnvironmentKeys {
                environment.removeValue(forKey: key)
            }
        case .sikarugirMSyncReference:
            environment["WINEMSYNC"] = "1"
            environment["WINEESYNC"] = "0"
        }
        return environment
    }
}

public enum PrefixSnapshotStrategy: String, Codable, Sendable {
    case copyOnWrite
    case targeted
}

public struct PrefixSnapshotManifest: Codable, Equatable, Sendable {
    public let version: Int
    public let strategy: PrefixSnapshotStrategy
    public let capturedPaths: [String]
    public let missingPaths: [String]

    public init(version: Int = 1, strategy: PrefixSnapshotStrategy, capturedPaths: [String], missingPaths: [String]) {
        self.version = version
        self.strategy = strategy
        self.capturedPaths = capturedPaths
        self.missingPaths = missingPaths
    }
}

/// A recoverable snapshot used before changing Wine runtime state in an existing
/// prefix. APFS clonefile is preferred. The fallback contains only Wine-managed
/// registry/link state and deliberately excludes steamapps, games and caches.
public enum PrefixSnapshot {
    public static let manifestName = ".portside-snapshot.json"
    public static let targetedRollbackPaths = ["system.reg", "user.reg", "userdef.reg", "dosdevices"]
    private static let cloneSafetyReserve: Int64 = 128 * 1024 * 1024

    public static func create(
        prefix: URL,
        backupsRoot: URL = PortsidePaths.backups,
        fileManager: FileManager = .default,
        strategy requestedStrategy: PrefixSnapshotStrategy? = nil,
        availableStorage: Int64? = nil
    ) throws -> URL {
        try fileManager.createDirectory(at: backupsRoot, withIntermediateDirectories: true)
        let strategy = requestedStrategy ?? (canClone(prefix: prefix, fileManager: fileManager) ? .copyOnWrite : .targeted)
        try validateAvailableSpace(prefix: prefix, strategy: strategy, availableStorage: availableStorage, fileManager: fileManager)
        let snapshot = backupsRoot.appendingPathComponent("Steam-prefix-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: snapshot, withIntermediateDirectories: true)

        var manifestStrategy = strategy
        var capturedPaths: [String] = []
        var missingPaths: [String] = []
        if strategy == .copyOnWrite, fileManager.fileExists(atPath: prefix.path) {
            let clonedPrefix = snapshot.appendingPathComponent("prefix", isDirectory: true)
            if !cloneItem(from: prefix, to: clonedPrefix) {
                manifestStrategy = .targeted
                try captureTargetedPaths(prefix: prefix, snapshot: snapshot, fileManager: fileManager, capturedPaths: &capturedPaths, missingPaths: &missingPaths)
            }
        } else if strategy == .copyOnWrite {
            try fileManager.createDirectory(at: snapshot.appendingPathComponent("prefix", isDirectory: true), withIntermediateDirectories: true)
        } else {
            try captureTargetedPaths(prefix: prefix, snapshot: snapshot, fileManager: fileManager, capturedPaths: &capturedPaths, missingPaths: &missingPaths)
        }

        let manifest = PrefixSnapshotManifest(strategy: manifestStrategy, capturedPaths: capturedPaths, missingPaths: missingPaths)
        let data = try JSONEncoder.portside.encode(manifest)
        try data.write(to: snapshot.appendingPathComponent(manifestName), options: .atomic)
        return snapshot
    }

    public static func restore(snapshot: URL, prefix: URL, fileManager: FileManager = .default) throws {
        let manifestURL = snapshot.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder.portside.decode(PrefixSnapshotManifest.self, from: data) else {
            // Compatibility with snapshots created by the previous release. New
            // snapshots never use this path and never copy the whole prefix.
            try restoreClonedPrefix(snapshot: snapshot, prefix: prefix, fileManager: fileManager)
            return
        }
        switch manifest.strategy {
        case .copyOnWrite:
            try restoreClonedPrefix(snapshot: snapshot.appendingPathComponent("prefix", isDirectory: true), prefix: prefix, fileManager: fileManager)
        case .targeted:
            try restoreTargeted(snapshot: snapshot, prefix: prefix, manifest: manifest, fileManager: fileManager)
        }
    }

    public static func retainOnly(_ snapshot: URL, backupsRoot: URL = PortsidePaths.backups, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: backupsRoot, withIntermediateDirectories: true)
        let keepName = snapshot.lastPathComponent
        let entries = try fileManager.contentsOfDirectory(at: backupsRoot, includingPropertiesForKeys: [.isDirectoryKey])
        for entry in entries where entry.lastPathComponent.hasPrefix("Steam-prefix-") && entry.lastPathComponent != keepName {
            try fileManager.removeItem(at: entry)
        }
    }

    public static func validateAvailableSpace(
        prefix: URL,
        strategy: PrefixSnapshotStrategy,
        availableStorage: Int64? = nil,
        fileManager: FileManager = .default
    ) throws {
        let available = availableStorage ?? ((try? prefix.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0)
        let required = estimatedBytes(prefix: prefix, strategy: strategy, fileManager: fileManager) + cloneSafetyReserve
        guard available >= required else {
            throw RuntimePipelineError.snapshotInsufficientSpace(required: required, available: available)
        }
    }

    private static func estimatedBytes(prefix: URL, strategy: PrefixSnapshotStrategy, fileManager: FileManager) -> Int64 {
        guard strategy == .targeted else { return 64 * 1024 * 1024 }
        return targetedRollbackPaths.reduce(Int64(0)) { total, relativePath in
            total + byteSize(of: prefix.appendingPathComponent(relativePath), fileManager: fileManager)
        }
    }

    private static func byteSize(of url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return (fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL }.reduce(Int64(0)) { total, child in
                total + Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }) ?? 0
        }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func canClone(prefix: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: prefix.path) else { return true }
        let probe = fileManager.temporaryDirectory.appendingPathComponent("portside-clone-probe-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: probe) }
        return cloneItem(from: prefix, to: probe)
    }

    private static func cloneItem(from source: URL, to destination: URL) -> Bool {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return Int32(-1) }
                return clonefile(sourcePath, destinationPath, 0)
            }
        }
        return result == 0
    }

    private static func captureTargetedPaths(prefix: URL, snapshot: URL, fileManager: FileManager, capturedPaths: inout [String], missingPaths: inout [String]) throws {
        let targetRoot = snapshot.appendingPathComponent("targeted", isDirectory: true)
        for relativePath in targetedRollbackPaths {
            let source = prefix.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: source.path) else {
                missingPaths.append(relativePath)
                continue
            }
            let destination = targetRoot.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            capturedPaths.append(relativePath)
        }
    }

    private static func restoreClonedPrefix(snapshot: URL, prefix: URL, fileManager: FileManager) throws {
        let parent = prefix.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let replacement = parent.appendingPathComponent(".restore-\(UUID().uuidString)", isDirectory: true)
        guard cloneItem(from: snapshot, to: replacement) || (try? fileManager.copyItem(at: snapshot, to: replacement)) != nil else {
            throw RuntimePipelineError.archiveExtractionFailed("The runtime snapshot could not be restored.")
        }
        if fileManager.fileExists(atPath: prefix.path) {
            let failedPrefix = parent.appendingPathComponent("Steam-prefix-failed-\(UUID().uuidString)", isDirectory: true)
            try fileManager.moveItem(at: prefix, to: failedPrefix)
        }
        try fileManager.moveItem(at: replacement, to: prefix)
    }

    private static func restoreTargeted(snapshot: URL, prefix: URL, manifest: PrefixSnapshotManifest, fileManager: FileManager) throws {
        let targetRoot = snapshot.appendingPathComponent("targeted", isDirectory: true)
        for relativePath in Set(manifest.capturedPaths + manifest.missingPaths) {
            let destination = prefix.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            guard manifest.capturedPaths.contains(relativePath) else { continue }
            let source = targetRoot.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        }
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

public struct PrefixRuntimeMetadata: Codable, Equatable, Sendable {
    public let runtimeIdentifier: String
    public let runtimeVersion: String
    public let preparedAt: Date

    public init(runtimeIdentifier: String, runtimeVersion: String, preparedAt: Date = Date()) {
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeVersion = runtimeVersion
        self.preparedAt = preparedAt
    }

    public static func load(prefix: URL, fileManager: FileManager = .default) -> PrefixRuntimeMetadata? {
        let url = prefix.appendingPathComponent(".portside-runtime.json")
        guard fileManager.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.portside.decode(PrefixRuntimeMetadata.self, from: data)
    }

    public func write(to prefix: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: prefix, withIntermediateDirectories: true)
        let data = try JSONEncoder.portside.encode(self)
        try data.write(to: prefix.appendingPathComponent(".portside-runtime.json"), options: .atomic)
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
    case runtimeMigrationFailed(Int32)
    case snapshotInsufficientSpace(required: Int64, available: Int64)

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
        case .runtimeMigrationFailed: return "The existing Wine prefix could not be migrated safely to the selected runtime."
        case .snapshotInsufficientSpace: return "There is not enough free space to create a safe runtime recovery point."
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
            let metadataPath = entry.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true).last.map(String.init) ?? entry
            if entry.hasPrefix("l") || entry.hasPrefix("h") {
                let linkParts = metadataPath.components(separatedBy: " -> ")
                guard linkParts.count == 2,
                      isSafeRelativePath(linkParts[0]),
                      isSafeLinkTarget(linkParts[0], target: linkParts[1]) else {
                    throw RuntimePipelineError.unexpectedArchiveEntry(metadataPath)
                }
            } else {
                guard isSafeRelativePath(metadataPath) else { throw RuntimePipelineError.unexpectedArchiveEntry(metadataPath) }
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xJf", archive.path, "-C", directory.path], logger: logger)
        guard result.status == 0 else { throw RuntimePipelineError.archiveExtractionFailed(result.output) }
    }

    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        return path.split(separator: "/").allSatisfy { $0 != ".." && !$0.isEmpty }
    }

    private static func isSafeLinkTarget(_ path: String, target: String) -> Bool {
        guard !target.isEmpty, !target.hasPrefix("/"), !target.contains("\0") else { return false }
        var components = path.split(separator: "/").dropLast().map(String.init)
        for component in target.split(separator: "/").map(String.init) {
            if component.isEmpty || component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else { return false }
                components.removeLast()
            } else {
                components.append(component)
            }
        }
        return true
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

public enum PrefixRuntimeMigration {
    public static func requiresMigration(prefix: URL, manifest: RuntimeManifest, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) else { return false }
        guard let metadata = PrefixRuntimeMetadata.load(prefix: prefix, fileManager: fileManager) else { return true }
        return metadata.runtimeIdentifier != manifest.identifier || metadata.runtimeVersion != manifest.version
    }

    public static func updateIfNeeded(
        prefix: URL,
        runtimeExecutable: URL,
        manifest: RuntimeManifest,
        runner: ProcessRunning = SystemProcessRunner(),
        logger: PortsideLogger = PortsideLogger(),
        fileManager: FileManager = .default
    ) async throws -> Bool {
        let hasPrefix = fileManager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path)
        let needsMigration = requiresMigration(prefix: prefix, manifest: manifest, fileManager: fileManager)
        guard !needsMigration || !hasPrefix else {
            logger.write("Migrating the existing Wine prefix with wineboot -u")
            let wineboot = runtimeExecutable.deletingLastPathComponent().appendingPathComponent("wineboot")
            let result = try await runner.run(
                ProcessLaunchSpec(
                    executable: wineboot,
                    arguments: ["-u"],
                    environment: WineProcessEnvironment.make(runtimeExecutable: runtimeExecutable, prefix: prefix),
                    workingDirectory: prefix
                ),
                logger: logger
            )
            guard result.status == 0 else { throw RuntimePipelineError.runtimeMigrationFailed(result.status) }
            return true
        }
        if !hasPrefix {
            logger.write("Initializing the Wine prefix with wineboot -u")
            let wineboot = runtimeExecutable.deletingLastPathComponent().appendingPathComponent("wineboot")
            let result = try await runner.run(
                ProcessLaunchSpec(
                    executable: wineboot,
                    arguments: ["-u"],
                    environment: WineProcessEnvironment.make(runtimeExecutable: runtimeExecutable, prefix: prefix),
                    workingDirectory: prefix
                ),
                logger: logger
            )
            guard result.status == 0 else { throw RuntimePipelineError.runtimeMigrationFailed(result.status) }
            return true
        }
        return false
    }
}

public enum RuntimeStorage {
    /// Removes only obsolete runtime directories after a successful prefix
    /// migration. It never touches Prefix, Steam, steamapps or Downloads.
    public static func removeObsolete11_15(
        runtimeRoot: URL = PortsidePaths.runtime,
        keepingVersion: String,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try fileManager.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        let entries = try fileManager.contentsOfDirectory(at: runtimeRoot, includingPropertiesForKeys: [.isDirectoryKey])
        var removed: [URL] = []
        for entry in entries where entry.lastPathComponent.hasPrefix("11.15") && entry.lastPathComponent != keepingVersion {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            try fileManager.removeItem(at: entry)
            removed.append(entry)
        }
        return removed
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
        let hadExistingPrefix = fileManager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path)
        let snapshot = hadExistingPrefix ? try PrefixSnapshot.create(prefix: prefix, fileManager: fileManager) : nil
        do {
            _ = try await PrefixRuntimeMigration.updateIfNeeded(
                prefix: prefix,
                runtimeExecutable: finalExecutable,
                manifest: manifest,
                logger: logger,
                fileManager: fileManager
            )
            let registryResult = try await WinePrefixManager.configureSilentCrashHandling(runtimeExecutable: finalExecutable, prefix: prefix, logger: logger)
            guard registryResult.status == 0 else { throw RuntimePipelineError.processFailed("Wine crash-dialog configuration", registryResult.status) }
            try PrefixRuntimeMetadata(runtimeIdentifier: manifest.identifier, runtimeVersion: manifest.version).write(to: prefix, fileManager: fileManager)
        } catch {
            logger.write("Runtime prefix transition failed; restoring the retained snapshot", level: .error)
            if let snapshot {
                try? PrefixSnapshot.restore(snapshot: snapshot, prefix: prefix, fileManager: fileManager)
            }
            throw error
        }
        if let snapshot {
            try? PrefixSnapshot.retainOnly(snapshot, fileManager: fileManager)
        }
        // Cleanup is intentionally after migration metadata is committed and
        // never removes the prefix or any Steam content.
        _ = try? RuntimeStorage.removeObsolete11_15(runtimeRoot: PortsidePaths.runtime, keepingVersion: manifest.version, fileManager: fileManager)
        progress?(1, .steamInstalling)
        let record = InstalledRuntimeRecord(manifest: manifest, installedPath: installedRoot, executablePath: finalExecutable, graphicsBackend: FreeRuntimeCatalog.graphics, installedAt: Date(), gstreamerInstalled: GStreamerManager.isInstalled)
        let recordURL = installedRoot.appendingPathComponent("portside-runtime.json")
        try JSONEncoder.portside.encode(record).write(to: recordURL, options: .atomic)
        return RuntimeInstallResult(record: record, prefixURL: prefix)
    }
}

public struct RuntimeSynchronizationState: Sendable, Equatable {
    public let bootstrapped: Bool
    public let running: Bool
    public let applicable: Bool

    public init(bootstrapped: Bool, running: Bool, applicable: Bool = false) {
        self.bootstrapped = bootstrapped
        self.running = running
        self.applicable = applicable
    }
}

public enum RuntimeSynchronizationLog {
    public static func state(from output: String) -> RuntimeSynchronizationState {
        let lines = output.lowercased().split(whereSeparator: \.isNewline).map(String.init)
        let hasSynchronizationMarkers = lines.contains { $0.contains("msync:") || $0.contains("esync:") }
        return RuntimeSynchronizationState(
            bootstrapped: lines.contains { $0.contains("msync: bootstrapped") },
            running: lines.contains { $0.contains("msync: up and running") },
            applicable: hasSynchronizationMarkers
        )
    }
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

public enum SteamProcessStatus: String, Codable, Sendable {
    case notRunning
    case starting
    case processHandoffComplete
    case exitedUnexpectedly
    case webhelperCrashLoop
}

public enum SteamInterfaceVerification: String, Codable, Sendable {
    case notVerified = "not_verified"
    case visuallyValidated = "visually_validated"
}

public enum SteamProcessOwnership {
    public static let prefixEvidenceKey = "PORTSIDE_PREFIX_EVIDENCE"

    public static func isManaged(snapshotLine: String, prefix: URL, processName: String) -> Bool {
        let line = snapshotLine.lowercased()
        let name = processName.lowercased()
        let marker = "\(WineProcessEnvironment.ownerMarkerKey.lowercased())=\(WineProcessEnvironment.prefixMarker(for: prefix).lowercased())"
        let evidence = "\(prefixEvidenceKey.lowercased())=\(WineProcessEnvironment.prefixMarker(for: prefix).lowercased())"
        guard line.contains(name) else { return false }
        // A legacy Portside launch may predate the owner marker. The exact
        // managed steam.exe path is still safe evidence for stopping it; helper
        // processes require the marker so an unrelated helper is never adopted.
        if name == "steam.exe" && (line.contains(prefix.standardizedFileURL.path.lowercased()) || line.contains(evidence)) { return true }
        guard line.contains(marker) || line.contains(evidence) else { return false }
        if name == "steamwebhelper" { return true }
        return line.contains(prefix.standardizedFileURL.path.lowercased())
    }
}

private struct SteamProcessSnapshot {
    let processIdentifier: pid_t
    let commandLine: String
}

public struct SteamReadinessReport: Sendable, Equatable {
    public let status: SteamProcessStatus
    public let processStarted: Bool
    public let processHandoffComplete: Bool
    public let webhelperStarted: Bool
    public let webhelperExitCode: Int32?
    public let webhelperRestartCount: Int
    public let webhelperProcessCount: Int
    public let webhelperStableDuration: TimeInterval
    public let windowDetected: Bool
    public let interfaceVerification: SteamInterfaceVerification
    public let runtimeSynchronization: RuntimeSynchronizationState

    public init(
        status: SteamProcessStatus,
        processStarted: Bool = false,
        processHandoffComplete: Bool = false,
        webhelperStarted: Bool,
        webhelperExitCode: Int32? = nil,
        webhelperRestartCount: Int = 0,
        webhelperProcessCount: Int = 0,
        webhelperStableDuration: TimeInterval = 0,
        windowDetected: Bool = false,
        interfaceVerification: SteamInterfaceVerification = .notVerified,
        runtimeSynchronization: RuntimeSynchronizationState = RuntimeSynchronizationState(bootstrapped: false, running: false)
    ) {
        self.status = status
        self.processStarted = processStarted
        self.processHandoffComplete = processHandoffComplete
        self.webhelperStarted = webhelperStarted
        self.webhelperExitCode = webhelperExitCode
        self.webhelperRestartCount = webhelperRestartCount
        self.webhelperProcessCount = webhelperProcessCount
        self.webhelperStableDuration = webhelperStableDuration
        self.windowDetected = windowDetected
        self.interfaceVerification = interfaceVerification
        self.runtimeSynchronization = runtimeSynchronization
    }
}

public final class SteamReadinessMonitor: @unchecked Sendable {
    private let logger: PortsideLogger
    private let processLogURL: URL

    public init(logger: PortsideLogger = PortsideLogger(), processLogURL: URL = PortsidePaths.logs.appendingPathComponent("steam-process.log")) {
        self.logger = logger
        self.processLogURL = processLogURL
    }

    public func waitForSteam(executable: URL, prefix: URL = PortsidePaths.steamPrefix, timeout: TimeInterval = 180) async -> SteamProcessStatus {
        await waitForSteamHandoff(prefix: prefix, timeout: timeout).status
    }

    /// A permission-free handoff check. It verifies the managed process tree and
    /// activates the owning process, but it never captures windows or display pixels.
    public func waitForSteamHandoff(prefix: URL = PortsidePaths.steamPrefix, baselineWebhelperLines: Set<String> = [], timeout: TimeInterval = 180, requiredStableDuration: TimeInterval = 4) async -> SteamReadinessReport {
        let deadline = Date().addingTimeInterval(timeout)
        var steamWasRunning = false
        var helperWasRunning = false
        var helperStarted = false
        var helperRestarts = 0
        var helperStableSince: Date?
        var helperProcessCount = 0
        var lastReport = RuntimeSynchronizationState(bootstrapped: false, running: false, applicable: false)

        while Date() < deadline {
            let snapshot = await processSnapshot(prefix: prefix)
            let steam = managedProcessSnapshot(snapshot, prefix: prefix, processNames: ["steam.exe"])
            let helpers = managedProcessLines(snapshot, prefix: prefix, processName: "steamwebhelper", baseline: baselineWebhelperLines)
            let helperRunning = !helpers.isEmpty
            helperProcessCount = max(helperProcessCount, helpers.count)
            steamWasRunning = steamWasRunning || steam

            if helperRunning {
                if !helperWasRunning {
                    helperStarted = true
                    helperStableSince = Date()
                    logger.write("steamwebhelper_started")
                }
            } else if helperWasRunning {
                helperRestarts += 1
                helperStableSince = nil
                logger.write("steamwebhelper_exited", level: .warning)
            }
            helperWasRunning = helperRunning

            if steam, helperRunning {
                if let process = steamProcessSnapshot(processSnapshot: snapshot, prefix: prefix) {
                    NSRunningApplication(processIdentifier: process.processIdentifier)?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                }
                let stableDuration = stableDuration(since: helperStableSince)
                if helperStarted && stableDuration >= requiredStableDuration {
                    logger.write("steam_process_handoff_complete")
                    return SteamReadinessReport(
                        status: .processHandoffComplete,
                        processStarted: steamWasRunning,
                        processHandoffComplete: true,
                        webhelperStarted: true,
                        webhelperRestartCount: helperRestarts,
                        webhelperProcessCount: helperProcessCount,
                        webhelperStableDuration: stableDuration,
                        windowDetected: false,
                        interfaceVerification: .notVerified,
                        runtimeSynchronization: lastReport
                    )
                }
            }

            if helperRestarts >= 3 {
                logger.write("steamwebhelper_crash_loop", level: .error)
                return SteamReadinessReport(
                    status: .webhelperCrashLoop,
                    processStarted: steamWasRunning,
                    webhelperStarted: helperStarted,
                    webhelperRestartCount: helperRestarts,
                    webhelperProcessCount: helperProcessCount,
                    webhelperStableDuration: stableDuration(since: helperStableSince),
                    runtimeSynchronization: lastReport
                )
            }

            lastReport = RuntimeSynchronizationLog.state(from: (try? String(contentsOf: processLogURL, encoding: .utf8)) ?? "")
            try? await Task.sleep(for: .milliseconds(750))
        }

        logger.write("steam_handoff_timeout", level: .error)
        return SteamReadinessReport(
            status: steamWasRunning ? (helperStarted ? .exitedUnexpectedly : .starting) : .notRunning,
            processStarted: steamWasRunning,
            webhelperStarted: helperStarted,
            webhelperRestartCount: helperRestarts,
            webhelperProcessCount: helperProcessCount,
            webhelperStableDuration: stableDuration(since: helperStableSince),
            runtimeSynchronization: lastReport
        )
    }

    public func isSteamProcessRunning(prefix: URL = PortsidePaths.steamPrefix) async -> Bool {
        managedProcessSnapshot(await processSnapshot(prefix: prefix), prefix: prefix, processNames: ["steam.exe", "steamwebhelper"])
    }

    public func captureWebhelperLines() async -> Set<String> {
        Set((await processSnapshot(prefix: PortsidePaths.steamPrefix)).split(whereSeparator: \.isNewline).map(String.init).filter { $0.contains("steamwebhelper") })
    }

    public func stopSteam(runtimeExecutable: URL, prefix: URL) async {
        let wineserver = runtimeExecutable.deletingLastPathComponent().appendingPathComponent("wineserver")
        if FileManager.default.isExecutableFile(atPath: wineserver.path) {
            let killServer = Process()
            killServer.executableURL = wineserver
            killServer.arguments = ["-k"]
            killServer.environment = WineProcessEnvironment.make(runtimeExecutable: runtimeExecutable, prefix: prefix)
            killServer.standardOutput = FileHandle.nullDevice
            killServer.standardError = FileHandle.nullDevice
            try? killServer.run()
            try? await Task.sleep(for: .milliseconds(750))
            if killServer.isRunning { killServer.terminate() }
        }
        await forceTerminateManagedSteamIfNeeded(prefix: prefix)
        logger.write("Managed Steam process tree termination requested")
    }

    public func waitForSteamToStop(prefix: URL = PortsidePaths.steamPrefix, timeout: TimeInterval = 20) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !(await isSteamProcessRunning(prefix: prefix)) {
                logger.write("Steam process tree stopped")
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logger.write("Steam process tree did not stop before the timeout", level: .error)
        return false
    }

    public func requestSteamProcessActivation(prefix: URL = PortsidePaths.steamPrefix) async -> Bool {
        let snapshot = await processSnapshot(prefix: prefix)
        guard managedProcessSnapshot(snapshot, prefix: prefix, processNames: ["steam.exe", "steamwebhelper"]),
              let steamProcess = steamProcessSnapshot(processSnapshot: snapshot, prefix: prefix) else { return false }
        NSRunningApplication(processIdentifier: steamProcess.processIdentifier)?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        return true
    }

    private func processSnapshot(prefix: URL = PortsidePaths.steamPrefix) async -> String {
        let result = try? await DirectProcess.run(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,ppid=,comm=,args="],
            logger: logger,
            logOutput: false
        )
        let rawLines = result?.output.lowercased().split(whereSeparator: \.isNewline).map(String.init) ?? []
        let marker = WineProcessEnvironment.prefixMarker(for: prefix)
        var enrichedLines: [String] = []
        for line in rawLines {
            guard line.contains("steam.exe") || line.contains("steamwebhelper") else {
                enrichedLines.append(line)
                continue
            }
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let pid = fields.first.flatMap({ pid_t(String($0)) }) else {
                enrichedLines.append(line)
                continue
            }
            let files = try? await DirectProcess.run(
                executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-p", String(pid), "-Fn"],
                logger: logger,
                logOutput: false
            )
            if files?.status == 0,
               files?.output.lowercased().contains(prefix.standardizedFileURL.path.lowercased()) == true {
                enrichedLines.append("\(line) \(SteamProcessOwnership.prefixEvidenceKey.lowercased())=\(marker)")
            } else {
                enrichedLines.append(line)
            }
        }
        return enrichedLines.joined(separator: "\n")
    }

    private func managedProcessLines(_ snapshot: String, prefix: URL, processName: String, baseline _: Set<String>) -> [String] {
        return snapshot.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            SteamProcessOwnership.isManaged(snapshotLine: line, prefix: prefix, processName: processName)
        }
    }

    private func managedProcessSnapshot(_ snapshot: String, prefix: URL, processNames: [String]) -> Bool {
        let lines = snapshot.split(whereSeparator: \.isNewline).map(String.init)
        return lines.contains { line in
            processNames.contains { SteamProcessOwnership.isManaged(snapshotLine: line, prefix: prefix, processName: $0) }
        }
    }

    private func steamProcessSnapshot(processSnapshot: String, prefix: URL) -> SteamProcessSnapshot? {
        for line in processSnapshot.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 3, let processIdentifier = pid_t(fields[0]) else { continue }
            let commandLine = String(fields[1...].joined(separator: " "))
            guard !commandLine.contains("steamwebhelper"),
                  SteamProcessOwnership.isManaged(snapshotLine: String(line), prefix: prefix, processName: "steam.exe") else { continue }
            return SteamProcessSnapshot(processIdentifier: processIdentifier, commandLine: commandLine)
        }
        return nil
    }

    private func forceTerminateManagedSteamIfNeeded(prefix: URL) async {
        let snapshot = await processSnapshot(prefix: prefix)
        let pids = snapshot.split(whereSeparator: \.isNewline).compactMap { line -> pid_t? in
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let pid = fields.first.flatMap({ pid_t(String($0)) }), fields.count >= 3 else { return nil }
            guard SteamProcessOwnership.isManaged(snapshotLine: String(line), prefix: prefix, processName: "steam.exe")
                    || SteamProcessOwnership.isManaged(snapshotLine: String(line), prefix: prefix, processName: "steamwebhelper") else { return nil }
            return pid
        }
        for pid in pids {
            logger.write("Terminating managed Steam process pid=\(pid)", level: .warning)
            _ = kill(pid, SIGTERM)
        }
        try? await Task.sleep(for: .milliseconds(750))
        let remaining = await processSnapshot(prefix: prefix)
        for pid in remaining.split(whereSeparator: \.isNewline).compactMap({ line -> pid_t? in
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let pid = fields.first.flatMap({ pid_t(String($0)) }), fields.count >= 3 else { return nil }
            guard SteamProcessOwnership.isManaged(snapshotLine: String(line), prefix: prefix, processName: "steam.exe")
                    || SteamProcessOwnership.isManaged(snapshotLine: String(line), prefix: prefix, processName: "steamwebhelper") else { return nil }
            return pid
        }) {
            logger.write("Force terminating managed Steam process pid=\(pid)", level: .error)
            _ = kill(pid, SIGKILL)
        }
    }

    private func stableDuration(since date: Date?) -> TimeInterval {
        guard let date else { return 0 }
        return max(0, Date().timeIntervalSince(date))
    }
}
