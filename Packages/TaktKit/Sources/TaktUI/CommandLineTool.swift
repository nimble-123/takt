import AppKit
import Foundation

// MARK: - CommandLineTool

/// The `takt` command line tool inside the app bundle (#189) and its link into the PATH.
nonisolated struct CommandLineTool: Equatable {

  // MARK: Lifecycle

  init(bundle: URL = Bundle.main.bundleURL, link: URL = Self.defaultLink) {
    helper = bundle.appending(components: "Contents", "Helpers", "takt")
    self.link = link
  }

  // MARK: Internal

  enum State: Equatable {
    /// The app was built without the tool, e.g. in a test.
    case unavailable
    case notInstalled
    /// The link points to this app's tool.
    case installed
    /// Something else is at the link's place, e.g. the tool of another copy of Takt.
    case other(String)
  }

  /// `/usr/local/bin` is in the default PATH of macOS shells.
  static let defaultLink = URL(filePath: "/usr/local/bin/takt")

  let helper: URL
  let link: URL

  var state: State {
    let files = FileManager.default
    guard files.isExecutableFile(atPath: helper.path) else { return .unavailable }
    guard let destination = try? files.destinationOfSymbolicLink(atPath: link.path) else {
      return files.fileExists(atPath: link.path) ? .other(link.path) : .notInstalled
    }
    return URL(filePath: destination).standardizedFileURL == helper.standardizedFileURL ? .installed : .other(destination)
  }

  /// The shell command that links the tool, for the administrator prompt or to copy.
  var installCommand: String {
    "mkdir -p \(Self.quoted(link.deletingLastPathComponent().path)) && ln -sf \(Self.quoted(helper.path)) \(Self.quoted(link.path))"
  }

  /// Links the tool with an administrator prompt, because `/usr/local/bin` belongs to root.
  /// Returns an error message, or `nil` on success or when the user cancelled.
  @MainActor
  func install() -> String? {
    let source = "do shell script \"\(Self.appleScriptEscaped(installCommand))\" with administrator privileges"
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    guard let error else { return nil }
    // -128: the user cancelled the prompt.
    if error[NSAppleScript.errorNumber] as? Int == -128 { return nil }
    return error[NSAppleScript.errorMessage] as? String ?? String(describing: error)
  }

  // MARK: Private

  /// Single quotes for the shell.
  private static func quoted(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func appleScriptEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
  }
}
