// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortsideRuntimeHost",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "PortsideRuntimeHost"),
        .testTarget(name: "PortsideRuntimeHostTests", dependencies: ["PortsideRuntimeHost"])
    ]
)
