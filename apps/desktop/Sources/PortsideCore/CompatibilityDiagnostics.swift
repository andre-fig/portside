import Foundation

public struct CompatibilityProcessDiagnostic: Codable, Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let command: String

    public init(pid: Int32, parentPID: Int32, command: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
    }
}

public struct CompatibilityDiagnosticsReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let wrapper: String
    public let engine: String
    public let engineChecksum: String
    public let rendererInventory: RuntimeComponentInventory
    public let relevantOptions: [String: String]
    public let environment: [String: String]
    public let prefixStructure: [String]
    public let processes: [CompatibilityProcessDiagnostic]
    public let steamLaunch: [String: String]
    public let logs: [String: String]

    public init(generatedAt: Date = Date(), wrapper: String, engine: String, engineChecksum: String, rendererInventory: RuntimeComponentInventory, relevantOptions: [String: String], environment: [String: String], prefixStructure: [String], processes: [CompatibilityProcessDiagnostic], steamLaunch: [String: String], logs: [String: String]) {
        self.generatedAt = generatedAt
        self.wrapper = wrapper
        self.engine = engine
        self.engineChecksum = engineChecksum
        self.rendererInventory = rendererInventory
        self.relevantOptions = relevantOptions
        self.environment = environment
        self.prefixStructure = prefixStructure
        self.processes = processes
        self.steamLaunch = steamLaunch
        self.logs = logs
    }
}

public enum CompatibilityDiagnostics {
    public static func capture(wrapper: URL = PortsidePaths.baselineWrapper, prefix: URL = PortsidePaths.steamPrefix, outputURL: URL? = nil, fileManager: FileManager = .default) throws -> URL {
        let infoURL = wrapper.appendingPathComponent("Contents/Info.plist")
        let info = (NSDictionary(contentsOf: infoURL) as? [String: Any]) ?? [:]
        let allowedKeys = ["D3DMETAL", "DXMT", "DXVK", "MOLTENVKCX", "WINEMSYNC", "WINEESYNC", "WINEDEBUG", "SkipMono", "SkipGecko"]
        var options: [String: String] = [:]
        for key in allowedKeys {
            if let value = info[key] { options[key] = String(describing: value) }
        }
        var environment = PortsideRuntimeConfiguration.golden.environment
        if let values = info["Environment"] as? [String: Any] {
            for (key, value) in values where allowedKeys.contains(key) { environment[key] = String(describing: value) }
        }
        let inventory = RuntimeComponentInventory.detect(wrapper: wrapper, fileManager: fileManager)
        let processes = SteamReadinessMonitor().captureProcessSnapshot()
        let managedPIDs = SteamProcessOwnership.managedPIDs(in: processes, wrapper: wrapper, prefix: prefix)
        let processRecords = processes.filter { managedPIDs.contains($0.pid) && SteamProcessOwnership.isLikelySteamRuntime($0.command) }.map { snapshot in
            CompatibilityProcessDiagnostic(pid: snapshot.pid, parentPID: snapshot.parentPID, command: PortsideLogger.sanitize(snapshot.command))
        }
        let prefixStructure = knownPrefixStructure(prefix: prefix, fileManager: fileManager)
        let logNames = ["runtime-install.log", "portside-update.log", "steam-readiness.log", "game-launches.log", "game-launch-attempts.jsonl", "portside-agent.log"]
        var logs: [String: String] = [:]
        for name in logNames {
            let url = PortsidePaths.logs.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                logs[name] = String(PortsideLogger.sanitize(String(text.suffix(16_384))))
            }
        }
        let steamLaunch = [
            "executable": PortsideLogger.sanitize((info["PortsideSteamExecutable"] as? String) ?? PortsideRuntimeConfiguration.windowsSteamExecutable),
            "arguments": PortsideLogger.sanitize((info["Program Flags"] as? String) ?? "")
        ]
        let report = CompatibilityDiagnosticsReport(wrapper: PortsideLogger.sanitize(wrapper.path), engine: PortsideRuntimeConfiguration.engineVersion, engineChecksum: PortsideRuntimeConfiguration.engineVersionSHA256, rendererInventory: sanitizedInventory(inventory), relevantOptions: options, environment: environment, prefixStructure: prefixStructure, processes: processRecords, steamLaunch: steamLaunch, logs: logs)
        let destination = outputURL ?? PortsidePaths.diagnostics.appendingPathComponent("compatibility-" + String(Int(Date().timeIntervalSince1970)) + ".json")
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.portside.encode(report).write(to: destination, options: .atomic)
        return destination
    }

    private static func knownPrefixStructure(prefix: URL, fileManager: FileManager) -> [String] {
        let names = ["drive_c", "dosdevices", "system.reg", "user.reg", "userdef.reg"]
        return names.filter { fileManager.fileExists(atPath: prefix.appendingPathComponent($0).path) }
    }

    private static func sanitizedInventory(_ inventory: RuntimeComponentInventory) -> RuntimeComponentInventory {
        let renderers = inventory.renderers.map { profile in
            RendererProfile(renderer: profile.renderer, available: profile.available, path: profile.path.map(sanitizedURL), version: profile.version, checksum: profile.checksum, notes: profile.notes)
        }
        let dependencies = inventory.dependencies.map { dependency in
            RuntimeDependencyProfile(name: dependency.name, available: dependency.available, path: dependency.path.map(sanitizedURL), version: dependency.version, checksum: dependency.checksum)
        }
        return RuntimeComponentInventory(wrapper: sanitizedURL(inventory.wrapper), detectedAt: inventory.detectedAt, renderers: renderers, dependencies: dependencies, prohibitedPayloads: inventory.prohibitedPayloads)
    }

    private static func sanitizedURL(_ url: URL) -> URL {
        let path = PortsideLogger.sanitize(url.path)
        return URL(fileURLWithPath: path.hasPrefix("/") ? path : "/" + path)
    }
}
