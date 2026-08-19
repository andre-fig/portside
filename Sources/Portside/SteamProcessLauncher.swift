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
    private var outputPipe: Pipe?

    func launch(runtimePath: URL, prefix: URL, steamExecutable: URL, arguments: [String]) async throws -> Process {
        guard process?.isRunning != true else {
            throw PortsideError.processLaunchFailed("A managed Wine Steam process is already running.")
        }

        removeLegacySteamHostBundle()

        let process = Process()
        process.executableURL = runtimePath
        process.arguments = [steamExecutable.path] + arguments
        process.environment = WineProcessEnvironment.make(runtimeExecutable: runtimePath, prefix: prefix)
        process.currentDirectoryURL = prefix

        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8),
                  !output.isEmpty else { return }
            self?.logger.write("steam_process_output: \(output)")
        }
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { [weak self] _ in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, self.process?.processIdentifier == process.processIdentifier else { return }
                self.process = nil
                self.outputPipe = nil
            }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw PortsideError.processLaunchFailed("Steam could not be started.")
        }
        self.process = process
        self.outputPipe = outputPipe
        logger.write("Wine Steam process started directly")
        return process
    }

    func waitForExit(timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard process?.isRunning == true else {
                process = nil
                outputPipe = nil
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return process?.isRunning != true
    }

    private func removeLegacySteamHostBundle() {
        let legacyBundle = PortsidePaths.launchers.appendingPathComponent("Steam.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacyBundle.path) else { return }
        do {
            try FileManager.default.removeItem(at: legacyBundle)
            logger.write("Removed legacy macOS Steam host bundle")
        } catch {
            logger.write("Could not remove legacy macOS Steam host bundle", level: .warning)
        }
    }
}
