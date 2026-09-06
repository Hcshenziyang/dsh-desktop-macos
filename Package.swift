// swift-tools-version: 5.9
import PackageDescription

// One dependency graph drives editor indexing, regression tests and release builds.
let package = Package(
    name: "DSHDesktopCommunity",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DSHLauncher", targets: ["DSHLauncher"])],
    targets: [
        .target(name: "DSHCore", path: "Sources/Core", exclude: ["Web"],
                linkerSettings: [.linkedFramework("ServiceManagement")]),
        .target(name: "DSHWeb", path: "Sources/Core/Web"),
        .target(name: "DSHUI", path: "Sources/UI"),
        .target(name: "LocalModelFeature", dependencies: ["DSHCore", "DSHUI"], path: "Sources/Features/LocalModel"),
        .target(name: "ArchiveFeature", dependencies: ["DSHCore", "DSHUI"], path: "Sources/Features/Archive"),
        .target(name: "InspectorFeature", dependencies: ["DSHCore", "DSHUI"], path: "Sources/Features/Inspector"),
        .target(name: "PluginsFeature", dependencies: ["DSHCore", "DSHUI"], path: "Sources/Features/Plugins"),
        .target(name: "ThemesFeature", dependencies: ["DSHUI"], path: "Sources/Features/Themes"),
        .executableTarget(name: "DSHLauncher", dependencies: [
            "DSHCore", "DSHWeb", "DSHUI", "LocalModelFeature", "ArchiveFeature",
            "InspectorFeature", "PluginsFeature", "ThemesFeature"
        ], path: "Sources/App"),
        .testTarget(name: "DSHCoreTests", dependencies: ["DSHCore"], path: "Tests/Core"),
        .testTarget(name: "PluginsFeatureTests", dependencies: ["PluginsFeature", "DSHCore"], path: "Tests/Plugins", exclude: ["plugin-inventory.test.mjs"]),
        .testTarget(name: "FeatureBoundaryTests", dependencies: [
            "DSHCore", "DSHUI", "LocalModelFeature", "ArchiveFeature", "InspectorFeature", "PluginsFeature"
        ], path: "Tests/Boundaries"),
        .testTarget(name: "ServiceIntegrationTests", dependencies: ["DSHCore", "LocalModelFeature"],
                    path: "Tests/Integration"),
    ],
    swiftLanguageVersions: [.v5]
)
