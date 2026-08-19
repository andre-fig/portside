import Foundation
import AppKit
import CoreGraphics
import CryptoKit

public enum EnvironmentPhase: String, Codable, CaseIterable, Sendable {
    case requirementsChecking, rosettaRequired, runtimeDownloading, runtimeVerifying, runtimeInstalling
    case prefixCreating, steamInstalling, steamUpdating, steamLaunching, windowWaiting, steamReady
    case failedRecoverable, failedFatal
}

public enum GraphicsBackend: String, Codable, CaseIterable, Sendable {
    case wineD3D, d3dMetal, dxmt, dxvk, vkd3d

    public var displayName: String {
        switch self {
        case .wineD3D: return "WineD3D"
        case .d3dMetal: return "D3DMetal"
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .vkd3d: return "VKD3D"
        }
    }
}

public struct SikarugirBaselineConfiguration: Codable, Equatable, Sendable {
    public static let wrapperName = "PortsideBaseline.app"
    public static let creatorVersion = "1.0.1"
    public static let templateVersion = "1.0.11"
    public static let engineName = "WS12WineSikarugir10.0_6"
    public static let engineVersion = "wine sikarugir 10.0 (revision 6)"
    public static let engineArchiveSHA256 = "9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2"
    public static let engineVersionSHA256 = "9af9c71ffe2ca443c35a34b7f45fa1977f864eac984c0257ba7fd0341d084586"
    public static let templateArchiveSHA256 = "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a"
    public static let winetricksSHA256 = "f35c29737ca08a583569e6a3752d52fbe23333c5acfad5f16c4177d25eaf3f4b"
    public static let windowsSteamExecutable = "/Program Files (x86)/Steam/steam.exe"

    public let renderer: GraphicsBackend
    public let d3dMetal: Bool
    public let dxmt: Bool
    public let dxvk: Bool
    public let msync: Bool
    public let esync: Bool
    public let wineDebug: String
    public let programFlags: String

    public init(renderer: GraphicsBackend = .wineD3D, d3dMetal: Bool = false, dxmt: Bool = false, dxvk: Bool = false, msync: Bool = true, esync: Bool = true, wineDebug: String = "-plugplay,+loaddll", programFlags: String = "") throws {
        guard renderer == .wineD3D, !d3dMetal, !dxmt, !dxvk else {
            throw PortsideError.invalidArtifact("the golden Steam baseline only permits WineD3D")
        }
        self.renderer = renderer
        self.d3dMetal = d3dMetal
        self.dxmt = dxmt
        self.dxvk = dxvk
        self.msync = msync
        self.esync = esync
        self.wineDebug = wineDebug
        self.programFlags = programFlags
    }

    public static let golden: SikarugirBaselineConfiguration = try! SikarugirBaselineConfiguration()

    public var environment: [String: String] {
        [
            "WINEDEBUG": wineDebug,
            "WINEMSYNC": msync ? "1" : "0",
            "WINEESYNC": esync ? "1" : "0",
            "D3DMETAL": "0",
            "DXMT": "0",
            "DXVK": "0"
        ]
    }
}

public struct SikarugirArtifact: Codable, Equatable, Hashable, Sendable {
    public let identifier: String
    public let version: String
    public let url: URL
    public let sha256: String
    public let expectedSize: Int64?
    public let sourceRepository: URL
    public let sourceCommit: String?
    public let license: String

    public init(identifier: String, version: String, url: URL, sha256: String, expectedSize: Int64? = nil, sourceRepository: URL, sourceCommit: String? = nil, license: String) {
        self.identifier = identifier
        self.version = version
        self.url = url
        self.sha256 = sha256
        self.expectedSize = expectedSize
        self.sourceRepository = sourceRepository
        self.sourceCommit = sourceCommit
        self.license = license
    }
}

