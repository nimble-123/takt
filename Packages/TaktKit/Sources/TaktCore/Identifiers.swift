import Foundation

// MARK: - UUIDIdentifier

/// A UUID-based identifier. Stored as `uuidString` (`TEXT`), never as a blob.
public protocol UUIDIdentifier: Hashable, Sendable, Codable, CustomStringConvertible {
  init(rawValue: UUID)

  var rawValue: UUID { get }
}

extension UUIDIdentifier {

  // MARK: Lifecycle

  /// Creates a new random identifier.
  public init() {
    self.init(rawValue: UUID())
  }

  /// Parses an identifier from its stored `uuidString`.
  public init?(uuidString: String) {
    guard let uuid = UUID(uuidString: uuidString) else { return nil }
    self.init(rawValue: uuid)
  }

  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(UUID.self))
  }

  // MARK: Public

  public var uuidString: String {
    rawValue.uuidString
  }

  public var description: String {
    rawValue.uuidString
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

// MARK: - EntryID

public struct EntryID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - SegmentID

public struct SegmentID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - GlobalPauseID

public struct GlobalPauseID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - ProjectID

public struct ProjectID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - TaskID

public struct TaskID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - CategoryID

public struct CategoryID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - WorkItemLinkID

public struct WorkItemLinkID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - IdleEventID

public struct IdleEventID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - TagID

public struct TagID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - SyncRecordID

public struct SyncRecordID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - RuleID

public struct RuleID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}

// MARK: - SegmentChangeID

public struct SegmentChangeID: UUIDIdentifier {
  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public let rawValue: UUID
}
