import XCTest
@testable import PortsideCore

final class PortsideStorageMaintenanceTests: XCTestCase {
    func testMaintenanceBoundsReplaceableStorageAndPreservesManagedData() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let cache = root.appendingPathComponent("Cache", isDirectory: true)
        let pending = runtime.appendingPathComponent("Pending", isDirectory: true)
        let legacyBackups = root.appendingPathComponent("Backups", isDirectory: true)
        let diagnosticBackups = root.appendingPathComponent("Diagnostics/Backups", isDirectory: true)
        let prefix = root.appendingPathComponent("Prefixes/PortsideBaseline", isDirectory: true)
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        for directory in [runtime, cache, pending, legacyBackups, diagnosticBackups, prefix] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("steam account and save marker".utf8).write(to: prefix.appendingPathComponent("user-data"))
        defer { try? fileManager.removeItem(at: root) }

        let oldRollback = try makeDirectory(named: "rollback-old", in: runtime, modified: now.addingTimeInterval(-300))
        let newRollback = try makeDirectory(named: "rollback-new", in: runtime, modified: now.addingTimeInterval(-100))
        let oldFailed = try makeDirectory(named: "failed-old", in: runtime, modified: now.addingTimeInterval(-300))
        let newFailed = try makeDirectory(named: "failed-new", in: runtime, modified: now.addingTimeInterval(-100))
        let unrelatedRuntime = try makeDirectory(named: "release-metadata", in: runtime, modified: now.addingTimeInterval(-400))

        let staleCache = try makeDirectory(named: "portside-runtime-stale", in: cache, modified: now.addingTimeInterval(-PortsideStorageMaintenance.orphanMaximumAge - 1))
        let recentCache = try makeDirectory(named: "portside-runtime-current", in: cache, modified: now.addingTimeInterval(-60))
        let stalePending = try makeDirectory(named: ".pending-stale", in: pending, modified: now.addingTimeInterval(-PortsideStorageMaintenance.orphanMaximumAge - 1))
        let unrelatedCache = try makeDirectory(named: "Downloads", in: cache, modified: now.addingTimeInterval(-100_000))

        let oldBackup = try makeDirectory(named: "Steam-prefix-old", in: legacyBackups, modified: now.addingTimeInterval(-300))
        let newBackup = try makeDirectory(named: "Steam-prefix-new", in: diagnosticBackups, modified: now.addingTimeInterval(-100))

        let external = try makeDirectory(named: "external", in: root, modified: now.addingTimeInterval(-1_000))
        let rollbackLink = runtime.appendingPathComponent("rollback-link")
        try fileManager.createSymbolicLink(at: rollbackLink, withDestinationURL: external)

        let maintenance = PortsideStorageMaintenance(
            runtimeDirectory: runtime,
            cacheDirectory: cache,
            pendingDirectory: pending,
            legacyBackupDirectories: [legacyBackups, diagnosticBackups],
            fileManager: fileManager
        )
        let report = maintenance.run(now: now)

        XCTAssertEqual(report.removedRollbacks, 1)
        XCTAssertEqual(report.removedFailedWrappers, 1)
        XCTAssertEqual(report.removedTemporaryDirectories, 2)
        XCTAssertEqual(report.removedLegacyBackups, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: oldRollback.path))
        XCTAssertTrue(fileManager.fileExists(atPath: newRollback.path))
        XCTAssertFalse(fileManager.fileExists(atPath: oldFailed.path))
        XCTAssertTrue(fileManager.fileExists(atPath: newFailed.path))
        XCTAssertFalse(fileManager.fileExists(atPath: staleCache.path))
        XCTAssertTrue(fileManager.fileExists(atPath: recentCache.path))
        XCTAssertFalse(fileManager.fileExists(atPath: stalePending.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedRuntime.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedCache.path))
        XCTAssertFalse(fileManager.fileExists(atPath: oldBackup.path))
        XCTAssertTrue(fileManager.fileExists(atPath: newBackup.path))
        XCTAssertTrue(fileManager.fileExists(atPath: rollbackLink.path))
        XCTAssertTrue(fileManager.fileExists(atPath: external.path))
        XCTAssertEqual(try String(contentsOf: prefix.appendingPathComponent("user-data")), "steam account and save marker")
    }

    func testTimestampedHistoryNamesSortNewestFirst() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        try fileManager.createDirectory(at: runtime, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let olderName = PortsideStorageMaintenance.historyName(
            prefix: "rollback-",
            now: Date(timeIntervalSince1970: 2_000_000_000),
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let newerName = PortsideStorageMaintenance.historyName(
            prefix: "rollback-",
            now: Date(timeIntervalSince1970: 2_000_000_100),
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        try fileManager.createDirectory(at: runtime.appendingPathComponent(olderName), withIntermediateDirectories: true)
        let newer = runtime.appendingPathComponent(newerName)
        try fileManager.createDirectory(at: newer, withIntermediateDirectories: true)

        let maintenance = PortsideStorageMaintenance(
            runtimeDirectory: runtime,
            cacheDirectory: root.appendingPathComponent("Cache"),
            pendingDirectory: root.appendingPathComponent("Pending"),
            legacyBackupDirectories: [],
            fileManager: fileManager
        )

        XCTAssertEqual(
            maintenance.newestRollback()?.resolvingSymlinksInPath().standardizedFileURL,
            newer.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    @discardableResult
    private func makeDirectory(named name: String, in parent: URL, modified: Date) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }
}
