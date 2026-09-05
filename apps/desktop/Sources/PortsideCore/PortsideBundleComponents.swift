import Foundation
import Security

/// Resolves executable URLs from each bundle's metadata. Only the custom
/// embedded-agent directory is part of Portside's packaging contract; executable
/// filenames and standard bundle directories are resolved by Foundation.
public enum PortsideBundleComponents {
    public static func agent(in application: Bundle = .main, fileManager: FileManager = .default) throws -> URL {
        let nestedURL = application.bundleURL.appendingPathComponent("Contents/Helpers/PortsideAgent.app", isDirectory: true)
        guard let nested = Bundle(url: nestedURL) else {
            throw rejection(bundleURL: application.bundleURL, helperURL: nestedURL, reason: "The embedded Portside agent bundle could not be loaded", fileManager: fileManager)
        }
        return try executable(in: nested, expectedIdentifier: "com.portside.agent", container: application.bundleURL, fileManager: fileManager)
    }

    public static func runtimeHost(in wrapper: URL, fileManager: FileManager = .default) throws -> URL {
        guard let bundle = Bundle(url: wrapper) else {
            throw rejection(bundleURL: wrapper, helperURL: nil, reason: "The Portside runtime bundle could not be loaded", fileManager: fileManager)
        }
        return try executable(in: bundle, expectedIdentifier: "com.portside.runtime", container: wrapper, fileManager: fileManager)
    }

    private static func executable(in bundle: Bundle, expectedIdentifier: String, container: URL, fileManager: FileManager) throws -> URL {
        let executable = bundle.executableURL
        let reason: String?
        if bundle.bundleIdentifier != expectedIdentifier {
            reason = "The helper bundle identifier does not match \(expectedIdentifier)"
        } else if executable == nil {
            reason = "The helper executable could not be resolved from CFBundleExecutable"
        } else if !executable!.resolvingSymlinksInPath().path.hasPrefix(container.resolvingSymlinksInPath().path + "/") {
            reason = "The helper executable resolves outside its containing bundle"
        } else if !fileManager.isExecutableFile(atPath: executable!.path) {
            reason = "The helper executable is missing or is not executable"
        } else {
            reason = nil
        }
        if let reason {
            throw rejection(bundleURL: bundle.bundleURL, helperURL: executable, reason: reason, fileManager: fileManager)
        }
        return executable!.standardizedFileURL
    }

    private static func rejection(bundleURL: URL, helperURL: URL?, reason: String, fileManager: FileManager) -> PortsideBundleComponentError {
        let exists = helperURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let signature = helperURL.map(signatureStatus) ?? "not_checked:no_executable_url"
        let diagnostic = PortsideLogger.sanitize(
            "notInBundle bundle_url=\(bundleURL.absoluteString) helper_url=\(helperURL?.absoluteString ?? "unresolved") file_exists=\(exists) signature=\(signature) reason=\(reason)"
        )
        PortsideLogger().write(diagnostic, level: .error)
        return PortsideBundleComponentError(reason: reason, diagnostic: diagnostic)
    }

    public static func signatureStatus(at url: URL) -> String {
        var code: SecStaticCode?
        let creation = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard creation == errSecSuccess, let code else { return "unavailable:OSStatus=\(creation)" }
        let validation = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil)
        return validation == errSecSuccess ? "valid" : "invalid:OSStatus=\(validation)"
    }
}

public struct PortsideBundleComponentError: LocalizedError, Sendable {
    public let reason: String
    public let diagnostic: String
    public var errorDescription: String? { "Portside could not locate a required component. \(reason)." }
}
