import Foundation

/// Diagnostic IPC only. Runtime authentication still belongs to the manifest
/// and installer. A fresh UUID prevents an earlier launch from answering this one.
public struct RuntimeLaunchReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let launchID: UUID
    public let phase: String
    public let hostPID: Int32
    public let childPID: Int32?
    public let terminationStatus: Int32?
    public let terminationReason: String?
    public let signal: Int32?
    public let duration: TimeInterval
    public let executionError: String?

    public static func read(launchID: UUID, directory: URL = PortsidePaths.logs.appendingPathComponent("RuntimeLaunches")) -> Self? {
        let url = directory.appendingPathComponent(launchID.uuidString + ".json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
              let data = try? Data(contentsOf: url),
              let receipt = try? JSONDecoder().decode(Self.self, from: data),
              receipt.schemaVersion == 1, receipt.launchID == launchID,
              ["running", "executionFailed", "terminated"].contains(receipt.phase) else { return nil }
        return receipt
    }

    public var isTerminal: Bool { phase == "executionFailed" || phase == "terminated" }
}

public enum SteamLaunchFailure: Error, LocalizedError, Codable, Equatable, Sendable {
    case wineExecutionFailed
    case wineSignaled(Int32)
    case wineExited(Int32)
    case steamExitedBeforeReady
    case steamNotStarted
    case processWithoutWindow
    case windowWithoutWebHelper
    case rendererInitializationFailed

    public var code: String {
        switch self {
        case .wineExecutionFailed: "wine_execution_failed"
        case .wineSignaled: "wine_terminated_by_signal"
        case .wineExited: "wine_exit_failed"
        case .steamExitedBeforeReady: "steam_exited_before_ready"
        case .steamNotStarted: "steam_process_not_started"
        case .processWithoutWindow: "steam_window_failed"
        case .windowWithoutWebHelper: "steam_webhelper_failed"
        case .rendererInitializationFailed: "steam_renderer_failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .wineExecutionFailed: "Portside could not execute Wine. Steam was not started."
        case .wineSignaled(let signal): "Wine was terminated by signal \(signal) before Steam was ready."
        case .wineExited(let status): "Wine exited with status \(status) before Steam was ready."
        case .steamExitedBeforeReady: "Steam closed before it was ready. Please try again."
        case .steamNotStarted: "Steam did not start. Please try again."
        case .processWithoutWindow: "Steam is running, but its window could not be opened. Please try again."
        case .windowWithoutWebHelper: "A Steam window was detected, but its web helper did not start. Please try again."
        case .rendererInitializationFailed: "Steam could not render its interface. Its window may be blank. Close Steam and try again; your Steam data is preserved."
        }
    }
}
