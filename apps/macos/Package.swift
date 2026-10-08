// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yumu",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CGrain", path: "Sources/CGrain"),
        .executableTarget(
            name: "Yumu",
            dependencies: ["CGrain"],
            path: "Sources/Yumu",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .unsafeFlags(["-L", ".build/grain"]),
                .linkedLibrary("grain"),
                .linkedLibrary("iconv"),
                // reqwest reads the macOS system proxy through SystemConfiguration.
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
    ]
)
