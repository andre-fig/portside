import Foundation
import CryptoKit

public enum PortsideRuntimeCatalog {
    public static let wrapperName = "PortsideBaseline.app"
    public static let requiredComponents = ["wrapper", "engine", "winetricks"]
    public static let steamExecutable = "C:\\Program Files (x86)\\Steam\\steam.exe"
}

public struct PortsideRuntimeArtifact: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let component: String
    public let version: String
    public let url: URL
    public let sha256: String
    public let expectedSize: Int64
    public let sourceCommit: String?
    public let sourceSnapshotChecksum: String?
    public let license: String

    public init(id: String, component: String, version: String, url: URL, sha256: String, expectedSize: Int64, sourceCommit: String? = nil, sourceSnapshotChecksum: String? = nil, license: String = "Not specified") {
        self.id = id
        self.component = component
        self.version = version
        self.url = url
        self.sha256 = sha256
        self.expectedSize = expectedSize
        self.sourceCommit = sourceCommit
        self.sourceSnapshotChecksum = sourceSnapshotChecksum
        self.license = license
    }

    public init(component: PortsideRuntimeComponent) {
        self.init(id: component.id, component: component.component, version: component.version, url: component.downloadURL, sha256: component.sha256, expectedSize: component.size, sourceCommit: component.sourceCommit, sourceSnapshotChecksum: component.sourceSnapshotChecksum, license: component.license ?? "Not specified")
    }
}

public struct PortsideRuntimeRecord: Codable, Equatable, Sendable {
    public let manifest: PortsideRuntimeArtifact
    public let installedPath: URL
    public let executablePath: URL
    public let graphicsBackend: GraphicsBackend
    public let installedAt: Date

    public init(manifest: PortsideRuntimeArtifact, installedPath: URL, executablePath: URL, graphicsBackend: GraphicsBackend, installedAt: Date = Date()) {
        self.manifest = manifest
        self.installedPath = installedPath
        self.executablePath = executablePath
        self.graphicsBackend = graphicsBackend
        self.installedAt = installedAt
    }

    private enum CodingKeys: String, CodingKey { case manifest, installedPath, executablePath, graphicsBackend, installedAt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.installedPath = try values.decode(URL.self, forKey: .installedPath)
        self.executablePath = try values.decode(URL.self, forKey: .executablePath)
        self.graphicsBackend = try values.decode(GraphicsBackend.self, forKey: .graphicsBackend)
        self.installedAt = try values.decode(Date.self, forKey: .installedAt)
        if let current = try? values.decode(PortsideRuntimeArtifact.self, forKey: .manifest) {
            self.manifest = current
            return
        }
        let legacy = try values.superDecoder(forKey: .manifest)
        let legacyValues = try legacy.container(keyedBy: LegacyArtifactKeys.self)
        let identifier = try legacyValues.decodeIfPresent(String.self, forKey: .identifier) ?? "runtime"
        let component = identifier.localizedCaseInsensitiveContains("winetricks") ? "winetricks" : identifier.localizedCaseInsensitiveContains("engine") ? "engine" : "wrapper"
        let version = try legacyValues.decodeIfPresent(String.self, forKey: .version) ?? "legacy"
        let sha256 = try legacyValues.decodeIfPresent(String.self, forKey: .sha256) ?? String(repeating: "0", count: 64)
        let size = try legacyValues.decodeIfPresent(Int64.self, forKey: .expectedSize) ?? 1
        let url = try legacyValues.decodeIfPresent(URL.self, forKey: .url) ?? URL(string: "https://legacy.portside.invalid/runtime")!
        let license = try legacyValues.decodeIfPresent(String.self, forKey: .license) ?? "Legacy installation"
        self.manifest = PortsideRuntimeArtifact(id: identifier, component: component, version: version, url: url, sha256: sha256, expectedSize: max(1, size), license: license)
    }

    private enum LegacyArtifactKeys: String, CodingKey { case identifier, version, url, sha256, expectedSize, license }
}

public struct PortsideWrapperValidation: Equatable, Sendable {
    public let wrapper: URL
    public let prefix: URL
    public let launcher: URL
    public let engineVersion: String
    public let configuration: PortsideRuntimeConfiguration
}

public struct PortsideRuntimeInstallResult: Sendable {
    public let validation: PortsideWrapperValidation
    public let runtimeRecord: PortsideRuntimeRecord
}

public struct PortsideWrapperConfiguration: Sendable, Equatable {
    public let baseline: PortsideRuntimeConfiguration

