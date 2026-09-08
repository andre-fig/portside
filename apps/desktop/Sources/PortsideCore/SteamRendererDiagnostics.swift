import Foundation

/// Reads only new, timestamped GPU diagnostics from the selected prefix. No
/// credential files or raw log content enter reports. Create BEFORE launching.
public final class SteamRendererDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private let file: URL
    private let prefix: URL
    private let started: Date
    private var identity: UInt64?
    private var offset: UInt64 = 0
    private var partial = Data()
    private var failedAt: Date?

    public init(prefix: URL, started: Date = Date()) {
        self.prefix = prefix.resolvingSymlinksInPath()
        file = self.prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs/webhelper_gpu.txt")
        self.started = started
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           attrs[.type] as? FileAttributeType == .typeRegular {
            identity = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
            offset = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        }
    }

    public func currentFailure(now: Date = Date()) -> SteamLaunchFailure? {
        lock.lock()
        defer { lock.unlock() }
        guard file.resolvingSymlinksInPath().path.hasPrefix(prefix.path + "/"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              attrs[.type] as? FileAttributeType == .typeRegular,
              let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        if identity != inode || size < offset {
            identity = inode; offset = 0; partial.removeAll(); failedAt = nil
        }
        // Bound IO and refuse an incomplete leading line when catching up.
        if size - offset > 262_144 {
            offset = size - 262_144; partial.removeAll()
            try? handle.seek(toOffset: offset)
            if let chunk = try? handle.read(upToCount: 262_144) {
                offset += UInt64(chunk.count)
                if let newline = chunk.firstIndex(of: 10) { partial.append(chunk.suffix(from: chunk.index(after: newline))) }
            }
        } else {
            try? handle.seek(toOffset: offset)
            if let chunk = try? handle.read(upToCount: 262_144) { offset += UInt64(chunk.count); partial.append(chunk) }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        while let newline = partial.firstIndex(of: 10) {
            let line = String(decoding: partial.prefix(upTo: newline), as: UTF8.self)
            partial.removeSubrange(...newline)
            guard line.hasPrefix("["), line.count >= 21,
                  let date = formatter.date(from: String(line.dropFirst().prefix(19))),
                  date.timeIntervalSince1970 >= floor(started.timeIntervalSince1970), date <= now.addingTimeInterval(1) else { continue }
            if line.contains("GPU process started:") { failedAt = nil }
            if line.contains("[ GL implementation parts ]: (gl=egl-angle,angle=") {
                failedAt = nil
            }
            if line.contains("GPU process was unable to boot:") { failedAt = date }
        }
        if partial.count > 65_536 { partial.removeAll() }
        // A fresh process restart clears a failed attempt. Generic EGL errors
        // and historical GPU reports are never themselves a terminal failure.
        guard let failedAt, now.timeIntervalSince(failedAt) >= 3 else { return nil }
        return .rendererInitializationFailed
    }
}