public enum SikarugirOfficialCatalog {
    public static let creator = SikarugirArtifact(
        identifier: "Creator",
        version: SikarugirBaselineConfiguration.creatorVersion,
        url: URL(string: "https://github.com/Sikarugir-App/Creator/releases/download/v1.0.1/Creator-v1.0.1.tar.xz")!,
        sha256: "187825e4e6bf96f294cf9ccb65e53049432b3ee2925480e8ad1cbca12a96e819",
        expectedSize: 793_320,
        sourceRepository: URL(string: "https://github.com/Sikarugir-App/Creator")!,
        sourceCommit: "6086e3d",
        license: "See the official Creator distribution and notices."
    )
    public static let template = SikarugirArtifact(
        identifier: "Wrapper Template",
        version: SikarugirBaselineConfiguration.templateVersion,
        url: URL(string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz")!,
        sha256: SikarugirBaselineConfiguration.templateArchiveSHA256,
        expectedSize: 84_533_420,
        sourceRepository: URL(string: "https://github.com/Sikarugir-App/Wrapper")!,
        license: "See the official Wrapper distribution and notices."
    )
    public static let engine = SikarugirArtifact(
        identifier: SikarugirBaselineConfiguration.engineName,
        version: "10.0 revision 6",
        url: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz")!,
        sha256: SikarugirBaselineConfiguration.engineArchiveSHA256,
        expectedSize: 166_304_096,
        sourceRepository: URL(string: "https://github.com/Sikarugir-App/Engines")!,
        sourceCommit: "9581b3a7d1e473b832c0dda2ecdf6eac1791c0dc",
        license: "Wine and included component licenses; see RUNTIME_LICENSES.md."
    )
    public static let winetricks = SikarugirArtifact(
        identifier: "Sikarugir winetricks",
        version: "2026-08-07",
        url: URL(string: "https://raw.githubusercontent.com/Sikarugir-App/winetricks/5a59ea07513b24093bd90fad943ecf9543cf05bc/src/winetricks")!,
        sha256: SikarugirBaselineConfiguration.winetricksSHA256,
        sourceRepository: URL(string: "https://github.com/Sikarugir-App/winetricks")!,
        sourceCommit: "5a59ea07513b24093bd90fad943ecf9543cf05bc",
        license: "LGPL-2.1-or-later"
    )
    public static let engineListURL = URL(string: "https://raw.githubusercontent.com/Sikarugir-App/Engines/main/EngineList.txt")!
    public static let all: [SikarugirArtifact] = [creator, template, engine, winetricks]
}

public struct InstalledRuntimeRecord: Codable, Equatable, Sendable {
    public let manifest: SikarugirArtifact
    public let installedPath: URL
    public let executablePath: URL
    public let graphicsBackend: GraphicsBackend
    public let installedAt: Date
    public let gstreamerInstalled: Bool

    public init(manifest: SikarugirArtifact, installedPath: URL, executablePath: URL, graphicsBackend: GraphicsBackend, installedAt: Date = Date(), gstreamerInstalled: Bool = false) {
        self.manifest = manifest
        self.installedPath = installedPath
        self.executablePath = executablePath
        self.graphicsBackend = graphicsBackend
        self.installedAt = installedAt
        self.gstreamerInstalled = gstreamerInstalled
    }
}

public enum SikarugirArtifactValidator {
    public static func validate(_ artifact: SikarugirArtifact) throws {
        guard artifact.url.scheme == "https",
              artifact.url.host == "github.com" || artifact.url.host == "raw.githubusercontent.com" else {
            throw PortsideError.invalidArtifact("artifact URL is not an official HTTPS source")
        }
        guard artifact.sha256.count == 64, artifact.sha256.allSatisfy(\.isHexDigit) else {
            throw PortsideError.invalidArtifact("missing checksum")
        }
        if let size = artifact.expectedSize, size <= 0 { throw PortsideError.invalidArtifact("invalid expected size") }
    }
}

public enum SafeArchiveExtractor {
    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/").contains("..")
    }

    public static func validateListing(_ listing: String) throws {
        for line in listing.split(whereSeparator: \.isNewline) where !line.isEmpty {
            guard isSafeRelativePath(String(line)) else { throw PortsideError.invalidArtifact("archive path traversal") }
        }
    }
}

public struct SikarugirWrapperConfiguration: Sendable, Equatable {
    public let baseline: SikarugirBaselineConfiguration
    public init(baseline: SikarugirBaselineConfiguration = .golden) { self.baseline = baseline }

    public func plistValues() -> [String: Any] {
        [
            "CFBundleName": "PortsideBaseline",
            "CFBundleDisplayName": "Portside",
            "Program Name and Path": SikarugirBaselineConfiguration.windowsSteamExecutable,
            "Program Flags": baseline.programFlags,
            "D3DMETAL": 0,
            "DXMT": 0,
            "DXVK": 0,
            "MOLTENVKCX": 1,
            "WINEMSYNC": baseline.msync ? 1 : 0,
            "WINEESYNC": baseline.esync ? 1 : 0,
            "WINEDEBUG": baseline.wineDebug,
            "NSBGOnly": "1",
            "Winetricks silent": 1,
            "Winetricks disable logging": 1
        ]
    }

