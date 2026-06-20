// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Less",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "Packages/GRDB.swift"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Less",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "Sparkle",
            ],
            path: "Sources/Less",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
