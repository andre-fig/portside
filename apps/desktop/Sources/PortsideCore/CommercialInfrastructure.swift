import Foundation
import CryptoKit
import Security

public struct PortsideBackendConfiguration: Sendable, Equatable {
    public let baseURL: URL?
    public let allowedHosts: Set<String>
    public let runtimeManifestPublicKey: String?
    public let licensePublicKey: String?
    public let licenseKeyID: String?
    public let buildChannel: String

    public init(baseURL: URL?, allowedHosts: Set<String> = [], runtimeManifestPublicKey: String? = nil, licensePublicKey: String? = nil, licenseKeyID: String? = nil, buildChannel: String = "production") {
        self.baseURL = baseURL
        self.allowedHosts = allowedHosts
        self.runtimeManifestPublicKey = runtimeManifestPublicKey
        self.licensePublicKey = licensePublicKey
        self.licenseKeyID = licenseKeyID
        self.buildChannel = buildChannel
    }

    public var isConfigured: Bool { baseURL != nil && !(allowedHosts.isEmpty) }

    public static func fromBundle(_ bundle: Bundle = .main) -> Self {
        let rawURL = (bundle.object(forInfoDictionaryKey: "PortsideAPIBaseURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = rawURL.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        let artifactHosts = ((bundle.object(forInfoDictionaryKey: "PortsideArtifactHosts") as? String) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let host = Set((url?.host.map { [$0] } ?? []) + artifactHosts)
        func value(_ key: String) -> String? {
            let value = (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        return Self(baseURL: url, allowedHosts: host, runtimeManifestPublicKey: value("PortsideRuntimeManifestPublicKey"), licensePublicKey: value("PortsideLicensePublicKey"), licenseKeyID: value("PortsideLicenseKeyID"), buildChannel: value("PortsideBuildChannel") ?? "production")
    }
}

public enum PortsideCommercialError: LocalizedError, Equatable {
    case backendUnavailable
    case invalidManifest(String)
    case invalidSignature
    case incompatibleVersion
    case unauthorizedURL
    case invalidLicenseToken
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .backendUnavailable: return "Portside services are temporarily unavailable."
        case .invalidManifest(let reason): return "The Portside update information is invalid: \(reason)"
        case .invalidSignature: return "The Portside update signature is invalid."
        case .incompatibleVersion: return "This update is not compatible with this version of Portside."
        case .unauthorizedURL: return "The download address is not approved for Portside."
        case .invalidLicenseToken: return "The Portside license could not be validated."
        case .keychainFailure(let status): return "Secure local storage failed (\(status))."
        }
    }
}

public enum PortsideAppUpdateConfiguration {
    public static func isConfigured(feed: String?, publicKey: String?) -> Bool {
        let feed = feed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !feed.isEmpty && !publicKey.isEmpty && !feed.contains("example.invalid")
    }
}

public struct PortsideRuntimeComponent: Codable, Equatable, Sendable {
    public let id: String
    public let component: String
    public let version: String
    public let downloadURL: URL
    public let sha256: String
    public let size: Int64
    public let critical: Bool
    public let rollbackVersion: String?

    public init(id: String, component: String, version: String, downloadURL: URL, sha256: String, size: Int64, critical: Bool = false, rollbackVersion: String? = nil) {
        self.id = id; self.component = component; self.version = version; self.downloadURL = downloadURL; self.sha256 = sha256; self.size = size; self.critical = critical; self.rollbackVersion = rollbackVersion
    }
}

public struct PortsideRuntimeManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let channel: String
    public let manifestVersion: String
    public let minimumPortsideVersion: String
    public let publishedAt: Date
    public let components: [PortsideRuntimeComponent]
    public let rendererDefaults: [String: String]
    public let compatibilityRules: [[String: String]]
    public let critical: Bool
    public let rollbackVersion: String?
    public let signatureKeyId: String
    public let signature: String

    public init(schemaVersion: Int, channel: String, manifestVersion: String, minimumPortsideVersion: String, publishedAt: Date, components: [PortsideRuntimeComponent], rendererDefaults: [String: String], compatibilityRules: [[String: String]], critical: Bool, rollbackVersion: String?, signatureKeyId: String, signature: String) {
        self.schemaVersion = schemaVersion; self.channel = channel; self.manifestVersion = manifestVersion; self.minimumPortsideVersion = minimumPortsideVersion; self.publishedAt = publishedAt; self.components = components; self.rendererDefaults = rendererDefaults; self.compatibilityRules = compatibilityRules; self.critical = critical; self.rollbackVersion = rollbackVersion; self.signatureKeyId = signatureKeyId; self.signature = signature
    }
}

public enum PortsideManifestVerifier {
    public static func verify(_ data: Data, publicKeyBase64: String, expectedKeyID: String? = nil, expectedChannel: String? = nil, currentVersion: String, allowedHosts: Set<String> = []) throws -> PortsideRuntimeManifest {
        let decoder = JSONDecoder.portside
        let manifest = try decoder.decode(PortsideRuntimeManifest.self, from: data)
        if let expectedKeyID, manifest.signatureKeyId != expectedKeyID { throw PortsideCommercialError.invalidSignature }
        if let expectedChannel, manifest.channel != expectedChannel { throw PortsideCommercialError.invalidManifest("manifest channel is not approved for this build") }
        let signature = try Data(base64Encoded: manifest.signature, options: [.ignoreUnknownCharacters]).unwrap(or: PortsideCommercialError.invalidSignature)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKeyBase64, options: [.ignoreUnknownCharacters]).unwrap(or: PortsideCommercialError.invalidSignature))
        var unsigned = data
        if var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object["signature"] = NSNull()
            unsigned = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        guard publicKey.isValidSignature(signature, for: unsigned) else { throw PortsideCommercialError.invalidSignature }
        guard compareVersions(currentVersion, manifest.minimumPortsideVersion) >= 0 else { throw PortsideCommercialError.incompatibleVersion }
        guard !allowedHosts.isEmpty else { throw PortsideCommercialError.unauthorizedURL }
        var identifiers = Set<String>()
        for component in manifest.components {
            guard identifiers.insert(component.id).inserted else { throw PortsideCommercialError.invalidManifest("manifest contains a duplicate component") }
            guard !component.downloadURL.absoluteString.contains("example.invalid") else { throw PortsideCommercialError.invalidManifest("manifest contains a placeholder download") }
            guard component.downloadURL.scheme == "https", let host = component.downloadURL.host, allowedHosts.contains(host), !component.sha256.isEmpty, component.size > 0 else { throw PortsideCommercialError.invalidManifest("component is incomplete or outside the Portside host allowlist") }
        }
        return manifest
    }

    public static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) { let a = index < left.count ? left[index] : 0; let b = index < right.count ? right[index] : 0; if a != b { return a < b ? -1 : 1 } }
        return 0
    }

    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compareVersions(candidate, installed) > 0
    }
}

