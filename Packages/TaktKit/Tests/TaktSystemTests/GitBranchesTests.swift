import Foundation
import Testing

@testable import TaktSystem

struct GitBranchesTests {

  // MARK: Internal

  @Test
  func readsBranchesOfAFolderAndItsSubfolders() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let portal = try repository("portal", head: "ref: refs/heads/feature/1234-login\n")
    _ = try repository("backoffice", head: "ref: refs/heads/main\n")
    _ = try repository("detached", head: "3f9c0a1b2c3d4e5f60718293a4b5c6d7e8f90123\n")
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -3600)],
      ofItemAtPath: root.appending(path: "backoffice/.git/HEAD").path,
    )

    let branches = GitBranches(folders: [root]).current()

    #expect(branches.map(\.name) == ["feature/1234-login", "main"])
    #expect(branches.first?.repository.lastPathComponent == portal.lastPathComponent)
  }

  @Test
  func followsTheGitFileOfAWorktree() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let main = try repository("main", head: "ref: refs/heads/main\n")
    let worktreeGitDir = main.appending(path: ".git/worktrees/fix")
    try FileManager.default.createDirectory(at: worktreeGitDir, withIntermediateDirectories: true)
    try "ref: refs/heads/bugfix/AB#77\n".write(
      to: worktreeGitDir.appending(path: "HEAD"),
      atomically: true,
      encoding: .utf8,
    )
    let worktree = root.appending(path: "fix")
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    try "gitdir: \(worktreeGitDir.path)\n".write(
      to: worktree.appending(path: ".git"),
      atomically: true,
      encoding: .utf8,
    )

    #expect(GitBranches.branch(of: worktree)?.name == "bugfix/AB#77")
  }

  @Test
  func missingFoldersAreIgnored() {
    #expect(GitBranches(folders: [root.appending(path: "nope")]).current().isEmpty)
  }

  // MARK: Private

  private let root = FileManager.default.temporaryDirectory.appending(path: "takt-git-\(UUID().uuidString)")

  private func repository(_ name: String, head: String) throws -> URL {
    let repository = root.appending(path: name)
    try FileManager.default.createDirectory(
      at: repository.appending(path: ".git"),
      withIntermediateDirectories: true,
    )
    try head.write(to: repository.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
    return repository
  }

}
