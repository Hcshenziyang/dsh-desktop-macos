// swift-tools-version: 5.9

import PackageDescription

// This package description gives SourceKit-LSP a real Swift module to index.
// App bundle construction and release packaging continue to use build.sh.
let package = Package(
    name: "DSHDesktopCommunity",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "DSHLauncher", targets: ["DSHLauncher"]),
    ],
    targets: [
        .executableTarget(
            name: "DSHLauncher",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
