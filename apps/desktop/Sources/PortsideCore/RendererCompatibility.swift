import Foundation
import CryptoKit

public struct RendererProfile: Codable, Equatable, Sendable {
    public let renderer: GraphicsBackend
    public let available: Bool
    public let path: URL?
    public let version: String?
    public let checksum: String?
    public let notes: [String]

    public init(renderer: GraphicsBackend, available: Bool, path: URL? = nil, version: String? = nil, checksum: String? = nil, notes: [String] = []) {
        self.renderer = renderer
        self.available = available
        self.path = path
        self.version = version
        self.checksum = checksum
        self.notes = notes
    }
}

public struct RuntimeDependencyProfile: Codable, Equatable, Sendable {
    public let name: String
    public let available: Bool
    public let path: URL?
    public let version: String?
    public let checksum: String?

    public init(name: String, available: Bool, path: URL? = nil, version: String? = nil, checksum: String? = nil) {
        self.name = name
        self.available = available
        self.path = path
        self.version = version
        self.checksum = checksum
    }
}

public struct RuntimeComponentInventory: Codable, Equatable, Sendable {
    public let wrapper: URL
    public let detectedAt: Date
    public let renderers: [RendererProfile]
    public let dependencies: [RuntimeDependencyProfile]
    public let prohibitedPayloads: [String]

    public init(wrapper: URL, detectedAt: Date = Date(), renderers: [RendererProfile], dependencies: [RuntimeDependencyProfile] = [], prohibitedPayloads: [String] = []) {
        self.wrapper = wrapper
        self.detectedAt = detectedAt
        self.renderers = renderers
        self.dependencies = dependencies
        self.prohibitedPayloads = prohibitedPayloads
    }

    public func profile(for renderer: GraphicsBackend) -> RendererProfile? {
        renderers.first { $0.renderer == renderer }
    }

    public var availableRenderers: [GraphicsBackend] {
        renderers.filter(\.available).map(\.renderer)
    }

