import Foundation
import Darwin
import Security

/// State is confined to queue. A socket with SO_NOSIGPIPE lets us stop collecting
/// inherited output without sending SIGPIPE to a detached Steam process. Writes
/// after collection ends receive EPIPE; no process is signalled or terminated.
final class LaunchOutputCapture: @unchecked Sendable {
    let writer: FileHandle
    private let queue = DispatchQueue(label: "com.portside.runtime.output", qos: .utility)
    private let source: DispatchSourceRead
    private let descriptor: Int32
    private var captured = Data()
    private var discardingPartialLine = false
    private var reachedEOF = false
    private var completion: CheckedContinuation<Data, Never>?
    private let log: @Sendable (String) -> Void

    init(log: @escaping @Sendable (String) -> Void = { PortsideRuntimeHost.writeLog($0) }) throws {
        self.log = log
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw PortsideRuntimeHost.HostError.outputCaptureFailed
        }
        var enabled: Int32 = 1
        guard setsockopt(descriptors[1], SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0,
              fcntl(descriptors[0], F_SETFL, O_NONBLOCK) == 0,
              fcntl(descriptors[0], F_SETFD, FD_CLOEXEC) == 0,
              fcntl(descriptors[1], F_SETFD, FD_CLOEXEC) == 0 else {
            close(descriptors[0]); close(descriptors[1])
            throw PortsideRuntimeHost.HostError.outputCaptureFailed
        }
        descriptor = descriptors[0]
        writer = FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        let reader = descriptor
        source.setCancelHandler { close(reader) }
        source.activate()
    }

    deinit { source.cancel() }

    func finish(gracePeriod: TimeInterval) async -> Data {
        await withCheckedContinuation { continuation in
            queue.async {
                self.completion = continuation
                if self.reachedEOF { self.complete() }
                else {
                    self.queue.asyncAfter(deadline: .now() + gracePeriod) {
                        guard self.completion != nil else { return }
                        self.log("runtime_output_collection_ended inherited_output_grace_expired")
                        self.complete()
                    }
                }
            }
        }
    }

    private func complete() {
        source.cancel()
        completion?.resume(returning: captured)
        completion = nil
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Bound one event's work so a noisy child cannot starve the deadline.
        for _ in 0..<32 {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            if count <= 0 {
                if count < 0 { log("runtime_output_read_failed errno=\(errno)") }
                reachedEOF = true
                source.cancel()
                if completion != nil { complete() }
                return
            }
            var chunk = Data(buffer.prefix(count))
            if discardingPartialLine {
                guard let newline = chunk.firstIndex(of: 10) else { continue }
                chunk.removeSubrange(...newline)
                discardingPartialLine = false
            }
            captured.append(chunk)
            if captured.count > 65_536 {
                captured.removeFirst(captured.count - 65_536)
                // Discard a truncated credential line including its tail.
                if let newline = captured.firstIndex(of: 10) { captured.removeSubrange(...newline) }
                else { captured.removeAll(keepingCapacity: true); discardingPartialLine = true }
            }
        }
    }
}

/// Native launcher for a Portside runtime. It deliberately uses Foundation's
/// Process API with an executable URL and an argument array; no command string
/// is handed to a shell. Winetricks is an executable vendored script and is
/// launched directly so its own shebang selects the interpreter.
@main
struct PortsideRuntimeHost {
    struct Configuration: Decodable {
        let version: String
        let wineRelativePath: String
        let prefixRelativePath: String
        let winetricksRelativePath: String
        let steamExecutable: String
        let wineDebug: String
        let environment: [String: String]
    }

