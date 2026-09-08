import Foundation
import Darwin
import PortsideCore

/// Exercise the real installer using only a freshly allocated fixture. This
/// executable is a build-time control; it is not shipped in Portside.app.
@main struct SikarugirInstallationProbe {
    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else { fatalError("Expected runtime archive directory") }
        let artifactsRoot = URL(fileURLWithPath: CommandLine.arguments[1])
        var template = Array(FileManager.default.temporaryDirectory.appendingPathComponent("portside-sikarugir-install-XXXXXX").path.utf8CString)
        guard let created = mkdtemp(&template) else { throw PortsideError.invalidPath }
        let root = URL(fileURLWithPath: String(cString: created), isDirectory: true)
        print("Fixture: \(root.path)")
        fflush(stdout)
        let home = root.appendingPathComponent("home")
        let state = home.appendingPathComponent("Library/Application Support/Portside")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let logger = PortsideLogger(logDirectory: state.appendingPathComponent("Logs"))
        let runner = FixtureRunner(home: home)
        let manifestURL = artifactsRoot.appendingPathComponent("runtime-manifest-unsigned.json")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        let components = raw["components"] as! [[String: Any]]
        var artifacts: [PortsideRuntimeArtifact: URL] = [:]
        for value in components {
            let component = try JSONDecoder().decode(PortsideRuntimeComponent.self, from: JSONSerialization.data(withJSONObject: value))
            artifacts[PortsideRuntimeArtifact(component: component)] = artifactsRoot.appendingPathComponent(component.downloadURL.lastPathComponent)
        }
        let installer = PortsideRuntimeInstaller(runner: runner, logger: logger, rootDirectory: state)
        // Reproduce the running desktop's cached legacy entry point before
        // replacing the same URL. This is synthetic metadata, never a copied
        // installed wrapper, real user prefix or executable that we run.
        let legacyWrapper = state.appendingPathComponent("Wrappers/PortsideBaseline.app")
        let legacyHost = legacyWrapper.appendingPathComponent("Contents/MacOS/PortsideRuntimeHost")
        try FileManager.default.createDirectory(at: legacyHost.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic legacy entry point".utf8).write(to: legacyHost)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: legacyHost.path)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.portside.runtime", "CFBundleExecutable": "PortsideRuntimeHost", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: legacyWrapper.appendingPathComponent("Contents/Info.plist"))
        guard let cachedLegacy = Bundle(url: legacyWrapper), cachedLegacy.executableURL?.lastPathComponent == "PortsideRuntimeHost" else {
            throw PortsideError.invalidArtifact("Fixture legacy bundle cache was not populated")
        }
        let start = Date()
        let first = try await installer.install(artifacts: artifacts)
        let firstDuration = Date().timeIntervalSince(start)
        let prefix = first.validation.prefix
        let wrapper = first.validation.wrapper
        let host = try PortsideBundleComponents.runtimeHost(in: wrapper)
        let marker = prefix.appendingPathComponent("portside-preservation.txt")
        try Data("synthetic preservation marker".utf8).write(to: marker)
        let info = try Data(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist"))
        func command(_ arguments: [String], expected: Int32 = 0) async throws {
            let result = try await runner.run(ProcessLaunchSpec(executable: host, arguments: ["--program"] + arguments, timeout: 60), logger: logger)
            guard result.status == expected else { throw PortsideError.processFailed("Fixture Windows control", result.status) }
        }
        try await command(["reg", "add", #"HKCU\Software\Microsoft\Windows\CurrentVersion\Run"#, "/v", "PortsideFixture", "/t", "REG_SZ", "/d", #"cmd /c echo unexpected > C:\portside-autostart-ran.txt"#, "/f"])
        let secondStart = Date()
        _ = try await installer.install(artifacts: artifacts)
        let secondDuration = Date().timeIntervalSince(secondStart)
        guard try String(contentsOf: marker, encoding: .utf8) == "synthetic preservation marker",
              !FileManager.default.fileExists(atPath: prefix.appendingPathComponent("drive_c/portside-autostart-ran.txt").path),
              try Data(contentsOf: wrapper.appendingPathComponent("Contents/Info.plist")) == info else {
            throw PortsideError.invalidArtifact("Fixture prefix data or wrapper metadata changed")
        }
        try await command(["reg", "delete", #"HKCU\Software\Microsoft\Windows\CurrentVersion\Run"#, "/v", "PortsideFixture", "/f"])
        try await command(["cmd", "/c", "exit", "37"], expected: 37)
        try await command([#"C:\windows\syswow64\cmd.exe"#, "/c", "exit", "23"], expected: 23)
        var installedSteam = false
        if CommandLine.arguments.contains("--install-steam") {
            let result = try await runner.run(PortsideSteamFlow.installationSpec(wrapper: wrapper), logger: logger)
            guard result.status == 0, FileManager.default.fileExists(atPath: PortsideSteamFlow.steamExecutable(prefix: prefix).path) else {
                throw PortsideError.processFailed("Fixture official Steam installation", result.status)
            }
            installedSteam = true
        }
        let report: [String: Any] = ["kind": "PortsideSikarugirInstallationProbe", "firstInstallationSeconds": firstDuration,
                                   "legacyMetadataReplacementVerified": true,
                                   "existingPrefixInstallationSeconds": secondDuration, "syntheticDataPreserved": true,
                                   "startupSkipped": true, "wrapperMetadataPreserved": true, "windowsX64Exit": 37, "windowsX86Exit": 23,
                                   "officialSteamInstalled": installedSteam, "renderedInteractionVerified": false,
                                   "portsideCommit": raw["portsideCommit"]!, "buildId": raw["buildId"]!,
                                   "archiveChecksums": Dictionary(uniqueKeysWithValues: artifacts.keys.map { ($0.component, $0.sha256) })]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]).write(to: root.appendingPathComponent("result.json"))
        // Keep this synthetic fixture for a separate LaunchServices/UI control.
        // Its exact root is local evidence only; never publish its contents.
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
        withExtendedLifetime(cachedLegacy) {}
    }
}

private struct FixtureRunner: ProcessRunning {
    let home: URL
    func run(_ specification: ProcessLaunchSpec, logger: PortsideLogger) async throws -> ProcessResult {
        var environment = specification.environment
        environment["HOME"] = home.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment["XDG_CACHE_HOME"] = home.appendingPathComponent("Cache").path
        let command = ProcessLaunchSpec(executable: specification.executable, arguments: specification.arguments,
                                        environment: environment, currentDirectory: specification.currentDirectory, timeout: specification.timeout)
        return try await SystemProcessRunner().run(command, logger: logger)
    }
}