    public func apply(to wrapper: URL, fileManager: FileManager = .default) throws {
        let info = wrapper.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              var plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw PortsideError.invalidArtifact("wrapper Info.plist is missing")
        }
        // Portside does not implement voice chat or any other microphone
        // capture path. The upstream template contains a generic declaration;
        // remove it so macOS does not request an unnecessary permission.
        plist.removeValue(forKey: "NSMicrophoneUsageDescription")
        for (key, value) in plistValues() { plist[key] = value }
        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try output.write(to: info, options: .atomic)
        let launcher = wrapper.appendingPathComponent("Contents/MacOS/Sikarugir")
        guard fileManager.isExecutableFile(atPath: launcher.path) else {
            throw PortsideError.invalidArtifact("official wrapper launcher is missing")
        }
    }
}

public struct WrapperValidation: Equatable, Sendable {
    public let wrapper: URL
    public let prefix: URL
    public let launcher: URL
    public let engineVersion: String
    public let configuration: SikarugirBaselineConfiguration
}

public enum SikarugirWrapperValidator {
    public static func validate(wrapper: URL, configuration: SikarugirBaselineConfiguration = .golden, fileManager: FileManager = .default) throws -> WrapperValidation {
        let launcher = wrapper.appendingPathComponent("Contents/MacOS/Sikarugir")
        let prefix = wrapper.appendingPathComponent("Contents/SharedSupport/prefix", isDirectory: true)
        let versionURL = wrapper.appendingPathComponent("Contents/SharedSupport/wine/version")
        guard fileManager.isExecutableFile(atPath: launcher.path),
              fileManager.fileExists(atPath: prefix.path),
              let version = try? String(contentsOf: versionURL).trimmingCharacters(in: .whitespacesAndNewlines),
              version.lowercased().contains("sikarugir 10.0") else {
            throw PortsideError.invalidArtifact("wrapper does not contain the requested official engine")
        }
        guard let info = NSDictionary(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              (info["Program Name and Path"] as? String) == SikarugirBaselineConfiguration.windowsSteamExecutable else {
            throw PortsideError.invalidArtifact("Steam executable is not configured in the wrapper")
        }
        guard (info["D3DMETAL"] as? NSNumber)?.intValue == 0,
              (info["DXMT"] as? NSNumber)?.intValue == 0,
              (info["DXVK"] as? NSNumber)?.intValue == 0 else {
            throw PortsideError.invalidArtifact("non-baseline renderer enabled")
        }
        guard info["NSMicrophoneUsageDescription"] == nil else {
            throw PortsideError.invalidArtifact("microphone permission is not allowed for Portside")
        }
        return WrapperValidation(wrapper: wrapper, prefix: prefix, launcher: launcher, engineVersion: version, configuration: configuration)
    }
}

public struct SikarugirWrapperInstallResult: Sendable {
    public let validation: WrapperValidation
    public let runtimeRecord: InstalledRuntimeRecord
    public init(validation: WrapperValidation, runtimeRecord: InstalledRuntimeRecord) {
        self.validation = validation
        self.runtimeRecord = runtimeRecord
    }
}

/// Installs only the official template, engine and winetricks assets. Creator is
/// recorded in the manifest for provenance but is never copied into Portside or
/// shown to the end user.
public final class SikarugirWrapperInstaller: @unchecked Sendable {
    private let runner: ProcessRunning
    private let logger: PortsideLogger
    private let fileManager: FileManager

    public init(runner: ProcessRunning = SystemProcessRunner(), logger: PortsideLogger = PortsideLogger(), fileManager: FileManager = .default) {
        self.runner = runner
        self.logger = logger
        self.fileManager = fileManager
    }

