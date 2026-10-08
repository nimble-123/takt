import Foundation
import GRDB
import TaktCore

/// Daily copies of the database via the SQLite backup API, keeping the newest generations.
public struct DatabaseBackup: Sendable {

  // MARK: Lifecycle

  public init(directory: URL, generations: Int = 14, timeZone: TimeZone = .current) {
    self.directory = directory
    self.generations = generations
    self.timeZone = timeZone
  }

  // MARK: Public

  public let directory: URL
  public let generations: Int
  public let timeZone: TimeZone

  /// Writes today's backup unless it exists, then removes generations beyond the limit.
  /// Returns the new file, or `nil` if today's backup already existed.
  @discardableResult
  public func backupIfNeeded(_ database: AppDatabase, now: Timestamp) throws -> URL? {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "takt-\(localDay(now)).sqlite")
    guard !FileManager.default.fileExists(atPath: url.path) else { return nil }

    // Write to a temporary file first, so a failed backup never looks like today's backup.
    let partial = url.appendingPathExtension("partial")
    try? FileManager.default.removeItem(at: partial)
    try database.writer.backup(to: DatabaseQueue(path: partial.path))
    try FileManager.default.moveItem(at: partial, to: url)

    try prune()
    return url
  }

  /// Backups, oldest first.
  public func backups() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("takt-") && $0.pathExtension == "sqlite" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  // MARK: Private

  private func prune() throws {
    for url in try backups().dropLast(generations) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// `YYYY-MM-DD` in the local time zone; sorts chronologically.
  private func localDay(_ timestamp: Timestamp) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day], from: timestamp.date)
    func pad(_ value: Int?, _ width: Int) -> String {
      let string = String(value ?? 0)
      return String(repeating: "0", count: max(0, width - string.count)) + string
    }
    return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))"
  }
}
