import Foundation
import CryptoKit

public final class PortsideBackendClient: @unchecked Sendable {
    private let configuration: PortsideBackendConfiguration
    private let session: URLSession
    private let downloader: SecureDownloader

    public init(configuration: PortsideBackendConfiguration, session: URLSession = .shared) throws {
        guard configuration.isConfigured, let baseURL = configuration.baseURL, baseURL.scheme == "https", baseURL.user == nil, baseURL.password == nil else { throw PortsideCommercialError.backendUnavailable }
        self.configuration = configuration
        self.session = session
        self.downloader = SecureDownloader(allowedHosts: configuration.allowedHosts)
    }

    public func fetchRuntimeManifest(currentVersion: String) async throws -> PortsideRuntimeManifest {
        guard let publicKey = configuration.runtimeManifestPublicKey else { throw PortsideCommercialError.invalidSignature }
        let cachedData = try? Data(contentsOf: PortsidePaths.runtimeManifest)
        let cachedManifest = cachedData.flatMap { try? PortsideManifestVerifier.verify($0, publicKeyBase64: publicKey, expectedChannel: expectedChannel, currentVersion: currentVersion, allowedHosts: configuration.allowedHosts) }
        let etag = try? String(contentsOf: PortsidePaths.runtimeManifestETag, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await requestResponse(path: "/v1/runtime/manifest", headers: etag.map { ["If-None-Match": $0] } ?? [:])
            if response.status == 304, let cachedManifest { return cachedManifest }
            guard (200..<300).contains(response.status), response.status != 304 else { throw PortsideCommercialError.backendUnavailable }
            let manifest = try PortsideManifestVerifier.verify(response.data, publicKeyBase64: publicKey, expectedChannel: expectedChannel, currentVersion: currentVersion, allowedHosts: configuration.allowedHosts)
            if let cachedManifest,
               PortsideManifestVerifier.compareVersions(manifest.manifestVersion, cachedManifest.manifestVersion) < 0,
               manifest.rollbackVersion != cachedManifest.manifestVersion {
                throw PortsideCommercialError.invalidManifest("runtime update would downgrade the installed release")
            }
            try FileManager.default.createDirectory(at: PortsidePaths.manifests, withIntermediateDirectories: true)
            try response.data.write(to: PortsidePaths.runtimeManifest, options: .atomic)
            if let responseETag = response.headers["etag"] {
                try responseETag.write(to: PortsidePaths.runtimeManifestETag, atomically: true, encoding: .utf8)
            } else { try? FileManager.default.removeItem(at: PortsidePaths.runtimeManifestETag) }
            return manifest
        } catch {
            // A verified cached manifest keeps an existing installation usable
            // while the service is offline or temporarily unavailable. Invalid
            // network data is never written over that cache.
            if let cachedManifest { return cachedManifest }
            throw error
        }
    }

