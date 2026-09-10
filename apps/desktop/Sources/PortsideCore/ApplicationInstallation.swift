import AppKit
import Darwin
import Foundation
import Security

public enum PortsideInstallationError: LocalizedError, Equatable {
    case permissionDenied
    case invalidSignature
    case invalidBundle
    case differentPublisher
    case newerInstallation
    case installationChanged
    case copyFailed
    case helperUnavailable
    case reopenFailed
    case alreadyMoving
    case launchNotApproved
    case launchPreparationFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Permission to install Portside in Applications was denied. Try again and approve the macOS authorization request."
        case .invalidSignature: return "The application’s signature could not be verified. Download a new copy of Portside from the official website."
        case .invalidBundle: return "The application’s identity or version could not be verified. Download a new copy of Portside from the official website."
        case .differentPublisher: return "The existing application was signed by a different publisher and cannot be replaced."
        case .newerInstallation: return "A newer version of Portside is already installed in Applications. Open that version to continue."
        case .installationChanged: return "The installation changed while Portside was being copied. No existing application was removed. Try again."
        case .copyFailed: return "Portside could not copy and verify the complete application. Check the available disk space and try again."
        case .helperUnavailable: return "The application’s installation helper is missing or invalid. Download a new copy of Portside from the official website."
        case .reopenFailed: return "Portside is installed, but macOS could not open it. Select Open Portside to try again."
        case .alreadyMoving: return "Portside is already being moved to Applications."
        case .launchNotApproved: return "macOS could not approve this copy of Portside. Connect to the internet and try again."
        case .launchPreparationFailed: return "Portside could not finish preparing the installed app. Try installing again."
        }
    }

    public var installerExitStatus: Int32 {
        switch self {
        case .permissionDenied: return 77
        case .invalidSignature: return 65
        case .invalidBundle: return 66
        case .differentPublisher: return 67
        case .newerInstallation: return 68
        case .installationChanged: return 69
        case .launchNotApproved: return 70
        case .launchPreparationFailed: return 71
        default: return 74
        }
    }

    static func from(exitStatus: Int32) -> Self {
        switch exitStatus {
        case 77: return .permissionDenied
        case 65: return .invalidSignature
        case 66: return .invalidBundle
        case 67: return .differentPublisher
        case 68: return .newerInstallation
        case 69: return .installationChanged
        case 70: return .launchNotApproved
        case 71: return .launchPreparationFailed
        default: return .copyFailed
        }
    }
}

public struct PortsideInstallationAssessment: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case diskImage, appTranslocation, readOnlyBundle, outsideApplications
    }
    public let isCommercialBuild: Bool
    public let reason: Reason?
    public var requiresMove: Bool { isCommercialBuild && reason != nil }

    public static func evaluate(bundleURL: URL, isCommercialBuild: Bool, isReadOnly: Bool, isDiskImage: Bool = false) -> Self {
        let path = bundleURL.standardizedFileURL.path
        let reason: Reason?
        if path.contains("/AppTranslocation/") { reason = .appTranslocation }
        else if isDiskImage || path.hasPrefix("/Volumes/") { reason = .diskImage }
        else if isReadOnly { reason = .readOnlyBundle }
        else if path != PortsideInstallationService.destination.path || bundleURL.resolvingSymlinksInPath().path != PortsideInstallationService.destination.path { reason = .outsideApplications }
        else { reason = nil }
        return Self(isCommercialBuild: isCommercialBuild, reason: reason)
    }
}

public struct PortsideSignedApplication: Equatable, Sendable {
    public let identifier: String
    public let teamIdentifier: String
    public let version: String
    public let buildVersion: String
    public let codeDirectoryHash: String

    public init(identifier: String, teamIdentifier: String, version: String, buildVersion: String, codeDirectoryHash: String) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.version = version
        self.buildVersion = buildVersion
        self.codeDirectoryHash = codeDirectoryHash
    }

    public func validateReplacement(of existing: Self) throws {
        guard identifier == existing.identifier else { throw PortsideInstallationError.invalidBundle }
        guard teamIdentifier == existing.teamIdentifier else { throw PortsideInstallationError.differentPublisher }
        let releaseComparison = version.compare(existing.version, options: .numeric)
        let buildComparison = buildVersion.compare(existing.buildVersion, options: .numeric)
        guard releaseComparison != .orderedAscending, buildComparison != .orderedAscending else {
            throw PortsideInstallationError.newerInstallation
        }
    }
}

