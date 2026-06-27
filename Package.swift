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
        .testTarget(
            name: "MaclovinCoreTests",
            dependencies: ["MaclovinCore"],
            swiftSettings: [
                .unsafeFlags(
                    ["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"],
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
