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
        let data = try await request(path: "/v1/runtime/manifest")
        guard let publicKey = configuration.runtimeManifestPublicKey else { throw PortsideCommercialError.invalidSignature }
        return try PortsideManifestVerifier.verify(data, publicKeyBase64: publicKey, currentVersion: currentVersion, allowedHosts: configuration.allowedHosts)
    }

    public func downloadBaselineArtifacts(currentVersion: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [SikarugirArtifact: URL] {
        let manifest = try await fetchRuntimeManifest(currentVersion: currentVersion)
        let expected = [SikarugirOfficialCatalog.template, SikarugirOfficialCatalog.engine, SikarugirOfficialCatalog.winetricks]
        var result: [SikarugirArtifact: URL] = [:]
        for (index, artifact) in expected.enumerated() {
            guard let component = manifest.components.first(where: { $0.component == artifact.identifier || $0.id == artifact.identifier }) else {
                throw PortsideCommercialError.invalidManifest("required runtime component is missing")
            }
            guard let host = component.downloadURL.host, configuration.allowedHosts.contains(host) else { throw PortsideCommercialError.unauthorizedURL }
            let destination = PortsidePaths.downloads.appendingPathComponent(component.downloadURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try IntegrityVerifier.verify(url: destination, expectedSHA256: component.sha256, expectedSize: component.size)
            } else {
                _ = try await downloader.download(from: component.downloadURL, to: destination, expectedSHA256: component.sha256, expectedSize: component.size)
            }
            result[artifact] = destination
            progress(Double(index + 1) / Double(expected.count))
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

    private func request(path: String) async throws -> Data {
        guard let baseURL = configuration.baseURL else { throw PortsideCommercialError.backendUnavailable }
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard url.host == baseURL.host, url.scheme == "https" else { throw PortsideCommercialError.unauthorizedURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PortsideCommercialError.backendUnavailable }
        return data
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
        try tokenStore.save(response.token)
        return PortsideActivationResult(token: response.token, deviceId: response.deviceId, offlineUntil: response.offlineUntil)
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
        try tokenStore.save(result.token)
        return try Self.verifyLocal(token: result.token, publicKeyBase64: configuration.licensePublicKey, expectedKeyID: configuration.licenseKeyID)
    }

    public func deactivate(licenseKey: String, deviceID: String) async throws {
        struct Empty: Decodable {}
        _ = try await request(path: "/v1/licenses/deactivate", body: ["licenseKey": licenseKey, "deviceId": deviceID]) as Empty
        try? tokenStore.clear()
    }

    public static func verifyLocal(token: String, publicKeyBase64: String?, expectedKeyID: String?, allowExpired: Bool = false) throws -> PortsideLicenseToken {
        guard let publicKeyBase64, let keyData = Data(base64Encoded: publicKeyBase64, options: [.ignoreUnknownCharacters]), let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw PortsideCommercialError.invalidLicenseToken }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let signature = Data(base64Encoded: String(parts[2]), options: [.ignoreUnknownCharacters]), publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)), let payload = Data(base64Encoded: String(parts[1]), options: [.ignoreUnknownCharacters]) else { throw PortsideCommercialError.invalidLicenseToken }
        let decoded = try JSONDecoder.portside.decode(LicensePayload.self, from: payload)
        if let expectedKeyID, decoded.keyId != expectedKeyID { throw PortsideCommercialError.invalidLicenseToken }
        guard (allowExpired || Date(timeIntervalSince1970: TimeInterval(decoded.offlineUntil)) > Date()), decoded.expiresAt >= decoded.offlineUntil else { throw PortsideCommercialError.invalidLicenseToken }
        return PortsideLicenseToken(licenseId: decoded.licenseId, deviceId: decoded.deviceId, plan: decoded.plan, issuedAt: Date(timeIntervalSince1970: TimeInterval(decoded.issuedAt)), expiresAt: Date(timeIntervalSince1970: TimeInterval(decoded.expiresAt)), offlineUntil: Date(timeIntervalSince1970: TimeInterval(decoded.offlineUntil)), keyId: decoded.keyId)
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
