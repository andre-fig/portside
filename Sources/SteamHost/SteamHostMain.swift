import AppKit
import Foundation
import PortsideCore

@main
struct SteamHostMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = SteamHostDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

@MainActor
private final class SteamHostDelegate: NSObject, NSApplicationDelegate {
    private let logger = PortsideLogger(logFileName: "steam-host.log")
    private var specification: SteamHostLaunchSpec?
    private var managedProcess: Process?
    private var monitorTask: Task<Void, Never>?
    private var outputPipe: Pipe?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.write("Steam host process started")
        guard let specification = SteamHostLaunchSpecParser.parse(CommandLine.arguments) else {
            logger.write("steam_host_launch_failed: invalid arguments", level: .error)
            NSApp.terminate(nil)
            return
        }
        self.specification = specification
        logger.write("Steam host arguments parsed")
        let profile = SteamLaunchProfile.cef32LegacyLogin
        let profileApplied = Array(specification.steamArguments.prefix(profile.arguments.count)) == profile.arguments
        logger.write("steam_launch_profile=\(profile.identifier)")
        logger.write("steam_launch_arguments_applied=\(profileApplied)")
        guard profileApplied else {
            logger.write("steam_host_launch_failed: required Steam login profile was not received by steam.exe", level: .error)
            NSApp.terminate(nil)
            return
        }
        #if DEBUG
        for (index, argument) in specification.steamArguments.enumerated() {
            logger.write("steam_argument[\(index)]=\(argument)")
        }
        #endif
        NSApp.applicationIconImage = NSWorkspace.shared.icon(forFile: specification.steamExecutablePath)
        logger.write("Steam host icon configured")
        start(specification)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateSteamWindowSoon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        activateSteamWindowSoon()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitorTask?.cancel()
        monitorTask = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
    }

    private func start(_ specification: SteamHostLaunchSpec) {
        logger.write("Steam host checking for an existing managed process")
        if SteamHostProcessInspector.hasManagedSteam(prefix: specification.prefixPath) {
            logger.write("steam_host_launch_rejected: an existing Steam process is not adopted without a fresh UI validation", level: .warning)
            NSApp.terminate(nil)
            return
        }
        do {
            let process = try SteamHostProcessLauncher.launch(specification: specification, logger: logger)
            managedProcess = process
            outputPipe = process.standardOutput as? Pipe
        } catch {
            logger.write("steam_host_launch_failed", level: .error)
            NSApp.terminate(nil)
            return
        }

        monitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if !SteamHostProcessInspector.hasManagedSteam(prefix: specification.prefixPath) {
                    self.logger.write("Steam process tree ended; closing Steam host")
                    NSApp.terminate(nil)
                    return
                }
                self.activateSteamWindowSoon()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func activateSteamWindowSoon() {
        guard let prefix = specification?.prefixPath else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            _ = SteamHostWindowActivator.activate(prefix: prefix)
        }
    }
}

private enum SteamHostLaunchSpecParser {
    static func parse(_ arguments: [String]) -> SteamHostLaunchSpec? {
        var values: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { break }
            guard argument == "--runtime" || argument == "--prefix" || argument == "--steam",
                  index + 1 < arguments.count else { return nil }
            values[argument] = arguments[index + 1]
            index += 2
        }
        guard let runtime = values["--runtime"],
              let prefix = values["--prefix"],
              let steam = values["--steam"],
              !runtime.isEmpty, !prefix.isEmpty, !steam.isEmpty else { return nil }
        let steamArguments = index < arguments.count && arguments[index] == "--" ? Array(arguments.dropFirst(index + 1)) : []
        return SteamHostLaunchSpec(runtimePath: runtime, prefixPath: prefix, steamExecutablePath: steam, steamArguments: steamArguments)
    }
}

private enum SteamHostProcessLauncher {
    static func launch(specification: SteamHostLaunchSpec, logger: PortsideLogger) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: specification.runtimePath)
        process.arguments = [specification.steamExecutablePath] + specification.steamArguments
        process.environment = specification.childEnvironment
        process.currentDirectoryURL = URL(fileURLWithPath: specification.prefixPath)

        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            logger.write("steam_process_output: \(output)")
        }
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { _ in
            outputPipe.fileHandleForReading.readabilityHandler = nil
        }
        try process.run()
        logger.write("Steam host started the managed Steam process")
        return process
    }
}

private enum SteamHostProcessInspector {
    static func hasManagedSteam(prefix: String) -> Bool {
        let snapshot = processSnapshot()
        let normalizedPrefix = prefix.lowercased()
        return snapshot.split(whereSeparator: \.isNewline).contains { line in
            let command = String(line).lowercased()
            guard !command.contains("/steam.app/contents/macos/steam --runtime") else { return false }
            return (command.contains(normalizedPrefix) && command.contains("steam.exe")) || command.contains("steamwebhelper")
        }
    }

    private static func processSnapshot() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm=,args="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

private enum SteamHostWindowActivator {
    static func activate(prefix: String) -> Bool {
        let processSnapshot = processSnapshot()
        guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return false }
        for window in windows {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber).map({ pid_t($0.intValue) }),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  ((bounds["Width"] as? NSNumber)?.doubleValue ?? 0) >= 200,
                  ((bounds["Height"] as? NSNumber)?.doubleValue ?? 0) >= 120 else { continue }
            let isOnscreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            guard isOnscreen else { continue }
            let command = processSnapshot.split(whereSeparator: \.isNewline).first { line in
                let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count == 3, Int32(String(fields[0])) == Int32(ownerPID) else { return false }
                let value = String(fields[1...].joined(separator: " ")).lowercased()
                guard !value.contains("/steam.app/contents/macos/steam --runtime") else { return false }
                return value.contains(prefix.lowercased()) && (value.contains("steam.exe") || value.contains("steamwebhelper"))
            }
            guard command != nil else { continue }
            return NSRunningApplication(processIdentifier: ownerPID)?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) == true
        }
        return false
    }

    private static func processSnapshot() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm=,args="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
