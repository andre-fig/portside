import Foundation
import AppKit

final class PortsideAgentLauncher {
    private var process: Process?
    private var runtimeUpdaterProcess: Process?

    func start(wrapper: URL, prefix: URL) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/PortsideAgent.app/Contents/MacOS/PortsideAgent")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }
        let agent = Process()
        agent.executableURL = helper
        agent.arguments = ["--wrapper", wrapper.path, "--prefix", prefix.path]
        agent.standardOutput = FileHandle.nullDevice
        agent.standardError = FileHandle.nullDevice
        do {
            try agent.run()
            process = agent
        } catch {
            process = nil
        }
    }

    func startRuntimeUpdater() {
        guard runtimeUpdaterProcess?.isRunning != true else { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/PortsideAgent.app/Contents/MacOS/PortsideAgent")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }
        let updater = Process()
        updater.executableURL = helper
        updater.arguments = ["--runtime-updater"]
        updater.standardOutput = FileHandle.nullDevice
        updater.standardError = FileHandle.nullDevice
        do {
            try updater.run()
            runtimeUpdaterProcess = updater
        } catch {
            runtimeUpdaterProcess = nil
        }
    }
}
