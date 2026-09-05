import Foundation
import AppKit
import PortsideCore
import Darwin
import Security

@MainActor
final class PortsideAgentLauncher {
    private var process: Process?
    private var runtimeUpdaterProcess: Process?
    private let logger = PortsideLogger()
    private let updaterProcesses: any PortsideRuntimeUpdaterProcessControlling

    init(updaterProcesses: any PortsideRuntimeUpdaterProcessControlling = PortsideRuntimeUpdaterSystemProcesses()) {
        self.updaterProcesses = updaterProcesses
    }

    /// Older releases predate the cross-process bootstrap lease. Their updater
    /// only downloads into private pending directories; it never installs Steam
    /// or touches its prefix. Stop that exact service before taking the lease.
    func quiesceRuntimeUpdaters() async throws {
        let controller = updaterProcesses
        let stopped = try await Task.detached {
            try await PortsideRuntimeUpdaterMigration.quiesce(controller: controller)
        }.value
        runtimeUpdaterProcess = nil
        logger.write("runtime_updater_migration_quiesced count=\(stopped)")
    }

    func start(wrapper: URL, prefix: URL) {
        guard process?.isRunning != true, let helper = resolveAgent() else { return }
        let agent = Process()
        agent.executableURL = helper
        agent.arguments = ["--wrapper", wrapper.path, "--prefix", prefix.path]
        agent.standardOutput = FileHandle.nullDevice
        agent.standardError = FileHandle.nullDevice
        do {
            try agent.run()
            process = agent
        } catch {
            logger.write("agent_launch_failed reason=\(error.localizedDescription)", level: .error)
            process = nil
        }
    }

    func startRuntimeUpdater() {
        guard runtimeUpdaterProcess?.isRunning != true else { return }
        guard let helper = resolveAgent() else { return }
        let updater = Process()
        updater.executableURL = helper
        updater.arguments = ["--runtime-updater"]
        updater.standardOutput = FileHandle.nullDevice
        updater.standardError = FileHandle.nullDevice
        do {
            try updater.run()
            runtimeUpdaterProcess = updater
        } catch {
            logger.write("runtime_updater_agent_launch_failed reason=\(error.localizedDescription)", level: .error)
            runtimeUpdaterProcess = nil
        }
    }

    private func resolveAgent() -> URL? {
        do {
            return try PortsideBundleComponents.agent()
        } catch let error as PortsideBundleComponentError {
            logger.write(error.diagnostic, level: .error)
        } catch {
            logger.write("agent_resolution_failed reason=\(error.localizedDescription)", level: .error)
        }
        return nil
    }
}

struct PortsideRuntimeUpdaterProcess: Sendable, Equatable {
    let pid: pid_t
    let user: uid_t
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64
    let executable: URL
    let arguments: [String]

    var isRuntimeUpdater: Bool {
        // This is an ownership filter for an already-running process, not a
        // component resolver. Other products may use an identically named flag.
        let hierarchy = ["Portside.app", "Contents", "Helpers", "PortsideAgent.app", "Contents", "MacOS", "PortsideAgent"]
        return pid > 1 && pid != getpid() && executable.pathComponents.suffix(hierarchy.count).elementsEqual(hierarchy)
            && arguments == [executable.path, "--runtime-updater"]
    }
}

protocol PortsideRuntimeUpdaterProcessControlling: Sendable {
    var currentUser: uid_t { get }
    func applicationPublisher() throws -> String
    func candidates() throws -> [PortsideRuntimeUpdaterProcess]
    func hasValidAgentSignature(_ process: PortsideRuntimeUpdaterProcess, publisher: String) -> Bool
    func stillRunning(_ process: PortsideRuntimeUpdaterProcess) -> Bool
    func terminate(_ process: PortsideRuntimeUpdaterProcess, publisher: String) throws
}

enum PortsideRuntimeUpdaterMigrationError: LocalizedError {
    case couldNotStop
    var errorDescription: String? {
        "Portside could not pause its background updater. Close other Portside windows and try again."
    }
}

enum PortsideRuntimeUpdaterMigration {
    static func quiesce(controller: any PortsideRuntimeUpdaterProcessControlling, timeout: Duration = .seconds(5)) async throws -> Int {
        let candidates = try controller.candidates().filter { $0.user == controller.currentUser && $0.isRuntimeUpdater }
        guard !candidates.isEmpty else { return 0 }
        let publisher = try controller.applicationPublisher()
        var terminated: [PortsideRuntimeUpdaterProcess] = []
        for process in candidates {
            guard controller.stillRunning(process) else { continue }
            guard controller.hasValidAgentSignature(process, publisher: publisher) else {
                if !controller.stillRunning(process) { continue }
                throw PortsideRuntimeUpdaterMigrationError.couldNotStop
            }
            try controller.terminate(process, publisher: publisher)
            terminated.append(process)
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while terminated.contains(where: controller.stillRunning) {
            guard clock.now < deadline else { throw PortsideRuntimeUpdaterMigrationError.couldNotStop }
            try await Task.sleep(for: .milliseconds(50))
        }
        return terminated.count
    }
}

private struct PortsideRuntimeUpdaterSystemProcesses: PortsideRuntimeUpdaterProcessControlling {
    var currentUser: uid_t { getuid() }
    private let developerIDRequirement = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"

