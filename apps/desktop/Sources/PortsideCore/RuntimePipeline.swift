import Foundation
import AppKit
import CoreGraphics

public enum EnvironmentPhase: String, Codable, CaseIterable, Sendable {
    case requirementsChecking, rosettaRequired, runtimeDownloading, runtimeVerifying, runtimeInstalling
    case prefixCreating, steamInstalling, steamUpdating, steamLaunching, windowWaiting, steamReady
    case failedRecoverable, failedFatal
}

public enum GraphicsBackend: String, Codable, CaseIterable, Sendable, Hashable {
    case wineD3D, dxmt, dxvk, vkd3d, nativeVulkan, nativeOpenGL

    public var displayName: String {
        switch self {
        case .wineD3D: return "WineD3D"
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .vkd3d: return "VKD3D"
        case .nativeVulkan: return "Native Vulkan"
        case .nativeOpenGL: return "Native OpenGL"
        }
    }
}

public struct PortsideRuntimeConfiguration: Codable, Equatable, Sendable {
    public static let wrapperName = PortsideRuntimeCatalog.wrapperName
    public static let creatorVersion = "Portside"
    public static let templateVersion = "Portside wrapper 1"
    public static let engineName = "PortsideWineEngine"
    public static let engineVersion = "Portside Wine source build"
    public static let engineVersionSHA256 = "source-build-manifest"
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
            throw PortsideError.invalidArtifact("the Portside baseline only permits WineD3D")
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

    public static let golden: PortsideRuntimeConfiguration = try! PortsideRuntimeConfiguration()

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
            isManaged(snapshotLine: $0.command, wrapper: wrapper) || isManaged(snapshotLine: $0.command, prefix: prefix)
        }.map(\.pid))
        var changed = true
        while changed {
            changed = false
            for snapshot in snapshots where managed.contains(snapshot.parentPID) && managed.insert(snapshot.pid).inserted { changed = true }
        }
        return managed
    }

    public static func fileBackedManagedPIDs(in snapshots: [ManagedProcessSnapshot], wrapper: URL, prefix: URL) -> Set<Int32> {
        let candidates = snapshots.filter { isLikelySteamRuntime($0.command) || $0.command.localizedCaseInsensitiveContains(".exe") }
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
            guard let output = String(data: data, encoding: .utf8), output.contains(wrapper.path) || output.contains(prefix.path) else { return nil }
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
        do { try process.run() } catch { return [] }
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
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? NSNumber, managedPIDs.contains(ownerPID.int32Value),
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber,
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

    public init(appID: String, executable: String, architecture: String, graphicsAPI: String, preferredRenderer: GraphicsBackend, engine: String = PortsideRuntimeConfiguration.engineName, environment: [String: String] = [:], dllOverrides: [String: String] = [:], arguments: [String] = [], result: String? = nil) {
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
        case ("DirectX 10", _), ("DirectX 11", _): return [.dxmt, .wineD3D]
        case ("DirectX 12", _): return [.vkd3d, .wineD3D]
        case ("OpenGL", _): return [.nativeOpenGL, .wineD3D]
        case ("Vulkan", _): return [.nativeVulkan, .wineD3D]
        default: return [.wineD3D]
        }
    }

    public static func mutuallyExclusive(_ renderer: GraphicsBackend, environment: [String: String]) -> Bool {
        let enabled: [GraphicsBackend] = [environment["DXMT"] == "1" ? .dxmt : nil, environment["DXVK"] == "1" ? .dxvk : nil].compactMap { $0 }
        return enabled.count <= 1 && !enabled.contains(where: { $0 != renderer })
    }
}

public enum RosettaManager {
    public static func status() async -> RosettaStatus {
        #if arch(arm64)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        do { try process.run(); process.waitUntilExit(); return RosettaStatus(installed: process.terminationStatus == 0, output: "probe") }
        catch { return RosettaStatus(installed: false, output: "probe failed") }
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