    public func install(artifacts: [SikarugirArtifact: URL], configuration: SikarugirBaselineConfiguration = .golden) async throws -> SikarugirWrapperInstallResult {
        guard let templateURL = artifacts[SikarugirOfficialCatalog.template],
              let engineURL = artifacts[SikarugirOfficialCatalog.engine],
              let winetricksURL = artifacts[SikarugirOfficialCatalog.winetricks] else {
            throw PortsideError.invalidArtifact("baseline artifact set is incomplete")
        }
        let staging = PortsidePaths.cache.appendingPathComponent("wrapper-staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let templateExtract = staging.appendingPathComponent("template", isDirectory: true)
        let engineExtract = staging.appendingPathComponent("engine", isDirectory: true)
        try await extract(archive: templateURL, to: templateExtract)
        try await extract(archive: engineURL, to: engineExtract)

        guard let templateBundle = findBundle(in: templateExtract) else { throw PortsideError.invalidArtifact("Template.app not found in official archive") }
        let wrapperStage = staging.appendingPathComponent(SikarugirBaselineConfiguration.wrapperName, isDirectory: true)
        try fileManager.copyItem(at: templateBundle, to: wrapperStage)
        guard let wine = findEngineBundle(in: engineExtract) else { throw PortsideError.invalidArtifact("engine bundle not found") }
        let wineDestination = wrapperStage.appendingPathComponent("Contents/SharedSupport/wine", isDirectory: true)
        if fileManager.fileExists(atPath: wineDestination.path) { try fileManager.removeItem(at: wineDestination) }
        try fileManager.copyItem(at: wine, to: wineDestination)
        let winetricksDestination = wrapperStage.appendingPathComponent("Contents/SharedSupport/winetricks")
        if fileManager.fileExists(atPath: winetricksDestination.path) { try fileManager.removeItem(at: winetricksDestination) }
        try fileManager.copyItem(at: winetricksURL, to: winetricksDestination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: winetricksDestination.path)
        try SikarugirWrapperConfiguration(baseline: configuration).apply(to: wrapperStage, fileManager: fileManager)

        let destination = PortsidePaths.baselineWrapper
        if fileManager.fileExists(atPath: destination.path) {
            let previous = PortsidePaths.runtime.appendingPathComponent("rollback-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            try fileManager.createDirectory(at: previous.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: destination, to: previous)
        }
        try AtomicInstaller.installDirectory(from: wrapperStage, to: destination, fileManager: fileManager)
        let wrapperPrefix = destination.appendingPathComponent("Contents/SharedSupport/prefix", isDirectory: true)
        let managedPrefix = PortsidePaths.prefixes.appendingPathComponent("PortsideBaseline", isDirectory: true)
        try fileManager.createDirectory(at: PortsidePaths.prefixes, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: managedPrefix.path) {
            if fileManager.fileExists(atPath: wrapperPrefix.path) { try fileManager.removeItem(at: wrapperPrefix) }
            try fileManager.createSymbolicLink(at: wrapperPrefix, withDestinationURL: managedPrefix)
        } else {
            if !fileManager.fileExists(atPath: wrapperPrefix.appendingPathComponent("system.reg").path) {
                let prefixResult = try await runner.run(
                    ProcessLaunchSpec(
                        executable: destination.appendingPathComponent("Contents/MacOS/Sikarugir"),
                        arguments: ["WSS-wineprefixcreate"],
                        currentDirectory: destination,
                        timeout: 1_800
                    ),
                    logger: logger
                )
                guard prefixResult.status == 0 else {
                    throw PortsideError.processFailed("official Sikarugir prefix creation", prefixResult.status)
                }
            }
            do {
                try fileManager.moveItem(at: wrapperPrefix, to: managedPrefix)
            } catch {
                // Some APFS layouts reject moving a newly-created Wine prefix
                // containing device symlinks. The prefix is still new and
                // contains no Steam data, so copy it atomically then remove
                // only that staging prefix.
                try fileManager.copyItem(at: wrapperPrefix, to: managedPrefix)
                try fileManager.removeItem(at: wrapperPrefix)
            }
            try fileManager.createSymbolicLink(at: wrapperPrefix, withDestinationURL: managedPrefix)
        }
        let validation = try SikarugirWrapperValidator.validate(wrapper: destination, configuration: configuration, fileManager: fileManager)
        let canonicalValidation = WrapperValidation(wrapper: validation.wrapper, prefix: managedPrefix, launcher: validation.launcher, engineVersion: validation.engineVersion, configuration: validation.configuration)
        let metadata: [String: String] = ["wrapper": destination.path, "prefix": managedPrefix.path, "engine": SikarugirBaselineConfiguration.engineName]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: PortsidePaths.prefixes.appendingPathComponent("PortsideBaseline.json"), options: .atomic)
        let record = InstalledRuntimeRecord(manifest: SikarugirOfficialCatalog.engine, installedPath: destination, executablePath: validation.launcher, graphicsBackend: configuration.renderer)
        logger.write("Installed official Sikarugir wrapper \(SikarugirBaselineConfiguration.templateVersion) with \(SikarugirBaselineConfiguration.engineName)")
        return SikarugirWrapperInstallResult(validation: canonicalValidation, runtimeRecord: record)
    }

    private func extract(archive: URL, to destination: URL) async throws {
        let listing = try await runner.run(ProcessLaunchSpec(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tf", archive.path], timeout: 120), logger: logger)
        guard listing.status == 0 else { throw PortsideError.processFailed("archive listing", listing.status) }
        try SafeArchiveExtractor.validateListing(listing.output)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let result = try await runner.run(ProcessLaunchSpec(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xJf", archive.path, "-C", destination.path], timeout: 900), logger: logger)
        guard result.status == 0 else { throw PortsideError.processFailed("archive extraction", result.status) }
    }

    private func findBundle(in root: URL) -> URL? {
        let urls = (fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])?.compactMap { $0 as? URL } ?? [])
        return urls.first { $0.pathExtension == "app" }
    }

    private func findDirectory(named name: String, in root: URL) -> URL? {
        let urls = (fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])?.compactMap { $0 as? URL } ?? [])
        return urls.first { $0.lastPathComponent == name && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private func findEngineBundle(in root: URL) -> URL? {
        if let bundle = findDirectory(named: "wswine.bundle", in: root) { return bundle }
        let urls = (fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])?.compactMap { $0 as? URL } ?? [])
        return urls.first {
            fileManager.fileExists(atPath: $0.appendingPathComponent("bin/wine").path)
                && fileManager.fileExists(atPath: $0.appendingPathComponent("share/wine").path)
        }
    }
}

public final class SikarugirUpdateService: @unchecked Sendable {
    private let downloader: SecureDownloader
    private let logger: PortsideLogger
    private let fileManager: FileManager

