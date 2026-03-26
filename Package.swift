// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Engify",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Engify", targets: ["Engify"])
    ],
    targets: [
        .executableTarget(
            name: "Engify",
            path: "Sources"
        )
    ]
)
