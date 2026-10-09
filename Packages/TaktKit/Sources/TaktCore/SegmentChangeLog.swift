import Foundation

// MARK: - SegmentChangeRecord

/// One entry of the change log: a segment created, changed or deleted after the fact (AZ-04).
/// Live tracking writes none; the log makes corrections traceable, it cannot prevent them.
public struct SegmentChangeRecord: Hashable, Sendable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: SegmentChangeID = SegmentChangeID(),
    segmentID: SegmentID,
    entryID: EntryID,
    kind: Kind,
    oldStart: Timestamp? = nil,
    oldEnd: Timestamp? = nil,
    newStart: Timestamp? = nil,
    newEnd: Timestamp? = nil,
    changedAt: Timestamp,
    reason: String? = nil,
  ) {
    self.id = id
    self.segmentID = segmentID
    self.entryID = entryID
    self.kind = kind
    self.oldStart = oldStart
    self.oldEnd = oldEnd
    self.newStart = newStart
    self.newEnd = newEnd
    self.changedAt = changedAt
    self.reason = reason
  }

  // MARK: Public

  public enum Kind: String, Sendable, CaseIterable {
    case created
    case changed
    case deleted
  }

  public var id: SegmentChangeID
  public var segmentID: SegmentID
  public var entryID: EntryID
  public var kind: Kind
  public var oldStart: Timestamp?
  public var oldEnd: Timestamp?
  public var newStart: Timestamp?
  public var newEnd: Timestamp?
  public var changedAt: Timestamp
  public var reason: String?

  /// The records for the changes of one write. `segments` returns the stored segments of an entry
  /// before the write; deleting an entry deletes its segments, restoring it creates them again.
  public static func records(
    for changes: [TimerChange],
    log: ChangeLog,
    segments: (EntryID) throws -> [Segment],
  ) rethrows -> [SegmentChangeRecord] {
    var records = [SegmentChangeRecord]()
    for change in changes {
      switch change {
      case .segment(let before, let after):
        if let record = record(before, after, log) { records.append(record) }

      case .entry(let before, let after):
        guard let before, let after, (before.deletedAt == nil) != (after.deletedAt == nil) else { continue }
        // Segments the same write closes are logged with their new end.
        let touched = Dictionary(
          changes.compactMap { change -> (SegmentID, Segment)? in
            guard case .segment(_, let segment?) = change, segment.entryID == after.id else { return nil }
            return (segment.id, segment)
          },
          uniquingKeysWith: { $1 },
        )
        let stored = try segments(after.id).map { touched[$0.id] ?? $0 }.filter { !$0.isOpen }
        records += after.deletedAt != nil
          ? stored.compactMap { record($0, nil, log) }
          : stored.compactMap { record(nil, $0, log) }

      case .globalPause, .idleEvent:
        continue
      }
    }
    return records
  }

  // MARK: Private

  /// `nil` for changes that only start, stop or reopen live tracking.
  private static func record(_ before: Segment?, _ after: Segment?, _ log: ChangeLog) -> SegmentChangeRecord? {
    guard let segment = after ?? before else { return nil }
    let kind: Kind
    switch (before, after) {
    case (nil, let after?):
      if after.isOpen { return nil }
      kind = .created

    case (_?, nil):
      kind = .deleted

    case (let before?, let after?):
      if before.start == after.start, before.end == after.end, before.entryID == after.entryID { return nil }
      if before.start == after.start, before.entryID == after.entryID, before.isOpen || after.isOpen { return nil }
      kind = .changed

    case (nil, nil):
      return nil
    }
    return SegmentChangeRecord(
      segmentID: segment.id,
      entryID: after?.entryID ?? segment.entryID,
      kind: kind,
      oldStart: before?.start,
      oldEnd: before?.end,
      newStart: after?.start,
      newEnd: after?.end,
      changedAt: log.at,
      reason: log.reason,
    )
  }
}

// MARK: - ChangeLog

/// Asks a store to log the segment changes of a write (AZ-04). Timer commands leave it `nil`.
public struct ChangeLog: Hashable, Sendable {
  public init(at: Timestamp, reason: String? = nil) {
    self.at = at
    self.reason = reason
  }

  public var at: Timestamp
  /// Why times were corrected; optional, asked for days older than 7 days if enabled.
  public var reason: String?
}
