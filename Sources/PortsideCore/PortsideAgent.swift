import Foundation

public struct GameLaunchSignals: Codable, Equatable, Sendable {
    public let appID: String
    public let executable: String
    public let renderer: GraphicsBackend
    public let architecture: PEArchitecture
    public let duration: TimeInterval
    public let exitCode: Int32?
    public let earlyExit: Bool
    public let missingDLL: Bool
    public let deviceCreationFailed: Bool
    public let shaderCompilationFailed: Bool
    public let assetBundleFailed: Bool
    public let launcherFailed: Bool
    public let steamAPIFailed: Bool
    public let anticheatDetected: Bool
    public let timeout: Bool
    public let stable: Bool
    public let visualStateVerified: Bool
    public let notes: [String]

    public init(appID: String, executable: String, renderer: GraphicsBackend, architecture: PEArchitecture, duration: TimeInterval, exitCode: Int32?, earlyExit: Bool = false, missingDLL: Bool = false, deviceCreationFailed: Bool = false, shaderCompilationFailed: Bool = false, assetBundleFailed: Bool = false, launcherFailed: Bool = false, steamAPIFailed: Bool = false, anticheatDetected: Bool = false, timeout: Bool = false, stable: Bool = false, visualStateVerified: Bool = false, notes: [String] = []) {
        self.appID = appID
        self.executable = executable
        self.renderer = renderer
        self.architecture = architecture
        self.duration = duration
        self.exitCode = exitCode
        self.earlyExit = earlyExit
        self.missingDLL = missingDLL
        self.deviceCreationFailed = deviceCreationFailed
        self.shaderCompilationFailed = shaderCompilationFailed
        self.assetBundleFailed = assetBundleFailed
        self.launcherFailed = launcherFailed
        self.steamAPIFailed = steamAPIFailed
        self.anticheatDetected = anticheatDetected
        self.timeout = timeout
        self.stable = stable
        self.visualStateVerified = visualStateVerified
        self.notes = notes
    }
}

public enum GameLaunchMonitor {
    public static func classify(_ signals: GameLaunchSignals) -> CompatibilityResultCategory {
        if signals.anticheatDetected { return .anticheatUnsupported }
        if signals.launcherFailed { return .launcherFailed }
        if signals.steamAPIFailed { return .steamAPIFailed }
        if signals.assetBundleFailed { return .assetBundleFailed }
        if signals.shaderCompilationFailed { return .shaderCompilationFailed }
        if signals.missingDLL { return .missingDependency }
        if signals.deviceCreationFailed { return .graphicsInitializationFailed }
        if signals.timeout { return .processCrashed }
        if signals.earlyExit && !signals.stable { return .processCrashed }
        if signals.stable && signals.visualStateVerified { return .stableLaunch }
        return .visualStateUnverified
    }

    public static func attempt(from signals: GameLaunchSignals) -> CompatibilityAttempt {
        let result = classify(signals)
        return CompatibilityAttempt(appID: signals.appID, executable: signals.executable, renderer: signals.renderer, architecture: signals.architecture, duration: signals.duration, exitCode: signals.exitCode, result: result, visualStateUnverified: !signals.visualStateVerified, notes: signals.notes)
    }
}

public final class GameLaunchRecorder: @unchecked Sendable {
    private let logger: PortsideLogger
    private let fileManager: FileManager
    private let fileURL: URL
    private let lock = NSLock()

    public init(logger: PortsideLogger = PortsideLogger(logFileName: "game-launches.log"), fileManager: FileManager = .default, fileURL: URL = PortsidePaths.logs.appendingPathComponent("game-launch-attempts.jsonl")) {
        self.logger = logger
        self.fileManager = fileManager
        self.fileURL = fileURL
    }

    public func record(_ signals: GameLaunchSignals) -> CompatibilityAttempt {
        let attempt = GameLaunchMonitor.attempt(from: signals)
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.portside.encode(attempt)
            if !fileManager.fileExists(atPath: fileURL.path) { fileManager.createFile(atPath: fileURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.close()
        } catch {
            logger.write("could not persist compatibility attempt", level: .warning)
        }
        logger.write("game attempt app=" + signals.appID + " renderer=" + signals.renderer.rawValue + " result=" + attempt.result.rawValue)
        return attempt
    }
}

public struct PortsideAgentConfiguration: Equatable, Sendable {
    public let wrapper: URL
    public let prefix: URL
    public let scanInterval: TimeInterval