public struct PortsideLicenseToken: Codable, Equatable, Sendable {
    public let licenseId: String
    public let deviceId: String
    public let plan: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let offlineUntil: Date
    public let keyId: String
}

public final class PortsideLicenseKeyStore: @unchecked Sendable {
    private let service = "com.portside.license.device-key"
    private let account = "device"

    public init() {}

    public func publicKeyAndCreateIfNeeded() throws -> Data {
        if let existing = try loadPrivateKey() {
            guard let publicKey = SecKeyCopyPublicKey(existing), let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw PortsideCommercialError.keychainFailure(errSecDecode) }
            return data
        }
        let privateAttrs: [CFString: Any] = [
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: service.data(using: .utf8)!,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: false
        ]
        var attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: privateAttrs
        ]
        var error: Unmanaged<CFError>?
        var key: SecKey?
        if SecureEnclave.isAvailable {
            attributes[kSecAttrTokenID] = kSecAttrTokenIDSecureEnclave
            key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
        }
        if key == nil {
            attributes.removeValue(forKey: kSecAttrTokenID)
            error = nil
            key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
        }
        let keychainStatus: OSStatus = error.map { OSStatus(CFErrorGetCode($0.takeRetainedValue())) } ?? errSecParam
        guard let key else { throw PortsideCommercialError.keychainFailure(keychainStatus) }
        guard let publicKey = SecKeyCopyPublicKey(key), let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw PortsideCommercialError.keychainFailure(errSecDecode) }
        return data
    }

    public func sign(_ message: Data) throws -> Data {
        guard let key = try loadPrivateKey() else { throw PortsideCommercialError.keychainFailure(errSecItemNotFound) }
        var error: Unmanaged<CFError>?
        let signatureRef = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, message as CFData, &error)
        let keychainStatus: OSStatus = error.map { OSStatus(CFErrorGetCode($0.takeRetainedValue())) } ?? errSecParam
        guard let signatureRef, let signature = signatureRef as Data? else { throw PortsideCommercialError.keychainFailure(keychainStatus) }
        return signature
    }

    private func loadPrivateKey() throws -> SecKey? {
        let query: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: service.data(using: .utf8)!, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let result else { throw PortsideCommercialError.keychainFailure(status) }
        return (result as! SecKey)
    }

}

public final class PortsideLicenseTokenStore: @unchecked Sendable {
    private let service = "com.portside.license.token"
    public init() {}
    public func save(_ token: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "current"]
        SecItemDelete(query as CFDictionary)
        var item = query; item[kSecValueData] = Data(token.utf8); item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; item[kSecAttrSynchronizable] = false
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw PortsideCommercialError.keychainFailure(status) }
    }
    public func load() throws -> String? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "current", kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }; guard status == errSecSuccess, let data = result as? Data else { throw PortsideCommercialError.keychainFailure(status) }; return String(data: data, encoding: .utf8)
    }
    public func clear() throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "current"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PortsideCommercialError.keychainFailure(status) }
    }
}

private extension Optional {
    func unwrap<E: Error>(or error: @autoclosure () -> E) throws -> Wrapped { guard let value = self else { throw error() }; return value }
}
