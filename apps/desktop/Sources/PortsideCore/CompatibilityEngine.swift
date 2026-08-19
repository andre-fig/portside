import Foundation
import CryptoKit

// MARK: - Valve metadata

public indirect enum ValveValue: Equatable, Sendable {
    case string(String)
    case object([String: ValveValue])

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var objectValue: [String: ValveValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

public struct ValveKeyValueParser: Sendable {
    public let maxBytes: Int
    public let maxDepth: Int
    public let maxNodes: Int
    public let maxTokenLength: Int

    public init(maxBytes: Int = 8 * 1024 * 1024, maxDepth: Int = 64, maxNodes: Int = 100_000, maxTokenLength: Int = 1 * 1024 * 1024) {
        self.maxBytes = maxBytes
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
        self.maxTokenLength = maxTokenLength
    }

    public func parse(data: Data) throws -> ValveValue {
        guard data.count <= maxBytes else { throw PortsideError.invalidArtifact("Valve metadata is too large") }
        var parser = Parser(bytes: Array(data), limits: self)
        return try parser.parse()
    }

    public func parse(text: String) throws -> ValveValue {
        try parse(data: Data(text.utf8))
    }

    private struct Parser {
        let bytes: [UInt8]
        let limits: ValveKeyValueParser
        var index = 0
        var nodes = 0

        mutating func parse() throws -> ValveValue {
            skipWhitespaceAndComments()
            let value: ValveValue
            if index < bytes.count, bytes[index] == 0x7b {
                value = try parseObject(depth: 0)
            } else {
                let key = try readToken()
                skipWhitespaceAndComments()
                value = .object([key: try parseObject(depth: 0)])
            }
            skipWhitespaceAndComments()
            guard index == bytes.count else { throw PortsideError.invalidArtifact("Trailing Valve metadata") }
            return value
        }

        mutating func parseObject(depth: Int) throws -> ValveValue {
            guard depth <= limits.maxDepth, consume(0x7b) else { throw PortsideError.invalidArtifact("Invalid Valve object") }
            nodes += 1
            guard nodes <= limits.maxNodes else { throw PortsideError.invalidArtifact("Valve metadata has too many nodes") }
            var values: [String: ValveValue] = [:]
            while true {
                skipWhitespaceAndComments()
                if consume(0x7d) { return .object(values) }
                guard index < bytes.count else { throw PortsideError.invalidArtifact("Unterminated Valve object") }
                let key = try readToken()
                skipWhitespaceAndComments()
                guard index < bytes.count else { throw PortsideError.invalidArtifact("Missing Valve value") }
                let value: ValveValue
                if bytes[index] == 0x7b {
                    value = try parseObject(depth: depth + 1)
                } else {
                    value = .string(try readToken())
                    nodes += 1
                    guard nodes <= limits.maxNodes else { throw PortsideError.invalidArtifact("Valve metadata has too many nodes") }
                }
                values[key] = value
            }
        }

        mutating func readToken() throws -> String {
            skipWhitespaceAndComments()
            guard index < bytes.count else { throw PortsideError.invalidArtifact("Missing Valve token") }
            if bytes[index] == 0x22 {
                index += 1
                var result = ""
                while index < bytes.count {
                    let byte = bytes[index]
                    index += 1
                    if byte == 0x22 { return String(result) }
                    if byte == 0x5c {
                        guard index < bytes.count else { throw PortsideError.invalidArtifact("Invalid Valve escape") }
                        let escaped = bytes[index]
                        index += 1
                        switch escaped {
                        case 0x6e: result.append("\n")
                        case 0x72: result.append("\r")
                        case 0x74: result.append("\t")
                        case 0x22: result.append("\"")
                        case 0x5c: result.append("\\")
                        default: result.append(Character(UnicodeScalar(escaped)))
                        }
                    } else {
                        result.append(Character(UnicodeScalar(byte)))
                    }
                    guard result.count <= limits.maxTokenLength else { throw PortsideError.invalidArtifact("Valve token is too large") }
                }
                throw PortsideError.invalidArtifact("Unterminated Valve string")
            }
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d || byte == 0x7b || byte == 0x7d {
                    break
                }
                index += 1
            }
            guard index > start else { throw PortsideError.invalidArtifact("Invalid Valve token") }
            guard index - start <= limits.maxTokenLength else { throw PortsideError.invalidArtifact("Valve token is too large") }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        mutating func skipWhitespaceAndComments() {
            while index < bytes.count {
                if bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0a || bytes[index] == 0x0d {
                    index += 1
                } else if index + 1 < bytes.count && bytes[index] == 0x2f && bytes[index + 1] == 0x2f {
                    index += 2
                    while index < bytes.count && bytes[index] != 0x0a { index += 1 }
                } else {
                    break
                }
            }
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }
    }
}

public struct SteamGameInstallation: Codable, Equatable, Sendable, Hashable {
    public let appID: String
    public let gameName: String
    public let installDirectory: URL
    public let manifestURL: URL
    public let libraryRoot: URL
    public let stateFlags: Int
    public let isInstalled: Bool
    public let lastUpdated: Date?
    public let sizeOnDisk: Int64?

    public init(appID: String, gameName: String, installDirectory: URL, manifestURL: URL, libraryRoot: URL, stateFlags: Int, isInstalled: Bool, lastUpdated: Date?, sizeOnDisk: Int64?) {
        self.appID = appID
        self.gameName = gameName
        self.installDirectory = installDirectory
        self.manifestURL = manifestURL
        self.libraryRoot = libraryRoot
        self.stateFlags = stateFlags
        self.isInstalled = isInstalled
        self.lastUpdated = lastUpdated
        self.sizeOnDisk = sizeOnDisk
    }
}

public struct SteamLibrarySnapshot: Codable, Equatable, Sendable {
    public let scannedAt: Date
    public let libraries: [URL]
    public let games: [SteamGameInstallation]

    public init(scannedAt: Date = Date(), libraries: [URL], games: [SteamGameInstallation]) {
        self.scannedAt = scannedAt
        self.libraries = libraries
        self.games = games.sorted { $0.appID < $1.appID }
    }
}

public enum SteamLibraryChange: Equatable, Sendable {
    case installed(SteamGameInstallation)
    case updated(SteamGameInstallation)
    case removed(appID: String, gameName: String)
}

public struct SteamLibraryScanResult: Sendable {
    public let snapshot: SteamLibrarySnapshot
    public let changes: [SteamLibraryChange]

    public init(snapshot: SteamLibrarySnapshot, changes: [SteamLibraryChange] = []) {
        self.snapshot = snapshot
        self.changes = changes
    }
}

public final class SteamLibraryScanner: @unchecked Sendable {
    private let prefix: URL
    private let steamLibrary: URL
    private let fileManager: FileManager
    private let parser: ValveKeyValueParser
    private let maxExecutableFiles: Int
    private let maxExecutableDepth: Int

    public init(prefix: URL = PortsidePaths.steamPrefix, steamLibrary: URL = PortsidePaths.steamLibrary, fileManager: FileManager = .default, parser: ValveKeyValueParser = ValveKeyValueParser(), maxExecutableFiles: Int = 128, maxExecutableDepth: Int = 5) {
        self.prefix = prefix.standardizedFileURL
        self.steamLibrary = steamLibrary.standardizedFileURL
        self.fileManager = fileManager
        self.parser = parser
        self.maxExecutableFiles = maxExecutableFiles
        self.maxExecutableDepth = maxExecutableDepth
    }

    public func scan(previous: SteamLibrarySnapshot? = nil) throws -> SteamLibraryScanResult {
        let roots = try librarySteamAppsRoots()
        var games: [SteamGameInstallation] = []
        for steamApps in roots {
            let files = try fileManager.contentsOfDirectory(at: steamApps, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            for manifest in files where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension.lowercased() == "acf" {
                guard let game = try parseManifest(manifest, libraryRoot: steamApps.deletingLastPathComponent()) else { continue }
                games.append(game)
            }
        }
        var unique: [String: SteamGameInstallation] = [:]
        for game in games { unique[game.appID] = game }
        let snapshot = SteamLibrarySnapshot(libraries: roots.map { $0.deletingLastPathComponent() }, games: Array(unique.values))
        return SteamLibraryScanResult(snapshot: snapshot, changes: Self.changes(from: previous, to: snapshot))
    }

    public func executableCandidates(for game: SteamGameInstallation) -> [URL] {
        guard game.isInstalled, isInsideManagedRoots(game.installDirectory), fileManager.fileExists(atPath: game.installDirectory.path) else { return [] }
        guard let enumerator = fileManager.enumerator(at: game.installDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        let baseDepth = game.installDirectory.pathComponents.count
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - baseDepth
            if depth > maxExecutableDepth { enumerator.skipDescendants(); continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values?.isRegularFile == true && url.pathExtension.lowercased() == "exe" {
                result.append(url.standardizedFileURL)
                if result.count >= maxExecutableFiles { break }
            }
        }
        return result.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    public static func changes(from old: SteamLibrarySnapshot?, to new: SteamLibrarySnapshot) -> [SteamLibraryChange] {
        let oldGames = Dictionary(uniqueKeysWithValues: (old?.games ?? []).map { ($0.appID, $0) })
        let newGames = Dictionary(uniqueKeysWithValues: new.games.map { ($0.appID, $0) })
        var result: [SteamLibraryChange] = []
        for id in newGames.keys.sorted() {
            guard let game = newGames[id] else { continue }
            if let previous = oldGames[id] {
                if previous != game { result.append(.updated(game)) }
            } else {
                result.append(.installed(game))
            }
        }
        for id in oldGames.keys.sorted() where newGames[id] == nil {
            if let game = oldGames[id] { result.append(.removed(appID: id, gameName: game.gameName)) }
        }
        return result
    }

    private func librarySteamAppsRoots() throws -> [URL] {
        var candidates: [URL] = []
        let defaultSteamApps = [
            prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true),
            prefix.appendingPathComponent("drive_c/Program Files/Steam/steamapps", isDirectory: true),
            steamLibrary.appendingPathComponent("steamapps", isDirectory: true)
        ]
        candidates.append(contentsOf: defaultSteamApps)
        let foldersFiles = [
            defaultSteamApps[0].appendingPathComponent("libraryfolders.vdf"),
            defaultSteamApps[1].appendingPathComponent("libraryfolders.vdf"),
            steamLibrary.appendingPathComponent("steamapps/libraryfolders.vdf")
        ]
        for file in foldersFiles where fileManager.fileExists(atPath: file.path) {
            if let value = try? parser.parse(data: Data(contentsOf: file)), let root = value.objectValue,
               let libraries = root["libraryfolders"]?.objectValue {
                for item in libraries.values {
                    guard let object = item.objectValue, let path = object["path"]?.stringValue,
                          let library = resolveLibraryPath(path) else { continue }
                    candidates.append(library.appendingPathComponent("steamapps", isDirectory: true))
                }
            }
        }
        return uniqueExistingDirectories(candidates)
    }

    private func parseManifest(_ url: URL, libraryRoot: URL) throws -> SteamGameInstallation? {
        guard let value = try? parser.parse(data: Data(contentsOf: url)), let root = value.objectValue,
              let state = root["AppState"]?.objectValue,
              let appID = state["appid"]?.stringValue, appID.allSatisfy({ $0.isNumber }) else { return nil }
        let name = state["name"]?.stringValue ?? "Unknown game"
        guard let installDirectoryName = state["installdir"]?.stringValue, isSafeRelativeDirectory(installDirectoryName) else { return nil }
        let installDirectory = libraryRoot.appendingPathComponent("steamapps/common", isDirectory: true).appendingPathComponent(installDirectoryName, isDirectory: true).standardizedFileURL
        guard isInsideManagedRoots(installDirectory) else { return nil }
        let stateFlags = Int(state["StateFlags"]?.stringValue ?? "0") ?? 0
        let lastUpdated = Int64(state["LastUpdated"]?.stringValue ?? "").map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let sizeOnDisk = Int64(state["SizeOnDisk"]?.stringValue ?? "")
        let installed = stateFlags & 4 != 0 || fileManager.fileExists(atPath: installDirectory.path)
        return SteamGameInstallation(appID: appID, gameName: name, installDirectory: installDirectory, manifestURL: url.standardizedFileURL, libraryRoot: libraryRoot.standardizedFileURL, stateFlags: stateFlags, isInstalled: installed, lastUpdated: lastUpdated, sizeOnDisk: sizeOnDisk)
    }

    private func resolveLibraryPath(_ value: String) -> URL? {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        if normalized.count >= 2, normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":" {
            let drive = String(normalized.prefix(1)).lowercased()
            guard drive == "c" else { return nil }
            let suffix = String(normalized.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return prefix.appendingPathComponent("drive_c", isDirectory: true).appendingPathComponent(suffix, isDirectory: true).standardizedFileURL
        }
        let candidate = URL(fileURLWithPath: normalized).standardizedFileURL
        return isInsideManagedRoots(candidate) ? candidate : nil
    }

    private func uniqueExistingDirectories(_ values: [URL]) -> [URL] {
        var seen = Set<String>()
        return values.map(\.standardizedFileURL).filter { url in
            guard seen.insert(url.path).inserted else { return false }
            guard fileManager.fileExists(atPath: url.path), let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else { return false }
            return isInsideManagedRoots(url)
        }
    }

    private func isSafeRelativeDirectory(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        return !normalized.isEmpty && !normalized.hasPrefix("/") && !normalized.contains(":") && !normalized.split(separator: "/").contains("..")
    }

    private func isInsideManagedRoots(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        let roots = [prefix, steamLibrary, PortsidePaths.root].map { $0.standardizedFileURL.path }
        return roots.contains { candidate == $0 || candidate.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }
}

// MARK: - PE inspection

public enum PEArchitecture: String, Codable, CaseIterable, Sendable, Hashable {
    case x86
    case x86_64
    case arm64
    case unknown
}

public enum DetectedGraphicsAPI: String, Codable, CaseIterable, Sendable, Hashable {
    case directX8, directX9, directX10, directX11, directX12, vulkan, openGL, unknown
}

public enum AntiCheatProvider: String, Codable, CaseIterable, Sendable, Hashable {
    case easyAntiCheat, battlEye, gameGuard, nProtect, other
}

public struct PEImportEvidence: Codable, Equatable, Sendable {
    public let executable: URL
    public let architecture: PEArchitecture
    public let imports: [String]
    public let graphicsAPIs: [DetectedGraphicsAPI]
    public let engineHints: [String]
    public let launcherHints: [String]
    public let antiCheatProviders: [AntiCheatProvider]
    public let stringEvidence: [String]

    public init(executable: URL, architecture: PEArchitecture, imports: [String], graphicsAPIs: [DetectedGraphicsAPI], engineHints: [String] = [], launcherHints: [String] = [], antiCheatProviders: [AntiCheatProvider] = [], stringEvidence: [String] = []) {
        self.executable = executable
        self.architecture = architecture
        self.imports = imports
        self.graphicsAPIs = graphicsAPIs
        self.engineHints = engineHints
        self.launcherHints = launcherHints
        self.antiCheatProviders = antiCheatProviders
        self.stringEvidence = stringEvidence
    }
}

public final class PEImportScanner: @unchecked Sendable {
    public static let relevantImports: Set<String> = ["d3d8.dll", "d3d9.dll", "d3d10.dll", "d3d10_1.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll", "vulkan-1.dll", "opengl32.dll"]
    private let maxBytes: Int
    private let fileManager: FileManager

    public init(maxBytes: Int = 64 * 1024 * 1024, fileManager: FileManager = .default) {
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    public func scan(url: URL) throws -> PEImportEvidence {
        let size = (try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= maxBytes else { throw PortsideError.invalidArtifact("PE executable is outside the inspection limit") }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 0x40, data[0] == 0x4d, data[1] == 0x5a else { throw PortsideError.invalidArtifact("not a Windows PE executable") }
        let peOffset = Int(readUInt32(data, at: 0x3c))
        guard peOffset >= 0, peOffset + 24 <= data.count, data[peOffset] == 0x50, data[peOffset + 1] == 0x45, data[peOffset + 2] == 0, data[peOffset + 3] == 0 else { throw PortsideError.invalidArtifact("invalid PE header") }
        let machine = readUInt16(data, at: peOffset + 4)
        let architecture: PEArchitecture = machine == 0x14c ? .x86 : machine == 0x8664 ? .x86_64 : machine == 0xaa64 ? .arm64 : .unknown
        let sectionCount = Int(readUInt16(data, at: peOffset + 6))
        let optionalSize = Int(readUInt16(data, at: peOffset + 20))
        let optionalOffset = peOffset + 24
        guard optionalSize >= 2, optionalOffset + optionalSize <= data.count else { throw PortsideError.invalidArtifact("invalid PE optional header") }
        let magic = readUInt16(data, at: optionalOffset)
        let dataDirectoryOffset = magic == 0x10b ? 96 : magic == 0x20b ? 112 : -1
        var sections: [PESection] = []
        let sectionOffset = optionalOffset + optionalSize
        guard sectionCount <= 96, sectionOffset + sectionCount * 40 <= data.count else { throw PortsideError.invalidArtifact("invalid PE section table") }
        for index in 0..<sectionCount {
            let offset = sectionOffset + index * 40
            sections.append(PESection(virtualSize: readUInt32(data, at: offset + 8), virtualAddress: readUInt32(data, at: offset + 12), rawSize: readUInt32(data, at: offset + 16), rawOffset: readUInt32(data, at: offset + 20)))
        }
        var imports = Set<String>()
        if dataDirectoryOffset >= 0, optionalSize >= dataDirectoryOffset + 16 {
            let directory = optionalOffset + dataDirectoryOffset + 8
            let importRVA = readUInt32(data, at: directory)
            let importSize = readUInt32(data, at: directory + 4)
            if let importOffset = rvaToOffset(importRVA, sections: sections, dataCount: data.count) {
                let descriptorLimit = min(Int(importSize), 20 * 4_096)
                var descriptor = importOffset
                while descriptor + 20 <= importOffset + descriptorLimit, descriptor + 20 <= data.count {
                    let originalThunk = readUInt32(data, at: descriptor)
                    let nameRVA = readUInt32(data, at: descriptor + 12)
                    let firstThunk = readUInt32(data, at: descriptor + 16)
                    if originalThunk == 0 && nameRVA == 0 && firstThunk == 0 { break }
                    if let nameOffset = rvaToOffset(nameRVA, sections: sections, dataCount: data.count) {
                        let name = readCString(data, at: nameOffset).lowercased()
                        if !name.isEmpty { imports.insert(name) }
                    }
                    let thunkRVA = originalThunk == 0 ? firstThunk : originalThunk
                    if thunkRVA != 0, let thunkOffset = rvaToOffset(thunkRVA, sections: sections, dataCount: data.count) {
                        let entrySize = magic == 0x20b ? 8 : 4
                        for entry in 0..<1_024 {
                            let itemOffset = thunkOffset + entry * entrySize
                            guard itemOffset + entrySize <= data.count else { break }
                            let value = entrySize == 8 ? readUInt64(data, at: itemOffset) : UInt64(readUInt32(data, at: itemOffset))
                            if value == 0 { break }
                            let ordinalFlag = entrySize == 8 ? UInt64(0x8000000000000000) : UInt64(0x80000000)
                            if value & ordinalFlag != 0 { continue }
                            let hintNameRVA = UInt32(value & 0x7fffffff_ffff_ffff)
                            if let hintNameOffset = rvaToOffset(hintNameRVA, sections: sections, dataCount: data.count) {
                                let function = readCString(data, at: hintNameOffset + 2).lowercased()
                                if function.hasPrefix("xinput") || function.hasPrefix("xaudio") { imports.insert(function) }
                            }
                        }
                    }
                    descriptor += 20
                }
            }
        }
        let strings = boundedASCIIStrings(data)
        let evidenceText = ([url.lastPathComponent] + strings).joined(separator: " ").lowercased()
        let stringImports = Self.relevantImports.filter { evidenceText.contains($0) }
        imports.formUnion(stringImports)
        let graphics = Self.graphicsAPIs(for: imports)
        let engineHints = Self.hints(in: evidenceText, values: ["unity", "unreal", "unrealengine", "ue4", "ue5", "godot", "gamemaker", "source engine"])
        let launcherHints = Self.hints(in: evidenceText, values: ["launcher", "bootstrapper", "client", "updater"])
        var antiCheat: [AntiCheatProvider] = []
        if evidenceText.contains("easyanticheat") || evidenceText.contains("easy anti-cheat") { antiCheat.append(.easyAntiCheat) }
        if evidenceText.contains("battleye") { antiCheat.append(.battlEye) }
        if evidenceText.contains("gameguard") { antiCheat.append(.gameGuard) }
        if evidenceText.contains("nprotect") { antiCheat.append(.nProtect) }
        return PEImportEvidence(executable: url.standardizedFileURL, architecture: architecture, imports: imports.sorted(), graphicsAPIs: graphics, engineHints: engineHints, launcherHints: launcherHints, antiCheatProviders: antiCheat, stringEvidence: Array(strings.filter { $0.localizedCaseInsensitiveContains("unity") || $0.localizedCaseInsensitiveContains("unreal") || $0.localizedCaseInsensitiveContains("battleye") || $0.localizedCaseInsensitiveContains("easyanti") }.prefix(32)))
    }

    public func scan(game: SteamGameInstallation, scanner: SteamLibraryScanner) -> [PEImportEvidence] {
        scanner.executableCandidates(for: game).compactMap { try? scan(url: $0) }
    }

    private struct PESection {
        let virtualSize: UInt32
        let virtualAddress: UInt32
        let rawSize: UInt32
        let rawOffset: UInt32
    }

    private static func graphicsAPIs(for imports: Set<String>) -> [DetectedGraphicsAPI] {
        var result: [DetectedGraphicsAPI] = []
        if imports.contains("d3d8.dll") { result.append(.directX8) }
        if imports.contains("d3d9.dll") { result.append(.directX9) }
        if imports.contains("d3d10.dll") || imports.contains("d3d10_1.dll") { result.append(.directX10) }
        if imports.contains("d3d11.dll") || imports.contains("dxgi.dll") { result.append(.directX11) }
        if imports.contains("d3d12.dll") { result.append(.directX12) }
        if imports.contains("vulkan-1.dll") { result.append(.vulkan) }
        if imports.contains("opengl32.dll") { result.append(.openGL) }
        return result.isEmpty ? [.unknown] : result
    }

    private static func hints(in text: String, values: [String]) -> [String] {
        values.filter { text.contains($0) }
    }

    private func boundedASCIIStrings(_ data: Data) -> [String] {
        var result: [String] = []
        var buffer: [UInt8] = []
        for byte in data {
            if byte >= 0x20 && byte <= 0x7e {
                buffer.append(byte)
            } else if buffer.count >= 4 {
                result.append(String(decoding: buffer, as: UTF8.self))
                buffer.removeAll(keepingCapacity: true)
                if result.count >= 4_096 { break }
            } else {
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if buffer.count >= 4 { result.append(String(decoding: buffer, as: UTF8.self)) }
        return result
    }

    private func rvaToOffset(_ rva: UInt32, sections: [PESection], dataCount: Int) -> Int? {
        for section in sections {
            let size = max(section.virtualSize, section.rawSize)
            guard rva >= section.virtualAddress, rva - section.virtualAddress < size else { continue }
            let offset = UInt64(section.rawOffset) + UInt64(rva - section.virtualAddress)
            guard offset < UInt64(dataCount) else { return nil }
            return Int(offset)
        }
        return rva < UInt32(dataCount) ? Int(rva) : nil
    }

    private func readCString(_ data: Data, at offset: Int) -> String {
        guard offset >= 0, offset < data.count else { return "" }
        var end = offset
        while end < data.count && data[end] != 0 && end - offset < 512 { end += 1 }
        return String(decoding: data[offset..<end], as: UTF8.self)
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else { return 0 }
        var result: UInt64 = 0
        for index in 0..<8 { result |= UInt64(data[offset + index]) << UInt64(index * 8) }
        return result
    }
}

// MARK: - Compatibility profiles

public enum CompatibilityProfileSource: String, Codable, CaseIterable, Sendable {
    case backendValidated, localValidated, peAnalysis, defaultProfile, userConfirmed
}

public enum CompatibilityConfidence: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

public enum CompatibilityResultCategory: String, Codable, CaseIterable, Sendable {
    case graphicsInitializationFailed = "graphics_initialization_failed"
    case shaderCompilationFailed = "shader_compilation_failed"
    case assetBundleFailed = "asset_bundle_failed"
    case missingDependency = "missing_dependency"
    case launcherFailed = "launcher_failed"
    case steamAPIFailed = "steam_api_failed"
    case anticheatUnsupported = "anticheat_unsupported"
    case anticheatInstallFailed = "anticheat_install_failed"
    case processCrashed = "process_crashed"
    case visualStateUnverified = "visual_state_unverified"
    case stableLaunch = "stable_launch"
}

public struct AntiCheatProfile: Codable, Equatable, Sendable {
    public let provider: AntiCheatProvider
    public let kernelDriverRequired: Bool
    public let wineSupport: String
    public let nativeMacAvailable: Bool
    public let status: String
    public let evidence: [String]

    public init(provider: AntiCheatProvider, kernelDriverRequired: Bool = false, wineSupport: String = "unknown", nativeMacAvailable: Bool = false, status: String = "informational", evidence: [String] = []) {
        self.provider = provider
        self.kernelDriverRequired = kernelDriverRequired
        self.wineSupport = wineSupport
        self.nativeMacAvailable = nativeMacAvailable
        self.status = status
        self.evidence = evidence
    }
}

public struct CompatibilityEvidence: Codable, Equatable, Sendable {
    public let executable: URL
    public let architecture: PEArchitecture
    public let imports: [String]
    public let graphicsAPIs: [DetectedGraphicsAPI]
    public let engineHints: [String]
    public let launcherHints: [String]
    public let antiCheatProviders: [AntiCheatProvider]
    public let notes: [String]

    public init(from evidence: PEImportEvidence) {
        executable = evidence.executable
        architecture = evidence.architecture
        imports = evidence.imports
        graphicsAPIs = evidence.graphicsAPIs
        engineHints = evidence.engineHints
        launcherHints = evidence.launcherHints
        antiCheatProviders = evidence.antiCheatProviders
        notes = evidence.stringEvidence
    }
}

public struct ExecutableProfile: Codable, Equatable, Sendable {
    public let executablePath: String
    public let architecture: PEArchitecture
    public let detectedAPIs: [DetectedGraphicsAPI]
    public let preferredRenderer: GraphicsBackend
    public let fallbackRenderers: [GraphicsBackend]
    public let dllOverrides: [String: String]
    public let environment: [String: String]
    public let arguments: [String]
    public let evidence: [CompatibilityEvidence]

    public init(executablePath: String, architecture: PEArchitecture, detectedAPIs: [DetectedGraphicsAPI], preferredRenderer: GraphicsBackend, fallbackRenderers: [GraphicsBackend] = [], dllOverrides: [String: String] = [:], environment: [String: String] = [:], arguments: [String] = [], evidence: [CompatibilityEvidence] = []) {
        self.executablePath = executablePath
        self.architecture = architecture
        self.detectedAPIs = detectedAPIs
        self.preferredRenderer = preferredRenderer
        self.fallbackRenderers = fallbackRenderers
        self.dllOverrides = dllOverrides
        self.environment = environment
        self.arguments = arguments
        self.evidence = evidence
    }
}

public struct GameCompatibilityProfile: Codable, Equatable, Sendable {
    public let appID: String
    public let gameName: String
    public let executables: [ExecutableProfile]
    public let preferredRenderer: GraphicsBackend
    public let fallbackRenderers: [GraphicsBackend]
    public let dllOverrides: [String: String]
    public let environment: [String: String]
    public let arguments: [String]
    public let antiCheat: [AntiCheatProfile]
    public let profileVersion: Int
    public let source: CompatibilityProfileSource
    public let confidence: CompatibilityConfidence
    public let lastSuccessfulRenderer: GraphicsBackend?
    public let lastFailure: CompatibilityResultCategory?
    public let updatedAt: Date

    public init(appID: String, gameName: String, executables: [ExecutableProfile], preferredRenderer: GraphicsBackend, fallbackRenderers: [GraphicsBackend], dllOverrides: [String: String] = [:], environment: [String: String] = [:], arguments: [String] = [], antiCheat: [AntiCheatProfile] = [], profileVersion: Int = 1, source: CompatibilityProfileSource = .defaultProfile, confidence: CompatibilityConfidence = .low, lastSuccessfulRenderer: GraphicsBackend? = nil, lastFailure: CompatibilityResultCategory? = nil, updatedAt: Date = Date()) {
        self.appID = appID
        self.gameName = gameName
        self.executables = executables
        self.preferredRenderer = preferredRenderer
        self.fallbackRenderers = fallbackRenderers
        self.dllOverrides = dllOverrides
        self.environment = environment
        self.arguments = arguments
        self.antiCheat = antiCheat
        self.profileVersion = profileVersion
        self.source = source
        self.confidence = confidence
        self.lastSuccessfulRenderer = lastSuccessfulRenderer
        self.lastFailure = lastFailure
        self.updatedAt = updatedAt
    }
}

public struct CompatibilityAttempt: Codable, Equatable, Sendable {
    public let appID: String
    public let executable: String
    public let renderer: GraphicsBackend
    public let architecture: PEArchitecture
    public let duration: TimeInterval
    public let exitCode: Int32?
    public let result: CompatibilityResultCategory
    public let visualStateUnverified: Bool
    public let notes: [String]
    public let createdAt: Date

    public init(appID: String, executable: String, renderer: GraphicsBackend, architecture: PEArchitecture, duration: TimeInterval, exitCode: Int32?, result: CompatibilityResultCategory, visualStateUnverified: Bool = true, notes: [String] = [], createdAt: Date = Date()) {
        self.appID = appID
        self.executable = executable
        self.renderer = renderer
        self.architecture = architecture
        self.duration = duration
        self.exitCode = exitCode
        self.result = result
        self.visualStateUnverified = visualStateUnverified
        self.notes = notes
        self.createdAt = createdAt
    }
}

public protocol CompatibilityProfileRemote: Sendable {
    func validatedProfile(appID: String) async throws -> GameCompatibilityProfile?
}

public actor CompatibilityProfileProvider {
    private let storeURL: URL
    private let remote: CompatibilityProfileRemote?
    private var localProfiles: [String: GameCompatibilityProfile]

    public init(storeURL: URL = PortsidePaths.profiles.appendingPathComponent("compatibility-profiles.json"), remote: CompatibilityProfileRemote? = nil) {
        self.storeURL = storeURL
        self.remote = remote
        if let data = try? Data(contentsOf: storeURL), let profiles = try? JSONDecoder.portside.decode([String: GameCompatibilityProfile].self, from: data) {
            self.localProfiles = profiles
        } else {
            self.localProfiles = [:]
        }
    }

    public func profile(for appID: String) -> GameCompatibilityProfile? { localProfiles[appID] }

    public func save(_ profile: GameCompatibilityProfile) throws {
        localProfiles[profile.appID] = profile
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.portside.encode(localProfiles).write(to: storeURL, options: .atomic)
    }

    public func resolve(appID: String, detected: GameCompatibilityProfile?) async -> GameCompatibilityProfile {
        if let remote, let backend = try? await remote.validatedProfile(appID: appID), backend.source == .backendValidated {
            return backend
        }
        if let local = localProfiles[appID], local.source == .localValidated || local.source == .userConfirmed {
            return local
        }
        if let detected { return detected }
        return Self.defaultProfile(appID: appID, gameName: "Unknown game")
    }

    public static func defaultProfile(appID: String, gameName: String) -> GameCompatibilityProfile {
        GameCompatibilityProfile(appID: appID, gameName: gameName, executables: [], preferredRenderer: .wineD3D, fallbackRenderers: [], source: .defaultProfile, confidence: .low)
    }
}

public enum CompatibilityProfileBuilder {
    public static func build(appID: String, gameName: String, evidences: [PEImportEvidence]) -> GameCompatibilityProfile {
        let profiles = evidences.map { evidence -> ExecutableProfile in
            let renderers = renderers(for: evidence)
            return ExecutableProfile(executablePath: evidence.executable.path, architecture: evidence.architecture, detectedAPIs: evidence.graphicsAPIs, preferredRenderer: renderers.first ?? .wineD3D, fallbackRenderers: Array(renderers.dropFirst()), evidence: [CompatibilityEvidence(from: evidence)])
        }
        let allRenderers = profiles.flatMap { [$0.preferredRenderer] + $0.fallbackRenderers }
        let preferred = profiles.first?.preferredRenderer ?? .wineD3D
        return GameCompatibilityProfile(appID: appID, gameName: gameName, executables: profiles, preferredRenderer: preferred, fallbackRenderers: Array(allRenderers.dropFirst()), antiCheat: antiCheatProfiles(from: evidences), source: evidences.isEmpty ? .defaultProfile : .peAnalysis, confidence: evidences.isEmpty ? .low : .medium)
    }

    public static func renderers(for evidence: PEImportEvidence) -> [GraphicsBackend] {
        let apis = Set(evidence.graphicsAPIs)
        if apis.contains(.directX8) || apis.contains(.directX9) { return [.wineD3D] }
        if apis.contains(.directX12) { return [.vkd3d, .wineD3D] }
        if apis.contains(.vulkan) { return [.nativeVulkan, .wineD3D] }
        if apis.contains(.openGL) { return [.nativeOpenGL, .wineD3D] }
        if apis.contains(.directX10) || apis.contains(.directX11) {
            let unity = evidence.engineHints.contains { $0 == "unity" }
            return unity ? [.dxmt, .dxvk, .wineD3D] : [.dxmt, .wineD3D]
        }
        return [.wineD3D]
    }

    private static func antiCheatProfiles(from evidences: [PEImportEvidence]) -> [AntiCheatProfile] {
        let providers = Set(evidences.flatMap(\.antiCheatProviders))
        return providers.sorted { $0.rawValue < $1.rawValue }.map { provider in
            AntiCheatProfile(provider: provider, kernelDriverRequired: provider == .battlEye || provider == .easyAntiCheat, wineSupport: "unknown", status: "informational", evidence: evidences.filter { $0.antiCheatProviders.contains(provider) }.map { $0.executable.lastPathComponent })
        }
    }
}