    public static func detect(wrapper: URL, fileManager: FileManager = .default) -> RuntimeComponentInventory {
        let root = wrapper.standardizedFileURL
        let wineRoot = root.appendingPathComponent("Contents/SharedSupport/wine", isDirectory: true)
        let frameworks = root.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let wineVersion = readFirstLine(wineRoot.appendingPathComponent("bin/version"))
        let wined3d = firstExisting([
            wineRoot.appendingPathComponent("lib/wine/i386-windows/wined3d.dll"),
            wineRoot.appendingPathComponent("lib/wine/x86_64-windows/wined3d.dll")
        ], fileManager: fileManager)
        let dxmt = existingDirectory(frameworks.appendingPathComponent("renderer/dxmt"), fileManager: fileManager)
        let dxvk = existingDirectory(frameworks.appendingPathComponent("renderer/dxvk"), fileManager: fileManager)
        let vkd3d = findNamedPath(in: frameworks, containing: "vkd3d", fileManager: fileManager)
        let moltenVK = firstExisting([
            frameworks.appendingPathComponent("moltenvkcx/libMoltenVK.dylib"),
            frameworks.appendingPathComponent("libMoltenVK.dylib")
        ], fileManager: fileManager)
        let openGL = firstExisting([
            wineRoot.appendingPathComponent("lib/wine/i386-windows/opengl32.dll"),
            wineRoot.appendingPathComponent("lib/wine/x86_64-windows/opengl32.dll")
        ], fileManager: fileManager)
        let gstreamer = existingDirectory(frameworks.appendingPathComponent("GStreamer.framework"), fileManager: fileManager)
        let mono = findNamedPath(in: wineRoot.appendingPathComponent("share/wine/mono"), containing: "wine-mono", fileManager: fileManager)
        let gecko = findNamedPath(in: wineRoot.appendingPathComponent("share/wine/gecko"), containing: "wine-gecko", fileManager: fileManager)
        let info = (NSDictionary(contentsOf: root.appendingPathComponent("Contents/Info.plist")) as? [String: Any]) ?? [:]
        let d3dMetalPayload = existingDirectory(frameworks.appendingPathComponent("renderer/d3dmetal"), fileManager: fileManager) != nil
        let d3dMetalEnabled = (info["D3DMETAL"] as? NSNumber)?.intValue == 1
        let renderers = [
            RendererProfile(renderer: .wineD3D, available: wined3d != nil, path: wined3d, version: wineVersion, checksum: digest(wined3d)),
            RendererProfile(renderer: .dxmt, available: dxmt != nil, path: dxmt, version: componentVersion(dxmt), checksum: digest(representativeFile(in: dxmt, fileManager: fileManager)), notes: dxmt == nil ? ["DXMT payload not found"] : []),
            RendererProfile(renderer: .dxvk, available: dxvk != nil, path: dxvk, version: componentVersion(dxvk), checksum: digest(representativeFile(in: dxvk, fileManager: fileManager)), notes: dxvk == nil ? ["DXVK payload not found"] : []),
            RendererProfile(renderer: .vkd3d, available: vkd3d != nil, path: vkd3d, version: componentVersion(vkd3d), checksum: digest(representativeFile(in: vkd3d, fileManager: fileManager)), notes: vkd3d == nil ? ["VKD3D payload not found"] : []),
            RendererProfile(renderer: .nativeVulkan, available: moltenVK != nil, path: moltenVK, version: componentVersion(moltenVK), checksum: digest(moltenVK), notes: moltenVK == nil ? ["MoltenVKCX payload not found"] : []),
            RendererProfile(renderer: .nativeOpenGL, available: openGL != nil, path: openGL, version: wineVersion, checksum: digest(openGL), notes: openGL == nil ? ["Wine OpenGL bridge not found"] : [])
        ]
        let dependencies = [
            RuntimeDependencyProfile(name: "GStreamer", available: gstreamer != nil, path: gstreamer, version: componentVersion(gstreamer), checksum: digest(representativeFile(in: gstreamer, fileManager: fileManager))),
            RuntimeDependencyProfile(name: "Wine Mono", available: mono != nil, path: mono, version: mono?.lastPathComponent, checksum: digest(representativeFile(in: mono, fileManager: fileManager))),
            RuntimeDependencyProfile(name: "Wine Gecko", available: gecko != nil, path: gecko, version: gecko?.lastPathComponent, checksum: digest(representativeFile(in: gecko, fileManager: fileManager)))
        ]
        var prohibited: [String] = []
        if d3dMetalPayload { prohibited.append(d3dMetalEnabled ? "D3DMetal payload present and enabled unexpectedly" : "D3DMetal payload present but disabled by wrapper configuration") }
        return RuntimeComponentInventory(wrapper: root, renderers: renderers, dependencies: dependencies, prohibitedPayloads: prohibited)
    }

    private static func firstExisting(_ urls: [URL], fileManager: FileManager) -> URL? {
        urls.first { fileManager.fileExists(atPath: $0.path) }
    }

    private static func existingDirectory(_ url: URL, fileManager: FileManager) -> URL? {
        guard fileManager.fileExists(atPath: url.path), let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else { return nil }
        return url.standardizedFileURL
    }

    private static func findNamedPath(in directory: URL, containing name: String, fileManager: FileManager) -> URL? {
        guard fileManager.fileExists(atPath: directory.path), let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent.localizedCaseInsensitiveContains(name) {
            return url.standardizedFileURL
        }
        return nil
    }

