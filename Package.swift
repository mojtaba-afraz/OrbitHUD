// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AntigravityUsageWidget",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AntigravityUsageWidget", targets: ["AntigravityUsageWidget"]),
        .library(name: "AntigravityUsageCore", targets: ["AntigravityUsageCore"])
    ],
    targets: [
        .target(
            name: "AntigravityUsageCore",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "AntigravityUsageWidget",
            dependencies: ["AntigravityUsageCore"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AntigravityUsageCoreTests",
            dependencies: ["AntigravityUsageCore"],
            path: "Tests/AntigravityUsageCoreTests"
        )
    ]
)