    public init(downloader: SecureDownloader = SecureDownloader(), logger: PortsideLogger = PortsideLogger(), fileManager: FileManager = .default) {
        self.downloader = downloader
        self.logger = logger
        self.fileManager = fileManager
    }

    public static func latestStableEngine(in engineList: String) -> String? {
        let names = engineList.split(whereSeparator: \.isNewline).map(String.init)
            .filter { $0.hasPrefix("WS12WineSikarugir") && !$0.contains("battle.net") }
        return names.sorted(by: NaturalVersion.compare).last
    }

    public static func shouldCheck(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= 86_400
    }

    public func fetchOfficialEngineList() async throws -> String {
        let destination = PortsidePaths.manifests.appendingPathComponent("EngineList.txt")
        let result = try await downloader.download(from: SikarugirOfficialCatalog.engineListURL, to: destination)
        logger.write("Fetched official EngineList.txt (\(result.bytes) bytes)")
        return try String(contentsOf: destination)
    }

    public func validatePinnedCatalog() throws {
        for artifact in SikarugirOfficialCatalog.all { try SikarugirArtifactValidator.validate(artifact) }
    }

    public func downloadBaselineArtifacts(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [SikarugirArtifact: URL] {
        try validatePinnedCatalog()
        try fileManager.createDirectory(at: PortsidePaths.downloads, withIntermediateDirectories: true)
        var result: [SikarugirArtifact: URL] = [:]
        let baselineArtifacts = [SikarugirOfficialCatalog.template, SikarugirOfficialCatalog.engine, SikarugirOfficialCatalog.winetricks]
        for (index, artifact) in baselineArtifacts.enumerated() {
            let file = PortsidePaths.downloads.appendingPathComponent(artifact.url.lastPathComponent)
            if fileManager.fileExists(atPath: file.path) {
                try IntegrityVerifier.verify(url: file, expectedSHA256: artifact.sha256, expectedSize: artifact.expectedSize)
            } else {
                _ = try await downloader.download(from: artifact.url, to: file, expectedSHA256: artifact.sha256, expectedSize: artifact.expectedSize)
            }
            result[artifact] = file
            progress(Double(index + 1) / Double(baselineArtifacts.count))
        }
        return result
    }
}

private enum NaturalVersion {
    static func compare(_ lhs: String, _ rhs: String) -> Bool {
        func parts(_ value: String) -> [Int] {
            value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let left = parts(lhs)
        let right = parts(rhs)
        return (left + [0, 0, 0]).lexicographicallyPrecedes(right + [0, 0, 0])
    }
}

public enum SikarugirSteamFlow {
    private static var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        environment["XDG_CACHE_HOME"] = PortsidePaths.cache.appendingPathComponent("XDG", isDirectory: true).path
        return environment
    }

