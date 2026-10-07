import Foundation

/// A UUID-based identifier. Stored as `uuidString` (`TEXT`), never as a blob.
public protocol UUIDIdentifier: Hashable, Sendable, Codable, CustomStringConvertible {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

extension UUIDIdentifier {
    /// Creates a new random identifier.
    public init() {
        self.init(rawValue: UUID())
    }

    /// Parses an identifier from its stored `uuidString`.
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }

    public var uuidString: String { rawValue.uuidString }
    public var description: String { rawValue.uuidString }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UUID.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct EntryID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct SegmentID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct GlobalPauseID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ProjectID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct TaskID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct CategoryID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct WorkItemLinkID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct IdleEventID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct TagID: UUIDIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}
