// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Less",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "Packages/GRDB.swift"),
    ],
    targets: [
        .executableTarget(
            name: "Less",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Less",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
