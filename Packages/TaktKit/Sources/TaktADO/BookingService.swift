import Foundation
import os
import TaktCore
import TaktStore

// MARK: - BookingLine

/// What should be booked for one entry, work item and local day (DO-20, DO-24).
public struct BookingLine: Hashable, Sendable, Identifiable {

  // MARK: Public

  /// One line per entry, work item and day.
  public struct Key: Hashable, Sendable {
    public var entryID: EntryID
    public var workItemID: WorkItemLinkID
    public var localDay: String
  }

  /// Azure DevOps keeps hours with two decimals, so differences are booked in steps of 0.01 h.
  public static let step = 36

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

  public var id: Key {
    Key(entryID: entryID, workItemID: workItem.id, localDay: localDay)
  }

  /// Soll − Gebucht in steps of 0.01 h. Positive increases Completed Work, negative reduces it.
  public var difference: Int {
    Self.quantized(target - booked - inFlight)
  }

  // MARK: Internal

  /// `seconds` rounded to whole steps, halves away from zero. A record holds exactly what reaches
  /// Azure DevOps; the rest (under half a step) stays in the next difference instead of adding up.
  static func quantized(_ seconds: Int) -> Int {
    seconds.signum() * ((abs(seconds) + step / 2) / step) * step
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
    var titles = [EntryID: (title: String, note: String?)]()
    for entry in entries {
      titles[entry.id] = (entry.entry.title, entry.entry.note)
      guard let link = entry.entry.workItemLinkID, let seconds = allocated[entry.id] else { continue }
      targets[Key(entry: entry.id, link: link)] = Int(rounding.round(seconds).rounded())
    }
    let recordsByKey = Dictionary(grouping: records.filter { $0.localDay == localDay }) {
      Key(entry: $0.entryID, link: $0.workItemLinkID)
    }
    let keys = Set(targets.keys).union(recordsByKey.keys)

    return keys.compactMap { key -> BookingLine? in
      guard let workItem = workItems[key.link] else { return nil }
      let mine = recordsByKey[key] ?? []
      let booked = mine.filter { $0.status == .synced }.reduce(0) { $0 + $1.deltaSeconds }
      let inFlight = mine.filter { $0.status == .pending }.reduce(0) { $0 + $1.deltaSeconds }
      let failed = mine.last { $0.status == .failed }
      let lastFailedIsLatest =
        failed.map { failure in !mine.contains { $0.createdAt > failure.createdAt } } ?? false
      let title = titles[key.entry]?.title ?? deletedTitles[key.entry] ?? "?"
      return BookingLine(
        entryID: key.entry,
        title: title,
        note: titles[key.entry]?.note,
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
  public func book(_ lines: [BookingLine]) async -> [BookingLine.Key: Outcome] {
    var outcomes = [BookingLine.Key: Outcome]()
    for line in lines {
      outcomes[line.id] = await book(line)
    }
    return outcomes
  }

  public func book(_ line: BookingLine) async -> Outcome {
    guard line.inFlight == 0, line.difference != 0 else { return .nothingToDo }
    // Reserved synchronously, before the first suspension: a second call for the same line waits
    // for nothing and books nothing (the actor is reentrant at every `await`).
    guard linesInProgress.insert(line.id).inserted else { return .nothingToDo }
    defer { linesInProgress.remove(line.id) }
    do {
      guard let client = try accounts.client(for: line.workItem.organization) else {
        return .failed(.notConnected)
      }
      // The caller's line may be stale: the difference is taken from the stored records.
      guard let difference = try await currentDifference(of: line) else { return .nothingToDo }
      // The field is checked when sending, so an offline booking can still be queued.
      let record = SyncRecord(
        entryID: line.entryID,
        workItemLinkID: line.workItem.id,
        localDay: line.localDay,
        field: TimeField.completedWork,
        deltaSeconds: difference,
        createdAt: clock.now(),
      )
      // Reserved before it becomes visible as pending, so the queue does not send it a second time.
      recordsInFlight.insert(record.id)
      defer { recordsInFlight.remove(record.id) }
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
    // One keychain read per organization and run; nil means not connected.
    var clients = [String: ADOClient?]()
    for listed in pending {
      // Being sent right now by `book` or another run of the queue.
      guard recordsInFlight.insert(listed.id).inserted else { continue }
      defer { recordsInFlight.remove(listed.id) }
      // The list was read before the earlier records were sent: `book` or another run may have
      // finished this one meanwhile, so only a record that is still pending goes out.
      guard let record = try? await records.record(listed.id), record.status == .pending else { continue }
      guard let link = try? await cache.link(record.workItemLinkID) else {
        _ = await fail(record, .workItemUnknown)
        continue
      }
      if clients[link.organization] == nil {
        clients[link.organization] = .some(try? accounts.client(for: link.organization))
      }
      // Not connected (any more): stays pending until the organization is connected again.
      guard let client = clients[link.organization] ?? nil else { continue }
      do {
        if let revision = try await client.revision(of: link.workItemID, withHistoryContaining: record.marker) {
          try await markSynced(record, revision: revision)
          continue
        }
      } catch ADOError.notFound {
        // The work item is gone, so nothing can be booked on it any more, whatever arrived before.
        _ = await fail(record, .workItemGone)
        continue
      } catch ADOError.unauthorized {
        // Whether the booking arrived is still unknown: it stays pending until the token works again,
        // like an organization that is not connected.
        clients[link.organization] = .some(nil)
        schedule(after: backoff)
        continue
      } catch {
        // Unknown as well (server error, offline, the record could not be stored): ask again later.
        _ = keepPending(after: error)
        break
      }
      let entryNote = await note(of: record)
      if await send(record, note: entryNote, client: client) == .queued { break }
    }
    return (try? await records.pending().count) ?? 0
  }

  // MARK: Internal

  static let maxConflictRetries = 3
  /// First wait of the offline queue; doubles with every failed attempt up to `maxBackoff`.
  static let initialBackoff: TimeInterval = 30
  static let maxBackoff: TimeInterval = 15 * 60

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
  private var backoff = initialBackoff
  /// Lines `book` is working on, by `BookingLine.id`.
  private var linesInProgress = Set<BookingLine.Key>()
  /// Pending records that `book` or the queue is sending; nobody else touches them meanwhile.
  private var recordsInFlight = Set<SyncRecordID>()
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "booking")

  /// Whether Azure DevOps provably did not apply a patch: the token, the work item or the request
  /// was rejected. Any other failure (5xx, an answer that does not decode) leaves it open.
  private static func wasRejected(_ error: any Error) -> Bool {
    switch error {
    case ADOError.unauthorized, ADOError.notFound: true
    case ADOError.server(let status): status < 500
    default: false
    }
  }

  private static func rounded(_ hours: Double) -> Double {
    (hours * 100).rounded() / 100
  }

  /// Target minus what is booked or in flight according to the stored records; nil if nothing is
  /// left to book or another booking of the line is still pending.
  private func currentDifference(of line: BookingLine) async throws -> Int? {
    let stored = try await records.records(onDay: line.localDay).filter {
      $0.entryID == line.entryID && $0.workItemLinkID == line.workItem.id
    }
    guard !stored.contains(where: { $0.status == .pending }) else { return nil }
    let booked = stored.filter { $0.status == .synced }.reduce(0) { $0 + $1.deltaSeconds }
    let difference = BookingLine.quantized(line.target - booked)
    return difference == 0 ? nil : difference
  }

  private func send(_ record: SyncRecord, note: String?, client: ADOClient) async -> Outcome {
    guard let link = try? await cache.link(record.workItemLinkID) else {
      return await fail(record, .workItemUnknown)
    }
    var record = record
    let options = options()
    for _ in 0..<Self.maxConflictRetries {
      let patch: [PatchOperation]
      do {
        record.field = try await timeField(for: link, client: client)
        let current = try await client.timeValues(of: link.workItemID)
        let taken = try await remainingWorkTaken(onLineOf: record)
        (patch, record.remainingDeltaSeconds) = operations(
          for: record,
          current: current,
          remainingWorkTaken: taken,
          note: note,
          options: options,
        )
        // Stored before sending: if the outcome stays unknown and the queue finds the marker, the
        // record still says what the patch did to Remaining Work.
        try await records.update(record)
      } catch {
        // Nothing was sent yet, so a lasting failure is final.
        if handleTransient(error) == .queued { return .queued }
        return await fail(record, BookingFailure(error))
      }
      let revision: Int
      do {
        revision = try await client.patch(workItem: link.workItemID, patch)
      } catch ADOError.conflict {
        // Someone changed the work item in the meantime: read again and reapply.
        continue
      } catch {
        guard Self.wasRejected(error) else {
          // The patch may have been applied: the queue looks for the marker before sending again.
          return keepPending(after: error)
        }
        return await fail(record, BookingFailure(error))
      }
      do {
        try await markSynced(record, revision: revision)
      } catch {
        // Booked, but not stored: the queue finds the marker and marks the record synced.
        return keepPending(after: error)
      }
      backoff = Self.initialBackoff
      nextAttempt = nil
      return .booked
    }
    return await fail(record, .keepsChanging)
  }

  /// The patch and what it changes Remaining Work by, in seconds. A booking takes its time from
  /// Remaining Work down to 0; a correction gives back at most what the line took (DO-22).
  private func operations(
    for record: SyncRecord,
    current: ADOClient.TimeValues,
    remainingWorkTaken: Int,
    note: String?,
    options: Options,
  ) -> (operations: [PatchOperation], remainingDelta: Int) {
    let hours = Double(record.deltaSeconds) / 3600
    var operations = [PatchOperation(op: "test", path: "/rev", value: .int(current.revision))]
    var remainingDelta = 0
    if record.field == TimeField.completedWork {
      let completed = Self.rounded(max(0, (current.completedWork ?? 0) + hours))
      operations.append(
        PatchOperation(op: "add", path: "/fields/\(TimeField.completedWork)", value: .double(completed))
      )
      if options.reduceRemainingWork, let remaining = current.remainingWork {
        let changed =
          hours >= 0
            ? Self.rounded(max(0, remaining - hours))
            : Self.rounded(remaining + min(-hours, Double(remainingWorkTaken) / 3600))
        remainingDelta = Int(((changed - remaining) * 3600).rounded())
        operations.append(
          PatchOperation(op: "add", path: "/fields/\(TimeField.remainingWork)", value: .double(changed))
        )
      }
    }
    operations.append(
      PatchOperation(
        op: "add",
        path: "/fields/\(TimeField.history)",
        value: .string(comment(record, hours: hours, note: options.includeNote ? note : nil)),
      )
    )
    return (operations, remainingDelta)
  }

  /// Remaining Work the synced bookings of the record's line took and did not give back yet.
  /// Records from before this was kept count with their full time, as Takt assumed back then.
  private func remainingWorkTaken(onLineOf record: SyncRecord) async throws -> Int {
    let line = try await records.records(onDay: record.localDay).filter {
      $0.entryID == record.entryID && $0.workItemLinkID == record.workItemLinkID && $0.status == .synced
        && $0.id != record.id
    }
    let taken = line.reduce(0) { sum, booked in
      sum - (booked.remainingDeltaSeconds ?? (booked.field == TimeField.completedWork ? -booked.deltaSeconds : 0))
    }
    return max(0, taken)
  }

  /// `Takt: +0,25 h am 06.10.2026 · Notiz [takt:3f9c…]`
  private func comment(_ record: SyncRecord, hours: Double, note: String?) -> String {
    let amount =
      (hours >= 0 ? "+" : "−")
        + abs(hours).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE")))
    let day =
      Timestamp.localDayParts(record.localDay).map {
        String(format: "%02d.%02d.%04d", $0.day, $0.month, $0.year)
      } ?? record.localDay
    // German like the rest of the team's history in Azure DevOps (TECHNICAL_CONCEPT example).
    var text = "Takt: \(amount) h am \(day)"
    if let note, !note.isEmpty {
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

  /// The outcome of a sent patch is unknown: the record stays pending and the queue resolves it
  /// through the marker in the history, after the backoff (DO-26).
  private func keepPending(after error: any Error) -> Outcome {
    if handleTransient(error) == .queued { return .queued }
    logger.error("Booking outcome unknown, checked again later: \(String(describing: error), privacy: .public)")
    schedule(after: backoff)
    return .queued
  }

  private func schedule(after seconds: TimeInterval) {
    nextAttempt = clock.now().adding(seconds: seconds)
    backoff = min(backoff * 2, Self.maxBackoff)
  }

  /// The entry's note for the history comment when a booking is sent again.
  private func note(of record: SyncRecord) async -> String? {
    try? await entries.entry(record.entryID)?.note
  }
}
