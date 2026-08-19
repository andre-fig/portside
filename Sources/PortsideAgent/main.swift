import Foundation
import PortsideCore

if CommandLine.arguments.contains("--capture-diagnostics") {
    var wrapper = PortsidePaths.baselineWrapper
    var prefix = PortsidePaths.steamPrefix
    var index = 1
    while index + 1 < CommandLine.arguments.count {
        if CommandLine.arguments[index] == "--wrapper" { wrapper = URL(fileURLWithPath: CommandLine.arguments[index + 1]) }
        if CommandLine.arguments[index] == "--prefix" { prefix = URL(fileURLWithPath: CommandLine.arguments[index + 1]) }
        index += 2
    }
    if let report = try? CompatibilityDiagnostics.capture(wrapper: wrapper, prefix: prefix) {
        print(report.path)
    }
} else {
    let agent = PortsideAgentRuntime.make()
    agent.start()
    while agent.isRunning {
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }
}
