// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "corgi-bar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "corgi-bar",
            path: "Sources/corgi-bar",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
    ]
)
