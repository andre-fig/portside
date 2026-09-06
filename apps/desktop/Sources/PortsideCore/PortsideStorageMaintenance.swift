import Foundation

public struct PortsideStorageMaintenanceReport: Equatable, Sendable {
    public var removedRollbacks = 0
    public var removedFailedWrappers = 0
    public var removedTemporaryDirectories = 0
    public var removedLegacyBackups = 0

    public init() {}

    public var removedItemCount: Int {
        removedRollbacks + removedFailedWrappers + removedTemporaryDirectories + removedLegacyBackups
    }
}

/// Bounds replaceable Portside storage without entering the managed Steam
/// prefix or game library. Callers must first establish that the active wrapper
/// is valid so that cleanup never removes the only recovery candidate.
public final class PortsideStorageMaintenance: @unchecked Sendable {
    public static let orphanMaximumAge: TimeInterval = 24 * 60 * 60

    private let runtimeDirectory: URL
    private let cacheDirectory: URL
    private let pendingDirectory: URL
    private let legacyBackupDirectories: [URL]
    private let fileManager: FileManager

    public init(
        runtimeDirectory: URL = PortsidePaths.runtime,
        cacheDirectory: URL = PortsidePaths.cache,
        pendingDirectory: URL = PortsidePaths.runtimePending,
        legacyBackupDirectories: [URL] = [
            PortsidePaths.root.appendingPathComponent("Backups", isDirectory: true),
            PortsidePaths.backups
        ],
        fileManager: FileManager = .default
    ) {
        self.runtimeDirectory = runtimeDirectory
        self.cacheDirectory = cacheDirectory
        self.pendingDirectory = pendingDirectory
        self.legacyBackupDirectories = legacyBackupDirectories
        self.fileManager = fileManager
    }

    public func run(now: Date = Date()) -> PortsideStorageMaintenanceReport {
        var report = PortsideStorageMaintenanceReport()
        report.removedRollbacks = pruneDirectChildren(
            in: runtimeDirectory,
            prefix: "rollback-",
            retaining: 1
        )
        report.removedFailedWrappers = pruneDirectChildren(
            in: runtimeDirectory,
            prefix: "failed-",
            retaining: 1
        )
        report.removedTemporaryDirectories += removeStaleDirectChildren(
            in: cacheDirectory,
            prefix: "portside-runtime-",
            olderThan: now.addingTimeInterval(-Self.orphanMaximumAge)
        )
        report.removedTemporaryDirectories += removeStaleDirectChildren(
            in: pendingDirectory,
            prefix: ".pending-",
            olderThan: now.addingTimeInterval(-Self.orphanMaximumAge)
        )
        report.removedLegacyBackups = pruneAcrossDirectories(
            legacyBackupDirectories,
            prefix: "Steam-prefix-",
            retaining: 1
        )
        return report
    }

    public static func historyName(prefix: String, now: Date = Date(), identifier: UUID = UUID()) -> String {
        let milliseconds = Int64(now.timeIntervalSince1970 * 1_000)
        return "\(prefix)\(milliseconds)-\(identifier.uuidString)"
    }

    public func newestRollback() -> URL? {
        sortedCandidates(in: runtimeDirectory, prefix: "rollback-").first?.url
    }

    private struct Candidate {
        let url: URL
        let date: Date
    }

    private func pruneDirectChildren(in directory: URL, prefix: String, retaining count: Int) -> Int {
        remove(Array(sortedCandidates(in: directory, prefix: prefix).dropFirst(max(0, count))))
    }

    private func pruneAcrossDirectories(_ directories: [URL], prefix: String, retaining count: Int) -> Int {
        let candidates = directories.flatMap { sortedCandidates(in: $0, prefix: prefix) }
            .sorted(by: newestFirst)
        return remove(Array(candidates.dropFirst(max(0, count))))
    }

    private func removeStaleDirectChildren(in directory: URL, prefix: String, olderThan cutoff: Date) -> Int {
        remove(sortedCandidates(in: directory, prefix: prefix).filter { $0.date < cutoff })
    }

    private func remove(_ candidates: [Candidate]) -> Int {
        var removed = 0
        for candidate in candidates {
            do {
                try fileManager.removeItem(at: candidate.url)
                removed += 1
            } catch {
                // Storage maintenance is best effort and must not block startup.
            }
        }
        return removed
    }

    private func sortedCandidates(in directory: URL, prefix: String) -> [Candidate] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        return ((try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        )) ?? []).compactMap { url in
            guard url.lastPathComponent.hasPrefix(prefix),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { return nil }
            return Candidate(
                url: url,
                date: timestamp(in: url.lastPathComponent, prefix: prefix)
                    ?? values.contentModificationDate
                    ?? .distantPast
            )
        }.sorted(by: newestFirst)
    }

    private func newestFirst(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.url.lastPathComponent > rhs.url.lastPathComponent
    }

    private func timestamp(in name: String, prefix: String) -> Date? {
        let suffix = name.dropFirst(prefix.count)
        guard let firstComponent = suffix.split(separator: "-", maxSplits: 1).first,
              let milliseconds = Int64(firstComponent),
              milliseconds >= 1_000_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}
