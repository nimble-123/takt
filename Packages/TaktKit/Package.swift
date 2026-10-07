// swift-tools-version: 6.2
import PackageDescription

// Layers (dependencies point downwards only):
// TaktUI → services (TaktADO, TaktSystem, TaktAnalytics, TaktCalendar) → TaktStore → TaktCore.
// TaktCore, TaktStore and TaktAnalytics build on Linux; their tests run in a separate CI job.
// Targets that need Apple-only frameworks are declared inside `#if os(macOS)` below.

let package = Package(
    name: "TaktKit",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TaktCore", targets: ["TaktCore"]),
        .library(name: "TaktStore", targets: ["TaktStore"]),
        .library(name: "TaktAnalytics", targets: ["TaktAnalytics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(name: "TaktCore"),
        .target(
            name: "TaktStore",
            dependencies: [
                "TaktCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(name: "TaktAnalytics", dependencies: ["TaktCore", "TaktStore"]),
        .testTarget(name: "TaktCoreTests", dependencies: ["TaktCore"]),
        .testTarget(name: "TaktStoreTests", dependencies: ["TaktStore"]),
        .testTarget(
            name: "TaktAnalyticsTests",
            dependencies: ["TaktAnalytics", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)

#if os(macOS)
    package.products += [
        .library(name: "TaktSystem", targets: ["TaktSystem"]),
        .library(name: "TaktADO", targets: ["TaktADO"]),
        .library(name: "TaktCalendar", targets: ["TaktCalendar"]),
        .library(name: "TaktUI", targets: ["TaktUI"]),
    ]
    package.targets += [
        .target(
            name: "TaktSystem",
            dependencies: [
                "TaktCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .target(name: "TaktADO", dependencies: ["TaktCore", "TaktStore"]),
        .target(name: "TaktCalendar", dependencies: ["TaktCore", "TaktStore"]),
        .target(
            name: "TaktUI",
            dependencies: [
                "TaktCore",
                "TaktStore",
                "TaktAnalytics",
                "TaktSystem",
                "TaktADO",
                "TaktCalendar",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "TaktSystemTests", dependencies: ["TaktSystem"]),
        .testTarget(name: "TaktUITests", dependencies: ["TaktUI"]),
    ]
#endif
