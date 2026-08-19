import AppKit
import Foundation
import PortsideCore

@MainActor
struct SteamHostLauncher {
    func launch(runtimePath: URL, prefix: URL, steamExecutable: URL, arguments: [String]) async throws -> NSRunningApplication {
        let hostURL = try ensureLauncherBundle()

        let specification = SteamHostLaunchSpec(
            runtimePath: runtimePath.path,
            prefixPath: prefix.path,
            steamExecutablePath: steamExecutable.path,
            steamArguments: arguments
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = specification.arguments
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: hostURL, configuration: configuration) { application, error in
                if let application,
                   application.bundleIdentifier == SteamHostMetadata.bundleIdentifier,
                   application.localizedName == SteamHostMetadata.displayName {
                    continuation.resume(returning: application)
                } else if let application {
                    continuation.resume(throwing: PortsideError.processLaunchFailed(
                        "Steam host launched with an unexpected application identity (\(application.localizedName ?? "unknown"))."
                    ))
                } else {
                    continuation.resume(throwing: error ?? PortsideError.processLaunchFailed("Steam host could not be opened."))
                }
            }
        }
    }

    func waitForExit(timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let isRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == SteamHostMetadata.bundleIdentifier
            }
            if !isRunning { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return !NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == SteamHostMetadata.bundleIdentifier
        }
    }

    private func ensureLauncherBundle() throws -> URL {
        let fileManager = FileManager.default
        let templateURL = Bundle.main.bundleURL.appendingPathComponent(SteamHostMetadata.templateRelativePath)
        let launcherDirectory = PortsidePaths.launchers
        let launcherURL = launcherDirectory.appendingPathComponent(SteamHostMetadata.launcherDirectoryName)
        try fileManager.createDirectory(at: launcherDirectory, withIntermediateDirectories: true)

        if !isValidLauncherBundle(at: launcherURL) {
            if fileManager.fileExists(atPath: launcherURL.path) {
                try fileManager.removeItem(at: launcherURL)
            }
            guard isValidLauncherBundle(at: templateURL) else {
                throw PortsideError.processLaunchFailed("Steam host bundle is missing or has an invalid identity.")
            }
            try fileManager.copyItem(at: templateURL, to: launcherURL)
        }
        guard isValidLauncherBundle(at: launcherURL) else {
            throw PortsideError.processLaunchFailed("Steam host bundle is missing or has an invalid identity.")
        }
        return launcherURL
    }

    private func isValidLauncherBundle(at url: URL) -> Bool {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              info["CFBundleIdentifier"] as? String == SteamHostMetadata.bundleIdentifier,
              info["CFBundleDisplayName"] as? String == SteamHostMetadata.displayName,
              info["CFBundleVersion"] as? String == SteamHostMetadata.launcherBuild,
              info["CFBundleExecutable"] as? String == "Steam",
              info["CFBundleIconFile"] as? String == "Steam" else { return false }
        let executableURL = url.appendingPathComponent("Contents/MacOS/Steam")
        let iconURL = url.appendingPathComponent("Contents/Resources/Steam.icns")
        return FileManager.default.isExecutableFile(atPath: executableURL.path)
            && FileManager.default.fileExists(atPath: iconURL.path)
    }
}
