import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktCLI

/// The command line tool's commands against an in-memory database (#189).
struct SessionTests {

  // MARK: Lifecycle

  init() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    calendar.firstWeekday = 2
    session = Session(database: try AppDatabase.inMemory(), clock: clock, calendar: calendar)
  }

  // MARK: Internal

  @Test
  func startResolvesTokensAppliesRulesAndSwitches() async throws {
    let catalog = CatalogStore(database: session.database)
    let review = EntryCategory(name: "Review", color: "#7C3AED")
    let portal = Project(name: "Portal", color: "#0F766E", createdAt: clock.now())
    try await catalog.save(review)
    try await catalog.save(portal)
    try await RuleStore(database: session.database)
      .save([Rule(conditions: [.titleContains("review")], tags: ["quality"])])

    try await session.start("Ticket", parallel: false)
    let started = try await session.start("Code review @rev /port #urgent", parallel: false)

    #expect(started.title == "Code review")
    #expect(started.project == "Portal")
    #expect(started.category == "Review")
    let status = try await session.status()
    #expect(status.map(\.state) == ["running", "paused"])
    let entryID = try #require(EntryID(uuidString: started.id))
    let tags = try await catalog.tags(of: [entryID])[entryID]?.map(\.name).sorted()
    #expect(tags == ["quality", "urgent"])
  }

  @Test
  func unknownAndAmbiguousNamesFailWithTheirExitCodes() async throws {
    let catalog = CatalogStore(database: session.database)
    try await catalog.save(EntryCategory(name: "Meeting", color: "#C2410C"))
    try await catalog.save(EntryCategory(name: "Development", color: "#2563EB"))

    await #expect(throws: CLIError.notFound("project “nope”")) { try await session.start("x /nope", parallel: false) }
    await #expect(throws: CLIError.ambiguous("e", candidates: ["Development", "Meeting"])) {
      try await session.start("x @e", parallel: false)
    }
    await #expect(throws: CLIError.invalid("Give a title, e.g. takt start \"Code review @Review\".")) {
      try await session.start("  ", parallel: false)
    }
    #expect(CLIError.nothingActive.exitCode == 3)
    #expect(CLIError.notFound("").exitCode == 4)
    #expect(CLIError.ambiguous("", candidates: []).exitCode == 5)
  }

  @Test
  func aWorkItemNumberStartsTheCachedWorkItem() async throws {
    try await WorkItemCache(database: session.database)
      .store([WorkItemLink(organization: "contoso", project: "Portal", workItemID: 4821, cachedTitle: "Login")])

    let started = try await session.start("#4821", parallel: true)

    #expect(started.title == "Login")
    #expect(started.workItem == 4821)
    await #expect(throws: CLIError.notFound("work item #99 (not in the cache; open it in Takt once)")) {
      try await session.start("99", parallel: false)
    }
  }

  @Test
  func stopPauseAndResumeFindEntriesByTitleOrID() async throws {
    await #expect(throws: CLIError.nothingActive) { try await session.stop(nil) }
    try await session.start("Architecture review", parallel: true)
    let code = try await session.start("Code review", parallel: true)

    await #expect(throws: CLIError.ambiguous("review", candidates: ["Architecture review", "Code review"])) {
      try await session.stop("review")
    }
    #expect(try await session.pause(String(code.id.prefix(8))) == ["Code review"])
    #expect(try await session.pause(nil) == ["Architecture review"])
    // Two paused, but the last "pause" without an entry paused only one: it comes back.
    #expect(try await session.resume(nil, parallel: false) == ["Architecture review"])
    #expect(try await session.stop("code") == ["Code review"])
    #expect(try await session.stop(nil) == ["Architecture review"])
    await #expect(throws: CLIError.nothingActive) { try await session.resume(nil, parallel: false) }
  }

  @Test
  func logAndReportCoverThePeriod() async throws {
    let catalog = CatalogStore(database: session.database)
    let portal = Project(name: "Portal", color: "#0F766E", createdAt: clock.now())
    try await catalog.save(portal)
    try await session.start("A /Portal", parallel: false)
    clock.advance(seconds: 3600)
    try await session.start("B", parallel: false)
    clock.advance(seconds: 1800)
    try await session.stop(nil)

    let log = try await session.log(.day)
    #expect(log.rows.map(\.title) == ["A", "B"])
    #expect(log.totalSeconds == 5400)
    #expect(log.rows.last?.end != nil)

    let report = try await session.report(.week, by: .project)
    #expect(report.groups.map(\.name) == ["Portal", "(none)"])
    #expect(report.groups.map(\.seconds) == [3600, 1800])
    #expect(report.totalSeconds == 5400)

    let json = try Format.json(report)
    #expect(json.contains("\"name\" : \"Portal\""))
    #expect(Format.report(report).hasSuffix("Total     1:30"))
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000)) // Wed 2026-10-07 10:00 Berlin
  private let session: Session
}