public enum PortsideApplicationSignature {
    public static func validate(bundleURL: URL, expectedIdentifier: String = "com.portside.app") throws -> PortsideSignedApplication {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess, let code else {
            throw PortsideInstallationError.invalidSignature
        }
        // Require Developer ID, not merely any ad hoc or locally trusted signature.
        let requirementText = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess else {
            throw PortsideInstallationError.invalidSignature
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw PortsideInstallationError.invalidSignature }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              values[kSecCodeInfoIdentifier as String] as? String == expectedIdentifier,
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let hash = values[kSecCodeInfoUnique as String] as? Data else { throw PortsideInstallationError.invalidSignature }
        // NSBundle caches Info.plist by URL even after an atomic replacement.
        // Read the fresh, signature-validated plist from this SecStaticCode.
        guard let plist = values[kSecCodeInfoPList as String] as? [String: Any],
              plist["CFBundleIdentifier"] as? String == expectedIdentifier,
              let version = plist["CFBundleShortVersionString"] as? String,
              let build = plist["CFBundleVersion"] as? String,
              validVersion(version), validVersion(build) else { throw PortsideInstallationError.invalidBundle }
        return PortsideSignedApplication(identifier: expectedIdentifier, teamIdentifier: team, version: version, buildVersion: build, codeDirectoryHash: hash.map { String(format: "%02x", $0) }.joined())
    }

    private static func validVersion(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}

/// Injection boundary keeps all tests away from /Applications and LaunchServices.
@MainActor public protocol PortsideApplicationInstalling {
    func validate(_ url: URL) throws -> PortsideSignedApplication
    func exists(_ url: URL) -> Bool
    func install(source: URL, identity: PortsideSignedApplication) async throws
    func reopen(_ url: URL) async throws
    func scheduleDiskImageEjection(source: URL, installed: URL)
}

@MainActor public final class PortsideInstallationService {
    public nonisolated static let destination = URL(fileURLWithPath: "/Applications/Portside.app", isDirectory: true)
    private let bundle: Bundle
    private let installer: any PortsideApplicationInstalling
    private let logger: PortsideLogger
    private var isMoving = false

    public init(bundle: Bundle = .main, installer: (any PortsideApplicationInstalling)? = nil, logger: PortsideLogger = PortsideLogger()) {
        self.bundle = bundle
        self.installer = installer ?? PortsideSystemApplicationInstaller(bundle: bundle)
        self.logger = logger
    }

    public nonisolated static func isCommercialBuild(bundle: Bundle = .main) -> Bool {
        #if DEBUG
        return false
        #else
        // Missing configuration in a release bundle fails closed. Only the
        // development packaging script opts out through its signed Info.plist.
        return bundle.object(forInfoDictionaryKey: "PortsideBuildChannel") as? String != "development"
        #endif
    }

    public func inspect() -> PortsideInstallationAssessment {
        let values = try? bundle.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey, .isWritableKey])
        let readOnly = values?.volumeIsReadOnly == true || values?.isWritable != true
        let commercial = Self.isCommercialBuild(bundle: bundle)
        let diskImage = commercial && PortsideInstallationTransaction.diskImageVolume(containing: bundle.bundleURL) != nil
        let assessment = PortsideInstallationAssessment.evaluate(bundleURL: bundle.bundleURL, isCommercialBuild: commercial, isReadOnly: readOnly, isDiskImage: diskImage)
        if !assessment.isCommercialBuild {
            logger.write("Installation location validation skipped for a non-commercial development build.")
        } else {
            logger.write("Installation location check: \(assessment.reason?.rawValue ?? "installed in Applications").")
        }
        return assessment
    }

    /// Returns only after LaunchServices has opened the installed copy. The
    /// caller must then terminate this instance; the ejection helper waits for it.
    public func moveToApplicationsAndReopen(onOpening: () -> Void = {}) async throws {
        guard !isMoving else { throw PortsideInstallationError.alreadyMoving }
        isMoving = true
        defer { isMoving = false }
        let identity = try installer.validate(bundle.bundleURL)
        do {
            if installer.exists(Self.destination) {
                try identity.validateReplacement(of: installer.validate(Self.destination))
            }
            try await installer.install(source: bundle.bundleURL, identity: identity)
        } catch PortsideInstallationError.newerInstallation {
            // Also handle a newer app arriving between preflight and the
            // installation transaction. Revalidate it before automatic opening.
            onOpening()
            try await openInstalledApplication()
            logger.write("Newer installed Portside copy opened automatically.")
            return
        }
        let installed = try installer.validate(Self.destination)
        guard identity == installed else { throw PortsideInstallationError.installationChanged }
        onOpening()
        try await installer.reopen(Self.destination)
        logger.write("Installed Portside copy opened successfully; the installer instance can now exit.")
        installer.scheduleDiskImageEjection(source: bundle.bundleURL, installed: Self.destination)
    }

    public func hasNewerInstalledApplication() throws -> Bool {
        guard installer.exists(Self.destination) else { return false }
        let source = try installer.validate(bundle.bundleURL)
        let installed = try installer.validate(Self.destination)
        do {
            try source.validateReplacement(of: installed)
            return false
        } catch PortsideInstallationError.newerInstallation {
            // A higher release with a lower build (or another publisher) is
            // not an eligible destination for this automatic handoff.
            try installed.validateReplacement(of: source)
            return true
        }
    }

    public func openInstalledApplication() async throws {
        let source = try installer.validate(bundle.bundleURL)
        let installed = try installer.validate(Self.destination)
        try installed.validateReplacement(of: source)
        try await installer.reopen(Self.destination)
        installer.scheduleDiskImageEjection(source: bundle.bundleURL, installed: Self.destination)
    }
}

