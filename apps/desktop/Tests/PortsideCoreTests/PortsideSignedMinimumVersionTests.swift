import CryptoKit
import XCTest
@testable import PortsideCore

private final class ManifestResponse: @unchecked Sendable {
    let lock = NSLock()
    private var stored: Data?
    var data: Data? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

private final class ManifestProtocol: URLProtocol, @unchecked Sendable {
    static let response = ManifestResponse()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let data = Self.response.data else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PortsideSignedMinimumVersionTests: XCTestCase {
    func testSignedBlockRemainsMandatoryWhenUpdatingCacheFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let key = Curve25519.Signing.PrivateKey()
        try manifest(version: "1.0", minimum: "1.0", key: key).write(to: directory.appendingPathComponent("runtime-manifest.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManifestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = try PortsideBackendClient(configuration: .init(
            baseURL: URL(string: "https://updates.portside.test"), allowedHosts: ["updates.portside.test"],
            runtimeManifestPublicKey: key.publicKey.rawRepresentation.base64EncodedString()
        ), session: session, manifestDirectory: directory)
        ManifestProtocol.response.data = try manifest(version: "2.0", minimum: "2.0", key: key)

        do {
            _ = try await client.fetchRuntimeManifest(currentVersion: "1.0")
            XCTFail("A cache write error must not discard a newly authenticated version block")
        } catch {
            XCTAssertEqual(error as? PortsideCommercialError, .incompatibleVersion)
        }
    }

    func testSignedBlockSurvivesOldCacheAndOfflineLaunchWithoutOpeningSteam() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Curve25519.Signing.PrivateKey()
        let old = try manifest(version: "1.0", minimum: "1.0", key: key)
        try old.write(to: directory.appendingPathComponent("runtime-manifest.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManifestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = try PortsideBackendClient(configuration: .init(
            baseURL: URL(string: "https://updates.portside.test"),
            allowedHosts: ["updates.portside.test"],
            runtimeManifestPublicKey: key.publicKey.rawRepresentation.base64EncodedString()
        ), session: session, manifestDirectory: directory)

        ManifestProtocol.response.data = try manifest(version: "2.0", minimum: "2.0", key: key)
        for offline in [false, true] {
            if offline { ManifestProtocol.response.data = nil }
            do {
                _ = try await client.fetchRuntimeManifest(currentVersion: "1.0")
                XCTFail("A signed blocked version must never reach runtime or Steam")
            } catch {
                XCTAssertEqual(error as? PortsideCommercialError, .incompatibleVersion)
            }
        }
        let updated = try await client.fetchRuntimeManifest(currentVersion: "2.0")
        XCTAssertEqual(updated.minimumPortsideVersion, "2.0")
    }

    private func manifest(version: String, minimum: String, key: Curve25519.Signing.PrivateKey) throws -> Data {
        var value: [String: Any] = [
            "schemaVersion": 1, "channel": "production", "manifestVersion": version,
            "minimumPortsideVersion": minimum, "publishedAt": "2026-08-19T00:00:00Z",
            "components": ["wrapper", "engine", "winetricks"].map { name -> [String: Any] in
                ["id": name, "component": name, "version": version,
                 "downloadURL": "https://updates.portside.test/\(name).tar.xz",
                 "sha256": String(repeating: "a", count: 64), "size": 10, "critical": false,
                 "builtBy": "Portside", "sourcePath": "vendor/\(name)",
                 "sourceCommit": String(repeating: "b", count: 40),
                 "sourceSnapshotChecksum": String(repeating: "c", count: 64), "license": "LGPL-2.1-or-later"]
            },
            "rendererDefaults": [:], "compatibilityRules": [], "critical": true,
            "signatureKeyId": "test", "signature": NSNull()
        ]
        value["signature"] = try key.signature(for: PortsideCanonicalJSON.data(from: value)).base64EncodedString()
        return try JSONSerialization.data(withJSONObject: value)
    }
}
