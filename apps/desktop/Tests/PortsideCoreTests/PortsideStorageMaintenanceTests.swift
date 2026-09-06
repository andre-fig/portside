import XCTest
@testable import PortsideCore

final class PortsideStorageMaintenanceTests: XCTestCase {
    func testMaintenanceBoundsReplaceableStorageAndPreservesManagedData() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let cache = root.appendingPathComponent("Cache", isDirectory: true)
        let downloads = cache.appendingPathComponent("Downloads", isDirectory: true)
        let legacyDownloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let pending = runtime.appendingPathComponent("Pending", isDirectory: true)
        let legacyBackups = root.appendingPathComponent("Backups", isDirectory: true)
        let diagnosticBackups = root.appendingPathComponent("Diagnostics/Backups", isDirectory: true)
        let prefix = root.appendingPathComponent("Prefixes/PortsideBaseline", isDirectory: true)
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        for directory in [runtime, cache, downloads, legacyDownloads, pending, legacyBackups, diagnosticBackups, prefix] {
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
        let staleDownload = try makeFile(named: "old-runtime.tar.xz", in: downloads, modified: now.addingTimeInterval(-PortsideStorageMaintenance.orphanMaximumAge - 1))
        let recentDownload = try makeFile(named: "current-runtime.tar.xz", in: downloads, modified: now.addingTimeInterval(-60))
        let staleDownloadDirectory = try makeDirectory(named: "abandoned-download", in: downloads, modified: now.addingTimeInterval(-PortsideStorageMaintenance.orphanMaximumAge - 1))
        let staleLegacyDownload = try makeFile(named: "old-installer.pkg", in: legacyDownloads, modified: now.addingTimeInterval(-PortsideStorageMaintenance.orphanMaximumAge - 1))

        let oldBackup = try makeDirectory(named: "Steam-prefix-old", in: legacyBackups, modified: now.addingTimeInterval(-300))
        let newBackup = try makeDirectory(named: "Steam-prefix-new", in: diagnosticBackups, modified: now.addingTimeInterval(-100))

        let external = try makeDirectory(named: "external", in: root, modified: now.addingTimeInterval(-1_000))
        let rollbackLink = runtime.appendingPathComponent("rollback-link")
        try fileManager.createSymbolicLink(at: rollbackLink, withDestinationURL: external)
        let downloadLink = downloads.appendingPathComponent("external-link")
        try fileManager.createSymbolicLink(at: downloadLink, withDestinationURL: external)

        let maintenance = PortsideStorageMaintenance(
            runtimeDirectory: runtime,
            cacheDirectory: cache,
            pendingDirectory: pending,
            downloadDirectories: [downloads, legacyDownloads],
            legacyBackupDirectories: [legacyBackups, diagnosticBackups],
            fileManager: fileManager
        )
        let report = maintenance.run(now: now)

        XCTAssertEqual(report.removedRollbacks, 1)
        XCTAssertEqual(report.removedFailedWrappers, 1)
        XCTAssertEqual(report.removedTemporaryDirectories, 2)
        XCTAssertEqual(report.removedCachedDownloads, 3)
        XCTAssertEqual(report.removedLegacyBackups, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: oldRollback.path))
        XCTAssertTrue(fileManager.fileExists(atPath: newRollback.path))
        XCTAssertFalse(fileManager.fileExists(atPath: oldFailed.path))
        XCTAssertTrue(fileManager.fileExists(atPath: newFailed.path))
        XCTAssertFalse(fileManager.fileExists(atPath: staleCache.path))
        XCTAssertTrue(fileManager.fileExists(atPath: recentCache.path))
        XCTAssertFalse(fileManager.fileExists(atPath: stalePending.path))
        XCTAssertFalse(fileManager.fileExists(atPath: staleDownload.path))
        XCTAssertTrue(fileManager.fileExists(atPath: recentDownload.path))
        XCTAssertFalse(fileManager.fileExists(atPath: staleDownloadDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: staleLegacyDownload.path))
        XCTAssertTrue(fileManager.fileExists(atPath: downloadLink.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedRuntime.path))
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

    func testLegacySecondTimestampSortsAheadOfOlderUUIDFallback() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        try fileManager.createDirectory(at: runtime, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        _ = try makeDirectory(
            named: "rollback-00000000-0000-0000-0000-000000000001",
            in: runtime,
            modified: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let legacyNewest = try makeDirectory(
            named: "rollback-2000000000",
            in: runtime,
            modified: Date(timeIntervalSince1970: 1_600_000_000)
        )
        let maintenance = PortsideStorageMaintenance(
            runtimeDirectory: runtime,
            cacheDirectory: root.appendingPathComponent("Cache"),
            pendingDirectory: root.appendingPathComponent("Pending"),
            downloadDirectories: [],
            legacyBackupDirectories: [],
            fileManager: fileManager
        )

        XCTAssertEqual(
            maintenance.newestRollback()?.resolvingSymlinksInPath().standardizedFileURL,
            legacyNewest.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    func testArchivedEpochModificationDateFallsBackToAttributeDate() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        try fileManager.createDirectory(at: runtime, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let archivedNewest = try makeDirectory(
            named: "rollback-00000000-0000-0000-0000-000000000002",
            in: runtime,
            modified: Date(timeIntervalSince1970: 0)
        )
        _ = try makeDirectory(
            named: "rollback-older",
            in: runtime,
            modified: Date().addingTimeInterval(-3_600)
        )
        let maintenance = PortsideStorageMaintenance(
            runtimeDirectory: runtime,
            cacheDirectory: root.appendingPathComponent("Cache"),
            pendingDirectory: root.appendingPathComponent("Pending"),
            downloadDirectories: [],
            legacyBackupDirectories: [],
            fileManager: fileManager
        )

        XCTAssertEqual(
            maintenance.newestRollback()?.resolvingSymlinksInPath().standardizedFileURL,
            archivedNewest.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    @discardableResult
    private func makeDirectory(named name: String, in parent: URL, modified: Date) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    private func makeFile(named name: String, in parent: URL, modified: Date) throws -> URL {
        let url = parent.appendingPathComponent(name)
        try Data("replaceable download".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }
}
