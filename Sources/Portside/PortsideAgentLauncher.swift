import Foundation
import AppKit

final class PortsideAgentLauncher {
    private var process: Process?

    func start(wrapper: URL, prefix: URL) {
        let identifier = "com.portside.agent"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty else { return }
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
}
