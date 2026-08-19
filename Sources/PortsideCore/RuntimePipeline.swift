import Foundation
import AppKit
import CryptoKit

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
        let backup = parent.appendingPathComponent(".backup-(UUID().uuidString)", isDirectory: true)
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
    public static func run(specification: ProcessLaunchSpec, logger: PortsideLogger = PortsideLogger()) async throws -> ProcessResult {
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
            logger.write("\(specification.executable.lastPathComponent) timed out, output=\(String(data: data, encoding: .utf8) ?? "")", level: .error)
            throw RuntimePipelineError.processTimedOut(specification.executable.lastPathComponent)
        }
        try? outputHandle.close()
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        try? FileManager.default.removeItem(at: outputURL)
        let output = String(data: data, encoding: .utf8) ?? ""
        let duration = Date().timeIntervalSince(started)
        logger.write("\(specification.executable.lastPathComponent) exited with \(task.terminationStatus), duration \(String(format: "%.2f", duration))s, output=\(output)")
        return ProcessResult(status: task.terminationStatus, output: output, duration: duration)
    }

    public static func run(executable: URL, arguments: [String], environment: [String: String] = [:], logger: PortsideLogger = PortsideLogger()) async throws -> ProcessResult {
        try await run(specification: ProcessLaunchSpec(executable: executable, arguments: arguments, environment: environment), logger: logger)
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
        let list = try await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tf", archive.path], logger: logger)
        guard list.status == 0 else { throw RuntimePipelineError.archiveExtractionFailed(list.output) }
        for entry in list.output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            guard isSafeRelativePath(entry) else { throw RuntimePipelineError.unexpectedArchiveEntry(entry) }
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
        try await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/sbin/softwareupdate"), arguments: ["--install-rosetta", "--agree-to-license"])
    }
}

public enum GStreamerManager {
    public static var frameworkURL: URL {
        let privateURL = PortsidePaths.runtime.appendingPathComponent("Dependencies/GStreamer.framework")
        return FileManager.default.fileExists(atPath: privateURL.path) ? privateURL : URL(fileURLWithPath: "/Library/Frameworks/GStreamer.framework")
    }
    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: frameworkURL.appendingPathComponent("Versions/1.0/lib/libgstreamer-1.0.0.dylib").path) }

    public static func install(using downloader: SecureDownloader = SecureDownloader(), logger: PortsideLogger = PortsideLogger()) async throws {
        let pkgURL = PortsidePaths.downloads.appendingPathComponent("gstreamer-\(FreeRuntimeCatalog.gstreamer.version).pkg")
        if !FileManager.default.fileExists(atPath: pkgURL.path) {
            _ = try await downloader.download(from: FreeRuntimeCatalog.gstreamer.upstreamURL, to: pkgURL)
        }
        do {
            try IntegrityVerifier.verify(url: pkgURL, expectedSHA256: FreeRuntimeCatalog.gstreamer.sha256)
        } catch {
            try? FileManager.default.removeItem(at: pkgURL)
            throw error
        }
        let temporary = PortsidePaths.runtime.appendingPathComponent(".gstreamer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result = try await DirectProcess.run(executable: URL(fileURLWithPath: "/usr/sbin/pkgutil"), arguments: ["--expand-full", pkgURL.path, temporary.path], logger: logger)
        guard result.status == 0 else { throw RuntimePipelineError.gstreamerInstallFailed(result.status, result.output) }
        let destination = PortsidePaths.runtime.appendingPathComponent("Dependencies/GStreamer.framework", isDirectory: true)
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
        let gstreamerRoot = GStreamerManager.frameworkURL.deletingLastPathComponent()
        let environment = ["WINEPREFIX": prefix.path, "WINEARCH": "win64", "WINEDLLOVERRIDES": "mscoree,mshtml=", "WINEDEBUG": "-all", "PATH": finalExecutable.deletingLastPathComponent().path, "DYLD_FRAMEWORK_PATH": gstreamerRoot.path, "GST_PLUGIN_PATH": GStreamerManager.frameworkURL.appendingPathComponent("Versions/1.0/lib/gstreamer-1.0").path]
        let wineboot = installedRoot.appendingPathComponent("Contents/Resources/wine/bin/wineboot")
        if !fileManager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) {
            let result = try await DirectProcess.run(executable: wineboot, arguments: ["-u"], environment: environment, logger: logger)
            guard result.status == 0 else { throw RuntimePipelineError.processFailed("prefix initialization", result.status) }
        }
        progress?(1, .steamInstalling)
        let record = InstalledRuntimeRecord(manifest: manifest, installedPath: installedRoot, executablePath: finalExecutable, graphicsBackend: FreeRuntimeCatalog.graphics, installedAt: Date(), gstreamerInstalled: GStreamerManager.isInstalled)
        let recordURL = installedRoot.appendingPathComponent("portside-runtime.json")
        try JSONEncoder.portside.encode(record).write(to: recordURL, options: .atomic)
        return RuntimeInstallResult(record: record, prefixURL: prefix)
    }
}

public enum SteamProcessStatus: String, Codable, Sendable { case notRunning, wineProcessRunning, steamProcessRunning, windowVisible, ready, exitedUnexpectedly }

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
            let markerExists = FileManager.default.fileExists(atPath: marker.path) || FileManager.default.fileExists(atPath: alternateMarker.path)
            if markerExists && (snapshot.contains("steam.exe") || snapshot.contains("steamwebhelper")) {
                logger.write("Steam bootstrap marker detected")
                return true
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    public func waitForSteam(executable: URL, timeout: TimeInterval = 180) async -> SteamProcessStatus {
        let deadline = Date().addingTimeInterval(timeout)
        var sawSteam = false
        while Date() < deadline {
            let snapshot = await processSnapshot()
            if snapshot.contains("steam.exe") || snapshot.contains("steamwebhelper") { sawSteam = true }
            if sawSteam, let processIdentifier = visibleSteamWindowProcessIdentifier() {
                NSRunningApplication(processIdentifier: processIdentifier)?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                logger.write("Steam window detected and activated")
                return .windowVisible
            }
            if sawSteam { try? await Task.sleep(for: .milliseconds(750)); continue }
            if snapshot.contains(executable.lastPathComponent) { try? await Task.sleep(for: .milliseconds(750)); continue }
            try? await Task.sleep(for: .seconds(1))
        }
        return sawSteam ? .steamProcessRunning : .exitedUnexpectedly
    }

    private func processSnapshot() async -> String {
        let result = try? await DirectProcess.run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-axo", "comm=,args="] , logger: logger)
        return result?.output.lowercased() ?? ""
    }

    private func visibleSteamWindowProcessIdentifier() -> pid_t? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.compactMap { window -> pid_t? in
            let owner = (window[kCGWindowOwnerName as String] as? String)?.lowercased() ?? ""
            let name = (window[kCGWindowName as String] as? String)?.lowercased() ?? ""
            let steamTitle = ["steam", "login", "sign in", "update", "store", "library"].contains { name.contains($0) }
            guard owner.contains("steam") || steamTitle || (owner.contains("wine") && steamTitle) else { return nil }
            return (window[kCGWindowOwnerPID as String] as? NSNumber).map { pid_t($0.intValue) }
        }.first
    }
}
