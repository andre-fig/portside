// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portside",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PortsideCore", targets: ["PortsideCore"]),
        .executable(name: "Portside", targets: ["Portside"])
    ],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.26.0")
    ],
    targets: [
        .target(name: "PortsideCore"),
        .executableTarget(
            name: "Portside",
            dependencies: [
                "PortsideCore",
                .product(name: "Sentry", package: "sentry-cocoa")
            ]
        ),
        .executableTarget(
            name: "SteamHost",
            dependencies: ["PortsideCore"]
        ),
        .testTarget(name: "PortsideCoreTests", dependencies: ["PortsideCore"])
    ]
)