    public init(wrapper: URL = PortsidePaths.baselineWrapper, prefix: URL = PortsidePaths.steamPrefix, scanInterval: TimeInterval = 30) {
        self.wrapper = wrapper.standardizedFileURL
        self.prefix = prefix.standardizedFileURL
        self.scanInterval = max(10, scanInterval)
    }
}

public final class PortsideAgent: @unchecked Sendable {
    private let configuration: PortsideAgentConfiguration
    private let scanner: SteamLibraryScanner
    private let profileProvider: CompatibilityProfileProvider
    private let rendererManager: RendererManager
    private let processMonitor: SteamReadinessMonitor
    private let launchRecorder: GameLaunchRecorder
    private let logger: PortsideLogger
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var previousSnapshot: SteamLibrarySnapshot?
    private var configuredAppIDs = Set<String>()
    private var observedGames: [Int32: (appID: String, executable: URL, renderer: GraphicsBackend, architecture: PEArchitecture, startedAt: Date)] = [:]
    private var running = false

    public init(configuration: PortsideAgentConfiguration = PortsideAgentConfiguration(), scanner: SteamLibraryScanner? = nil, profileProvider: CompatibilityProfileProvider = CompatibilityProfileProvider(), rendererManager: RendererManager? = nil, processMonitor: SteamReadinessMonitor = SteamReadinessMonitor(logger: PortsideLogger(logFileName: "agent-processes.log")), launchRecorder: GameLaunchRecorder = GameLaunchRecorder(), logger: PortsideLogger = PortsideLogger(logFileName: "portside-agent.log")) {
        self.configuration = configuration
        self.scanner = scanner ?? SteamLibraryScanner(prefix: configuration.prefix)
        self.profileProvider = profileProvider
        self.rendererManager = rendererManager ?? RendererManager(wrapper: configuration.wrapper, prefix: configuration.prefix)
        self.processMonitor = processMonitor
        self.launchRecorder = launchRecorder
        self.logger = logger
        self.queue = DispatchQueue(label: "com.portside.agent", qos: .utility)
    }

    public var isRunning: Bool { queue.sync { running } }

    public func start() {
        queue.sync { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.logger.write("compatibility agent started")
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.configuration.scanInterval)
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        queue.async { [weak self] in self?.stopOnQueue(reason: "requested") }
    }

    public func pollNow() {
        queue.async { [weak self] in self?.poll() }
    }

    public static func shouldContinue(steamManagedProcessCount: Int) -> Bool {
        steamManagedProcessCount > 0
    }

    private func poll() {
        let snapshots = processMonitor.captureProcessSnapshot()
        var managedPIDs = SteamProcessOwnership.managedPIDs(in: snapshots, wrapper: configuration.wrapper, prefix: configuration.prefix)
        managedPIDs.formUnion(SteamProcessOwnership.fileBackedManagedPIDs(in: snapshots, wrapper: configuration.wrapper, prefix: configuration.prefix))
        let steamPIDs = Set(snapshots.filter { snapshot in
            managedPIDs.contains(snapshot.pid) && (snapshot.command.localizedCaseInsensitiveContains("steam.exe") || snapshot.command.localizedCaseInsensitiveContains("steamwebhelper"))
        }.map(\.pid))
        guard Self.shouldContinue(steamManagedProcessCount: steamPIDs.count) else {
            stopOnQueue(reason: "managed Steam exited")
            return
        }
        do {
            let result = try scanner.scan(previous: previousSnapshot)
            previousSnapshot = result.snapshot
            for game in result.snapshot.games where game.isInstalled && !configuredAppIDs.contains(game.appID) {
                configuredAppIDs.insert(game.appID)
                configure(game)
            }
            let activeGames = Set(snapshots.filter { managedPIDs.contains($0.pid) && isGameProcess($0.command) }.map(\.pid))
            for process in snapshots where managedPIDs.contains(process.pid) && isGameProcess(process.command) {
                logger.write("detected managed game process " + process.command)
                observe(process: process, games: result.snapshot.games)
            }
            let finishedGames = observedGames.filter { !activeGames.contains($0.key) }
            for (pid, observation) in finishedGames {
                let duration = Date().timeIntervalSince(observation.startedAt)
                _ = launchRecorder.record(GameLaunchSignals(appID: observation.appID, executable: observation.executable.path, renderer: observation.renderer, architecture: observation.architecture, duration: duration, exitCode: nil, earlyExit: duration < 8, stable: duration >= 20, visualStateVerified: false, notes: ["process exited; visual state was not inspected"]))
                observedGames.removeValue(forKey: pid)
            }
        } catch {
            logger.write("library scan failed", level: .warning)
        }
    }

