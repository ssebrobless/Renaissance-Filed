// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RenaissanceLedger",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "RenaissanceLedger", targets: ["RenaissanceLedger"]),
        .executable(name: "RenaissanceHarness", targets: ["RenaissanceHarness"]),
    ],
    targets: [
        .executableTarget(
            name: "RenaissanceLedger",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "RenaissanceHarness",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
