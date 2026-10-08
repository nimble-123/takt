import Foundation
import os
import TaktCore
import TaktStore

// MARK: - BookingLine

/// What should be booked for one entry, work item and local day (DO-20, DO-24).
public struct BookingLine: Hashable, Sendable, Identifiable {
  public var entryID: EntryID
  public var title: String
  public var note: String?
  public var workItem: WorkItemLink
  /// `YYYY-MM-DD`
  public var localDay: String
  /// Rounded, allocated time of the entry on that day; 0 if it was deleted or moved.
  public var target: Int
  /// Sum of the successful bookings.
  public var booked: Int
  /// Sum of bookings that are sent but not confirmed yet.
  public var inFlight: Int
  /// The latest failed booking, shown in the day close.
  public var failure: String?

  public var id: String {
    "\(entryID.uuidString)|\(workItem.id.uuidString)|\(localDay)"
  }

  /// Soll − Gebucht. Positive increases Completed Work, negative reduces it.
  public var difference: Int {
    target - booked - inFlight
  }
}

// MARK: - BookingFailure

/// Why a booking failed; stored in `sync_record.error`, worded by the UI.
public enum BookingFailure: String, Error, Sendable {
  case notConnected
  case workItemUnknown
  case unauthorized
  case workItemGone
  case keepsChanging
  case server

  init(_ error: any Error) {
    switch error {
    case ADOError.unauthorized: self = .unauthorized
    case ADOError.notFound: self = .workItemGone
    case let failure as BookingFailure: self = failure
    default: self = .server
    }
  }
}

// MARK: - BookingPlanner

public enum BookingPlanner {
  /// Lines for every entry with a work item on `day`, plus every earlier booking of that day whose
  /// entry, link or time changed – so corrections are booked as differences, never twice.
  public static func lines(
    entries: [EntryWithSegments],
    workItems: [WorkItemLinkID: WorkItemLink],
    records: [SyncRecord],
    day: Range<Timestamp>,
    localDay: String,
    now: Timestamp,
    defaultMode: CountingMode,
    rounding: Rounding,
    deletedTitles: [EntryID: String] = [:],
  ) -> [BookingLine] {
    // Allocation over all entries of the day, also those without a work item: they share the time.
    let inputs = entries.flatMap { entry in
      entry.segments.map {
        Allocation.Input(
          entryID: entry.id,
          start: $0.start,
          end: $0.end ?? now,
          mode: entry.entry.countingMode ?? defaultMode,
          weight: entry.entry.weight,
        )
      }
    }
    let allocated = Allocation.allocate(inputs, in: day)

    struct Key: Hashable {
      var entry: EntryID
      var link: WorkItemLinkID
    }
    var targets = [Key: Int]()
    var titles = [EntryID: (String, String?)]()
    for entry in entries {
      titles[entry.id] = (entry.entry.title, entry.entry.note)
      guard let link = entry.entry.workItemLinkID, let seconds = allocated[entry.id] else { continue }
      targets[Key(entry: entry.id, link: link)] = Int(rounding.round(seconds).rounded())
    }
    let dayRecords = records.filter { $0.localDay == localDay }
    var keys = Set(targets.keys)
    keys.formUnion(dayRecords.map { Key(entry: $0.entryID, link: $0.workItemLinkID) })

    return keys.compactMap { key -> BookingLine? in
      guard let workItem = workItems[key.link] else { return nil }
      let mine = dayRecords.filter { $0.entryID == key.entry && $0.workItemLinkID == key.link }
      let booked = mine.filter { $0.status == .synced }.reduce(0) { $0 + $1.deltaSeconds }
      let inFlight = mine.filter { $0.status == .pending }.reduce(0) { $0 + $1.deltaSeconds }
      let failed = mine.last { $0.status == .failed }
      let lastFailedIsLatest =
        failed.map { failure in !mine.contains { $0.createdAt > failure.createdAt } } ?? false
      let title = titles[key.entry]?.0 ?? deletedTitles[key.entry] ?? "?"
      return BookingLine(
        entryID: key.entry,
        title: title,
        note: titles[key.entry]?.1,
        workItem: workItem,
        localDay: localDay,
        target: targets[key] ?? 0,
        booked: booked,
        inFlight: inFlight,
        failure: lastFailedIsLatest ? failed?.error : nil,
      )
    }
    .sorted { ($0.workItem.workItemID, $0.title) < ($1.workItem.workItemID, $1.title) }
  }
}

