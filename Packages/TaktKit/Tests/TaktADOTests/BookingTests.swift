import Foundation
import Synchronization
import TaktCore
import TaktStore
import Testing

@testable import TaktADO

/// Planner and service against recorded Azure DevOps responses (TECHNICAL_CONCEPT "Teststrategie":
/// conflict, offline, 401, recovery after a crash, negative difference).
struct BookingTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    records = SyncRecordStore(database: database)
    cache = WorkItemCache(database: database)
    try secrets.write("token", for: "contoso")
    let accounts = ADOAccounts(
      secrets: secrets,
      suiteName: "takt-booking-\(UUID().uuidString)",
      session: stub.session,
    )
    accounts.save(ADOConnection(organization: "contoso", userName: "Nils"))
    service = BookingService(
      accounts: accounts,
      records: records,
      cache: cache,
      entries: EntryQueries(database: database),
      clock: clock,
    ) { BookingService.Options(reduceRemainingWork: true, includeNote: true) }
  }

  // MARK: Internal

  @Test
  func plannerBooksTheRoundedDifference() async throws {
    let link = try await workItem()
    _ = try await entry(link, minutes: 23)
    let line = try #require(try await lines(link, rounding: Rounding(minutes: 15)).first)
    #expect(line.target == 30 * 60)
    #expect(line.difference == 30 * 60)
  }

  @Test
  func deletedEntryIsBookedBackAsNegativeDifference() async throws {
    let link = try await workItem()
    let id = try await entry(link)
    try await records.insert(
      SyncRecord(
        entryID: id,
        workItemLinkID: link.id,
        localDay: "2026-10-07",
        field: TimeField.completedWork,
        deltaSeconds: 1800,
        status: .synced,
        adoRevision: 58,
        createdAt: clock.now(),
      )
    )
    let stored = try #require(try await EntryQueries(database: database).entry(id))
    try await TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
      .apply(EntryEdits.delete(stored, openSegment: nil, now: clock.now()))

    let line = try #require(try await lines(link).first)
    #expect(line.target == 0)
    #expect(line.difference == -1800)
  }

  @Test
  func pendingBookingIsNotBookedTwice() async throws {
    let link = try await workItem()
    let id = try await entry(link)
    try await records.insert(
      SyncRecord(
        entryID: id,
        workItemLinkID: link.id,
        localDay: "2026-10-07",
        field: TimeField.completedWork,
        deltaSeconds: 1800,
        createdAt: clock.now(),
      )
    )
    let line = try #require(try await lines(link).first)
    #expect(line.difference == 0)
    #expect(await service.book(line) == .nothingToDo)
  }

  @Test
  func bookingSendsOnePatchWithRevisionTimeAndMarker() async throws {
    respondNormally()
    let link = try await workItem()
    _ = try await entry(link)
    let line = try #require(try await lines(link).first)

    #expect(await service.book(line) == .booked)

    let body = try patchBody()
    #expect(body.first?["op"] as? String == "test")
    #expect(value("/rev", in: body) as? Int == 57)
    #expect(value("/fields/\(TimeField.completedWork)", in: body) as? Double == 8.0)
    #expect(value("/fields/\(TimeField.remainingWork)", in: body) as? Double == 2.5)
    let record = try #require(try await records.records(onDay: "2026-10-07").first)
    let comment = try #require(value("/fields/System.History", in: body) as? String)
    #expect(comment == "Takt: +0,50 h am 07.10.2026 · Ursache gefunden [\(record.marker)]")
    #expect(record.status == .synced && record.adoRevision == 58)
    #expect(
      stub.requests.first { $0.httpMethod == "PATCH" }?.value(forHTTPHeaderField: "Content-Type")
        == "application/json-patch+json"
    )
  }

  @Test
  func conflictIsRetriedWithFreshRevision() async throws {
    respondNormally { attempt in attempt == 1 ? 412 : 200 }
    let link = try await workItem()
    _ = try await entry(link)

    #expect(await service.book(try #require(try await lines(link).first)) == .booked)
    #expect(stub.requests.count(where: { $0.httpMethod == "PATCH" }) == 2)
    #expect(
      stub.requests.count(where: { $0.url?.path() == "/contoso/_apis/wit/workitems/1234" && $0.httpMethod == "GET" })
        == 2
    )
  }

  @Test
  func conflictsGiveUpAfterThreeAttempts() async throws {
    respondNormally { _ in 412 }
    let link = try await workItem()
    _ = try await entry(link)

    #expect(await service.book(try #require(try await lines(link).first)) == .failed(.keepsChanging))
    #expect(stub.requests.count(where: { $0.httpMethod == "PATCH" }) == 3)
    #expect(try await records.records(onDay: "2026-10-07").first?.status == .failed)
  }

  @Test
  func offlineBookingStaysPendingAndIsSentLater() async throws {
    stub.respond { _ in throw URLError(.notConnectedToInternet) }
    let link = try await workItem()
    _ = try await entry(link)

    #expect(await service.book(try #require(try await lines(link).first)) == .queued)
    #expect(try await records.pending().count == 1)
    // Still offline within the backoff: nothing is sent.
    #expect(await service.processPending() == 1)

    respondNormally()
    clock.advance(seconds: 60)
    stub.respond { request in
      if request.url?.path().hasSuffix("/updates") == true {
        return Stub.Response(status: 200, body: Data(#"{"count":0,"value":[]}"#.utf8))
      }
      if request.url?.path().contains("workitemtypes") == true {
        return Stub.Response(status: 200, body: try Stub.fixture("type-fields-task"))
      }
      if request.httpMethod == "PATCH" {
        return Stub.Response(status: 200, body: try Stub.fixture("workitem-patched"))
      }
      return Stub.Response(status: 200, body: try Stub.fixture("workitem-time"))
    }
    #expect(await service.processPending() == 0)
    #expect(try await records.pending().isEmpty)
    #expect(try await lines(link).first?.difference == 0)
  }

  @Test
  func rejectedTokenFailsVisibly() async throws {
    respondNormally()
    let link = try await workItem()
    _ = try await entry(link)
    let line = try #require(try await lines(link).first)
    stub.respond { request in
      request.httpMethod == "PATCH"
        ? Stub.Response(status: 401, body: Data())
        : request.url?.path().contains("workitemtypes") == true
          ? Stub.Response(status: 200, body: try Stub.fixture("type-fields-task"))
          : Stub.Response(status: 200, body: try Stub.fixture("workitem-time"))
    }

    #expect(await service.book(line) == .failed(.unauthorized))
    let failed = try #require(try await lines(link).first)
    #expect(failed.failure == BookingFailure.unauthorized.rawValue)
    #expect(failed.difference == 1800) // a failed booking does not count as booked
  }

  @Test
  func negativeDifferenceReducesCompletedAndRestoresRemaining() async throws {
    respondNormally()
    let link = try await workItem()
    let id = try await entry(link, minutes: 30)
    try await records.insert(
      SyncRecord(
        entryID: id,
        workItemLinkID: link.id,
        localDay: "2026-10-07",
        field: TimeField.completedWork,
        deltaSeconds: 3600,
        status: .synced,
        adoRevision: 57,
        createdAt: clock.now(),
      )
    )
    let line = try #require(try await lines(link).first)
    #expect(line.difference == -1800)

    #expect(await service.book(line) == .booked)
    let body = try patchBody()
    #expect(value("/fields/\(TimeField.completedWork)", in: body) as? Double == 7.0)
    #expect(value("/fields/\(TimeField.remainingWork)", in: body) as? Double == 3.5)
    #expect(
      (value("/fields/System.History", in: body) as? String)?.hasPrefix("Takt: −0,50 h am 07.10.2026") == true
    )
  }

  @Test
  func crashAfterSendingIsRecoveredFromTheHistory() async throws {
    let link = try await workItem()
    let id = try await entry(link)
    // The booking reached Azure DevOps, but Takt died before marking it synced.
    let record = SyncRecord(
      entryID: id,
      workItemLinkID: link.id,
      localDay: "2026-10-07",
      field: TimeField.completedWork,
      deltaSeconds: 1800,
      createdAt: clock.now(),
    )
    try await records.insert(record)
    let updates = String(decoding: try Stub.fixture("updates"), as: UTF8.self).replacingOccurrences(
      of: "MARKER",
      with: record.marker,
    )
    stub.respond { _ in Stub.Response(status: 200, body: Data(updates.utf8)) }

    #expect(await service.processPending() == 0)

    let recovered = try #require(try await records.record(record.id))
    #expect(recovered.status == .synced && recovered.adoRevision == 58)
    #expect(!stub.requests.contains { $0.httpMethod == "PATCH" })
  }

  @Test
  func crashBeforeSendingSendsAgain() async throws {
    respondNormally()
    let link = try await workItem()
    let id = try await entry(link)
    let record = SyncRecord(
      entryID: id,
      workItemLinkID: link.id,
      localDay: "2026-10-07",
      field: TimeField.completedWork,
      deltaSeconds: 1800,
      createdAt: clock.now(),
    )
    try await records.insert(record)
    stub.respond { request in
      if request.url?.path().hasSuffix("/updates") == true {
        return Stub.Response(status: 200, body: try Stub.fixture("updates")) // marker of another booking
      }
      if request.url?.path().contains("workitemtypes") == true {
        return Stub.Response(status: 200, body: try Stub.fixture("type-fields-task"))
      }
      if request.httpMethod == "PATCH" {
        return Stub.Response(status: 200, body: try Stub.fixture("workitem-patched"))
      }
      return Stub.Response(status: 200, body: try Stub.fixture("workitem-time"))
    }

    #expect(await service.processPending() == 0)
    #expect(stub.requests.count(where: { $0.httpMethod == "PATCH" }) == 1)
    #expect(try await records.record(record.id)?.status == .synced)
  }

  @Test
  func typeWithoutTimeFieldGetsOnlyTheComment() async throws {
    respondNormally()
    let link = try await workItem(type: "Epic")
    _ = try await entry(link)

    #expect(await service.book(try #require(try await lines(link).first)) == .booked)
    let body = try patchBody()
    #expect(value("/fields/\(TimeField.completedWork)", in: body) == nil)
    #expect(value("/fields/System.History", in: body) != nil)
    #expect(try await records.records(onDay: "2026-10-07").first?.field == TimeField.history)
  }

  @Test
  func queueDoesNotResendABookingThatIsStillBeingSent() async throws {
    let link = try await workItem()
    _ = try await entry(link)
    let line = try #require(try await lines(link).first)
    let (reachedNetwork, signal) = AsyncStream.makeStream(of: Void.self)
    let release = DispatchSemaphore(value: 0)
    let reads = Mutex(0)
    respondNormally()
    let normal = stub.currentHandler
    stub.respond { request in
      if request.url?.path().hasSuffix("/updates") == true {
        return Stub.Response(status: 200, body: Data(#"{"count":0,"value":[]}"#.utf8))
      }
      // The first read of the work item belongs to `book`: hold it until the queue has run.
      if
        request.httpMethod == "GET", request.url?.path() == "/contoso/_apis/wit/workitems/1234",
        reads.withLock({ count in
          count += 1
          return count
        }) == 1
      {
        signal.yield()
        _ = release.wait(timeout: .now() + 5)
      }
      return try normal(request)
    }

    let booking = Task { await service.book(line) }
    var iterator = reachedNetwork.makeAsyncIterator()
    _ = await iterator.next()
    await service.processPending(force: true)
    release.signal()

    #expect(await booking.value == .booked)
    #expect(stub.requests.count(where: { $0.httpMethod == "PATCH" }) == 1)
  }

  @Test
  func differenceBelowAHundredthOfAnHourIsNotBooked() async throws {
    respondNormally()
    let link = try await workItem()
    _ = try await entry(link, minutes: 10.0 / 60)
    let line = try #require(try await lines(link).first)

    #expect(line.difference == 0)
    #expect(await service.book(line) == .nothingToDo)
    #expect(!stub.requests.contains { $0.httpMethod == "PATCH" })
  }

  @Test
  func queueSkipsABookingThatChangedWhileItRan() async throws {
    let link = try await workItem()
    let id = try await entry(link)
    let first = SyncRecord(
      entryID: id,
      workItemLinkID: link.id,
      localDay: "2026-10-07",
      field: TimeField.completedWork,
      deltaSeconds: 900,
      createdAt: clock.now(),
    )
    let second = SyncRecord(
      entryID: id,
      workItemLinkID: link.id,
      localDay: "2026-10-07",
      field: TimeField.completedWork,
      deltaSeconds: 900,
      createdAt: clock.now().adding(seconds: 1),
    )
    try await records.insert(first)
    try await records.insert(second)
    let firstUpdates = Data(
      String(decoding: try Stub.fixture("updates"), as: UTF8.self)
        .replacingOccurrences(of: "MARKER", with: first.marker).utf8
    )
    let (reachedNetwork, signal) = AsyncStream.makeStream(of: Void.self)
    let release = DispatchSemaphore(value: 0)
    let lookups = Mutex(0)
    respondNormally()
    let normal = stub.currentHandler
    stub.respond { request in
      guard request.url?.path().hasSuffix("/updates") == true else { return try normal(request) }
      let lookup = lookups.withLock { count in
        count += 1
        return count
      }
      guard lookup == 1 else { return Stub.Response(status: 200, body: Data(#"{"count":0,"value":[]}"#.utf8)) }
      // The queue holds both records in its list; hold the first lookup until the second changed.
      signal.yield()
      _ = release.wait(timeout: .now() + 5)
      return Stub.Response(status: 200, body: firstUpdates)
    }

    let queue = Task { await service.processPending() }
    var iterator = reachedNetwork.makeAsyncIterator()
    _ = await iterator.next()
    // Meanwhile another run of the queue gave up on the second booking.
    var failed = second
    failed.status = .failed
    failed.error = BookingFailure.keepsChanging.rawValue
    try await records.update(failed)
    release.signal()
    _ = await queue.value

    #expect(try await records.record(first.id)?.status == .synced)
    #expect(try await records.record(second.id)?.status == .failed)
    #expect(!stub.requests.contains { $0.httpMethod == "PATCH" })
  }

  @Test
  func recordHoldsExactlyWhatWasBooked() async throws {
    respondNormally()
    let link = try await workItem()
    // 50 seconds are 0.0139 h; Azure DevOps gets 0.01 h, so the record must say 36 seconds.
    _ = try await entry(link, minutes: 50.0 / 60)
    let line = try #require(try await lines(link).first)

    #expect(line.difference == 36)
    #expect(await service.book(line) == .booked)
    #expect(value("/fields/\(TimeField.completedWork)", in: try patchBody()) as? Double == 7.51)
    #expect(try await records.records(onDay: "2026-10-07").map(\.deltaSeconds) == [36])
    // The 14 seconds left over stay below the threshold instead of piling up.
    #expect(try await lines(link).first?.difference == 0)
  }

  @Test
  func staleLineIsNotBookedAgain() async throws {
    respondNormally()
    let link = try await workItem()
    _ = try await entry(link)
    let line = try #require(try await lines(link).first)

    #expect(await service.book(line) == .booked)
    // The same line, read before the first booking finished, must not book the time twice.
    #expect(await service.book(line) == .nothingToDo)
    #expect(stub.requests.count(where: { $0.httpMethod == "PATCH" }) == 1)
  }

  @Test
  func deletedWorkItemFailsTheQueuedBooking() async throws {
    let link = try await workItem()
    let id = try await entry(link)
    let record = SyncRecord(
      entryID: id,
      workItemLinkID: link.id,
      localDay: "2026-10-07",
      field: TimeField.completedWork,
      deltaSeconds: 1800,
      createdAt: clock.now(),
    )
    try await records.insert(record)
    stub.respond { _ in Stub.Response(status: 404, body: Data()) }

    #expect(await service.processPending() == 0)
    let failed = try #require(try await records.record(record.id))
    #expect(failed.status == .failed && failed.error == BookingFailure.workItemGone.rawValue)
  }

  @Test
  func queueCountsEveryBookingLeftWhenOffline() async throws {
    let link = try await workItem()
    let id = try await entry(link)
    for _ in 0..<2 {
      try await records.insert(
        SyncRecord(
          entryID: id,
          workItemLinkID: link.id,
          localDay: "2026-10-07",
          field: TimeField.completedWork,
          deltaSeconds: 900,
          createdAt: clock.now(),
        )
      )
    }
    stub.respond { _ in throw URLError(.notConnectedToInternet) }

    #expect(await service.processPending() == 2)
  }

  @Test
  func signInPageCountsAsRejectedToken() async throws {
    let link = try await workItem()
    _ = try await entry(link)
    // Azure DevOps answers an invalid token with a 203 HTML sign-in page in some setups.
    stub.respond { _ in Stub.Response(status: 203, body: Data("<html>Sign in</html>".utf8)) }

    #expect(await service.book(try #require(try await lines(link).first)) == .failed(.unauthorized))
  }

  @Test
  func serverErrorAfterPatchStaysPendingAndIsNotSentAgain() async throws {
    // A 502 from a gateway says nothing about whether the patch was applied behind it.
    respondNormally { _ in 502 }
    let link = try await workItem()
    _ = try await entry(link)
    let line = try #require(try await lines(link).first)

    #expect(await service.book(line) == .queued)
    #expect(try await records.pending().count == 1)
    #expect(await service.book(try #require(try await lines(link).first)) == .nothingToDo)
    #expect(await service.book(line) == .nothingToDo)
    #expect(stub.requests.count(where: { $0.httpMethod == "PATCH" }) == 1)
  }

  @Test
  func undecodableAnswerToPatchStaysPending() async throws {
    respondNormally()
    let normal = stub.currentHandler
    stub.respond { request in
      if request.httpMethod == "PATCH" {
        return Stub.Response(status: 200, body: Data("<html>Proxy</html>".utf8))
      }
      return try normal(request)
    }
    let link = try await workItem()
    _ = try await entry(link)

    #expect(await service.book(try #require(try await lines(link).first)) == .queued)
    let record = try #require(try await records.records(onDay: "2026-10-07").first)
    #expect(record.status == .pending)
    #expect(try await lines(link).first?.difference == 0)
  }

  @Test(arguments: [401, 500])
  func failedHistoryLookupKeepsTheBookingPending(status: Int) async throws {
    let link = try await workItem()
    let id = try await entry(link)
    let record = SyncRecord(
      entryID: id,
      workItemLinkID: link.id,
      localDay: "2026-10-07",
      field: TimeField.completedWork,
      deltaSeconds: 1800,
      createdAt: clock.now(),
    )
    try await records.insert(record)
    stub.respond { _ in Stub.Response(status: status, body: Data()) }

    #expect(await service.processPending() == 1)
    #expect(try await records.record(record.id)?.status == .pending)
    #expect(!stub.requests.contains { $0.httpMethod == "PATCH" })
    // Backoff: the next regular run does not ask again right away.
    let lookups = stub.requests.count
    #expect(await service.processPending() == 1)
    #expect(stub.requests.count == lookups)
  }

  @Test
  func markerOnALaterHistoryPageIsFound() async throws {
    respondNormally()
    let normal = stub.currentHandler
    let link = try await workItem()
    let id = try await entry(link)
    let record = SyncRecord(
      entryID: id,
      workItemLinkID: link.id,
      localDay: "2026-10-07",
      field: TimeField.completedWork,
      deltaSeconds: 1800,
      createdAt: clock.now(),
    )
    try await records.insert(record)
    // A full first page of other changes; the booking is on the second page.
    let others = (1...200).map { #"{"rev":\#($0),"fields":{}}"# }.joined(separator: ",")
    let firstPage = Data(#"{"count":200,"value":[\#(others)]}"#.utf8)
    let secondPage = Data(
      String(decoding: try Stub.fixture("updates"), as: UTF8.self)
        .replacingOccurrences(of: "MARKER", with: record.marker).utf8
    )
    stub.respond { request in
      guard let url = request.url, url.path().hasSuffix("/updates") else { return try normal(request) }
      let skip = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "$skip" }?.value
      return Stub.Response(status: 200, body: skip == "200" ? secondPage : firstPage)
    }

    #expect(await service.processPending() == 0)
    let recovered = try #require(try await records.record(record.id))
    #expect(recovered.status == .synced && recovered.adoRevision == 58)
    #expect(!stub.requests.contains { $0.httpMethod == "PATCH" })
  }

  // MARK: Private

  private let stub = Stub()
  private let secrets = MemorySecrets()
  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000)) // 2026-10-07 10:00 Berlin
  private let database: AppDatabase
  private let records: SyncRecordStore
  private let cache: WorkItemCache
  private let service: BookingService
  private let day = Timestamp(milliseconds: 1_791_324_000_000)..<Timestamp(milliseconds: 1_791_410_400_000)

  private func workItem(type: String = "Task") async throws -> WorkItemLink {
    let stored = try await cache.store([
      WorkItemLink(
        organization: "contoso",
        project: "Kundenportal",
        workItemID: 1234,
        cachedTitle: "Token",
        cachedType: type,
      )
    ])
    return try #require(stored.first)
  }

  /// An entry with 30 minutes on the day, linked to the work item.
  private func entry(_ link: WorkItemLink, minutes: Double = 30) async throws -> EntryID {
    let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    let (entry, changes) = try EntryEdits.create(
      EntryDraft(title: "Refresh", workItemLinkID: link.id, note: "Ursache gefunden"),
      from: day.lowerBound.adding(seconds: 9 * 3600),
      to: day.lowerBound.adding(seconds: 9 * 3600 + minutes * 60),
      now: clock.now(),
    )
    try await engine.apply(changes)
    return entry.id
  }

  private func lines(_ link: WorkItemLink, rounding: Rounding = .none) async throws -> [BookingLine] {
    BookingPlanner.lines(
      entries: try await EntryQueries(database: database).timeline(in: day, now: clock.now()).entries,
      workItems: [link.id: link],
      records: try await records.records(onDay: "2026-10-07"),
      day: day,
      localDay: "2026-10-07",
      now: clock.now(),
      defaultMode: .split,
      rounding: rounding,
    )
  }

  private func patchBody(_ index: Int = 0) throws -> [[String: Any]] {
    let patches = stub.requests.filter { $0.httpMethod == "PATCH" }
    let data = try #require(patches[index].httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
  }

  private func value(_ path: String, in body: [[String: Any]]) -> Any? {
    body.first { $0["path"] as? String == path }?["value"]
  }

  /// Fields, current values and the patch answered like Azure DevOps.
  private func respondNormally(patchStatus: @escaping @Sendable (Int) -> Int = { _ in 200 }) {
    let patches = Mutex(0)
    stub.respond { request in
      let path = request.url?.path(percentEncoded: false) ?? ""
      switch (request.httpMethod, path) {
      case ("GET", "/contoso/Kundenportal/_apis/wit/workitemtypes/Task/fields"):
        return Stub.Response(status: 200, body: try Stub.fixture("type-fields-task"))

      case ("GET", "/contoso/Kundenportal/_apis/wit/workitemtypes/Epic/fields"):
        return Stub.Response(status: 200, body: try Stub.fixture("type-fields-epic"))

      case ("GET", "/contoso/_apis/wit/workitems/1234"):
        return Stub.Response(status: 200, body: try Stub.fixture("workitem-time"))

      case ("PATCH", "/contoso/_apis/wit/workitems/1234"):
        let attempt = patches.withLock { count in
          count += 1
          return count
        }
        let status = patchStatus(attempt)
        return Stub.Response(
          status: status,
          body: try Stub.fixture(status == 200 ? "workitem-patched" : "412-test-failed"),
        )

      default:
        return Stub.Response(status: 404, body: Data())
      }
    }
  }

}
