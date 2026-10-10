import SwiftUI

// MARK: - AppVersion

/// The version of the running app, as release-please sets it (`MARKETING_VERSION`), and the build.
nonisolated enum AppVersion {
  /// `0.6.1`; `–` outside an app bundle, e.g. in tests.
  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
  }

  static var build: String? {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
  }

  /// `v0.6.1`, like the release tag.
  static var tag: String {
    "v\(version)"
  }

  /// `0.6.1 (412)`
  static var full: String {
    build.map { "\(version) (\($0))" } ?? version
  }
}

// MARK: - AboutSection

/// Settings → "About Takt": version and links to the website, the source, the release notes
/// and the issue tracker.
struct AboutSection: View {

  // MARK: Internal

  static let website = URL(string: "https://nimble-123.github.io/takt/")
  static let source = URL(string: "https://github.com/nimble-123/takt")
  static let releases = URL(string: "https://github.com/nimble-123/takt/releases")
  static let issues = URL(string: "https://github.com/nimble-123/takt/issues/new/choose")

  var body: some View {
    Section(String(localized: "About Takt", bundle: .module)) {
      LabeledContent(String(localized: "Version", bundle: .module)) {
        Text(verbatim: AppVersion.full)
          .monospacedDigit()
          .textSelection(.enabled)
      }
      HStack(spacing: 16) {
        link(String(localized: "Website", bundle: .module), Self.website)
        link(String(localized: "Source on GitHub", bundle: .module), Self.source)
        link(String(localized: "Release Notes", bundle: .module), Self.releases)
        link(String(localized: "Report a Problem", bundle: .module), Self.issues)
      }
      Text("© 2026 Nils Lutz · MIT License", bundle: .module)
        .font(.system(size: 11))
        .foregroundStyle(Palette.textSecondary)
    }
  }

  // MARK: Private

  @ViewBuilder
  private func link(_ title: String, _ url: URL?) -> some View {
    if let url {
      Link(title, destination: url)
    }
  }
}
