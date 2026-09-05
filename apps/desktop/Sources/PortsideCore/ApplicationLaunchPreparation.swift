import Darwin
import Foundation

/// Runs only on the private staged copy, before it replaces the installed app.
/// Copying a downloaded bundle preserves quarantine and can make LaunchServices
/// translocate it again even after installation into Applications.
enum PortsideApplicationLaunchPreparation {
    static func assess(_ bundle: URL) throws {
        let status = try PortsideInstallationTransaction.run(
            executable: URL(fileURLWithPath: "/usr/sbin/spctl"),
            arguments: ["--assess", "--type", "execute", bundle.path],
            timeout: 60
        )
        guard status == 0 else { throw PortsideInstallationError.launchNotApproved }
    }

    static func prepare(
        _ bundle: URL,
        identity: PortsideSignedApplication,
        assess: (URL) throws -> Void,
        validate: (URL) throws -> PortsideSignedApplication
    ) throws {
        guard try validate(bundle) == identity else { throw PortsideInstallationError.invalidSignature }
        // Keep Gatekeeper's policy decision, including notarization/revocation,
        // in front of any change to the downloaded copy's quarantine metadata.
        try assess(bundle)
        guard try validate(bundle) == identity else { throw PortsideInstallationError.installationChanged }

        var info = stat()
        guard lstat(bundle.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw PortsideInstallationError.invalidBundle
        }
        var enumerationFailed = false
        guard let entries = FileManager.default.enumerator(
            at: bundle,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            errorHandler: { _, _ in enumerationFailed = true; return false }
        ) else { throw PortsideInstallationError.copyFailed }

        try releaseQuarantine(bundle)
        for case let entry as URL in entries {
            // Never follow bundle symlinks into another app or user data.
            if try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { continue }
            try releaseQuarantine(entry)
        }
        guard !enumerationFailed else { throw PortsideInstallationError.copyFailed }
        guard try validate(bundle) == identity else { throw PortsideInstallationError.invalidSignature }
    }

    private static func releaseQuarantine(_ url: URL) throws {
        // Preserve resource forks, ACLs, and every unrelated extended attribute.
        if removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0, errno != ENOATTR {
            throw PortsideInstallationError.launchPreparationFailed
        }
    }
}
