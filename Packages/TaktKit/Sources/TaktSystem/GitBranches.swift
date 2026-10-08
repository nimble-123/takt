import Foundation
import TaktCore

// MARK: - GitBranch

/// The checked-out branch of a repository and when it was last switched.
public struct GitBranch: Hashable, Sendable {
  public init(repository: URL, name: String, switchedAt: Timestamp) {
    self.repository = repository
    self.name = name
    self.switchedAt = switchedAt
  }

  public var repository: URL
  public var name: String
  public var switchedAt: Timestamp

}

// MARK: - GitBranches

/// Reads branches from `.git/HEAD` without running `git` (PRD "Vorgeschlagene Items" 4).
public struct GitBranches: Sendable {

  // MARK: Lifecycle

  public init(folders: [URL]) {
    self.folders = folders
  }

  // MARK: Public

  public let folders: [URL]

  /// Each folder and its direct subfolders that are repositories; newest switch first.
  public func current() -> [GitBranch] {
    repositories().compactMap(Self.branch(of:)).sorted { $0.switchedAt > $1.switchedAt }
  }

  /// `current()` on the concurrent pool, so reading the files never blocks the main actor.
  @concurrent
  public func load() async -> [GitBranch] {
    current()
  }

  // MARK: Internal

  /// `.git` is a directory, or a file `gitdir: <path>` in a worktree or submodule.
  static func gitDirectory(of repository: URL) -> URL? {
    let dotGit = repository.appending(path: ".git")
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }
    if isDirectory.boolValue { return dotGit }
    guard
      let content = try? String(contentsOf: dotGit, encoding: .utf8),
      let line = content.split(separator: "\n").first, line.hasPrefix("gitdir:")
    else { return nil }
    let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
    return path.hasPrefix("/") ? URL(filePath: path) : repository.appending(path: path)
  }

  /// `nil` for a detached HEAD.
  static func branch(of repository: URL) -> GitBranch? {
    guard let gitDirectory = gitDirectory(of: repository) else { return nil }
    let head = gitDirectory.appending(path: "HEAD")
    guard let content = try? String(contentsOf: head, encoding: .utf8) else { return nil }
    let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard line.hasPrefix("ref: refs/heads/") else { return nil }
    let modified = (try? FileManager.default.attributesOfItem(atPath: head.path)[.modificationDate] as? Date) ?? nil
    return GitBranch(
      repository: repository,
      name: String(line.dropFirst("ref: refs/heads/".count)),
      switchedAt: modified.map(Timestamp.init) ?? Timestamp(milliseconds: 0),
    )
  }

  func repositories() -> [URL] {
    let fileManager = FileManager.default
    var found = [URL]()
    for folder in folders {
      if Self.gitDirectory(of: folder) != nil { found.append(folder) }
      let children =
        (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
      found += children.filter { Self.gitDirectory(of: $0) != nil }
    }
    return found
  }

}
