import Foundation

/// Reads only new, timestamped renderer diagnostics from the selected prefix. No
/// credential files or raw log content enter reports. Create BEFORE launching.
public final class SteamRendererDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private let gpu: LogCursor
    private let cef: LogCursor
    private let started: Date
    private var initializationFailedAt: Date?
    private var presentationFailedAt: Date?
    private var restartedAt: Date?
    private var initializedAt: Date?

    public init(prefix: URL, started: Date = Date()) {
        let root = prefix.resolvingSymlinksInPath()
        gpu = LogCursor(prefix: root, name: "webhelper_gpu.txt")
        cef = LogCursor(prefix: root, name: "cef_log.txt")
        self.started = started
    }

    public func currentFailure(now: Date = Date()) -> SteamLaunchFailure? {
        lock.lock()
        defer { lock.unlock() }
        let gpuUpdate = gpu.read()
        if gpuUpdate.reset {
            initializationFailedAt = nil; restartedAt = nil; initializedAt = nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        for line in gpuUpdate.lines {
            guard line.hasPrefix("["), line.count >= 21,
                  let date = formatter.date(from: String(line.dropFirst().prefix(19))),
                  isCurrent(date, now: now) else { continue }
            if line.contains("GPU process started:") { record(date, in: &restartedAt) }
            if line.contains("[ GL implementation parts ]: (gl=egl-angle,angle=") {
                record(date, in: &initializedAt)
            }
            if line.contains("GPU process was unable to boot:") { record(date, in: &initializationFailedAt) }
        }
        let cefUpdate = cef.read()
        if cefUpdate.reset { presentationFailedAt = nil }
        for line in cefUpdate.lines {
            // Device initialization is not window-surface creation. Generic EGL
            // warnings do not qualify, and a later GL capability report cannot
            // clear this explicit presentation failure.
            guard line.contains(":ERROR:"),
                  line.contains("eglCreateWindowSurface failed with error EGL_BAD_ALLOC"),
                  let date = cefDate(line), isCurrent(date, now: now) else { continue }
            record(date, in: &presentationFailedAt)
        }
        // Compare timestamps across files, not read order. A new GPU process
        // starts another attempt; this never establishes a usable interface.
        if let failure = presentationFailedAt,
           failure >= (restartedAt ?? .distantPast), now.timeIntervalSince(failure) >= 3 {
            return .rendererPresentationFailed
        }
        if let failure = initializationFailedAt,
           failure > max(restartedAt ?? .distantPast, initializedAt ?? .distantPast),
           now.timeIntervalSince(failure) >= 3 {
            return .rendererInitializationFailed
        }
        return nil
    }

    private func record(_ date: Date, in value: inout Date?) {
        value = max(value ?? .distantPast, date)
    }

    private func isCurrent(_ date: Date, now: Date) -> Bool {
        date.timeIntervalSince1970 >= floor(started.timeIntervalSince1970) && date <= now.addingTimeInterval(1)
    }

    private func cefDate(_ line: String) -> Date? {
        // CEF's [pid:tid:MMdd/HHmmss.SSS:ERROR:...] omits the year. Select the
        // closest year to launch, including a session spanning New Year's Eve.
        guard line.hasPrefix("[") else { return nil }
        let fields = line.split(separator: ":", maxSplits: 3)
        guard fields.count == 4, fields[2].count == 15 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd/HHmmss.SSS"
        formatter.isLenient = false
        let year = Calendar(identifier: .gregorian).component(.year, from: started)
        return ((year - 1)...(year + 1)).compactMap {
            formatter.date(from: String($0) + fields[2])
        }.min { abs($0.timeIntervalSince(started)) < abs($1.timeIntervalSince(started)) }
    }

    private final class LogCursor {
        let file: URL
        let prefix: URL
        var identity: UInt64?
        var offset: UInt64 = 0
        var partial = Data()

        init(prefix: URL, name: String) {
            self.prefix = prefix
            file = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/logs/" + name)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               attrs[.type] as? FileAttributeType == .typeRegular {
                identity = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
                offset = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            }
        }

        func read() -> (lines: [String], reset: Bool) {
            guard file.resolvingSymlinksInPath().path.hasPrefix(prefix.path + "/"),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
                  let size = (attrs[.size] as? NSNumber)?.uint64Value,
                  let handle = try? FileHandle(forReadingFrom: file) else { return ([], true) }
            defer { try? handle.close() }
            let reset = identity != inode || size < offset
            if reset { identity = inode; offset = 0; partial.removeAll() }
            // Bound IO and refuse an incomplete leading line when catching up.
            let skipLeading = size - offset > 262_144
            if skipLeading { offset = size - 262_144; partial.removeAll() }
            do {
                try handle.seek(toOffset: offset)
                if let chunk = try handle.read(upToCount: 262_144) {
                    offset += UInt64(chunk.count)
                    if skipLeading {
                        if let newline = chunk.firstIndex(of: 10) { partial.append(chunk.suffix(from: chunk.index(after: newline))) }
                    } else { partial.append(chunk) }
                }
            } catch { return ([], reset) }
            var lines: [String] = []
            while let newline = partial.firstIndex(of: 10) {
                lines.append(String(decoding: partial.prefix(upTo: newline), as: UTF8.self))
                partial.removeSubrange(...newline)
            }
            if partial.count > 65_536 { partial.removeAll() }
            return (lines, reset)
        }
    }
}
