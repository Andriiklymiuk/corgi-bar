// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "corgi-bar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "corgi-bar", targets: ["CorgiBar"])],
    targets: [
        .executableTarget(
            name: "CorgiBar",
            path: "Sources/CorgiBar",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "CorgiBarTests",
            dependencies: ["CorgiBar"],
            path: "Tests/CorgiBarTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
