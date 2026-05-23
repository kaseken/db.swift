// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "db_tutorial_swift",
    targets: [
        .target(
            name: "DatabaseCore",
            path: "Sources/DatabaseCore",
        ),
        .executableTarget(
            name: "db",
            dependencies: ["DatabaseCore"],
            path: "Sources/db",
        ),
        .testTarget(
            name: "DatabaseCoreTests",
            dependencies: ["DatabaseCore"],
            path: "Tests/DatabaseCoreTests",
        ),
    ],
)