    public init(baseline: PortsideRuntimeConfiguration = .golden) {
        self.baseline = baseline
    }

    public func apply(to wrapper: URL, fileManager: FileManager = .default) throws {
        let infoURL = wrapper.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              var info = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw PortsideError.invalidArtifact("Portside wrapper metadata is missing")
        }
        info.removeValue(forKey: "NSMicrophoneUsageDescription")
        info["CFBundleName"] = "PortsideBaseline"
        info["CFBundleDisplayName"] = "Portside"
        info["PortsideRuntime"] = true
        info["PortsideRenderer"] = "WineD3D"
        info["PortsideSteamExecutable"] = PortsideRuntimeCatalog.steamExecutable
        info["PortsideWineDebug"] = baseline.wineDebug
        info["PortsideWinEMSync"] = baseline.msync ? 1 : 0
        info["PortsideWineESync"] = baseline.esync ? 1 : 0
        info["PortsideD3DMetal"] = 0
        info["PortsideDXMT"] = 0
        info["PortsideDXVK"] = 0
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL, options: .atomic)
        let host = wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        guard fileManager.isExecutableFile(atPath: host.path) else { throw PortsideError.invalidArtifact("PortsideRuntimeHost is missing") }
    }
}

public enum PortsideRuntimeValidator {
    public static func validate(wrapper: URL, configuration: PortsideRuntimeConfiguration = .golden, fileManager: FileManager = .default) throws -> PortsideWrapperValidation {
        let host = wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        let prefix = wrapper.appendingPathComponent("Contents/SharedSupport/prefix", isDirectory: true)
        let engine = wrapper.appendingPathComponent("Contents/SharedSupport/engine", isDirectory: true)
        let versionURL = engine.appendingPathComponent("version")
        guard fileManager.isExecutableFile(atPath: host.path),
              fileManager.fileExists(atPath: prefix.path),
              fileManager.isExecutableFile(atPath: engine.appendingPathComponent("bin/wine").path),
              fileManager.fileExists(atPath: engine.appendingPathComponent("share/wine").path),
              let version = try? String(contentsOf: versionURL).trimmingCharacters(in: .whitespacesAndNewlines),
              version.localizedCaseInsensitiveContains("wine") else {
            throw PortsideError.invalidArtifact("Portside wrapper does not contain a complete Wine engine")
        }
        guard let info = NSDictionary(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              (info["PortsideRuntime"] as? NSNumber)?.boolValue == true,
              (info["PortsideRenderer"] as? String) == "WineD3D",
              (info["PortsideD3DMetal"] as? NSNumber)?.intValue == 0,
              (info["PortsideDXMT"] as? NSNumber)?.intValue == 0,
              (info["PortsideDXVK"] as? NSNumber)?.intValue == 0,
              info["NSMicrophoneUsageDescription"] == nil else {
            throw PortsideError.invalidArtifact("Portside wrapper options are incomplete or enable an unsupported renderer")
        }
        return PortsideWrapperValidation(wrapper: wrapper, prefix: prefix, launcher: host, engineVersion: version, configuration: configuration)
    }
}

public final class PortsideRuntimeInstaller: @unchecked Sendable {
    private let runner: ProcessRunning
    private let logger: PortsideLogger
    private let fileManager: FileManager

    public init(runner: ProcessRunning = SystemProcessRunner(), logger: PortsideLogger = PortsideLogger(), fileManager: FileManager = .default) {
        self.runner = runner
        self.logger = logger
        self.fileManager = fileManager
    }