    public func downloadBaselineArtifacts(currentVersion: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [PortsideRuntimeArtifact: URL] {
        let manifest = try await fetchRuntimeManifest(currentVersion: currentVersion)
        return try await downloadArtifacts(manifest: manifest, to: PortsidePaths.downloads, progress: progress)
    }

    public func downloadArtifacts(manifest: PortsideRuntimeManifest, to directory: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [PortsideRuntimeArtifact: URL] {
        var result: [PortsideRuntimeArtifact: URL] = [:]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, component) in manifest.components.enumerated() {
            guard PortsideRuntimeCatalog.requiredComponents.contains(component.component) else {
                throw PortsideCommercialError.invalidManifest("required runtime component is missing")
            }
            guard let host = component.downloadURL.host, configuration.allowedHosts.contains(host) else { throw PortsideCommercialError.unauthorizedURL }
            let destination = directory.appendingPathComponent(component.downloadURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try IntegrityVerifier.verify(url: destination, expectedSHA256: component.sha256, expectedSize: component.size)
            } else {
                _ = try await downloader.download(from: component.downloadURL, to: destination, expectedSHA256: component.sha256, expectedSize: component.size)
            }
            result[PortsideRuntimeArtifact(component: component)] = destination
            progress(Double(index + 1) / Double(manifest.components.count))
        }
        return result
    }

    public func signedArtifactURL(id: String) async throws -> URL {
        let data = try await request(path: "/v1/artifacts/\(id)/download")
        struct Response: Decodable { let url: URL }
        let response = try JSONDecoder.portside.decode(Response.self, from: data)
        guard let host = response.url.host, configuration.allowedHosts.contains(host), response.url.scheme == "https" else { throw PortsideCommercialError.unauthorizedURL }
        return response.url
    }

    private struct HTTPResponse {
        let data: Data
        let status: Int
        let headers: [String: String]
    }

    private func request(path: String) async throws -> Data {
        let response = try await requestResponse(path: path, headers: [:])
        guard (200..<300).contains(response.status) else { throw PortsideCommercialError.backendUnavailable }
        return response.data
    }

    private func requestResponse(path: String, headers: [String: String]) async throws -> HTTPResponse {
        guard let baseURL = configuration.baseURL else { throw PortsideCommercialError.backendUnavailable }
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard url.host == baseURL.host, url.scheme == "https" else { throw PortsideCommercialError.unauthorizedURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PortsideCommercialError.backendUnavailable }
        let responseHeaders = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key.lowercased()] = value }
        }
        return HTTPResponse(data: data, status: http.statusCode, headers: responseHeaders)
    }

    private var expectedChannel: String? {
        configuration.buildChannel == "production" ? "production" : nil
    }
}

public struct PortsideActivationResult: Codable, Equatable, Sendable {
    public let token: String
    public let deviceId: String
    public let offlineUntil: Date
}

public final class PortsideLicenseClient: @unchecked Sendable {
    private let configuration: PortsideBackendConfiguration
    private let session: URLSession
    private let keyStore: PortsideLicenseKeyStore
    private let tokenStore: PortsideLicenseTokenStore

    public init(configuration: PortsideBackendConfiguration, session: URLSession = .shared, keyStore: PortsideLicenseKeyStore = PortsideLicenseKeyStore(), tokenStore: PortsideLicenseTokenStore = PortsideLicenseTokenStore()) {
        self.configuration = configuration; self.session = session; self.keyStore = keyStore; self.tokenStore = tokenStore
    }

    public func activate(licenseKey: String) async throws -> PortsideActivationResult {
        let key = try keyStore.publicKeyAndCreateIfNeeded()
        let response: ActivationResponse = try await request(path: "/v1/licenses/activate", body: ["licenseKey": licenseKey, "publicKey": key.base64EncodedString()])
        let verified = try Self.verifyActivationResponse(
            token: response.token,
            deviceID: response.deviceId,
            offlineUntil: response.offlineUntil,
            publicKeyBase64: configuration.licensePublicKey,
            expectedKeyID: configuration.licenseKeyID
        )
        // Never persist network data until its server signature and device
        // binding have been verified locally.
        try tokenStore.save(response.token)
        return PortsideActivationResult(token: response.token, deviceId: verified.deviceId, offlineUntil: verified.offlineUntil)
    }

    public func validate(allowOffline: Bool = true) async throws -> PortsideLicenseToken {
        guard let token = try tokenStore.load(), !token.isEmpty else { throw PortsideCommercialError.invalidLicenseToken }
        let decoded = try Self.verifyLocal(token: token, publicKeyBase64: configuration.licensePublicKey, expectedKeyID: configuration.licenseKeyID, allowExpired: true)
        if allowOffline && decoded.offlineUntil > Date() { return decoded }
        let challenge: ChallengeResponse = try await request(path: "/v1/licenses/challenge", body: ["licenseId": decoded.licenseId, "deviceId": decoded.deviceId])
        let signature = try keyStore.sign(Data(challenge.challenge.utf8)).base64EncodedString()
        struct ValidateResponse: Decodable { let valid: Bool; let offlineUntil: Date; let token: String }
        let result: ValidateResponse = try await request(path: "/v1/licenses/validate", body: ["token": token, "challenge": challenge.challenge, "signature": signature])
        guard result.valid else { throw PortsideCommercialError.invalidLicenseToken }
        let refreshed = try Self.verifyLocal(token: result.token, publicKeyBase64: configuration.licensePublicKey, expectedKeyID: configuration.licenseKeyID)
        guard refreshed.licenseId == decoded.licenseId,
              refreshed.deviceId == decoded.deviceId,
              abs(refreshed.offlineUntil.timeIntervalSince(result.offlineUntil)) <= 1 else {
            throw PortsideCommercialError.invalidLicenseToken
        }
        try tokenStore.save(result.token)
        return refreshed
    }

