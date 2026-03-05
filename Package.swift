// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperKiller",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhisperKiller", targets: ["WhisperKiller"])
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "WhisperKiller",
            dependencies: [
            ],
            path: "Sources/WhisperFree",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
