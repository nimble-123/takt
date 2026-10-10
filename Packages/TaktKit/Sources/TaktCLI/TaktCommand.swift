import ArgumentParser
import Foundation
import TaktAnalytics
import TaktCore

// MARK: - TaktCommand

/// `takt`: Takt from the terminal (#189, CL-01–CL-06).
public struct TaktCommand: AsyncParsableCommand {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public static let configuration = CommandConfiguration(
    commandName: "takt",
    abstract: "Track time with Takt from the terminal.",
    discussion: """
      Changes appear in the menu bar and the main window at once. The data folder is the app's, \
      or TAKT_DATA_DIR.

      Exit codes: 0 success, 1 invalid input, 3 nothing running or paused, 4 not found, 5 ambiguous.
      """,
    subcommands: [Status.self, Start.self, Stop.self, Pause.self, Resume.self, LogCommand.self, ReportCommand.self],
    defaultSubcommand: Status.self,
  )
}

// MARK: - GlobalOptions

struct GlobalOptions: ParsableArguments {
  @Flag(help: "Print JSON instead of text.")
  var json = false

  @Option(name: .customLong("data-dir"), help: "Use this data folder instead of the app's.")
  var dataDirectory: String?

  func session() throws -> Session {
    try Session.open(dataDirectory: dataDirectory)
  }
}

// MARK: - Status

struct Status: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Show running and paused timers.")

  @OptionGroup var options: GlobalOptions

  func run() async throws {
    try await report {
      let timers = try await options.session().status()
      return options.json ? try Format.json(timers) : Format.status(timers)
    }
  }
}

// MARK: - Start

struct Start: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Start a timer.",
    discussion: """
      The text is the title, with @category, /project or /project/task and #tag as in the menu bar. \
      #4821 or 4821 alone starts that work item. By default the running timer pauses.

      Examples:
        takt start "Code review @Review /Portal"
        takt start 4821 --parallel
      """,
  )

  @OptionGroup var options: GlobalOptions

  @Flag(help: "Keep the running timers running.")
  var parallel = false

  @Argument(help: "Title with optional @category /project/task #tag, or a work item number.")
  var text: [String]

  func run() async throws {
    try await report {
      let started = try await options.session().start(text.joined(separator: " "), parallel: parallel)
      return options.json ? try Format.json(started) : "Started: \(started.line)"
    }
  }
}

// MARK: - Stop

struct Stop: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Stop one timer, or all of them.")

  @OptionGroup var options: GlobalOptions

  @Argument(help: "The start of an entry's ID or its title; all timers without it.")
  var entry: String?

  func run() async throws {
    try await report {
      let titles = try await options.session().stop(entry)
      return options.json ? try Format.json(["stopped": titles]) : "Stopped: " + titles.joined(separator: ", ")
    }
  }
}

// MARK: - Pause

struct Pause: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Pause one timer, or all running ones.")

  @OptionGroup var options: GlobalOptions

  @Argument(help: "The start of an entry's ID or its title; all running timers without it.")
  var entry: String?

  func run() async throws {
    try await report {
      let titles = try await options.session().pause(entry)
      return options.json ? try Format.json(["paused": titles]) : "Paused: " + titles.joined(separator: ", ")
    }
  }
}

// MARK: - Resume

struct Resume: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Resume a paused timer.",
    discussion: "Without an entry it resumes what `takt pause` paused, or the only paused timer.",
  )

  @OptionGroup var options: GlobalOptions

  @Flag(help: "Keep the running timers running.")
  var parallel = false

  @Argument(help: "The start of an entry's ID or its title.")
  var entry: String?

  func run() async throws {
    try await report {
      let titles = try await options.session().resume(entry, parallel: parallel)
      return options.json ? try Format.json(["resumed": titles]) : "Resumed: " + titles.joined(separator: ", ")
    }
  }
}

// MARK: - PeriodOptions

struct PeriodOptions: ParsableArguments {
  @Flag(help: "The period (default: day for log, week for report).")
  var period: Session.Period?

  @Option(help: "A day in the period, as YYYY-MM-DD (default: today).")
  var date: String?

  func day() throws -> Timestamp? {
    guard let date else { return nil }
    guard
      let parts = Timestamp.localDayParts(date),
      let day = Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    else {
      throw CLIError.invalid("Use a date like 2026-10-07.")
    }
    return Timestamp(day)
  }
}

// MARK: - LogCommand

struct LogCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(commandName: "log", abstract: "List the entries of a day, week or month.")

  @OptionGroup var options: GlobalOptions
  @OptionGroup var period: PeriodOptions

  func run() async throws {
    try await report {
      let session = try options.session()
      let log = try await session.log(period.period ?? .day, around: try period.day())
      return options.json ? try Format.json(log) : Format.log(log, calendar: session.calendar)
    }
  }
}

// MARK: - ReportCommand

struct ReportCommand: AsyncParsableCommand {
  enum By: String, ExpressibleByArgument, CaseIterable {
    case project
    case category
  }

  static let configuration = CommandConfiguration(commandName: "report", abstract: "Sum up the time per project or category.")

  @OptionGroup var options: GlobalOptions
  @OptionGroup var period: PeriodOptions

  @Option(help: "Group by project or category.")
  var by = By.project

  func run() async throws {
    try await report {
      let grouping: Grouping = by == .project ? .project : .category
      let report = try await options.session().report(period.period ?? .week, around: try period.day(), by: grouping)
      return options.json ? try Format.json(report) : Format.report(report)
    }
  }
}

// MARK: - Session.Period + EnumerableFlag

extension Session.Period: EnumerableFlag { }

/// Prints the output, or the error to standard error with the error's exit code.
private func report(_ body: () async throws -> String) async throws {
  do {
    // Standard output is the command line tool's interface, not a log.
    // swiftlint:disable:next no_direct_standard_out_logs
    print(try await body())
  } catch let error as CLIError {
    FileHandle.standardError.write(Data("takt: \(error)\n".utf8))
    throw ExitCode(error.exitCode)
  }
}
