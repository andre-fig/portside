import Foundation
import AppKit
import PortsideCore

@MainActor
final class SteamNativeLoginCoordinator {
    private static let steamBundleIdentifier = "com.valvesoftware.steam"
    private static let nativeSteamDMGURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/steam.dmg")!
    private static let nativeSteamDMG = PortsidePaths.downloads.appendingPathComponent("Steam-macOS.dmg")
    private static let nativeSteamApplicationsDirectory = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)[0]

    private let fileManager: FileManager
    private let workspace: NSWorkspace
    private let logger: PortsideLogger
    private let downloader: SecureDownloader

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared,
        logger: PortsideLogger = PortsideLogger()
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
        self.logger = logger
        self.downloader = SecureDownloader(fileManager: fileManager, logger: logger)
    }

    func migrateIfNeeded() async throws -> Bool {
        guard !SteamNativeLoginMigration.isComplete(fileManager: fileManager) else {
            logger.write("Native Steam login migration already completed")
            return false
        }

        let sourceRoot = SteamNativeLoginMigration.nativeSteamSupportDirectory
        var applicationURL = locateNativeSteamApplication()
        var installedByPortside = false
        var runningApplication: NSRunningApplication?
        var shouldTerminateApplication = false

        do {
            if applicationURL == nil {
                logger.write("Native Steam was not found; installing it temporarily for login migration")
                applicationURL = try await installNativeSteam()
                installedByPortside = true
            }
            guard let applicationURL else {
                throw SteamNativeLoginMigrationError.nativeSteamApplicationUnavailable
            }

            let existingLoginState = SteamNativeLoginMigration.loginState(at: sourceRoot, fileManager: fileManager)
            let mustOpenForLogin = installedByPortside || existingLoginState != .loggedIn
            if mustOpenForLogin {
                runningApplication = runningNativeSteamApplication(at: applicationURL)
                if runningApplication == nil {
                    runningApplication = try await openNativeSteam(at: applicationURL)
                }
                shouldTerminateApplication = true
                try await waitForNativeLogin(at: sourceRoot)
                if let runningApplication {
                    try await terminateNativeSteam(runningApplication)
                }
                shouldTerminateApplication = false
            }

            _ = try SteamNativeLoginMigration.copyLoginData(
                from: sourceRoot,
                to: SteamNativeLoginMigration.managedSteamDirectory,
                fileManager: fileManager
            )
            logger.write("Native Steam login migration copied the required data")

            if installedByPortside {
                try removeTemporaryNativeSteam(at: applicationURL)
            }
            return true
        } catch {
            if shouldTerminateApplication, let runningApplication {
                try? await terminateNativeSteam(runningApplication)
            }
            if installedByPortside, let applicationURL {
                try? removeTemporaryNativeSteam(at: applicationURL)
            }
            throw error
        }
    }

    private func locateNativeSteamApplication() -> URL? {
        if let application = workspace.urlForApplication(withBundleIdentifier: Self.steamBundleIdentifier),
           fileManager.fileExists(atPath: application.path) {
            return application
        }

        let candidates = [
            URL(fileURLWithPath: "/Applications/Steam.app", isDirectory: true),
            Self.nativeSteamApplicationsDirectory.appendingPathComponent("Steam.app", isDirectory: true)
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func runningNativeSteamApplication(at applicationURL: URL) -> NSRunningApplication? {
        workspace.runningApplications.first { application in
            guard !application.isTerminated else { return false }
            if application.bundleIdentifier == Self.steamBundleIdentifier { return true }
            return application.bundleURL?.standardizedFileURL == applicationURL.standardizedFileURL
        }
    }

    private func openNativeSteam(at applicationURL: URL) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSRunningApplication, Error>) in
            workspace.openApplication(at: applicationURL, configuration: configuration) { application, error in
                if let application {
                    continuation.resume(returning: application)
                } else {
                    continuation.resume(throwing: error ?? SteamNativeLoginMigrationError.nativeSteamApplicationUnavailable)
                }
            }
        }
    }

    private func waitForNativeLogin(at sourceRoot: URL) async throws {
        let timeout = max(30, min(900, TimeInterval(ProcessInfo.processInfo.environment["PORTSIDE_NATIVE_LOGIN_TIMEOUT"] ?? "300") ?? 300))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if SteamNativeLoginMigration.loginState(at: sourceRoot, fileManager: fileManager) == .loggedIn {
                logger.write("Native Steam login state detected")
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw SteamNativeLoginMigrationError.loginNotDetected
    }

    private func terminateNativeSteam(_ application: NSRunningApplication) async throws {
        guard !application.isTerminated else { return }
        logger.write("Closing native Steam after login migration")
        application.terminate()
        let deadline = Date().addingTimeInterval(20)
        while !application.isTerminated && Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if !application.isTerminated {
            application.forceTerminate()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard application.isTerminated else {
            throw SteamNativeLoginMigrationError.nativeSteamApplicationUnavailable
        }
    }

    private func installNativeSteam() async throws -> URL {
        do {
            let download = try await downloader.download(from: Self.nativeSteamDMGURL, to: Self.nativeSteamDMG)
            guard download.bytes >= 1_000_000 else {
                throw SteamNativeLoginMigrationError.nativeSteamInstallationFailed
            }

            let mountPoint = fileManager.temporaryDirectory.appendingPathComponent("Portside-Steam-Mount-(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            let attach = try await DirectProcess.run(
                executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["attach", Self.nativeSteamDMG.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path],
                logger: logger,
                logOutput: false
            )
            guard attach.status == 0 else {
                try? fileManager.removeItem(at: mountPoint)
                throw SteamNativeLoginMigrationError.nativeSteamInstallationFailed
            }

            do {
                let sourceApplication = mountPoint.appendingPathComponent("Steam.app", isDirectory: true)
                guard fileManager.fileExists(atPath: sourceApplication.path) else {
                    throw SteamNativeLoginMigrationError.nativeSteamInstallationFailed
                }
                let destination = Self.nativeSteamApplicationsDirectory.appendingPathComponent("Steam.app", isDirectory: true)
                guard !fileManager.fileExists(atPath: destination.path) else {
                    throw SteamNativeLoginMigrationError.nativeSteamApplicationUnavailable
                }
                try fileManager.createDirectory(at: Self.nativeSteamApplicationsDirectory, withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceApplication, to: destination)
                _ = try? await DirectProcess.run(
                    executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                    arguments: ["detach", mountPoint.path, "-force"],
                    logger: logger,
                    logOutput: false
                )
                try? fileManager.removeItem(at: mountPoint)
                return destination
            } catch {
                _ = try? await DirectProcess.run(
                    executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                    arguments: ["detach", mountPoint.path, "-force"],
                    logger: logger,
                    logOutput: false
                )
                try? fileManager.removeItem(at: mountPoint)
                throw error
            }
        } catch let error as SteamNativeLoginMigrationError {
            throw error
        } catch {
            throw SteamNativeLoginMigrationError.nativeSteamInstallationFailed
        }
    }

    private func removeTemporaryNativeSteam(at applicationURL: URL) throws {
        let expectedURL = Self.nativeSteamApplicationsDirectory.appendingPathComponent("Steam.app", isDirectory: true).standardizedFileURL
        guard applicationURL.standardizedFileURL == expectedURL else {
            logger.write("Temporary native Steam cleanup skipped because the path was not Portside-managed", level: .warning)
            return
        }
        try fileManager.removeItem(at: applicationURL)
        logger.write("Removed the temporary native Steam installation")
    }
}