    private static func representativeFile(in path: URL?, fileManager: FileManager) -> URL? {
        guard let path, fileManager.fileExists(atPath: path.path) else { return nil }
        if let values = try? path.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true { return path }
        guard let enumerator = fileManager.enumerator(at: path, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let item as URL in enumerator {
            if let values = try? item.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true { return item }
        }
        return nil
    }

    private static func readFirstLine(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    private static func componentVersion(_ path: URL?) -> String? {
        guard let path else { return nil }
        let candidates = [path.appendingPathComponent("version"), path.deletingLastPathComponent().appendingPathComponent("version")]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return readFirstLine(candidate)
        }
        return path.lastPathComponent
    }

    private static func digest(_ url: URL?) -> String? {
        guard let url, let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct RendererConfiguration: Codable, Equatable, Sendable {
    public let appID: String
    public let executable: String
    public let renderer: GraphicsBackend
    public let dllOverrides: [String: String]
    public let environment: [String: String]
    public let arguments: [String]
    public let updatedAt: Date

    public init(appID: String, executable: String, renderer: GraphicsBackend, dllOverrides: [String: String], environment: [String: String], arguments: [String], updatedAt: Date = Date()) {
        self.appID = appID
        self.executable = executable
        self.renderer = renderer
        self.dllOverrides = dllOverrides
        self.environment = environment
        self.arguments = arguments
        self.updatedAt = updatedAt
    }
}

public struct RendererConfigurationSnapshot: Codable, Equatable, Sendable {
    public let key: String
    public let configuration: RendererConfiguration?
    public let capturedAt: Date

    public init(key: String, configuration: RendererConfiguration?, capturedAt: Date = Date()) {
        self.key = key
        self.configuration = configuration
        self.capturedAt = capturedAt
    }
}

public struct CompatibilityFallbackDecision: Equatable, Sendable {
    public let renderer: GraphicsBackend
    public let reason: String

    public init(renderer: GraphicsBackend, reason: String) {
        self.renderer = renderer
        self.reason = reason
    }
}

public enum CompatibilityFallbackPolicy {
    public static func nextRenderer(profile: GameCompatibilityProfile, executable: String, attempted: GraphicsBackend, result: CompatibilityResultCategory, attemptsAlreadyMade: Int, onlineSession: Bool = false, riskAccepted: Bool = false) -> CompatibilityFallbackDecision? {
        guard attemptsAlreadyMade == 0, !onlineSession, !riskAccepted else { return nil }
        guard result == .graphicsInitializationFailed || result == .shaderCompilationFailed else { return nil }
        guard profile.antiCheat.isEmpty else { return nil }
        let executableProfile = profile.executables.first { $0.executablePath == executable }
        let candidates = executableProfile.map { [$0.preferredRenderer] + $0.fallbackRenderers } ?? [profile.preferredRenderer] + profile.fallbackRenderers
        guard let next = candidates.first(where: { $0 != attempted }) else { return nil }
        return CompatibilityFallbackDecision(renderer: next, reason: "clear graphics failure; one conservative retry")
    }
}

public struct RendererIsolationProof: Equatable, Sendable {
    public let first: RendererConfiguration
    public let second: RendererConfiguration
    public let independent: Bool

    public init(first: RendererConfiguration, second: RendererConfiguration) {
        self.first = first
        self.second = second
        self.independent = first.appID == second.appID && first.executable != second.executable && first.renderer != second.renderer && first.dllOverrides != second.dllOverrides
    }
}

public final class RendererManager: @unchecked Sendable {
    private let wrapper: URL
    private let prefix: URL
    private let runner: ProcessRunning
    private let logger: PortsideLogger
    private let fileManager: FileManager
    private let configurationURL: URL
    private let executeRegistryChanges: Bool
    public let inventory: RuntimeComponentInventory
    private let lock = NSLock()
    private var configurations: [String: RendererConfiguration]

    public init(wrapper: URL = PortsidePaths.baselineWrapper, prefix: URL = PortsidePaths.steamPrefix, runner: ProcessRunning = SystemProcessRunner(), logger: PortsideLogger = PortsideLogger(logFileName: "renderer-manager.log"), fileManager: FileManager = .default, configurationURL: URL = PortsidePaths.profiles.appendingPathComponent("renderer-configurations.json"), executeRegistryChanges: Bool = true, inventory: RuntimeComponentInventory? = nil) {
        self.wrapper = wrapper.standardizedFileURL
        self.prefix = prefix.standardizedFileURL
        self.runner = runner
        self.logger = logger
        self.fileManager = fileManager
        self.configurationURL = configurationURL
        self.executeRegistryChanges = executeRegistryChanges
        self.inventory = inventory ?? RuntimeComponentInventory.detect(wrapper: wrapper, fileManager: fileManager)
        if let data = try? Data(contentsOf: configurationURL), let values = try? JSONDecoder.portside.decode([String: RendererConfiguration].self, from: data) {
            self.configurations = values
        } else {
            self.configurations = [:]
        }
    }

    public var availableRenderers: [GraphicsBackend] { inventory.availableRenderers }

    public func verify(_ renderer: GraphicsBackend) throws -> RendererProfile {
        guard let profile = inventory.profile(for: renderer), profile.available else { throw PortsideError.runtimeUnavailable }
        return profile
    }

    public func install(_ renderer: GraphicsBackend) throws -> RendererProfile {
        // Renderer payloads are owned by the verified official wrapper. The
        // manager verifies them and never replaces global or game files.
        try verify(renderer)
    }

    public func snapshot(appID: String, executable: URL) -> RendererConfigurationSnapshot {
        let key = Self.configurationKey(appID: appID, executable: executable)
        lock.lock(); defer { lock.unlock() }
        return RendererConfigurationSnapshot(key: key, configuration: configurations[key])
    }

    public func configuration(appID: String, executable: URL) -> RendererConfiguration? {
        let key = Self.configurationKey(appID: appID, executable: executable)
        lock.lock(); defer { lock.unlock() }
        return configurations[key]
    }

    public func apply(renderer: GraphicsBackend, appID: String, executable: URL, baseEnvironment: [String: String] = [:], arguments: [String] = []) async throws -> RendererConfiguration {
        _ = try verify(renderer)
        let overrides = Self.dllOverrides(for: renderer)
        let environment = Self.environment(for: renderer, base: baseEnvironment)
        let configuration = RendererConfiguration(appID: appID, executable: executable.standardizedFileURL.path, renderer: renderer, dllOverrides: overrides, environment: environment, arguments: arguments)
        let key = Self.configurationKey(appID: appID, executable: executable)
        let all = replacing(configuration, forKey: key)
        try persist(all)
        if executeRegistryChanges { try await writeRegistry(configuration: configuration, key: key) }
        logger.write("configured app " + appID + " executable " + executable.lastPathComponent + " with " + renderer.rawValue)
        return configuration
    }

    public func rollback(_ snapshot: RendererConfigurationSnapshot) async throws {
        let all = replacing(snapshot.configuration, forKey: snapshot.key)
        try persist(all)
        if executeRegistryChanges { try await writeRegistry(configuration: snapshot.configuration, key: snapshot.key) }
        logger.write("rolled back renderer configuration " + snapshot.key)
    }

    public func remove(appID: String, executable: URL) async throws {
        let snapshot = snapshot(appID: appID, executable: executable)
        try await rollback(RendererConfigurationSnapshot(key: snapshot.key, configuration: nil))
    }

    public func retryAfterFailure(profile: GameCompatibilityProfile, attempt: CompatibilityAttempt, snapshot: RendererConfigurationSnapshot, attemptsAlreadyMade: Int = 0, onlineSession: Bool = false, riskAccepted: Bool = false) async throws -> RendererConfiguration? {
        guard let decision = CompatibilityFallbackPolicy.nextRenderer(profile: profile, executable: attempt.executable, attempted: attempt.renderer, result: attempt.result, attemptsAlreadyMade: attemptsAlreadyMade, onlineSession: onlineSession, riskAccepted: riskAccepted) else { return nil }
        try await rollback(snapshot)
        let executable = URL(fileURLWithPath: attempt.executable)
        return try await apply(renderer: decision.renderer, appID: attempt.appID, executable: executable)
    }

    public static func isolationProof(first: RendererConfiguration, second: RendererConfiguration) -> RendererIsolationProof {
        RendererIsolationProof(first: first, second: second)
    }

    public static func configurationKey(appID: String, executable: URL) -> String {
        appID + ":" + executable.standardizedFileURL.path.lowercased()
    }

    public static func dllOverrides(for renderer: GraphicsBackend) -> [String: String] {
        switch renderer {
        case .wineD3D: return ["d3d8": "builtin", "d3d9": "builtin", "d3d10": "builtin", "d3d10_1": "builtin", "d3d11": "builtin", "d3d12": "builtin", "dxgi": "builtin", "vulkan-1": "builtin", "opengl32": "builtin"]
        case .dxmt: return ["d3d10": "native,builtin", "d3d10_1": "native,builtin", "d3d11": "native,builtin", "dxgi": "native,builtin"]
        case .dxvk: return ["d3d8": "native,builtin", "d3d9": "native,builtin", "d3d10": "native,builtin", "d3d10_1": "native,builtin", "d3d11": "native,builtin", "dxgi": "native,builtin"]
        case .vkd3d: return ["d3d12": "native,builtin", "dxgi": "native,builtin"]
        case .nativeVulkan: return ["vulkan-1": "native,builtin"]
        case .nativeOpenGL: return ["opengl32": "builtin"]
        }
    }

    public static func environment(for renderer: GraphicsBackend, base: [String: String] = [:]) -> [String: String] {
        var environment = base
        environment["D3DMETAL"] = "0"
        environment["DXMT"] = renderer == .dxmt ? "1" : "0"
        environment["DXVK"] = renderer == .dxvk ? "1" : "0"
        if renderer == .nativeVulkan { environment["MOLTENVKCX"] = "1" }
        return environment
    }

    private func persist(_ values: [String: RendererConfiguration]) throws {
        try fileManager.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.portside.encode(values).write(to: configurationURL, options: .atomic)
    }

    private func replacing(_ configuration: RendererConfiguration?, forKey key: String) -> [String: RendererConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        if let configuration { configurations[key] = configuration } else { configurations.removeValue(forKey: key) }
        return configurations
    }

    private func writeRegistry(configuration: RendererConfiguration?, key: String) async throws {
        let registryURL = PortsidePaths.cache.appendingPathComponent("renderer-registry-" + UUID().uuidString + ".reg")
        var lines = ["Windows Registry Editor Version 5.00", ""]
        let executableName = configuration?.executable.split(separator: "/").last.map(String.init) ?? key.split(separator: ":").last.map(String.init) ?? "game.exe"
        guard executableName.count <= 255, !executableName.contains("\\"), !executableName.contains("\"") else { throw PortsideError.invalidPath }
        lines.append("[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\" + executableName + "\\DllOverrides]")
        if let configuration {
            for name in configuration.dllOverrides.keys.sorted() {
                let value = configuration.dllOverrides[name]!.replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("\"" + name + "\"=\"" + value + "\"")
            }
        } else {
            lines.append("@=-")
        }
        try fileManager.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: registryURL, options: .atomic)
        defer { try? fileManager.removeItem(at: registryURL) }
        let wine = wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wine")
        guard fileManager.isExecutableFile(atPath: wine.path) else { throw PortsideError.runtimeUnavailable }
        let specification = ProcessLaunchSpec(executable: wine, arguments: ["regedit", "/S", registryURL.path], environment: ["WINEPREFIX": prefix.path, "WINEDEBUG": "-all"], currentDirectory: prefix, timeout: 120)
        let result = try await runner.run(specification, logger: logger)
        guard result.status == 0 else { throw PortsideError.processFailed("regedit", result.status) }
    }
}
