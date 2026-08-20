import Foundation
import Darwin

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
        do {
            let bundle = try bundleURL()
            let configuration = try loadConfiguration(bundle: bundle)
            let result = try await run(arguments: Array(CommandLine.arguments.dropFirst()), bundle: bundle, configuration: configuration)
            exit(result)
        } catch {
            writeLog("runtime host failed: \(redact(String(describing: error)))")
            fputs("Portside could not start the gaming environment.\n", stderr)
            exit(1)
        }
    }

    static func run(arguments: [String], bundle: URL, configuration: Configuration) async throws -> Int32 {
        let engine = bundle.appendingPathComponent(configuration.wineRelativePath)
        let prefix = bundle.appendingPathComponent(configuration.prefixRelativePath)
        let winetricks = bundle.appendingPathComponent(configuration.winetricksRelativePath)

        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let environment = runtimeEnvironment(engine: engine, prefix: prefix, configuration: configuration)

        let request = try command(arguments: arguments, engine: engine, winetricks: winetricks, configuration: configuration)
        writeLog("starting \(request.label) version=\(configuration.version) renderer=WineD3D prefix=\(relative(prefix, from: bundle))")

        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = environment
        process.currentDirectoryURL = bundle
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let reader = Task.detached {
            output.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        let text = String(data: await reader.value, encoding: .utf8) ?? ""
        if !text.isEmpty { writeLog(redact(text)) }
        writeLog("finished \(request.label) status=\(process.terminationStatus)")
        return process.terminationStatus
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
            return Command(label: "prefix setup", executable: wineboot, arguments: ["-u"])
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

    static func bundleURL() throws -> URL {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent()
        guard bundle.pathExtension == "app" else { throw HostError.notInBundle }
        return bundle
    }

    static func loadConfiguration(bundle: URL) throws -> Configuration {
        let url = bundle.appendingPathComponent("Contents/Resources/portside-runtime.json")
        guard let data = try? Data(contentsOf: url) else { throw HostError.missingFile(url.path) }
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    static func relative(_ url: URL, from root: URL) -> String {
        url.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    static func writeLog(_ message: String) {
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Portside/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("runtime-host.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        }
    }

    static func redact(_ value: String) -> String {
        var result = value.replacingOccurrences(of: NSHomeDirectory(), with: "$USER_HOME")
        for pattern in ["(?i)(password|passwd|token|cookie|sessionid|steamid|auth)\\s*[=:]\\s*[^\\s,;]+", "(?i)(-steamid|--steamid)\\s+[^\\s]+"] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1=<redacted>")
            }
        }
        return String(result.suffix(1_000_000))
    }

    enum HostError: LocalizedError {
        case notInBundle
        case missingFile(String)
        case invalidArguments
        var errorDescription: String? {
            switch self {
            case .notInBundle: return "PortsideRuntimeHost must run inside an app bundle"
            case .missingFile(let path): return "required runtime file is missing: \(path)"
            case .invalidArguments: return "runtime host arguments are invalid"
            }
        }
    }
}