    func applicationPublisher() throws -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              valid(code: code, requirement: developerIDRequirement + " and identifier \"com.portside.app\"") else {
            throw PortsideRuntimeUpdaterMigrationError.couldNotStop
        }
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let publisher = values[kSecCodeInfoTeamIdentifier as String] as? String,
              !publisher.isEmpty, publisher.count <= 32,
              publisher.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.union(.decimalDigits).contains($0) }) else {
            throw PortsideRuntimeUpdaterMigrationError.couldNotStop
        }
        return publisher
    }

    func candidates() throws -> [PortsideRuntimeUpdaterProcess] {
        let byteCount = proc_listpids(UInt32(PROC_UID_ONLY), currentUser, nil, 0)
        guard byteCount >= 0 else { throw PortsideRuntimeUpdaterMigrationError.couldNotStop }
        var identifiers = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.size + 128)
        let actual = proc_listpids(UInt32(PROC_UID_ONLY), currentUser, &identifiers, Int32(identifiers.count * MemoryLayout<pid_t>.size))
        guard actual >= 0 else { throw PortsideRuntimeUpdaterMigrationError.couldNotStop }
        return identifiers.prefix(Int(actual) / MemoryLayout<pid_t>.size).compactMap(snapshot)
    }

    func hasValidAgentSignature(_ process: PortsideRuntimeUpdaterProcess, publisher: String) -> Bool {
        guard stillRunning(process) else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: process.pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        return valid(code: code, requirement: developerIDRequirement + " and identifier \"com.portside.agent\" and certificate leaf[subject.OU] = \"\(publisher)\"")
    }

    func stillRunning(_ process: PortsideRuntimeUpdaterProcess) -> Bool {
        guard let info = processInfo(process.pid) else { return false }
        return info.pbi_uid == process.user && info.pbi_start_tvsec == process.startedSeconds && info.pbi_start_tvusec == process.startedMicroseconds
    }

    func terminate(_ process: PortsideRuntimeUpdaterProcess, publisher: String) throws {
        // Revalidate argv, kernel start time and the running code immediately
        // before signalling. Never signal a reused PID or a compatibility agent.
        guard snapshot(process.pid) == process, hasValidAgentSignature(process, publisher: publisher), stillRunning(process) else { return }
        if kill(process.pid, SIGTERM) != 0 && errno != ESRCH { throw PortsideRuntimeUpdaterMigrationError.couldNotStop }
    }

    private func valid(code: SecCode, requirement text: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private func processInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return count == MemoryLayout<proc_bsdinfo>.size ? info : nil
    }

    private func snapshot(_ pid: pid_t) -> PortsideRuntimeUpdaterProcess? {
        guard pid > 1, pid != getpid(), let info = processInfo(pid), info.pbi_uid == currentUser else { return nil }
        // PROC_PIDPATHINFO_MAXSIZE is the C macro 4 * MAXPATHLEN; Swift does
        // not import that expression from sys/proc_info.h.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = URL(fileURLWithPath: String(decoding: path.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self))
        guard executable.lastPathComponent == "PortsideAgent", let arguments = arguments(pid), arguments == [executable.path, "--runtime-updater"] else { return nil }
        return PortsideRuntimeUpdaterProcess(pid: pid, user: info.pbi_uid, startedSeconds: info.pbi_start_tvsec, startedMicroseconds: info.pbi_start_tvusec, executable: executable, arguments: arguments)
    }

    private func arguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size, size <= 1_048_576 else { return nil }
        var data = Data(count: size)
        let status = data.withUnsafeMutableBytes { sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0) }
        guard status == 0, size >= MemoryLayout<Int32>.size else { return nil }
        data.count = size
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count == 2 else { return nil }
        let bytes = [UInt8](data)
        var index = MemoryLayout<Int32>.size
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var result: [String] = []
        for _ in 0..<count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            guard index < bytes.count, let argument = String(bytes: bytes[start..<index], encoding: .utf8) else { return nil }
            result.append(argument)
            index += 1
        }
        // Environment entries stay private in memory and are never interpreted
        // or logged. Only the two exact command-line arguments are considered.
        return result
    }
}
