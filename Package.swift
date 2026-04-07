// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-field-theory-cli",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ft",
            dependencies: [
                "FieldTheory",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "FieldTheory"
        ),
        .testTarget(
            name: "FieldTheoryTests",
            dependencies: ["FieldTheory"]
        ),
    ]
)
