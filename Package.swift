// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Maclovin",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "maclovin", targets: ["MaclovinCLI"]),
        .library(name: "MaclovinCore", targets: ["MaclovinCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "MaclovinCore"
        ),
        .executableTarget(
            name: "MaclovinCLI",
            dependencies: [
                "MaclovinCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // An executable runner (`swift run maclovin-tests`) instead of a
        // testTarget: on a Command Line Tools-only machine `swift test`
        // builds the bundle but silently never executes it (no xctest host),
        // so the suite runs through swift-testing's SwiftPM entry point in a
        // plain executable.
        .executableTarget(
            name: "maclovin-tests",
            dependencies: ["MaclovinCore"],
            path: "Tests/MaclovinCoreTests",
            swiftSettings: [
                .unsafeFlags(
                    [
                        "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                        // The CLT ships _Testing_Foundation as a binary-only
                        // framework (no swiftmodule), so the Foundation+Testing
                        // cross-import overlay cannot be loaded.
                        "-Xfrontend", "-disable-cross-import-overlays"
                    ],
                    .when(platforms: [.macOS])
                )
            ],
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                        "-Xlinker", "-rpath",
                        "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                    ],
                    .when(platforms: [.macOS])
                ),
                .linkedFramework("Testing", .when(platforms: [.macOS]))
            ]
        )
    ]
)
