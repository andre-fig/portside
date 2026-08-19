import XCTest
@testable import PortsideCore

final class PortsideCoreTests: XCTestCase {
    func testAppleSiliconRequirementAcceptsEnoughStorage() throws {
        let requirements = SystemRequirements(architecture: "arm64", macOSVersion: "macOS 26", availableStorage: 20_000_000_000)
        XCTAssertNoThrow(try requirements.validate())
    }

    func testRequirementRejectsIntel() {
        let requirements = SystemRequirements(architecture: "x86_64", macOSVersion: "macOS 26", availableStorage: 20_000_000_000)
        XCTAssertThrowsError(try requirements.validate()) { XCTAssertEqual($0 as? PortsideError, .unsupportedArchitecture("x86_64")) }
    }

    func testRequirementRejectsLowStorage() {
        let requirements = SystemRequirements(architecture: "arm64", macOSVersion: "macOS 26", availableStorage: 1)
        XCTAssertThrowsError(try requirements.validate())
    }

    func testSanitizerRedactsSecrets() {
        let sanitized = PortsideLogger.sanitize("password=secret token:abc123 bearer abc.def")
        XCTAssertFalse(sanitized.contains("secret")); XCTAssertFalse(sanitized.contains("abc123")); XCTAssertFalse(sanitized.contains("abc.def"))
    }

    func testProfileStoreRejectsPathTraversal() throws {
        let store = ProfileStore()
        XCTAssertNil(store.load(appID: "../123"))
        XCTAssertThrowsError(try store.save(CompatibilityProfile(appID: "../123", name: "Unsafe")))
    }

    func testSteamInstallerIsHTTPSAndOfficialHost() {
        XCTAssertEqual(SteamInstaller.officialURL.scheme, "https")
        XCTAssertEqual(SteamInstaller.officialURL.host, "cdn.cloudflare.steamstatic.com")
    }

    func testCompatibilityProfileKeepsUnprofiledGamesAllowedByDesign() {
        let profile = ProfileStore().load(appID: "3139440")
        XCTAssertNil(profile)
        // Absence of a profile is intentionally not an execution denial.
    }
}
