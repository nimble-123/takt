// swift-tools-version: 6.2
import PackageDescription

/// Development tools only. Provides the `format` command plugin (SwiftFormat and SwiftLint with the
/// Airbnb Swift Style Guide); kept apart from TaktKit so the app packages stay free of tool dependencies.
let package = Package(
  name: "BuildTools",
  dependencies: [
    .package(url: "https://github.com/airbnb/swift", exact: "1.2.0")
  ],
)