    public static func installationSpec(wrapper: URL) throws -> ProcessLaunchSpec {
        let launcher = wrapper.appendingPathComponent("Contents/MacOS/Sikarugir")
        guard FileManager.default.isExecutableFile(atPath: launcher.path) else { throw PortsideError.runtimeUnavailable }
        return ProcessLaunchSpec(executable: launcher, arguments: ["WSS-winetricks", "steam"], environment: processEnvironment, currentDirectory: wrapper, timeout: 3_600)
    }

    public static func cleanLaunchSpec(wrapper: URL) throws -> ProcessLaunchSpec {
        let launcher = wrapper.appendingPathComponent("Contents/MacOS/Sikarugir")
        guard FileManager.default.isExecutableFile(atPath: launcher.path) else { throw PortsideError.runtimeUnavailable }
        return ProcessLaunchSpec(executable: launcher, environment: processEnvironment, currentDirectory: wrapper, timeout: 60)
    }

    public static func steamExecutable(prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    }
}

public enum SteamReadinessState: String, Codable, Sendable {
    case processStarted, webHelperStarted, windowDetected, visibleButUnverified, uiReady, processRunningWithoutWindow, failed
}

public enum SteamInterfaceVerification: String, Codable, Sendable {
    case notVerified, manualConfirmed
}

public struct SteamReadinessReport: Codable, Equatable, Sendable {
    public let state: SteamReadinessState
    public let processStarted: Bool
    public let webHelperStarted: Bool
    public let windowDetected: Bool
    public let visibleButUnverified: Bool
    public let uiReady: Bool
    public let processRunningWithoutWindow: Bool
    public let interfaceVerification: SteamInterfaceVerification
    public let webHelperProcessCount: Int
    public let duration: TimeInterval

    public init(state: SteamReadinessState, processStarted: Bool, webHelperStarted: Bool, windowDetected: Bool, visibleButUnverified: Bool = false, uiReady: Bool = false, processRunningWithoutWindow: Bool = false, interfaceVerification: SteamInterfaceVerification = .notVerified, webHelperProcessCount: Int = 0, duration: TimeInterval = 0) {
        self.state = state
        self.processStarted = processStarted
        self.webHelperStarted = webHelperStarted
        self.windowDetected = windowDetected
        self.visibleButUnverified = visibleButUnverified
        self.uiReady = uiReady
        self.processRunningWithoutWindow = processRunningWithoutWindow
        self.interfaceVerification = interfaceVerification
        self.webHelperProcessCount = webHelperProcessCount
        self.duration = duration
    }
}

public struct ManagedProcessSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let command: String
    public init(pid: Int32, parentPID: Int32, command: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
    }
}

public enum SteamProcessOwnership {
    public static func isManaged(snapshotLine: String, wrapper: URL) -> Bool { snapshotLine.contains(wrapper.path) }
    public static func isManaged(snapshotLine: String, prefix: URL) -> Bool { snapshotLine.contains(prefix.path) }

    public static func isLikelySteamRuntime(_ command: String) -> Bool {
        command.localizedCaseInsensitiveContains("steam.exe")
            || command.localizedCaseInsensitiveContains("steamwebhelper")
            || command.localizedCaseInsensitiveContains("wineserver")
            || command.localizedCaseInsensitiveContains("/wine")
    }

    public static func managedPIDs(in snapshots: [ManagedProcessSnapshot], wrapper: URL, prefix: URL) -> Set<Int32> {
        var managed = Set(snapshots.filter {
            isManaged(snapshotLine: $0.command, wrapper: wrapper)
                || isManaged(snapshotLine: $0.command, prefix: prefix)
        }.map(\.pid))
        var changed = true
        while changed {
            changed = false
            for snapshot in snapshots where managed.contains(snapshot.parentPID) && managed.insert(snapshot.pid).inserted {
                changed = true
            }
        }
        return managed
    }