    public func deactivate(licenseKey: String, deviceID: String) async throws {
        struct Empty: Decodable {}
        _ = try await request(path: "/v1/licenses/deactivate", body: ["licenseKey": licenseKey, "deviceId": deviceID]) as Empty
        try? tokenStore.clear()
    }

    public static func verifyLocal(token: String, publicKeyBase64: String?, expectedKeyID: String?, allowExpired: Bool = false) throws -> PortsideLicenseToken {
        guard let publicKeyBase64,
              let keyData = licensePublicKeyData(publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw PortsideCommercialError.invalidLicenseToken }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let signature = base64URLData(String(parts[2])),
              publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)),
              let payload = base64URLData(String(parts[1])) else { throw PortsideCommercialError.invalidLicenseToken }
        let decoded = try JSONDecoder.portside.decode(LicensePayload.self, from: payload)
        if let expectedKeyID, decoded.keyId != expectedKeyID { throw PortsideCommercialError.invalidLicenseToken }
        guard (allowExpired || Date(timeIntervalSince1970: TimeInterval(decoded.offlineUntil)) > Date()), decoded.expiresAt >= decoded.offlineUntil else { throw PortsideCommercialError.invalidLicenseToken }
        return PortsideLicenseToken(licenseId: decoded.licenseId, deviceId: decoded.deviceId, plan: decoded.plan, issuedAt: Date(timeIntervalSince1970: TimeInterval(decoded.issuedAt)), expiresAt: Date(timeIntervalSince1970: TimeInterval(decoded.expiresAt)), offlineUntil: Date(timeIntervalSince1970: TimeInterval(decoded.offlineUntil)), keyId: decoded.keyId)
    }

    private static func licensePublicKeyData(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]), raw.count == 32 {
            return raw
        }

        let pemBody = trimmed
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN ED25519 PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END ED25519 PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: pemBody) else { return nil }

        // SubjectPublicKeyInfo for Ed25519: algorithm identifier followed by
        // the 32-byte raw public key. Require the exact prefix and length so
        // arbitrary PEM/DER data is never accepted as a license key.
        let ed25519SPKIPrefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])
        guard der.count == ed25519SPKIPrefix.count + 32,
              der.prefix(ed25519SPKIPrefix.count) == ed25519SPKIPrefix else { return nil }
        return Data(der.suffix(32))
    }

    private static func base64URLData(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    public static func verifyActivationResponse(token: String, deviceID: String, offlineUntil: Date, publicKeyBase64: String?, expectedKeyID: String?) throws -> PortsideLicenseToken {
        let decoded = try verifyLocal(token: token, publicKeyBase64: publicKeyBase64, expectedKeyID: expectedKeyID)
        guard decoded.deviceId == deviceID,
              abs(decoded.offlineUntil.timeIntervalSince(offlineUntil)) <= 1 else {
            throw PortsideCommercialError.invalidLicenseToken
        }
        return decoded
    }

    private struct ActivationResponse: Decodable { let token: String; let deviceId: String; let offlineUntil: Date }
    private struct ChallengeResponse: Decodable { let challenge: String; let expiresAt: Date }
    private struct LicensePayload: Decodable { let licenseId: String; let deviceId: String; let plan: String; let issuedAt: Int; let expiresAt: Int; let offlineUntil: Int; let keyId: String }

    private func request<T: Decodable>(path: String, body: [String: String]) async throws -> T {
        guard let baseURL = configuration.baseURL, let host = baseURL.host else { throw PortsideCommercialError.backendUnavailable }
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard url.scheme == "https", url.host == host else { throw PortsideCommercialError.unauthorizedURL }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 30; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PortsideCommercialError.backendUnavailable }
        return try JSONDecoder.portside.decode(T.self, from: data)
    }
}