    private func observe(process: ManagedProcessSnapshot, games: [SteamGameInstallation]) {
        guard observedGames[process.pid] == nil, let game = game(for: process.command, games: games) else { return }
        let executable = executable(for: process.command, game: game)
        let configuration = rendererManager.configuration(appID: game.appID, executable: executable)
        observedGames[process.pid] = (game.appID, executable, configuration?.renderer ?? .wineD3D, .unknown, Date())
    }

    private func game(for command: String, games: [SteamGameInstallation]) -> SteamGameInstallation? {
        let lower = command.lowercased()
        return games.first { game in
            lower.contains(game.installDirectory.path.lowercased()) || lower.contains(game.installDirectory.lastPathComponent.lowercased()) || lower.contains(windowsPath(for: game).lowercased())
        }
    }

    private func executable(for command: String, game: SteamGameInstallation) -> URL {
        let token = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).first(where: { $0.lowercased().contains(".exe") }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        if let token, token.hasPrefix(configuration.prefix.path) { return URL(fileURLWithPath: token) }
        let name = token?.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "game.exe"
        return game.installDirectory.appendingPathComponent(name)
    }

    private func windowsPath(for game: SteamGameInstallation) -> String {
        let path = game.installDirectory.path.replacingOccurrences(of: "\\", with: "/")
        guard let driveIndex = path.range(of: "/drive_c/", options: [.caseInsensitive]) else { return "" }
        let suffix = path[driveIndex.upperBound...].replacingOccurrences(of: "/", with: "\\")
        return "c:\\" + suffix
    }

    private func configure(_ game: SteamGameInstallation) {
        let evidences = PEImportScanner().scan(game: game, scanner: scanner)
        let detected = CompatibilityProfileBuilder.build(appID: game.appID, gameName: game.gameName, evidences: evidences)
        Task {
            let profile = await profileProvider.resolve(appID: game.appID, detected: detected)
            try? await profileProvider.save(profile)
            let executables = profile.executables.isEmpty ? evidences.map { evidence in
                ExecutableProfile(executablePath: evidence.executable.path, architecture: evidence.architecture, detectedAPIs: evidence.graphicsAPIs, preferredRenderer: profile.preferredRenderer, fallbackRenderers: profile.fallbackRenderers, evidence: [CompatibilityEvidence(from: evidence)])
            } : profile.executables
            for executable in executables {
                let url = URL(fileURLWithPath: executable.executablePath)
                let candidates = [executable.preferredRenderer] + executable.fallbackRenderers + [profile.preferredRenderer] + profile.fallbackRenderers
                guard let renderer = candidates.first(where: { rendererManager.availableRenderers.contains($0) }) else {
                    logger.write("no available renderer for " + game.appID, level: .warning)
                    continue
                }
                do {
                    _ = try await rendererManager.apply(renderer: renderer, appID: game.appID, executable: url, baseEnvironment: executable.environment.isEmpty ? profile.environment : executable.environment, arguments: executable.arguments.isEmpty ? profile.arguments : executable.arguments)
                } catch {
                    logger.write("could not configure renderer for " + game.appID, level: .warning)
                }
            }
        }
    }

    private func isGameProcess(_ command: String) -> Bool {
        let lower = command.lowercased()
        guard lower.contains(".exe"), !lower.contains("steam.exe"), !lower.contains("steamwebhelper"), !lower.contains("wineserver") else { return false }
        return true
    }

    private func stopOnQueue(reason: String) {
        guard running else { return }
        running = false
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        logger.write("compatibility agent stopped: " + reason)
    }
}

public enum PortsideAgentRuntime {
    public static func make(arguments: [String] = CommandLine.arguments) -> PortsideAgent {
        var wrapper = PortsidePaths.baselineWrapper
        var prefix = PortsidePaths.steamPrefix
        var index = 1
        while index + 1 < arguments.count {
            switch arguments[index] {
            case "--wrapper": wrapper = URL(fileURLWithPath: arguments[index + 1])
            case "--prefix": prefix = URL(fileURLWithPath: arguments[index + 1])
            default: break
            }
            index += 2
        }
        return PortsideAgent(configuration: PortsideAgentConfiguration(wrapper: wrapper, prefix: prefix))
    }
}
