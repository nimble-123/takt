import Foundation
import GRDB
import TaktCore
import TaktStore
import Testing

@testable import TaktAnalytics

/// "Analyse über 12 Monate < 500 ms" (NFR Performance), measured from the database to the report.
struct PerformanceTests {

  // MARK: Internal

  @Test
  func twelveMonthsAreAnalysedFastEnough() async throws {
    let (database, range) = try yearOfData()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    let analyzer = Analyzer(calendar: calendar)

    let clock = ContinuousClock()
    let started = clock.now
    let data = try await AnalyticsSource(database: database).load(range, now: range.upperBound)
    let report = analyzer.report(data, in: range, now: range.upperBound, by: .category)
    let elapsed = clock.now - started

    #expect(data.entries.count == 3000)
    #expect(report.slices.count == 3000)
    #expect(report.total > 0)
    // Release builds must stay under 500 ms; debug builds are several times slower.
    #if DEBUG
    #expect(elapsed < .seconds(3), "took \(elapsed)")
    #else
    #expect(elapsed < .milliseconds(500), "took \(elapsed)")
    #endif
    // Reports the measured duration in the test log; tests are not shipped.
    // swiftlint:disable:next no_direct_standard_out_logs
    print(
      "12 months: \(data.entries.count) entries, \(data.entries.reduce(0) { $0 + $1.segments.count }) segments in \(elapsed)"
    )
  }

  // MARK: Private

  /// 250 working days × 12 entries × 12 segments = 36,000 segments, partly parallel.
  private func yearOfData() throws -> (AppDatabase, Range<Timestamp>) {
    let database = try AppDatabase.inMemory()
    let start = Timestamp(milliseconds: 1_759_269_600_000) // 2025-10-01 00:00 Berlin
    try database.writer.write { db in
      let category = CategoryID().uuidString
      try db.execute(
        sql: "INSERT INTO category (id, name, color) VALUES (?, 'Entwicklung', '#2563EB')",
        arguments: [category],
      )
      var day = 0
      var workDays = 0
      while workDays < 250 {
        defer { day += 1 }
        guard day % 7 < 5 else { continue }
        workDays += 1
        let dayStart = Int64(day) * 86_400_000 + start.milliseconds + 8 * 3_600_000
        for entryIndex in 0..<12 {
          let entry = EntryID().uuidString
          try db.execute(
            sql: """
              INSERT INTO time_entry (id, title, category_id, counting_mode, weight, state, created_at, updated_at)
              VALUES (?, ?, ?, ?, 1, 'stopped', ?, ?)
              """,
            arguments: [
              entry,
              "Entry \(entryIndex)",
              entryIndex % 2 == 0 ? category : nil,
              entryIndex % 3 == 0 ? "full" : nil,
              dayStart,
              dayStart,
            ],
          )
          for segmentIndex in 0..<12 {
            // Every entry works in short stretches spread over ten hours; neighbours overlap.
            let segmentStart = dayStart + Int64(segmentIndex * 50 + entryIndex * 4) * 60_000
            try db.execute(
              sql:
              "INSERT INTO segment (id, entry_id, start_at, end_at, source) VALUES (?, ?, ?, ?, 'live')",
              arguments: [SegmentID().uuidString, entry, segmentStart, segmentStart + 6 * 60_000],
            )
          }
        }
      }
    }
    return (database, start..<start.adding(seconds: 366 * 86_400))
  }

}
