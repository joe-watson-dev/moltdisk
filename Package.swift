// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskSweep",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "DiskSweep", path: "Sources/DiskSweep")
    ],
    swiftLanguageModes: [.v5]
)
