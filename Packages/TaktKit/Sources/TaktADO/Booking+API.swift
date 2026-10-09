import Foundation

// MARK: - TimeField

/// Reference names of the scheduling fields (Agile, Scrum and CMMI use the same ones).
public enum TimeField {
  public static let completedWork = "Microsoft.VSTS.Scheduling.CompletedWork"
  public static let remainingWork = "Microsoft.VSTS.Scheduling.RemainingWork"
  /// Bookings for types without a time field only add a comment.
  public static let history = "System.History"
}

// MARK: - PatchOperation

/// One operation of a JSON patch.
public struct PatchOperation: Encodable, Hashable, Sendable {
  public enum Value: Encodable, Hashable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .int(let value): try container.encode(value)
      case .double(let value): try container.encode(value)
      case .string(let value): try container.encode(value)
      }
    }
  }

  public var op: String
  public var path: String
  public var value: Value
}

extension ADOClient {
  /// The current values of the time fields and the revision to test against.
  public struct TimeValues: Hashable, Sendable {
    public var revision: Int
    public var completedWork: Double?
    public var remainingWork: Double?
  }

  public func timeValues(of workItem: Int) async throws -> TimeValues {
    struct Response: Decodable {
      var rev: Int
      var fields: [String: FieldValue]?
    }
    let response: Response = try await get(
      "_apis/wit/workitems/\(workItem)",
      query: [URLQueryItem(name: "fields", value: "\(TimeField.completedWork),\(TimeField.remainingWork)")],
    )
    return TimeValues(
      revision: response.rev,
      completedWork: response.fields?[TimeField.completedWork]?.number,
      remainingWork: response.fields?[TimeField.remainingWork]?.number,
    )
  }

  /// Reference names of the fields a work item type has (DO-27).
  public func fieldNames(of type: String, in project: String) async throws -> Set<String> {
    struct Response: Decodable {
      struct Field: Decodable { var referenceName: String }
      var value: [Field]
    }
    let response: Response = try await get("\(project)/_apis/wit/workitemtypes/\(type)/fields")
    return Set(response.value.map(\.referenceName))
  }

  /// Applies a JSON patch; returns the new revision.
  @discardableResult
  public func patch(workItem: Int, _ operations: [PatchOperation]) async throws -> Int {
    struct Response: Decodable { var rev: Int }
    let response: Response = try await patch(
      "_apis/wit/workitems/\(workItem)",
      body: operations,
      contentType: "application/json-patch+json",
    )
    return response.rev
  }

  /// The revision whose history comment contains `marker`, if any (crash recovery). Reads every page
  /// of the updates, since Azure DevOps returns at most 200 per request.
  public func revision(of workItem: Int, withHistoryContaining marker: String) async throws -> Int? {
    struct Response: Decodable {
      struct Update: Decodable {
        struct Change: Decodable { var newValue: FieldValue? }
        var rev: Int
        var fields: [String: Change]?
      }

      var value: [Update]
    }
    let pageSize = 200
    var skip = 0
    while true {
      let page: Response = try await get(
        "_apis/wit/workitems/\(workItem)/updates",
        query: [URLQueryItem(name: "$top", value: "\(pageSize)"), URLQueryItem(name: "$skip", value: "\(skip)")],
      )
      let match = page.value.first { update in
        update.fields?[TimeField.history]?.newValue?.string?.contains(marker) == true
      }
      if let match { return match.rev }
      guard page.value.count >= pageSize else { return nil }
      skip += page.value.count
    }
  }
}