    public func install(artifacts: [PortsideRuntimeArtifact: URL], configuration: PortsideRuntimeConfiguration = .golden) async throws -> PortsideRuntimeInstallResult {
        guard let wrapperArchive = artifact("wrapper", in: artifacts),
              let engineArchive = artifact("engine", in: artifacts),
              let winetricksArchive = artifact("winetricks", in: artifacts) else {
            throw PortsideError.invalidArtifact("the Portside runtime manifest must contain wrapper, engine and winetricks")
        }
        let pending = PortsidePaths.cache.appendingPathComponent("portside-runtime-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: pending) }
        try fileManager.createDirectory(at: pending, withIntermediateDirectories: true)
        let wrapperExtract = pending.appendingPathComponent("wrapper", isDirectory: true)
        let engineExtract = pending.appendingPathComponent("engine", isDirectory: true)
        let winetricksExtract = pending.appendingPathComponent("winetricks", isDirectory: true)
        try await extract(archive: wrapperArchive, to: wrapperExtract)
        try await extract(archive: engineArchive, to: engineExtract)
        try await extract(archive: winetricksArchive, to: winetricksExtract)

        guard let wrapperBundle = findBundle(in: wrapperExtract),
              let engineRoot = findEngine(in: engineExtract),
              let winetricksRoot = findWinetricks(in: winetricksExtract) else {
            throw PortsideError.invalidArtifact("Portside runtime archive layout is incomplete")
        }
        let wrapperPending = pending.appendingPathComponent(PortsideRuntimeCatalog.wrapperName, isDirectory: true)
        try fileManager.copyItem(at: wrapperBundle, to: wrapperPending)
        let sharedSupport = wrapperPending.appendingPathComponent("Contents/SharedSupport", isDirectory: true)
        try fileManager.createDirectory(at: sharedSupport, withIntermediateDirectories: true)
        let engineDestination = sharedSupport.appendingPathComponent("engine", isDirectory: true)
        try fileManager.copyItem(at: engineRoot, to: engineDestination)
        let shareWine = engineDestination.appendingPathComponent("share-wine", isDirectory: true)
        if fileManager.fileExists(atPath: shareWine.path) {
            try fileManager.createDirectory(at: engineDestination.appendingPathComponent("share", isDirectory: true), withIntermediateDirectories: true)
            try fileManager.moveItem(at: shareWine, to: engineDestination.appendingPathComponent("share/wine", isDirectory: true))
        }
        let winetricksDestination = sharedSupport.appendingPathComponent("winetricks", isDirectory: true)
        try fileManager.copyItem(at: winetricksRoot, to: winetricksDestination)
        try PortsideWrapperConfiguration(baseline: configuration).apply(to: wrapperPending, fileManager: fileManager)

        let destination = PortsidePaths.baselineWrapper
        if fileManager.fileExists(atPath: destination.path) {
            let rollback = PortsidePaths.runtime.appendingPathComponent("rollback-(Int(Date().timeIntervalSince1970))", isDirectory: true)
            try fileManager.createDirectory(at: rollback.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: destination, to: rollback)
        }
        try AtomicInstaller.installDirectory(from: wrapperPending, to: destination, fileManager: fileManager)

        let wrapperPrefix = destination.appendingPathComponent("Contents/SharedSupport/prefix", isDirectory: true)
        let managedPrefix = PortsidePaths.steamPrefix
        try fileManager.createDirectory(at: PortsidePaths.prefixes, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: managedPrefix.path) {
            if fileManager.fileExists(atPath: wrapperPrefix.path) { try fileManager.removeItem(at: wrapperPrefix) }
            try fileManager.createSymbolicLink(at: wrapperPrefix, withDestinationURL: managedPrefix)
        } else {
            try fileManager.createDirectory(at: managedPrefix, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: wrapperPrefix.path) { try fileManager.removeItem(at: wrapperPrefix) }
            try fileManager.createSymbolicLink(at: wrapperPrefix, withDestinationURL: managedPrefix)
            let prefixResult = try await runner.run(PortsideSteamFlow.prefixCreationSpec(wrapper: destination), logger: logger)
            guard prefixResult.status == 0 else { throw PortsideError.processFailed("Portside prefix creation", prefixResult.status) }
        }

        let validation = try PortsideRuntimeValidator.validate(wrapper: destination, configuration: configuration, fileManager: fileManager)
        let canonical = PortsideWrapperValidation(wrapper: validation.wrapper, prefix: managedPrefix, launcher: validation.launcher, engineVersion: validation.engineVersion, configuration: validation.configuration)
        let metadata = ["wrapper": destination.path, "prefix": managedPrefix.path, "engine": validation.engineVersion]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: PortsidePaths.prefixes.appendingPathComponent("PortsideBaseline.json"), options: .atomic)
        guard let engineArtifact = artifacts.keys.first(where: { $0.component == "engine" }) else { throw PortsideError.invalidArtifact("engine artifact is missing") }
        let record = PortsideRuntimeRecord(manifest: engineArtifact, installedPath: destination, executablePath: validation.launcher, graphicsBackend: configuration.renderer)
        logger.write("Installed Portside runtime wrapper with WineD3D")
        return PortsideRuntimeInstallResult(validation: canonical, runtimeRecord: record)
    }

