// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EngifyApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EngifyApp", targets: ["EngifyApp"])
    ],
    targets: [
        .executableTarget(
            name: "EngifyApp",
            path: "Sources"
        )
    ]
)
