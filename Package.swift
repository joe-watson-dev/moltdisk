// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoltDisk",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "MoltDisk", path: "Sources/MoltDisk")
    ],
    swiftLanguageModes: [.v5]
)