    @discardableResult
    public func rollbackLatest() throws -> PortsideWrapperValidation? {
        let candidates = (try? fileManager.contentsOfDirectory(at: PortsidePaths.runtime, includingPropertiesForKeys: nil)) ?? []
        guard let previous = candidates.filter({ $0.lastPathComponent.hasPrefix("rollback-") }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else { return nil }
        let destination = PortsidePaths.baselineWrapper
        if fileManager.fileExists(atPath: destination.path) { try fileManager.moveItem(at: destination, to: PortsidePaths.runtime.appendingPathComponent("failed-(UUID().uuidString)", isDirectory: true)) }
        try fileManager.moveItem(at: previous, to: destination)
        return try PortsideRuntimeValidator.validate(wrapper: destination)
    }

    private func artifact(_ component: String, in artifacts: [PortsideRuntimeArtifact: URL]) -> URL? {
        artifacts.first(where: { $0.key.component == component })?.value
    }

    private func extract(archive: URL, to destination: URL) async throws {
        let listing = try await runner.run(ProcessLaunchSpec(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tf", archive.path], timeout: 120), logger: logger)
        guard listing.status == 0 else { throw PortsideError.processFailed("runtime archive listing", listing.status) }
        try SafeArchiveExtractor.validateListing(listing.output)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let result = try await runner.run(ProcessLaunchSpec(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xJf", archive.path, "-C", destination.path], timeout: 1_800), logger: logger)
        guard result.status == 0 else { throw PortsideError.processFailed("runtime archive extraction", result.status) }
    }

    private func findBundle(in root: URL) -> URL? {
        (fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])?.compactMap { $0 as? URL } ?? []).first { $0.pathExtension == "app" }
    }

    private func findEngine(in root: URL) -> URL? {
        (fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])?.compactMap { $0 as? URL } ?? []).first {
            fileManager.isExecutableFile(atPath: $0.appendingPathComponent("bin/wine").path)
                && fileManager.fileExists(atPath: $0.appendingPathComponent("share-wine").path)
        }
    }

    private func findWinetricks(in root: URL) -> URL? {
        (fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])?.compactMap { $0 as? URL } ?? []).first {
            fileManager.isExecutableFile(atPath: $0.appendingPathComponent("src/winetricks").path)
        }
    }
}

public final class PortsideUpdateService: @unchecked Sendable {
    private let logger: PortsideLogger
    private let backend: PortsideBackendClient?
    private let currentVersion: String
    public private(set) var lastManifestVersion: String?

    private struct PendingRuntimeIndex: Codable {
        let manifest: PortsideRuntimeManifest
        let artifacts: [String: String]
    }

    public init(logger: PortsideLogger = PortsideLogger(), backendConfiguration: PortsideBackendConfiguration? = nil, currentVersion: String = "0.1.0") {
        self.logger = logger
        self.backend = backendConfiguration.flatMap { try? PortsideBackendClient(configuration: $0) }
        self.currentVersion = currentVersion
    }

    public static func shouldCheck(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= 86_400
    }

