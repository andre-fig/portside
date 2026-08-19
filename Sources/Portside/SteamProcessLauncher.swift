import Foundation
import PortsideCore

/// Starts the Windows Steam executable directly through Wine.
///
/// This intentionally does not open a macOS wrapper application. macOS therefore
/// exposes the Wine process (the same identity used by the runtime) instead of a
/// second empty application named Steam.
@MainActor
final class SteamProcessLauncher {
    private let logger = PortsideLogger(logFileName: "steam-launch.log")
    private var process: Process?
    private var outputHandle: FileHandle?
    private let processLogURL = PortsidePaths.logs.appendingPathComponent("steam-process.log")

    func launch(runtimePath: URL, prefix: URL, steamExecutable: URL, arguments: [String] = []) async throws -> Process {
        guard process?.isRunning != true else {
            throw PortsideError.processLaunchFailed("A managed Wine Steam process is already running.")
        }

        let process = Process()
        process.executableURL = runtimePath
        process.arguments = [steamExecutable.path] + arguments
        process.environment = WineProcessEnvironment.make(runtimeExecutable: runtimePath, prefix: prefix)
        process.currentDirectoryURL = prefix

        let outputHandle: FileHandle
        do {
            outputHandle = try openRotatingProcessLog()
        } catch {
            throw PortsideError.processLaunchFailed("Steam output log could not be opened.")
        }
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        process.terminationHandler = { [weak self] _ in
            try? outputHandle.close()
            Task { @MainActor in
                guard let self, self.process?.processIdentifier == process.processIdentifier else { return }
                self.process = nil
                self.outputHandle = nil
            }
        }

        do {
            try process.run()
        } catch {
            try? outputHandle.close()
            throw PortsideError.processLaunchFailed("Steam could not be started.")
        }
        self.process = process
        self.outputHandle = outputHandle
        logger.write("Wine Steam process started directly with arguments: \(arguments.joined(separator: " "))")
        return process
    }

    func waitForExit(timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard process?.isRunning == true else {
                process = nil
                outputHandle = nil
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return process?.isRunning != true
    }

    private func openRotatingProcessLog() throws -> FileHandle {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: PortsidePaths.logs, withIntermediateDirectories: true)
        if let attributes = try? fileManager.attributesOfItem(atPath: processLogURL.path),
           (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 2 * 1024 * 1024 {
            let rotated = processLogURL.appendingPathExtension("1")
            try? fileManager.removeItem(at: rotated)
            try? fileManager.moveItem(at: processLogURL, to: rotated)
        }
        if !fileManager.fileExists(atPath: processLogURL.path) {
            fileManager.createFile(atPath: processLogURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: processLogURL)
        try handle.seekToEnd()
        return handle
    }

}
