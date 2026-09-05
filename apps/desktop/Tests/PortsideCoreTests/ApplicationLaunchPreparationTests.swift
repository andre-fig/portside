import Darwin
import XCTest
@testable import PortsideCore

final class ApplicationLaunchPreparationTests: XCTestCase {
    private let identity = PortsideSignedApplication(identifier: "com.portside.app", teamIdentifier: "TEST", version: "1", buildVersion: "1", codeDirectoryHash: "test")

    func testApprovedCopyReleasesQuarantineWithoutChangingSourceOtherMetadataOrSymlinkTargets() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Portside.app")
        let external = root.appendingPathComponent("unrelated.txt")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("user data".utf8).write(to: external)
        let nested = source.appendingPathComponent("Helper")
        try Data("helper".utf8).write(to: nested)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("external"), withDestinationURL: external)
        for url in [source, nested, external] { try setAttribute("com.apple.quarantine", value: "0081;12345678;PortsideTests;", at: url) }
        try setAttribute("com.portside.test", value: "preserved", at: source)
        var assessedPaths: [URL] = []
        try PortsideInstallationTransaction.perform(source: source, destination: destination, identity: identity, owner: getuid(), group: getgid(), assess: { staged in
            assessedPaths.append(staged)
            XCTAssertNotNil(self.attribute("com.apple.quarantine", at: staged))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }, validate: { _ in self.identity })
        XCTAssertEqual(assessedPaths.count, 1)
        XCTAssertNotEqual(assessedPaths.first, source)
        XCTAssertNil(attribute("com.apple.quarantine", at: destination))
        XCTAssertNil(attribute("com.apple.quarantine", at: destination.appendingPathComponent("Helper")))
        XCTAssertNotNil(attribute("com.apple.quarantine", at: source))
        XCTAssertNotNil(attribute("com.apple.quarantine", at: nested))
        XCTAssertNotNil(attribute("com.apple.quarantine", at: external))
        XCTAssertEqual(attribute("com.portside.test", at: destination), "preserved")
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), "user data")
    }

    func testGatekeeperRejectionLeavesExistingInstallationAndSourceUntouched() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Portside.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("previous app".utf8).write(to: destination.appendingPathComponent("marker"))
        try setAttribute("com.apple.quarantine", value: "0081;12345678;PortsideTests;", at: source)
        XCTAssertThrowsError(try PortsideInstallationTransaction.perform(source: source, destination: destination, identity: identity, owner: getuid(), group: getgid(), assess: { _ in
            throw PortsideInstallationError.launchNotApproved
        }, validate: { _ in self.identity })) {
            XCTAssertEqual($0 as? PortsideInstallationError, .launchNotApproved)
        }
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8), "previous app")
        XCTAssertNotNil(attribute("com.apple.quarantine", at: source))
    }

    func testInvalidSignatureNeverReleasesQuarantineOrCallsGatekeeper() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try setAttribute("com.apple.quarantine", value: "0081;12345678;PortsideTests;", at: root)
        XCTAssertThrowsError(try PortsideApplicationLaunchPreparation.prepare(root, identity: identity, assess: { _ in
            XCTFail("Unverified code reached Gatekeeper preparation")
        }, validate: { _ in throw PortsideInstallationError.invalidSignature })) {
            XCTAssertEqual($0 as? PortsideInstallationError, .invalidSignature)
        }
        XCTAssertNotNil(attribute("com.apple.quarantine", at: root))
    }

    func testChangedSignatureAfterAssessmentNeverReleasesQuarantine() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try setAttribute("com.apple.quarantine", value: "0081;12345678;PortsideTests;", at: root)
        var assessed = false
        XCTAssertThrowsError(try PortsideApplicationLaunchPreparation.prepare(root, identity: identity, assess: { _ in assessed = true }, validate: { _ in
            if assessed { throw PortsideInstallationError.invalidSignature }
            return self.identity
        }))
        XCTAssertNotNil(attribute("com.apple.quarantine", at: root))
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PortsideLaunchPreparation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func setAttribute(_ name: String, value: String, at url: URL) throws {
        let data = Data(value.utf8)
        let status = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        guard status == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private func attribute(_ name: String, at url: URL) -> String? {
        let count = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard count >= 0 else { return nil }
        var data = Data(count: count)
        let actual = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, count, 0, XATTR_NOFOLLOW) }
        guard actual >= 0 else { return nil }
        return String(decoding: data.prefix(actual), as: UTF8.self)
    }
}