    public func downloadBaselineArtifacts(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [PortsideRuntimeArtifact: URL] {
        guard let backend else { throw PortsideCommercialError.backendUnavailable }
        let manifest = try await backend.fetchRuntimeManifest(currentVersion: currentVersion)
        lastManifestVersion = manifest.manifestVersion
        return try await backend.downloadArtifacts(manifest: manifest, to: PortsidePaths.downloads, progress: progress)
    }

    @discardableResult
    public func prepareRuntimeUpdate(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> PortsideRuntimeManifest? {
        guard let backend else { throw PortsideCommercialError.backendUnavailable }
        let manifest = try await backend.fetchRuntimeManifest(currentVersion: currentVersion)
        let installedVersion = EnvironmentStore().load().runtimeManifestVersion
        if let installedVersion,
           PortsideManifestVerifier.compareVersions(manifest.manifestVersion, installedVersion) <= 0,
           manifest.rollbackVersion != installedVersion { return nil }
        let directory = PortsidePaths.runtimePending.appendingPathComponent(pendingDirectoryName(for: manifest.manifestVersion), isDirectory: true)
        let indexURL = directory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL), let existing = try? JSONDecoder.portside.decode(PendingRuntimeIndex.self, from: data), existing.manifest.manifestVersion == manifest.manifestVersion { return existing.manifest }
        let temporary = PortsidePaths.runtimePending.appendingPathComponent(".pending-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let artifactsDirectory = temporary.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsDirectory, withIntermediateDirectories: true)
        let artifacts = try await backend.downloadArtifacts(manifest: manifest, to: artifactsDirectory, progress: progress)
        let filenames = artifacts.reduce(into: [String: String]()) { $0[$1.key.id] = $1.value.lastPathComponent }
        try JSONEncoder.portside.encode(PendingRuntimeIndex(manifest: manifest, artifacts: filenames)).write(to: temporary.appendingPathComponent("index.json"), options: .atomic)
        try FileManager.default.createDirectory(at: PortsidePaths.runtimePending, withIntermediateDirectories: true)
        for existing in (try? FileManager.default.contentsOfDirectory(at: PortsidePaths.runtimePending, includingPropertiesForKeys: nil)) ?? [] where existing.lastPathComponent.hasPrefix("runtime-") && existing.path != directory.path { try? FileManager.default.removeItem(at: existing) }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.moveItem(at: temporary, to: directory)
        lastManifestVersion = manifest.manifestVersion
        logger.write("Verified and prepared Portside runtime \(manifest.manifestVersion)")
        return manifest
    }

    public func applyPendingRuntime(using installer: PortsideRuntimeInstaller) async throws -> (result: PortsideRuntimeInstallResult, manifest: PortsideRuntimeManifest)? {
        guard let pending = try pendingRuntimeUpdate() else { return nil }
        do {
            let result = try await installer.install(artifacts: pending.artifacts)
            removePendingRuntime(pending.manifest.manifestVersion)
            return (result, pending.manifest)
        } catch {
            _ = try? installer.rollbackLatest()
            throw error
        }
    }

    public func pendingRuntimeUpdate() throws -> (manifest: PortsideRuntimeManifest, artifacts: [PortsideRuntimeArtifact: URL])? {
        let directories = ((try? FileManager.default.contentsOfDirectory(at: PortsidePaths.runtimePending, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).filter { $0.lastPathComponent.hasPrefix("runtime-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let directory = directories.first else { return nil }
        let index = try JSONDecoder.portside.decode(PendingRuntimeIndex.self, from: Data(contentsOf: directory.appendingPathComponent("index.json")))
        var artifacts: [PortsideRuntimeArtifact: URL] = [:]
        for component in index.manifest.components {
            guard let filename = index.artifacts[component.id], SafeArchiveExtractor.isSafeRelativePath(filename) else { throw PortsideError.invalidArtifact("pending runtime path is unsafe") }
            let url = directory.appendingPathComponent("artifacts", isDirectory: true).appendingPathComponent(filename)
            guard url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: url.path) else { throw PortsideError.invalidArtifact("pending runtime artifact is missing") }
            artifacts[PortsideRuntimeArtifact(component: component)] = url
        }
        guard artifacts.count == PortsideRuntimeCatalog.requiredComponents.count else { throw PortsideError.invalidArtifact("pending runtime is incomplete") }
        return (index.manifest, artifacts)
    }

    public func removePendingRuntime(_ manifestVersion: String) {
        try? FileManager.default.removeItem(at: PortsidePaths.runtimePending.appendingPathComponent(pendingDirectoryName(for: manifestVersion), isDirectory: true))
    }

    private func pendingDirectoryName(for version: String) -> String {
        "runtime-" + SHA256.hash(data: Data(version.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
    }
}

public enum PortsideSteamFlow {
    private static var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = NSHomeDirectory()
        environment["XDG_CACHE_HOME"] = PortsidePaths.cache.appendingPathComponent("XDG", isDirectory: true).path
        return environment
    }

    public static func installationSpec(wrapper: URL) throws -> ProcessLaunchSpec {
        let host = wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        guard FileManager.default.isExecutableFile(atPath: host.path) else { throw PortsideError.runtimeUnavailable }
        return ProcessLaunchSpec(executable: host, arguments: ["--winetricks", "steam"], environment: processEnvironment, currentDirectory: wrapper, timeout: 3_600)
    }

    public static func prefixCreationSpec(wrapper: URL) throws -> ProcessLaunchSpec {
        let host = wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        guard FileManager.default.isExecutableFile(atPath: host.path) else { throw PortsideError.runtimeUnavailable }
        return ProcessLaunchSpec(executable: host, arguments: ["--create-prefix"], environment: processEnvironment, currentDirectory: wrapper, timeout: 1_800)
    }

    public static func cleanLaunchSpec(wrapper: URL) throws -> ProcessLaunchSpec {
        let host = wrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        guard FileManager.default.isExecutableFile(atPath: host.path) else { throw PortsideError.runtimeUnavailable }
        return ProcessLaunchSpec(executable: host, environment: processEnvironment, currentDirectory: wrapper, timeout: 60)
    }

    public static func steamExecutable(prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    }
}
