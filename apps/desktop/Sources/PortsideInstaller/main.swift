import Darwin
import Foundation
import PortsideCore

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments.count == 5, arguments[0] == "--install",
       let owner = uid_t(arguments[3]), let group = gid_t(arguments[4]) {
        try PortsideInstallationTransaction.install(source: URL(fileURLWithPath: arguments[1]), expectedHash: arguments[2], owner: owner, group: group)
    } else if arguments.count == 3, arguments[0] == "--eject-after-exit", let pid = pid_t(arguments[1]), geteuid() != 0 {
        PortsideInstallationTransaction.ejectDiskImageAfterExit(processIdentifier: pid, source: URL(fileURLWithPath: arguments[2]))
    } else {
        exit(64)
    }
} catch let error as PortsideInstallationError {
    exit(error.installerExitStatus)
} catch {
    exit(74)
}