// MARK: - BookingService

/// Books differences to Azure DevOps (TECHNICAL_CONCEPT "Buchungsablauf"): record first, then one
/// JSON patch with `test /rev`, time fields and a history comment carrying `takt:<id>`.
public actor BookingService {

  // MARK: Lifecycle

  public init(
    accounts: ADOAccounts,
    records: SyncRecordStore,
    cache: WorkItemCache,
    entries: EntryQueries,
    clock: any TaktClock,
    options: @escaping @Sendable () -> Options,
  ) {
    self.accounts = accounts
    self.records = records
    self.cache = cache
    self.entries = entries
    self.clock = clock
    self.options = options
  }

  // MARK: Public

  public struct Options: Sendable {
    public init(reduceRemainingWork: Bool = true, includeNote: Bool = true) {
      self.reduceRemainingWork = reduceRemainingWork
      self.includeNote = includeNote
    }

    /// DO-22: reduce Remaining Work by the same time, never below 0.
    public var reduceRemainingWork: Bool
    /// DO-23: add the entry's note to the history comment.
    public var includeNote: Bool

  }

  public enum Outcome: Equatable, Sendable {
    case booked
    /// Offline or throttled; stays pending and is sent again later (DO-26).
    case queued
    case failed(BookingFailure)
    case nothingToDo
  }

  /// Books the difference of every line; lines with a booking in flight are left to the queue.
  public func book(_ lines: [BookingLine]) async -> [String: Outcome] {
    var outcomes = [String: Outcome]()
    for line in lines {
      outcomes[line.id] = await book(line)
    }
    return outcomes
  }

  public func book(_ line: BookingLine) async -> Outcome {
    guard line.inFlight == 0, line.difference != 0 else { return .nothingToDo }
    do {
      guard let client = try accounts.client(for: line.workItem.organization) else {
        return .failed(.notConnected)
      }
      // The field is checked when sending, so an offline booking can still be queued.
      let record = SyncRecord(
        entryID: line.entryID,
        workItemLinkID: line.workItem.id,
        localDay: line.localDay,
        field: TimeField.completedWork,
        deltaSeconds: line.difference,
        createdAt: clock.now(),
      )
      // Recorded before sending: after a crash the marker in the history tells whether it arrived.
      try await records.insert(record)
      return await send(record, note: line.note, client: client)
    } catch {
      return .failed(BookingFailure(error))
    }
  }

  /// Sends pending bookings again: on launch, when the network returns and from the day close.
  /// A booking whose marker is already in the work item's history counts as done (DO-26, crash).
  @discardableResult
  public func processPending(force: Bool = false) async -> Int {
    if !force, let nextAttempt, clock.now() < nextAttempt { return (try? await records.pending().count) ?? 0 }
    guard let pending = try? await records.pending() else { return 0 }
    var remaining = 0
    for record in pending {
      guard
        let link = try? await cache.link(record.workItemLinkID),
        let client = try? accounts.client(for: link.organization)
      else {
        remaining += 1
        continue
      }
      do {
        if let revision = try await client.revision(of: link.workItemID, withHistoryContaining: record.marker) {
          try await markSynced(record, revision: revision)
          continue
        }
      } catch {
        remaining += 1
        if case .queued = handleTransient(error) { break }
        continue
      }
      let entryNote = await note(of: record)
      if await send(record, note: entryNote, client: client) == .queued {
        remaining += 1
        break
      }
    }
    return remaining
  }

  // MARK: Internal

  static let maxConflictRetries = 3

  // MARK: Private

  private let accounts: ADOAccounts
  private let records: SyncRecordStore
  private let cache: WorkItemCache
  private let entries: EntryQueries
  private let clock: any TaktClock
  private let options: @Sendable () -> Options
  private var fieldsByType = [String: Set<String>]()
  /// Exponential backoff for the offline queue; `Retry-After` wins if longer.
  private var nextAttempt: Timestamp?
  private var backoff: TimeInterval = 30
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "booking")

  private static func rounded(_ hours: Double) -> Double {
    (hours * 100).rounded() / 100
  }

  private func send(_ record: SyncRecord, note: String?, client: ADOClient) async -> Outcome {
    guard let link = try? await cache.link(record.workItemLinkID) else {
      return await fail(record, .workItemUnknown)
    }
    var record = record
    for _ in 0..<Self.maxConflictRetries {
      do {
        record.field = try await timeField(for: link, client: client)
        let current = try await client.timeValues(of: link.workItemID)
        let revision = try await client.patch(
          workItem: link.workItemID,
          operations(for: record, current: current, note: note),
        )
        try await markSynced(record, revision: revision)
        backoff = 30
        nextAttempt = nil
        return .booked
      } catch ADOError.conflict {
        // Someone changed the work item in the meantime: read again and reapply.
        continue
      } catch {
        let outcome = handleTransient(error)
        if outcome == .queued { return .queued }
        return await fail(record, BookingFailure(error))
      }
    }
    return await fail(record, .keepsChanging)
  }

  private func operations(for record: SyncRecord, current: ADOClient.TimeValues, note: String?) -> [PatchOperation] {
    let hours = Double(record.deltaSeconds) / 3600
    var operations = [PatchOperation(op: "test", path: "/rev", value: .int(current.revision))]
    if record.field == TimeField.completedWork {
      let completed = Self.rounded(max(0, (current.completedWork ?? 0) + hours))
      operations.append(
        PatchOperation(op: "add", path: "/fields/\(TimeField.completedWork)", value: .double(completed))
      )
      if options().reduceRemainingWork, let remaining = current.remainingWork {
        let reduced = Self.rounded(max(0, remaining - hours))
        operations.append(
          PatchOperation(op: "add", path: "/fields/\(TimeField.remainingWork)", value: .double(reduced))
        )
      }
    }
    operations.append(
      PatchOperation(
        op: "add",
        path: "/fields/\(TimeField.history)",
        value: .string(comment(record, hours: hours, note: note)),
      )
    )
    return operations
  }

  /// `Takt: +0,25 h am 06.10.2026 · Notiz [takt:3f9c…]`
  private func comment(_ record: SyncRecord, hours: Double, note: String?) -> String {
    let amount =
      (hours >= 0 ? "+" : "−")
        + abs(hours).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE")))
    let parts = record.localDay.split(separator: "-")
    let day = parts.count == 3 ? "\(parts[2]).\(parts[1]).\(parts[0])" : record.localDay
    // German like the rest of the team's history in Azure DevOps (TECHNICAL_CONCEPT example).
    var text = "Takt: \(amount) h am \(day)"
    if options().includeNote, let note, !note.isEmpty {
      text += " · " + note
    }
    return text + " [\(record.marker)]"
  }

  private func timeField(for item: WorkItemLink, client: ADOClient) async throws -> String {
    let key = "\(item.organization)|\(item.project)|\(item.cachedType ?? "")"
    if let fields = fieldsByType[key] {
      return fields.contains(TimeField.completedWork) ? TimeField.completedWork : TimeField.history
    }
    guard let type = item.cachedType else { return TimeField.completedWork }
    let fields = try await client.fieldNames(of: type, in: item.project)
    fieldsByType[key] = fields
    return fields.contains(TimeField.completedWork) ? TimeField.completedWork : TimeField.history
  }

  private func markSynced(_ record: SyncRecord, revision: Int) async throws {
    var synced = record
    synced.status = .synced
    synced.adoRevision = revision
    synced.error = nil
    synced.syncedAt = clock.now()
    try await records.update(synced)
  }

  private func fail(_ record: SyncRecord, _ failure: BookingFailure) async -> Outcome {
    var failed = record
    failed.status = .failed
    failed.error = failure.rawValue
    try? await records.update(failed)
    logger.error("Booking failed: \(failure.rawValue, privacy: .public)")
    return .failed(failure)
  }

  /// Offline and throttling keep the record pending and schedule the next attempt.
  private func handleTransient(_ error: any Error) -> Outcome {
    switch error {
    case ADOError.offline:
      schedule(after: backoff)
      return .queued

    case ADOError.throttled(let retryAfter):
      schedule(after: max(retryAfter ?? 0, backoff))
      return .queued

    default:
      return .failed(BookingFailure(error))
    }
  }

  private func schedule(after seconds: TimeInterval) {
    nextAttempt = clock.now().adding(seconds: seconds)
    backoff = min(backoff * 2, 15 * 60)
  }

  /// The entry's note for the history comment when a booking is sent again.
  private func note(of record: SyncRecord) async -> String? {
    try? await entries.entry(record.entryID)?.note
  }
}
