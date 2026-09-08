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

    public enum RuntimeIntegration: String, Sendable { case directWine, sikarugir }

    public static func runtimeIntegration(in wrapper: URL, fileManager: FileManager = .default) throws -> RuntimeIntegration {
        let resource = wrapper.appendingPathComponent("Contents/Resources/portside-runtime.json")
        let attributes: [FileAttributeKey: Any]
        do { attributes = try fileManager.attributesOfItem(atPath: resource.path) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) { return .directWine }
            throw rejection(bundleURL: wrapper, helperURL: resource, reason: "The runtime integration configuration could not be inspected", fileManager: fileManager)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              resource.resolvingSymlinksInPath().path.hasPrefix(wrapper.resolvingSymlinksInPath().path + "/"),
              (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 16_384,
              let data = try? Data(contentsOf: resource),
              let configuration = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw rejection(bundleURL: wrapper, helperURL: resource, reason: "The runtime integration configuration is invalid", fileManager: fileManager)
        }
        guard let value = configuration["integration"] else { return .directWine }
        guard let name = value as? String, let integration = RuntimeIntegration(rawValue: name) else {
            throw rejection(bundleURL: wrapper, helperURL: resource, reason: "The runtime integration is unsupported", fileManager: fileManager)
        }
        return integration
    }

    public static func runtimeLauncher(in wrapper: URL, fileManager: FileManager = .default) throws -> URL {
        guard let bundle = Bundle(url: wrapper) else {
            throw rejection(bundleURL: wrapper, helperURL: nil, reason: "The Portside runtime bundle could not be loaded", fileManager: fileManager)
        }
        let primary = try executable(in: bundle, expectedIdentifier: "com.portside.runtime", container: wrapper, fileManager: fileManager)
        if try runtimeIntegration(in: wrapper, fileManager: fileManager) == .sikarugir {
            guard primary.resolvingSymlinksInPath().lastPathComponent == "Sikarugir" else {
                throw rejection(bundleURL: wrapper, helperURL: primary, reason: "Sikarugir must remain the runtime application entry point", fileManager: fileManager)
            }
            _ = try containedRuntimeExecutable("Contents/Frameworks/SikarugirSdk.framework/Versions/A/SikarugirSdk", in: wrapper, fileManager: fileManager)
        }
        return primary
    }

    public static func runtimeHost(in wrapper: URL, fileManager: FileManager = .default) throws -> URL {
        let primary = try runtimeLauncher(in: wrapper, fileManager: fileManager)
        if try runtimeIntegration(in: wrapper, fileManager: fileManager) == .sikarugir {
            return try containedRuntimeExecutable("Contents/MacOS/PortsideRuntimeHost", in: wrapper, fileManager: fileManager)
        }
        return primary
    }

    private static func containedRuntimeExecutable(_ relative: String, in wrapper: URL, fileManager: FileManager) throws -> URL {
        let candidate = wrapper.appendingPathComponent(relative)
        guard candidate.resolvingSymlinksInPath().path.hasPrefix(wrapper.resolvingSymlinksInPath().path + "/"),
              fileManager.isExecutableFile(atPath: candidate.path) else {
            throw rejection(bundleURL: wrapper, helperURL: candidate, reason: "A required runtime component is missing or resolves outside the wrapper", fileManager: fileManager)
        }
        return candidate
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
