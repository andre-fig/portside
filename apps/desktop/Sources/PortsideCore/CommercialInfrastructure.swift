import Foundation
import CryptoKit
import Security
import CoreFoundation

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
    public let builtBy: String?
    public let sourcePath: String?
    public let sourceCommit: String?
    public let sourceSnapshotChecksum: String?
    public let license: String?
    public let buildId: String?
    public let sbom: String?

    public init(id: String, component: String, version: String, downloadURL: URL, sha256: String, size: Int64, critical: Bool = false, rollbackVersion: String? = nil, builtBy: String? = nil, sourcePath: String? = nil, sourceCommit: String? = nil, sourceSnapshotChecksum: String? = nil, license: String? = nil, buildId: String? = nil, sbom: String? = nil) {
        self.id = id; self.component = component; self.version = version; self.downloadURL = downloadURL; self.sha256 = sha256; self.size = size; self.critical = critical; self.rollbackVersion = rollbackVersion
        self.builtBy = builtBy; self.sourcePath = sourcePath; self.sourceCommit = sourceCommit; self.sourceSnapshotChecksum = sourceSnapshotChecksum; self.license = license; self.buildId = buildId; self.sbom = sbom
    }
}

enum PortsideCanonicalJSON {
    enum Error: Swift.Error {
        case unsupportedValue
        case invalidObject
    }

    static func data(from value: Any) throws -> Data {
        guard let string = try serialize(value) else { throw Error.unsupportedValue }
        return Data(string.utf8)
    }

    static func unsignedManifestData(from data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.invalidObject
        }
        object["signature"] = NSNull()
        return try self.data(from: object)
    }

    private static func serialize(_ value: Any) throws -> String? {
        if value is NSNull { return "null" }
        if let value = value as? String { return try serializeString(value) }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return value.boolValue ? "true" : "false"
            }
            let data = try JSONSerialization.data(withJSONObject: [value], options: [])
            let string = String(decoding: data, as: UTF8.self)
            return String(string.dropFirst().dropLast())
        }
        if let value = value as? Bool { return value ? "true" : "false" }
        if let value = value as? [Any] {
            let values = try value.map { try serialize($0).unwrap(or: Error.unsupportedValue) }
            return "[\(values.joined(separator: ","))]"
        }
        if let value = value as? [String: Any] {
            let entries = try value.keys.sorted().map { key -> String in
                let keyJSON = try serializeString(key)
                let valueJSON = try serialize(value[key].unwrap(or: Error.unsupportedValue)).unwrap(or: Error.unsupportedValue)
                return "\(keyJSON):\(valueJSON)"
            }
            return "{\(entries.joined(separator: ","))}"
        }
        return nil
    }

    private static func serializeString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [])
        let string = String(decoding: data, as: UTF8.self)
        return String(string.dropFirst().dropLast()).replacingOccurrences(of: "\\/", with: "/")
    }
}

private struct FlexibleManifestString: Codable, Equatable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = String(value)
        } else if let value = try? container.decode(Double.self) {
            self.value = String(value)
        } else if let value = try? container.decode(Bool.self) {
            self.value = String(value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a text, number or boolean value")
            )
        }
    }

    init(_ value: String) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, channel, manifestVersion, minimumPortsideVersion, publishedAt
        case components, rendererDefaults, compatibilityRules, critical, rollbackVersion
        case signatureKeyId, signature
    }

    public init(schemaVersion: Int, channel: String, manifestVersion: String, minimumPortsideVersion: String, publishedAt: Date, components: [PortsideRuntimeComponent], rendererDefaults: [String: String], compatibilityRules: [[String: String]], critical: Bool, rollbackVersion: String?, signatureKeyId: String, signature: String) {
        self.schemaVersion = schemaVersion; self.channel = channel; self.manifestVersion = manifestVersion; self.minimumPortsideVersion = minimumPortsideVersion; self.publishedAt = publishedAt; self.components = components; self.rendererDefaults = rendererDefaults; self.compatibilityRules = compatibilityRules; self.critical = critical; self.rollbackVersion = rollbackVersion; self.signatureKeyId = signatureKeyId; self.signature = signature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        channel = try container.decode(String.self, forKey: .channel)
        manifestVersion = try container.decode(String.self, forKey: .manifestVersion)
        minimumPortsideVersion = try container.decode(String.self, forKey: .minimumPortsideVersion)
        publishedAt = try container.decode(Date.self, forKey: .publishedAt)
        components = try container.decode([PortsideRuntimeComponent].self, forKey: .components)
        let flexibleDefaults = try container.decode([String: FlexibleManifestString].self, forKey: .rendererDefaults)
        rendererDefaults = flexibleDefaults.mapValues(\.value)
        compatibilityRules = try container.decode([[String: String]].self, forKey: .compatibilityRules)
        critical = try container.decode(Bool.self, forKey: .critical)
        rollbackVersion = try container.decodeIfPresent(String.self, forKey: .rollbackVersion)
        signatureKeyId = try container.decode(String.self, forKey: .signatureKeyId)
        signature = try container.decode(String.self, forKey: .signature)
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
        let unsigned = try PortsideCanonicalJSON.unsignedManifestData(from: data)
        guard publicKey.isValidSignature(signature, for: unsigned) else { throw PortsideCommercialError.invalidSignature }
        guard compareVersions(currentVersion, manifest.minimumPortsideVersion) >= 0 else { throw PortsideCommercialError.incompatibleVersion }
        guard !allowedHosts.isEmpty else { throw PortsideCommercialError.unauthorizedURL }
        var identifiers = Set<String>()
        guard manifest.components.count == PortsideRuntimeCatalog.requiredComponents.count,
              Set(manifest.components.map(\.component)) == Set(PortsideRuntimeCatalog.requiredComponents) else {
            throw PortsideCommercialError.invalidManifest("the runtime manifest must contain wrapper, engine and winetricks")
        }
        for component in manifest.components {
            guard identifiers.insert(component.id).inserted else { throw PortsideCommercialError.invalidManifest("manifest contains a duplicate component") }
            guard !component.downloadURL.absoluteString.contains("example.invalid") else { throw PortsideCommercialError.invalidManifest("manifest contains a placeholder download") }
            guard component.downloadURL.scheme == "https", let host = component.downloadURL.host, allowedHosts.contains(host), component.sha256.count == 64, component.sha256.allSatisfy(\.isHexDigit), component.size > 0, component.builtBy == "Portside", component.sourcePath?.isEmpty == false, component.sourceCommit?.isEmpty == false, component.sourceSnapshotChecksum?.isEmpty == false, component.license?.isEmpty == false else { throw PortsideCommercialError.invalidManifest("component is incomplete, not Portside-built, or outside the Portside host allowlist") }
            guard !component.downloadURL.absoluteString.localizedCaseInsensitiveContains("sikarugir"), !component.downloadURL.absoluteString.localizedCaseInsensitiveContains("raw.githubusercontent.com") else { throw PortsideCommercialError.unauthorizedURL }
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
