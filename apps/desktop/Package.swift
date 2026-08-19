// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portside",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PortsideCore", targets: ["PortsideCore"]),
        .executable(name: "Portside", targets: ["Portside"]),
        .executable(name: "PortsideAgent", targets: ["PortsideAgent"])
    ],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.26.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.5")
    ],
    targets: [
        .target(name: "PortsideCore"),
        .executableTarget(
            name: "Portside",
            dependencies: [
                "PortsideCore",
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(name: "PortsideAgent", dependencies: ["PortsideCore"]),
        .testTarget(name: "PortsideCoreTests", dependencies: ["PortsideCore"])
    ]
)
