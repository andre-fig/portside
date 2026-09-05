import Darwin
import Foundation

/// The bundled installer uses this same transaction with and without macOS
/// authorization. The destination is fixed by the executable, never by shell
/// input. Previous application bundles are retained; user data is never touched.
public enum PortsideInstallationTransaction {
    public static func install(source: URL, expectedHash: String, owner: uid_t, group: gid_t) throws {
        let ownIdentity = try PortsideApplicationSignature.validate(bundleURL: Bundle.main.bundleURL)
        let sourceIdentity = try PortsideApplicationSignature.validate(bundleURL: source)
        guard sourceIdentity == ownIdentity, sourceIdentity.codeDirectoryHash == expectedHash else {
            throw PortsideInstallationError.invalidSignature
        }
        try perform(source: source, destination: PortsideInstallationService.destination, identity: sourceIdentity, owner: owner, group: group, validate: { try PortsideApplicationSignature.validate(bundleURL: $0) })
    }

    // Internal injection is used only by tests with temporary directories.
    static func perform(source: URL, destination: URL, identity: PortsideSignedApplication, owner: uid_t, group: gid_t, assess: (URL) throws -> Void = PortsideApplicationLaunchPreparation.assess, validate: (URL) throws -> PortsideSignedApplication) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let lockURL = parent.appendingPathComponent(".Portside-installation.lock")
        let lock = open(lockURL.path, O_CREAT | O_NOFOLLOW | O_RDONLY, 0o644)
        guard lock >= 0 else { throw fileError() }
        defer { close(lock) }
        var lockInfo = stat()
        guard fstat(lock, &lockInfo) == 0, lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_nlink == 1,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw PortsideInstallationError.installationChanged }
        defer { flock(lock, LOCK_UN) }
        // An authorization shell uses umask 077. Keep this data-free advisory
        // lock readable so the next ordinary installation does not need a
        // second authorization merely to acquire the same lock.
        if lockInfo.st_uid == geteuid() { _ = fchmod(lock, 0o644) }
        let previousIdentity = fileManager.fileExists(atPath: destination.path) ? try validate(destination) : nil
        if let previousIdentity { try identity.validateReplacement(of: previousIdentity) }

        let stage: URL
        // Foundation provides a private replacement directory on the same
        // volume. In particular, elevated code must not stage through a path
        // another Applications-folder writer can rename into a symlink.
        do {
            stage = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stage.path)
        }
        catch { throw mappedFileError(error) }
        let stagedBundle = stage.appendingPathComponent("Portside.app", isDirectory: true)
        var preserveStage = false
        defer { if !preserveStage { try? fileManager.removeItem(at: stage) } }
        guard try run(executable: URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["--rsrc", "--extattr", "--acl", source.path, stagedBundle.path]) == 0 else { throw PortsideInstallationError.copyFailed }
        // Let the user update the installed bundle after an authorized copy.
        // Ownership and the outer directory's write bit do not change signed bytes.
        if geteuid() == 0 {
            guard try run(executable: URL(fileURLWithPath: "/usr/sbin/chown"), arguments: ["-R", "-P", "\(owner):\(group)", stagedBundle.path]) == 0 else { throw PortsideInstallationError.permissionDenied }
        }
        var permissions = stat()
        guard stat(stagedBundle.path, &permissions) == 0,
              chmod(stagedBundle.path, permissions.st_mode | S_IWUSR) == 0 else { throw fileError() }
        guard try validate(stagedBundle) == identity else { throw PortsideInstallationError.invalidSignature }
        try PortsideApplicationLaunchPreparation.prepare(stagedBundle, identity: identity, assess: assess, validate: validate)

        if let previousIdentity {
            // Revalidate immediately before exchanging directory entries. A
            // swap is atomic and retains every byte of the previous bundle.
            guard try validate(destination) == previousIdentity else { throw PortsideInstallationError.installationChanged }
            guard renamex_np(stagedBundle.path, destination.path, UInt32(RENAME_SWAP)) == 0 else { throw fileError() }
            preserveStage = true
            do {
                guard try validate(stagedBundle) == previousIdentity, try validate(destination) == identity else {
                    throw PortsideInstallationError.installationChanged
                }
            } catch {
                // Restore atomically on validation failure. If another actor
                // changed a bundle, leave both copies available for recovery.
                if (try? validate(destination)) == identity {
                    _ = renamex_np(stagedBundle.path, destination.path, UInt32(RENAME_SWAP))
                }
                throw error
            }
            // Retain the previous app beside the installation, with an exclusive
            // rename. If that fails, leave the private recovery copy intact.
            let backup = parent.appendingPathComponent(".Portside-Previous-\(UUID().uuidString).app", isDirectory: true)
            if renamex_np(stagedBundle.path, backup.path, UInt32(RENAME_EXCL)) == 0 { preserveStage = false }
            // Do not remove the backup or any runtime, prefixes, games or saves.
        } else {
            // RENAME_EXCL prevents races from replacing an application created
            // after the absence check; unlike mv it cannot nest an app bundle.
            guard renamex_np(stagedBundle.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { throw PortsideInstallationError.installationChanged }
                throw fileError()
            }
            guard try validate(destination) == identity else { throw PortsideInstallationError.invalidSignature }
        }
    }

    public static func ejectDiskImageAfterExit(processIdentifier: pid_t, source: URL) {
        guard processIdentifier > 1, processIdentifier != getpid(), let volume = diskImageVolume(containing: source) else { return }
        // The helper lives in the installed bundle, so it does not keep the
        // mounted image busy. Never force an unmount or eject another disk.
        let deadline = Date().addingTimeInterval(90)
        while kill(processIdentifier, 0) == 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        guard kill(processIdentifier, 0) != 0 else { return }
        _ = try? run(executable: URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["detach", volume.path], timeout: 15)
    }

    static func diskImageVolume(containing source: URL) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return nil }
        for image in images {
            guard (image["image-path"] as? String)?.lowercased().hasSuffix(".dmg") == true,
                  let entities = image["system-entities"] as? [[String: Any]] else { continue }
            for entity in entities {
                guard let path = entity["mount-point"] as? String else { continue }
                let volume = URL(fileURLWithPath: path, isDirectory: true)
                if source.standardizedFileURL == volume.standardizedFileURL || source.standardizedFileURL.path.hasPrefix(volume.standardizedFileURL.path + "/") { return volume }
                // App Translocation does not expose its original image through
                // public Bundle APIs. Do not infer that origin from a matching
                // app on another mounted image; an ambiguous image stays mounted.
            }
        }
        return nil
    }

    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func run(executable: URL, arguments: [String], timeout: TimeInterval = 300) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw PortsideInstallationError.helperUnavailable }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline { process.terminate(); throw PortsideInstallationError.copyFailed }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return process.terminationStatus
    }

    static func runAuthorization(appleScript: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw PortsideInstallationError.permissionDenied }
        let deadline = Date().addingTimeInterval(300)
        while process.isRunning {
            if Date() >= deadline { process.terminate(); throw PortsideInstallationError.permissionDenied }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // The AppleScript returns only the numeric status; never surface its
        // localized error message, command text or private source paths.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, data.count < 32,
              let result = Int32(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PortsideInstallationError.permissionDenied
        }
        return result == -128 ? 77 : result
    }

    private static func fileError() -> PortsideInstallationError {
        errno == EACCES || errno == EPERM || errno == EROFS ? .permissionDenied : .copyFailed
    }

    private static func mappedFileError(_ error: Error) -> PortsideInstallationError {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError { return .permissionDenied }
        return .copyFailed
    }
}