    /// Some Wine processes are reparented to launchd and expose only a Windows
    /// command line. Their open files still identify the wrapper and prefix.
    /// Inspect only Steam/Wine candidates so native macOS Steam is never
    /// selected by a broad process-name match.
    public static func fileBackedManagedPIDs(in snapshots: [ManagedProcessSnapshot], wrapper: URL, prefix: URL) -> Set<Int32> {
        let candidates = snapshots.filter { isLikelySteamRuntime($0.command) }
        guard !candidates.isEmpty else { return [] }
        return Set(candidates.compactMap { snapshot in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-a", "-p", String(snapshot.pid), "-Fn"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8),
                  output.contains(wrapper.path) || output.contains(prefix.path) else { return nil }
            return snapshot.pid
        })
    }
}

public final class SteamReadinessMonitor: @unchecked Sendable {
    private let logger: PortsideLogger
    public init(logger: PortsideLogger = PortsideLogger(logFileName: "steam-readiness.log")) { self.logger = logger }

    public func captureProcessSnapshot() -> [ManagedProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return []
        }
        // Read while ps is alive so long Steam command lines cannot fill the
        // pipe and deadlock the launch coordinator.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let pieces = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard pieces.count >= 3, let pid = Int32(pieces[0]), let ppid = Int32(pieces[1]) else { return nil }
            return ManagedProcessSnapshot(pid: pid, parentPID: ppid, command: String(pieces[2]))
        }
    }

    public func waitForSteamWindow(wrapper: URL, baselinePIDs: Set<Int32> = [], timeout: TimeInterval = 90, poll: TimeInterval = 0.5) async -> SteamReadinessReport {
        let started = Date()
        var processStarted = false
        var helperStarted = false
        var count = 0
        var windowDetected = false
        while Date().timeIntervalSince(started) < timeout {
            let allSnapshots = captureProcessSnapshot()
            var managedPIDs = SteamProcessOwnership.managedPIDs(in: allSnapshots, wrapper: wrapper, prefix: wrapper.appendingPathComponent("Contents/SharedSupport/prefix"))
            // Sikarugir may reparent Wine children to launchd/PID 1 and Wine
            // command lines may expose only the Windows path. A clean launch
            // snapshot is the safe fallback association for newly-created
            // Steam/Wine descendants; existing native Steam is already in the
            // baseline set.
            let newRuntimePIDs = allSnapshots.filter { !baselinePIDs.contains($0.pid) && SteamProcessOwnership.isLikelySteamRuntime($0.command) }.map(\.pid)
            managedPIDs.formUnion(newRuntimePIDs)
            let snapshot = allSnapshots.filter { managedPIDs.contains($0.pid) }
            processStarted = snapshot.contains { $0.command.localizedCaseInsensitiveContains("steam.exe") }
            count = snapshot.filter { $0.command.localizedCaseInsensitiveContains("steamwebhelper") }.count
            helperStarted = count > 0
            windowDetected = windowDetected || Self.detectManagedWindow(managedPIDs: managedPIDs)
            if windowDetected && helperStarted {
                let report = SteamReadinessReport(state: .visibleButUnverified, processStarted: processStarted, webHelperStarted: helperStarted, windowDetected: true, visibleButUnverified: true, webHelperProcessCount: count, duration: Date().timeIntervalSince(started))
                logger.write("Steam window detected; visual interaction remains a manual acceptance check")
                return report
            }
            try? await Task.sleep(for: .milliseconds(Int(poll * 1_000)))
        }
        let state: SteamReadinessState = windowDetected ? .visibleButUnverified : processStarted ? .processRunningWithoutWindow : .failed
        return SteamReadinessReport(state: state, processStarted: processStarted, webHelperStarted: helperStarted, windowDetected: windowDetected, visibleButUnverified: windowDetected, processRunningWithoutWindow: processStarted && !windowDetected, webHelperProcessCount: count, duration: Date().timeIntervalSince(started))
    }

    public static func detectManagedWindow(managedPIDs: Set<Int32>) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        for item in list {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? NSNumber, managedPIDs.contains(ownerPID.int32Value) else { continue }
            guard let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber,
                  width.doubleValue > 120, height.doubleValue > 80 else { continue }
            return true
        }
        return false
    }
}

public struct GameCompatibilityEntry: Codable, Equatable, Sendable {
    public let appID: String
    public let executable: String
    public let architecture: String
    public let graphicsAPI: String
    public let preferredRenderer: GraphicsBackend
    public let engine: String
    public let environment: [String: String]
    public let dllOverrides: [String: String]
    public let arguments: [String]
    public let result: String?

