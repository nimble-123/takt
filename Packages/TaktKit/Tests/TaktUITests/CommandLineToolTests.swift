import Foundation
import Testing

@testable import TaktUI

/// Whether `takt` is linked into the PATH (#189).
struct CommandLineToolTests {

  @Test
  func stateFollowsTheHelperAndTheLink() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "takt-cli-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appending(path: "Takt.app")
    let link = root.appending(components: "bin", "takt")
    let tool = CommandLineTool(bundle: app, link: link)
    #expect(tool.state == .unavailable)

    try FileManager.default.createDirectory(at: tool.helper.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: tool.helper.path, contents: Data(), attributes: [.posixPermissions: 0o755])
    #expect(tool.state == .notInstalled)

    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appending(path: "other"))
    #expect(tool.state == .other(root.appending(path: "other").path))

    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool.helper)
    #expect(tool.state == .installed)
  }

  @Test
  func installCommandQuotesPathsWithSpacesAndQuotes() {
    let tool = CommandLineTool(
      bundle: URL(filePath: "/Volumes/My Disk/Nils' Apps/Takt.app"),
      link: URL(filePath: "/usr/local/bin/takt"),
    )
    #expect(
      tool.installCommand
        == "mkdir -p '/usr/local/bin' && ln -sf '/Volumes/My Disk/Nils'\\'' Apps/Takt.app/Contents/Helpers/takt' '/usr/local/bin/takt'"
    )
  }
}
