import Foundation

/// Edits made after the fact in the main window (HW-02, UC-05). Each function returns the row
/// changes for `TimerEngine.apply(_:)`, so every edit is checked for conflicts and can be undone.
public enum EntryEdits {
  public enum EditError: Error, Equatable {
    /// A segment would end before it starts or run into the future.
    case invalidRange
    /// The split time is not inside the entry's tracked time.
    case splitOutsideEntry
  }

  /// Creates a stopped entry with one manual segment, e.g. drawn in the timeline.
  public static func create(
    _ draft: EntryDraft,
    from start: Timestamp,
    to end: Timestamp,
    now: Timestamp,
  ) throws -> (entry: TimeEntry, changes: [TimerChange]) {
    guard end > start, end <= now else { throw EditError.invalidRange }
    let entry = TimeEntry(draft: draft, state: .stopped, at: now)
    let segment = Segment(entryID: entry.id, start: start, end: end, source: .manual)
    return (entry, [.entry(before: nil, after: entry), .segment(before: nil, after: segment)])
  }

  /// Sets new bounds. An open segment keeps running; only its start can move.
  public static func setBounds(
    of segment: Segment,
    start: Timestamp,
    end: Timestamp?,
    now: Timestamp,
  ) throws -> [TimerChange] {
    var edited = segment
    edited.start = start
    edited.end = segment.isOpen ? nil : end
    guard start <= now, edited.end.map({ $0 > start && $0 <= now }) ?? true else {
      throw EditError.invalidRange
    }
    return edited == segment ? [] : [.segment(before: segment, after: edited)]
  }

  /// Moves a closed segment by `seconds`, keeping its length.
  public static func move(_ segment: Segment, by seconds: TimeInterval, now: Timestamp) throws -> [TimerChange] {
    guard let end = segment.end else { throw EditError.invalidRange }
    return try setBounds(
      of: segment,
      start: segment.start.adding(seconds: seconds),
      end: end.adding(seconds: seconds),
      now: now,
    )
  }

  /// "Pause in Arbeitszeit umwandeln": the gap between two segments of an entry becomes work.
  public static func closeGap(between first: Segment, and second: Segment) throws -> [TimerChange] {
    guard first.entryID == second.entryID, let end = first.end, end <= second.start else {
      throw EditError.invalidRange
    }
    var merged = first
    merged.end = second.end
    return [.segment(before: second, after: nil), .segment(before: first, after: merged)]
  }

  /// Splits an entry at `time`: everything after it moves to a new entry with the same settings
  /// and state; the original is stopped. A segment containing `time` is cut in two.
  public static func split(
    _ entry: TimeEntry,
    segments: [Segment],
    at time: Timestamp,
    now: Timestamp,
  ) throws -> (newEntry: TimeEntry, changes: [TimerChange]) {
    let tracked = segments.filter { $0.start < time }
    let later = segments.filter { ($0.end ?? now) > time }
    guard !tracked.isEmpty, !later.isEmpty, time < now else { throw EditError.splitOutsideEntry }

    var newEntry = entry
    newEntry.id = EntryID()
    newEntry.createdAt = now
    newEntry.updatedAt = now
    // The later part carries on as the original did (running, paused or stopped).
    var changes: [TimerChange] = [.entry(before: nil, after: newEntry)]

    if entry.state != .stopped {
      var stopped = entry
      stopped.state = .stopped
      stopped.updatedAt = now
      changes.append(.entry(before: entry, after: stopped))
    }
    for segment in later {
      var moved = segment
      moved.entryID = newEntry.id
      if segment.start < time {
        var cut = segment
        cut.end = time
        changes.append(.segment(before: segment, after: cut))
        moved.id = SegmentID()
        moved.start = time
        changes.append(.segment(before: nil, after: moved))
      } else {
        changes.append(.segment(before: segment, after: moved))
      }
    }
    return (newEntry, changes)
  }

  /// Soft-deletes an entry; a running or paused entry is stopped first.
  public static func delete(_ entry: TimeEntry, openSegment: Segment?, now: Timestamp) -> [TimerChange] {
    var changes = [TimerChange]()
    if let openSegment {
      if now > openSegment.start {
        var closed = openSegment
        closed.end = now
        changes.append(.segment(before: openSegment, after: closed))
      } else {
        changes.append(.segment(before: openSegment, after: nil))
      }
    }
    var deleted = entry
    deleted.state = .stopped
    deleted.deletedAt = now
    deleted.updatedAt = now
    changes.append(.entry(before: entry, after: deleted))
    return changes
  }

  /// Title, note, counting mode or weight changed in the inspector or the list.
  public static func update(_ entry: TimeEntry, now: Timestamp, _ edit: (inout TimeEntry) -> Void) -> [TimerChange] {
    var edited = entry
    edit(&edited)
    if edited.weight <= 0 { edited.weight = entry.weight }
    guard edited != entry else { return [] }
    edited.updatedAt = now
    return [.entry(before: entry, after: edited)]
  }
}
