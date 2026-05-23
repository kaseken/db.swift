// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "db_tutorial_swift",
    targets: [
        .executableTarget(name: "db", path: "Sources/db"),
    ],
)