    static func main() async {
        var launchID: UUID?
        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.first == "--launch-id" {
                guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else { throw HostError.invalidArguments }
                launchID = id
                arguments.removeFirst(2)
            }
            let bundle = try bundleURL()
            let configuration = try loadConfiguration(bundle: bundle)
            let result = try await run(arguments: arguments, bundle: bundle, configuration: configuration, launchID: launchID)
            exit(result)
        } catch {
            let detail = executionError(error)
            writeLog("runtime host failed: \(detail)")
            writeReceipt(LaunchReceipt(launchID: launchID, phase: "executionFailed", executionError: detail))
            fputs("Portside could not start the gaming environment.\n", stderr)
            exit(1)
        }
    }

    static func run(arguments: [String], bundle: URL, configuration: Configuration, launchID: UUID? = nil) async throws -> Int32 {
        let engine = bundle.appendingPathComponent(configuration.wineRelativePath)
        let prefixLink = bundle.appendingPathComponent(configuration.prefixRelativePath)
        let prefix = prefixLink.resolvingSymlinksInPath()
        let winetricks = bundle.appendingPathComponent(configuration.winetricksRelativePath)

        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let request = try command(arguments: arguments, engine: engine, winetricks: winetricks, configuration: configuration)
        var environment = runtimeEnvironment(engine: engine, prefix: prefix, configuration: configuration)
        if arguments.first == "--create-prefix" {
            // Wine registers these DLLs during prefix creation and upgrade. With no bundled
            // Mono/Gecko, registration opens modal optional-addon installers
            // before WoW64 prefix files are complete. Defer only those addons
            // for this bootstrap subprocess; Steam and game launches retain
            // normal DLL loading and no registry override is persisted.
            environment["WINEDLLOVERRIDES"] = [environment["WINEDLLOVERRIDES"], "mscoree,mshtml="].compactMap { $0 }.joined(separator: ";")
            writeLog("prefix_setup optional_addons=deferred scope=bootstrap_process")
        }
        let status = try await execute(request, environment: environment, bundle: bundle,
                                       configuration: configuration, launchID: launchID)
        guard arguments.first == "--create-prefix", status == 0 else { return status }
        // Wine's builtin Vulkan loader cannot expose Valve's bundled SwiftShader
        // ICD in this OpenGL engine. Let only CEF's executable load Valve's
        // native loader. Games keep Wine's default; no inherited DLL override,
        // renderer flags, sandbox changes, or third-party DLL downloads.
        let compatibility = try steamWebHelperCompatibilityCommand(engine: engine)
        return try await execute(compatibility,
                                 environment: runtimeEnvironment(engine: engine, prefix: prefix, configuration: configuration),
                                 bundle: bundle, configuration: configuration, launchID: launchID)
    }

    static func steamWebHelperCompatibilityCommand(engine: URL) throws -> Command {
        Command(label: "Steam web helper configuration",
                executable: try executable(in: engine, names: ["wine64", "wine"]),
                arguments: ["reg", "add", #"HKCU\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides"#,
                            "/v", "vulkan-1", "/t", "REG_SZ", "/d", "native,builtin", "/f"])
    }

    static func execute(_ request: Command, environment: [String: String], bundle: URL,
                        configuration: Configuration, launchID: UUID?) async throws -> Int32 {
        let commandDescription = diagnosticCommand(request)
        let version = configuration.version.range(of: #"^[0-9]+(?:\.[0-9]+){1,3}$"#, options: .regularExpression) != nil ? configuration.version : "unknown"
        writeLog("starting \(request.label) version=\(version) renderer=WineD3D \(commandDescription)")

        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = environment
        process.currentDirectoryURL = bundle
        let output = try LaunchOutputCapture()
        process.standardOutput = output.writer
        process.standardError = output.writer
        let termination = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            termination.continuation.yield(())
            termination.continuation.finish()
        }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try process.run()
        } catch {
            try? output.writer.close()
            _ = await output.finish(gracePeriod: 0)
            let duration = ProcessInfo.processInfo.systemUptime - started
            let detail = executionError(error)
            writeLog("execution_failed \(commandDescription) duration=\(duration) error=\(detail)")
            writeReceipt(LaunchReceipt(launchID: launchID, phase: "executionFailed", duration: duration, executionError: detail))
            return 1
        }
        writeReceipt(LaunchReceipt(launchID: launchID, phase: "running", childPID: process.processIdentifier))
        try? output.writer.close()
        for await _ in termination.stream { break }
        let duration = ProcessInfo.processInfo.systemUptime - started
        let reason = process.terminationReason == .uncaughtSignal ? "uncaughtSignal" : "exit"
        let signal: Int32? = process.terminationReason == .uncaughtSignal ? process.terminationStatus : nil
        writeReceipt(LaunchReceipt(launchID: launchID, phase: "terminated", childPID: process.processIdentifier,
                                  terminationStatus: process.terminationStatus, terminationReason: reason,
                                  signal: signal, duration: duration))
        writeLog("finished \(request.label) status=\(process.terminationStatus) terminationStatus=\(process.terminationStatus) terminationReason=\(reason) signal=\(signal.map(String.init) ?? "none") duration=\(duration) \(commandDescription)")
        // Detached children must not keep the host alive for an entire session.
        let captured = await output.finish(gracePeriod: 2)
        let text = String(decoding: captured, as: UTF8.self)
        if !text.isEmpty { writeLog(redact(text)) }
        return signal.map { 128 + $0 } ?? process.terminationStatus
    }

    // Versioned, per-launch diagnostic contract with PortsideCore.RuntimeLaunchReceipt.
    // No paths, argv, environment, credentials, or raw child output are serialized.
    struct LaunchReceipt: Encodable {
        var schemaVersion = 1
        let launchID: UUID?
        let phase: String
        var hostPID: Int32 = getpid()
        var childPID: Int32?
        var terminationStatus: Int32?
        var terminationReason: String?
        var signal: Int32?
        var duration: TimeInterval = 0
        var executionError: String?
    }

    static func writeReceipt(_ receipt: LaunchReceipt) {
        guard let id = receipt.launchID else { return }
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Portside/Logs/RuntimeLaunches")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(id.uuidString + ".json")
            try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            pruneReceipts(in: directory, preserving: id)
        } catch { writeLog("launch_receipt_write_failed \(executionError(error))") }
    }

    /// Retain at most 100 historical receipts for seven days. The current launch
    /// and files younger than five minutes are protected from concurrent launches
    /// while desktop readiness may still be consuming them.
    static func pruneReceipts(in directory: URL, preserving id: UUID, now: Date = Date()) {
        let manager = FileManager.default
        guard let attributes = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              attributes.isDirectory == true, attributes.isSymbolicLink == false,
              let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { return }
        let receipts = files.compactMap { file -> (URL, Date)? in
            guard file.pathExtension == "json", let fileID = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  fileID != id,
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink == false,
                  let date = values.contentModificationDate else { return nil }
            return (file, date)
        }.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 > $1.1 }
        for (index, entry) in receipts.enumerated() {
            let age = now.timeIntervalSince(entry.1)
            if age >= 300 && (index >= 100 || age > 7 * 24 * 60 * 60) {
                try? manager.removeItem(at: entry.0)
            }
        }
    }

    static func executionError(_ error: Error) -> String {
        if let error = error as? HostError { return redact(error.localizedDescription) }
        let error = error as NSError
        let domain = [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain].contains(error.domain) ? error.domain : "execution"
        let underlying = (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { " underlyingCode=\($0.code)" } ?? ""
        return "domain=\(domain) code=\(error.code)\(underlying)"
    }

    static func diagnosticCommand(_ command: Command) -> String {
        let executable = command.label == "runtime component setup" ? "winetricks" : command.executable.lastPathComponent
        let arguments: [String]
        switch command.label {
        case "version": arguments = ["--version"]
        case "prefix setup": arguments = ["-u", "-r"]
        case "Steam": arguments = ["$STEAM_EXECUTABLE"] + command.arguments.dropFirst().map { _ in "<redacted>" }
        default: arguments = command.arguments.map { _ in "<redacted>" }
        }
        return "executable=$RUNTIME/\(executable) arguments=\(arguments)"
    }

    struct Command {
        let label: String
        let executable: URL
        let arguments: [String]
    }

    static func command(arguments: [String], engine: URL, winetricks: URL, configuration: Configuration) throws -> Command {
        let wine = try executable(in: engine, names: ["wine64", "wine"])
        if arguments.first == "--version" {
            return Command(label: "version", executable: wine, arguments: ["--version"])
        }
        if arguments.first == "--create-prefix" {
            let wineboot = try executable(in: engine, names: ["wineboot", "wineboot.exe"])
            // -r skips Run/Startup programs, without killing processes. An
            // existing prefix may register Steam for autostart; it must not
            // launch under the temporary Mono/Gecko suppression before setup.
            return Command(label: "prefix setup", executable: wineboot, arguments: ["-u", "-r"])
        }
        if arguments.first == "--winetricks" {
            guard FileManager.default.isExecutableFile(atPath: winetricks.path), arguments.count > 1 else {
                throw HostError.missingFile("winetricks")
            }
            return Command(label: "runtime component setup", executable: winetricks, arguments: Array(arguments.dropFirst()))
        }
        if arguments.first == "--program" {
            guard arguments.count > 1 else { throw HostError.invalidArguments }
            return Command(label: "configured program", executable: wine, arguments: Array(arguments.dropFirst()))
        }
        return Command(label: "Steam", executable: wine, arguments: [configuration.steamExecutable] + arguments)
    }

    static func runtimeEnvironment(engine: URL, prefix: URL, configuration: Configuration) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path
        environment["WINEARCH"] = "win64"
        environment["WINEDEBUG"] = configuration.wineDebug
        environment["WINEMSYNC"] = configuration.environment["WINEMSYNC"] ?? "1"
        environment["WINEESYNC"] = configuration.environment["WINEESYNC"] ?? "1"
        environment["D3DMETAL"] = "0"
        environment["DXMT"] = "0"
        environment["DXVK"] = "0"
        environment["WINE"] = (try? executable(in: engine, names: ["wine64", "wine"]).path) ?? engine.appendingPathComponent("bin/wine").path
        environment["WINESERVER"] = engine.appendingPathComponent("bin/wineserver").path
        environment["WINELOADER"] = environment["WINE"]
        environment["PATH"] = engine.appendingPathComponent("bin").path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["HOME"] = NSHomeDirectory()
        environment["XDG_CACHE_HOME"] = NSHomeDirectory() + "/Library/Application Support/Portside/Cache/XDG"
        return environment
    }

    static func executable(in directory: URL, names: [String]) throws -> URL {
        for name in names {
            let candidate = directory.appendingPathComponent("bin", isDirectory: true).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw HostError.missingFile(names.joined(separator: " or "))
    }

    static func bundleURL(bundle: Bundle = .main) throws -> URL {
        let bundleURL = bundle.bundleURL
        let executable = bundle.executableURL
        let reason: String?
        if bundleURL.pathExtension != "app" {
            reason = "Foundation did not resolve an application bundle"
        } else if bundle.bundleIdentifier != "com.portside.runtime" {
            reason = "The runtime bundle identifier is not com.portside.runtime"
        } else if executable == nil {
            reason = "CFBundleExecutable did not resolve a runtime host executable"
        } else if executable?.lastPathComponent != "PortsideRuntimeHost" {
            reason = "CFBundleExecutable does not identify PortsideRuntimeHost"
        } else if !executable!.resolvingSymlinksInPath().path.hasPrefix(bundleURL.resolvingSymlinksInPath().path + "/") {
            reason = "The runtime host executable resolves outside its bundle"
        } else if !FileManager.default.isExecutableFile(atPath: executable!.path) {
            reason = "The runtime host executable is missing or is not executable"
        } else {
            reason = nil
        }
        if let reason {
            let diagnostic = bundleRejectionDiagnostic(bundleURL: bundleURL, executable: executable, reason: reason)
            writeLog(diagnostic)
            throw HostError.notInBundle(reason)
        }
        return bundleURL
    }

    static func bundleRejectionDiagnostic(bundleURL: URL, executable: URL?, reason: String) -> String {
        let exists = executable.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let signature = executable.map(signatureStatus) ?? "not_checked:no_executable_url"
        return redact("notInBundle bundle_url=\(bundleURL.absoluteString) helper_url=\(executable?.absoluteString ?? "unresolved") file_exists=\(exists) signature=\(signature) reason=\(reason)")
    }

    /// The assembled wrapper is mutable (its prefix is installed separately).
    /// Its trust comes from the verified runtime manifest; code-signature status
    /// here is diagnostic and does not replace that authentication contract.
    static func signatureStatus(at url: URL) -> String {
        var code: SecStaticCode?
        let creation = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard creation == errSecSuccess, let code else { return "unavailable:OSStatus=\(creation)" }
        let validation = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil)
        return validation == errSecSuccess ? "valid" : "invalid:OSStatus=\(validation)"
    }

    static func loadConfiguration(bundle: URL) throws -> Configuration {
        guard let runtimeBundle = Bundle(url: bundle),
              let url = runtimeBundle.url(forResource: "portside-runtime", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { throw HostError.missingFile("portside-runtime.json") }
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    static func relative(_ url: URL, from root: URL) -> String {
        url.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    static func writeLog(_ message: String) {
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Portside/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("runtime-host.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(redact(message))\n"
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        }
    }

    static func redact(_ value: String) -> String {
        var result = value.replacingOccurrences(of: NSHomeDirectory(), with: "$USER_HOME")
        result = result.replacingOccurrences(of: URL(fileURLWithPath: NSHomeDirectory()).absoluteString, with: "file://$USER_HOME/")
        // Sensitive command lines and headers are discarded as whole lines;
        // redacting a flag alone can leave its positional password behind.
        result = result.components(separatedBy: .newlines).map { line in
            if line.range(of: #"(?i)(?:-login\b|\b(?:authorization|password|passwd|token|cookie|sessionid|steamid|auth|username|email|account)\s*[=:])"#, options: .regularExpression) != nil {
                return "<redacted sensitive output>"
            }
            return line
        }.joined(separator: "\n")
        for pattern in [#"/Users/[^/\s]+"#, #"(?i)[A-Z]:\\users\\[^\\\r\n]+"#, #"/Volumes/[^\r\n\"']+"#] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<private-path>")
            }
        }
        for pattern in ["(?i)(password|passwd|token|cookie|sessionid|steamid|auth)\\s*[=:]\\s*[^\\s,;]+", "(?i)(-steamid|--steamid)\\s+[^\\s]+"] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1=<redacted>")
            }
        }
        return String(result.suffix(1_000_000))
    }

    enum HostError: LocalizedError {
        case notInBundle(String)
        case missingFile(String)
        case invalidArguments
        case outputCaptureFailed
        var errorDescription: String? {
            switch self {
            case .notInBundle(let reason): return "PortsideRuntimeHost must run inside its runtime app bundle. \(reason)."
            case .missingFile(let path): return "required runtime file is missing: \(path)"
            case .invalidArguments: return "runtime host arguments are invalid"
            case .outputCaptureFailed: return "runtime output capture could not be configured"
            }
        }
    }
}