    public init(appID: String, executable: String, architecture: String, graphicsAPI: String, preferredRenderer: GraphicsBackend, engine: String = SikarugirBaselineConfiguration.engineName, environment: [String: String] = [:], dllOverrides: [String: String] = [:], arguments: [String] = [], result: String? = nil) {
        self.appID = appID
        self.executable = executable
        self.architecture = architecture
        self.graphicsAPI = graphicsAPI
        self.preferredRenderer = preferredRenderer
        self.engine = engine
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.arguments = arguments
        self.result = result
    }
}

public struct GameCompatibilityManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var entries: [GameCompatibilityEntry]
    public init(schemaVersion: Int = 1, entries: [GameCompatibilityEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}

public struct GameExecutableInfo: Equatable, Sendable {
    public let architecture: String
    public let graphicsAPI: String
    public init(architecture: String, graphicsAPI: String) {
        self.architecture = architecture
        self.graphicsAPI = graphicsAPI
    }
}

public enum GameCompatibilityService {
    public static func detectExecutable(at url: URL) throws -> GameExecutableInfo {
        let data = try Data(contentsOf: url)
        guard data.count >= 0x40, data[0] == 0x4d, data[1] == 0x5a else { throw PortsideError.invalidArtifact("not a Windows PE executable") }
        let offset = Int(data[0x3c]) | Int(data[0x3d]) << 8 | Int(data[0x3e]) << 16 | Int(data[0x3f]) << 24
        guard offset >= 0, offset + 6 < data.count, data[offset] == 0x50, data[offset + 1] == 0x45 else { throw PortsideError.invalidArtifact("invalid PE header") }
        let machine = UInt16(data[offset + 4]) | UInt16(data[offset + 5]) << 8
        let architecture = machine == 0x8664 ? "x86_64" : machine == 0x14c ? "x86" : "unknown"
        let text = String(decoding: data, as: UTF8.self).lowercased()
        let graphicsAPI = text.contains("d3d12") ? "DirectX 12" : text.contains("d3d11") ? "DirectX 11" : text.contains("d3d10") ? "DirectX 10" : text.contains("d3d9") ? "DirectX 9" : text.contains("opengl32") ? "OpenGL" : text.contains("vulkan-1") ? "Vulkan" : "unknown"
        return GameExecutableInfo(architecture: architecture, graphicsAPI: graphicsAPI)
    }

    public static func renderer(for info: GameExecutableInfo) -> [GraphicsBackend] {
        switch (info.graphicsAPI, info.architecture) {
        case ("DirectX 8", _), ("DirectX 9", _): return [.dxvk, .wineD3D]
        case ("DirectX 10", "x86_64"), ("DirectX 11", "x86_64"): return [.d3dMetal, .dxmt, .dxvk, .wineD3D]
        case ("DirectX 10", _), ("DirectX 11", _): return [.dxvk, .wineD3D]
        case ("DirectX 12", _): return [.d3dMetal, .vkd3d]
        case ("OpenGL", _), ("Vulkan", _): return [.wineD3D]
        default: return [.wineD3D]
        }
    }

    public static func mutuallyExclusive(_ renderer: GraphicsBackend, environment: [String: String]) -> Bool {
        let enabled = [
            environment["D3DMETAL"] == "1" ? GraphicsBackend.d3dMetal : nil,
            environment["DXMT"] == "1" ? .dxmt : nil,
            environment["DXVK"] == "1" ? .dxvk : nil
        ].compactMap { $0 }
        return enabled.count <= 1 && !enabled.contains(where: { $0 != renderer })
    }
}

public enum RosettaManager {
    public static func status() async -> RosettaStatus {
        #if arch(arm64)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        do {
            try process.run()
            process.waitUntilExit()
            return RosettaStatus(installed: process.terminationStatus == 0, output: "probe")
        } catch {
            return RosettaStatus(installed: false, output: "probe failed")
        }
        #else
        return RosettaStatus(installed: true, output: "native x86_64")
        #endif
    }

    public static func install(using runner: ProcessRunning = SystemProcessRunner(), logger: PortsideLogger = PortsideLogger()) async throws -> ProcessResult {
        try await runner.run(ProcessLaunchSpec(executable: URL(fileURLWithPath: "/usr/sbin/softwareupdate"), arguments: ["--install-rosetta", "--agree-to-license"], timeout: 1_800), logger: logger)
    }
}

public struct RosettaStatus: Equatable, Sendable {
    public let installed: Bool
    public let output: String
    public init(installed: Bool, output: String = "") {
        self.installed = installed
        self.output = output
    }
}