@MainActor private final class PortsideSystemApplicationInstaller: PortsideApplicationInstalling {
    private let bundle: Bundle
    init(bundle: Bundle) { self.bundle = bundle }

    func validate(_ url: URL) throws -> PortsideSignedApplication { try PortsideApplicationSignature.validate(bundleURL: url) }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func install(source: URL, identity: PortsideSignedApplication) async throws {
        guard let helper = bundle.url(forAuxiliaryExecutable: "PortsideInstaller") else { throw PortsideInstallationError.helperUnavailable }
        let owner = getuid(), group = getgid()
        let arguments = ["--install", source.path, identity.codeDirectoryHash, String(owner), String(group)]
        let status = try await Task.detached { try PortsideInstallationTransaction.run(executable: helper, arguments: arguments) }.value
        PortsideLogger().write("application_install_helper_finished status=\(status)")
        if status == 0 { return }
        guard status == PortsideInstallationError.permissionDenied.installerExitStatus else { throw PortsideInstallationError.from(exitStatus: status) }
        // Copy into a root-owned private directory BEFORE executing elevated
        // code, then validate the complete signed bundle against the hash the
        // unprivileged caller inspected. A writable source cannot inject code
        // into the privileged operation after that verification.
        let helperRelativePath = helper.path.replacingOccurrences(of: source.path + "/", with: "")
        guard helperRelativePath == "Contents/MacOS/PortsideInstaller" else { throw PortsideInstallationError.helperUnavailable }
        let quote = PortsideInstallationTransaction.shellQuote
        let script = """
        set -eu
        umask 077
        installer_stage=$(/usr/bin/mktemp -d /private/tmp/portside-installer.XXXXXXXX)
        trap '/bin/rm -rf "$installer_stage"' EXIT
        /usr/bin/ditto --rsrc --extattr --acl \(quote(source.path)) "$installer_stage/Portside.app" || exit 74
        /usr/bin/codesign --verify --deep --strict -R \(quote("cdhash H\"\(identity.codeDirectoryHash)\"")) "$installer_stage/Portside.app" >/dev/null 2>&1 || exit 65
        "$installer_stage/Portside.app/Contents/MacOS/PortsideInstaller" --install "$installer_stage/Portside.app" \(quote(identity.codeDirectoryHash)) \(owner) \(group)
        """
        let appleScript = """
        try
            do shell script \(Self.appleScriptString(script)) with administrator privileges with prompt \(Self.appleScriptString("Portside needs permission to install in Applications."))
            return 0
        on error errorMessage number errorNumber
            return errorNumber
        end try
        """
        let result = try await Task.detached { try PortsideInstallationTransaction.runAuthorization(appleScript: appleScript) }.value
        guard result == 0 else { throw PortsideInstallationError.from(exitStatus: result) }
    }

    func reopen(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        do {
            let application = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            guard !application.isTerminated, application.bundleURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() else { throw PortsideInstallationError.reopenFailed }
        } catch { throw PortsideInstallationError.reopenFailed }
    }

    func scheduleDiskImageEjection(source: URL, installed: URL) {
        guard let installedBundle = Bundle(url: installed),
              let helper = installedBundle.url(forAuxiliaryExecutable: "PortsideInstaller") else { return }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--eject-after-exit", String(getpid()), source.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}
