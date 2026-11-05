// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmberCat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EmberCat", targets: ["EmberCat"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(
            name: "CZstd",
            path: "Vendor/CZstd",
            exclude: ["LICENSE", "VENDOR.md"],
            publicHeadersPath: ".",
            cSettings: [
                .define("ZSTD_DISABLE_ASM", to: "1"),
                .define("ZSTD_LEGACY_SUPPORT", to: "0"),
                .define("ZSTD_TRACE", to: "0"),
            ]
        ),
        .target(
            name: "AgentSpeedCore",
            dependencies: ["CZstd"],
            path: "Vendor/AgentSpeedCore"
        ),
        .executableTarget(
            name: "EmberCat",
            dependencies: ["AgentSpeedCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/EmberCat",
            exclude: [
                "Resources/Sprites",
                "Resources/NotchFlame",
            ],
            resources: [.copy("Resources/MenuBarPets"), .copy("Resources/SourceIcons"),
                        .copy("Resources/DockIdleCat"),
                        .copy("Resources/NotchLightning"),
                        .copy("Resources/PetPreview")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "EmberCatTests", dependencies: ["EmberCat"], path: "Tests/EmberCatTests"),
    ]
)
