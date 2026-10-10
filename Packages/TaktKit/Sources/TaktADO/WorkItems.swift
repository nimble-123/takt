import Foundation
import TaktCore

// MARK: - FieldValue

/// Field values of a work item as Azure DevOps returns them.
enum FieldValue: Decodable {
  case string(String)
  case number(Double)
  case identity(displayName: String)
  case other

  // MARK: Lifecycle

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let identity = try? container.decode(FieldValueIdentity.self), let name = identity.displayName {
      self = .identity(displayName: name)
    } else {
      self = .other
    }
  }

  // MARK: Internal

  var string: String? {
    switch self {
    case .string(let value): value
    case .identity(let name): name
    case .number(let value): String(value)
    case .other: nil
    }
  }

  var number: Double? {
    if case .number(let value) = self { return value }
    return nil
  }
}

// MARK: - FieldValueIdentity

struct FieldValueIdentity: Decodable {
  var displayName: String?
}

extension ADOClient {

  // MARK: Public

  /// `https://dev.azure.com/{org}/{project}/_workitems/edit/{id}` (DO-13: ⌘↩).
  public static func webURL(of item: WorkItemLink) -> URL {
    Self.defaultBaseURL.appending(path: item.organization).appending(path: item.project)
      .appending(path: "_workitems/edit/\(item.workItemID)")
  }

  /// Details of up to 200 work items per call; unknown IDs are left out. Keeps the order of `ids`.
  public func workItems(_ ids: [Int], seenAt now: Timestamp) async throws -> [WorkItemLink] {
    struct Request: Encodable {
      var ids: [Int]
      var fields: [String]
      var errorPolicy = "omit"
    }
    struct Response: Decodable {
      struct Item: Decodable {
        var id: Int?
        var fields: [String: FieldValue]?
      }

      var value: [Item?]
    }
    var items = [WorkItemLink]()
    for chunk in stride(from: 0, to: ids.count, by: 200).map({ Array(ids[$0..<min($0 + 200, ids.count)]) }) {
      let response: Response = try await post(
        "_apis/wit/workitemsbatch",
        body: Request(ids: chunk, fields: Self.previewFields),
      )
      items += response.value.compactMap { item in
        guard let item, let id = item.id, let fields = item.fields else { return nil }
        return link(id: id, fields: fields, seenAt: now)
      }
    }
    // An ID may be asked for twice; its first position counts.
    let order = Dictionary(ids.enumerated().map { ($1, $0) }) { first, _ in first }
    return items.sorted { (order[$0.workItemID] ?? 0) < (order[$1.workItemID] ?? 0) }
  }

  /// IDs matching a WIQL query, optionally in a team's context (for `@CurrentIteration`).
  public func wiql(_ query: String, project: String? = nil, team: String? = nil, top: Int = 20) async throws -> [Int] {
    struct Request: Encodable { var query: String }
    struct Response: Decodable {
      struct Reference: Decodable { var id: Int }
      var workItems: [Reference]
    }
    let scope = [project, team].compactMap { $0 }.map { "\($0)/" }.joined()
    let response: Response = try await post(
      "\(scope)_apis/wit/wiql",
      query: [URLQueryItem(name: "$top", value: String(top))],
      body: Request(query: query),
    )
    return response.workItems.map(\.id)
  }

  /// Full-text search over title and description; throws `notFound` if search is not available.
  public func fullTextSearch(_ text: String, top: Int = 20) async throws -> [Int] {
    struct Request: Encodable {
      var searchText: String
      var top: Int
      var skip = 0
      var includeFacets = false
      enum CodingKeys: String, CodingKey {
        case searchText, includeFacets
        case top = "$top"
        case skip = "$skip"
      }
    }
    struct Response: Decodable {
      struct Result: Decodable { var fields: [String: String] }
      var results: [Result]
    }
    let response: Response = try await post(
      "_apis/search/workitemsearchresults",
      body: Request(searchText: text, top: top),
      onSearchHost: true,
    )
    return response.results.compactMap { $0.fields["system.id"].flatMap(Int.init) }
  }

  /// The user's teams in a project.
  public func myTeams(in project: String) async throws -> [String] {
    struct Response: Decodable {
      struct Team: Decodable { var name: String }
      var value: [Team]
    }
    let response: Response = try await get(
      "_apis/projects/\(project)/teams",
      query: [URLQueryItem(name: "$mine", value: "true")],
    )
    return response.value.map(\.name)
  }

  // MARK: Internal

  /// Fields for the compact and the detail preview (DO-12, DO-13).
  static let previewFields = [
    "System.Id",
    "System.TeamProject",
    "System.WorkItemType",
    "System.Title",
    "System.State",
    "System.AssignedTo",
    "System.IterationPath",
    "Microsoft.VSTS.Scheduling.RemainingWork",
    "Microsoft.VSTS.Scheduling.CompletedWork",
    "System.Parent",
    "System.Description",
    "System.Tags",
  ]

  /// Strips HTML, decodes common entities and collapses whitespace.
  static func plainText(_ html: String, limit: Int) -> String {
    let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    let collapsed = decodeEntities(withoutTags).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
  }

  /// `&auml;`, `&#228;` and `&#xE4;`; unknown entities stay as they are.
  static func decodeEntities(_ text: String) -> String {
    var result = ""
    var rest = Substring(text)
    while let ampersand = rest.firstIndex(of: "&") {
      result += rest[..<ampersand]
      let candidate = rest[ampersand...]
      guard let semicolon = candidate.prefix(10).firstIndex(of: ";") else {
        result += "&"
        rest = rest[rest.index(after: ampersand)...]
        continue
      }
      let name = candidate[candidate.index(after: ampersand)..<semicolon]
      if let replacement = namedEntities[String(name)] ?? numericEntity(name) {
        result += replacement
      } else {
        result += candidate[...semicolon]
      }
      rest = rest[rest.index(after: semicolon)...]
    }
    return result + rest
  }

  // MARK: Private

  private static let namedEntities = [
    "nbsp": " ",
    "amp": "&",
    "lt": "<",
    "gt": ">",
    "quot": "\"",
    "apos": "'",
    "auml": "ä",
    "ouml": "ö",
    "uuml": "ü",
    "Auml": "Ä",
    "Ouml": "Ö",
    "Uuml": "Ü",
    "szlig": "ß",
    "euro": "€",
    "ndash": "–",
    "mdash": "—",
    "hellip": "…",
    "bdquo": "„",
    "ldquo": "“",
    "rdquo": "”",
  ]

  private static func numericEntity(_ name: Substring) -> String? {
    guard name.hasPrefix("#") else { return nil }
    let digits = name.dropFirst()
    let value =
      digits.hasPrefix("x") || digits.hasPrefix("X") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
    return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
  }

  private func link(id: Int, fields: [String: FieldValue], seenAt now: Timestamp) -> WorkItemLink {
    WorkItemLink(
      organization: organization,
      project: fields["System.TeamProject"]?.string ?? "",
      workItemID: id,
      cachedTitle: fields["System.Title"]?.string,
      cachedType: fields["System.WorkItemType"]?.string,
      cachedState: fields["System.State"]?.string,
      cachedAt: now,
      assignedTo: fields["System.AssignedTo"]?.string,
      iterationPath: fields["System.IterationPath"]?.string,
      remainingWork: fields["Microsoft.VSTS.Scheduling.RemainingWork"]?.number,
      completedWork: fields["Microsoft.VSTS.Scheduling.CompletedWork"]?.number,
      parentID: fields["System.Parent"]?.number.map { Int($0) },
      descriptionExcerpt: fields["System.Description"]?.string.map { Self.plainText($0, limit: 300) },
      tags: (fields["System.Tags"]?.string ?? "").split(separator: ";")
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
    )
  }

}

// MARK: - WorkItemSearch

/// Search and suggestions for one organization. Remembers whether full-text search is available
/// (TECHNICAL_CONCEPT "Zur Laufzeit erkannt, nicht konfiguriert").
public actor WorkItemSearch {

  // MARK: Lifecycle

  public init(client: ADOClient, clock: any TaktClock) {
    self.client = client
    self.clock = clock
  }

  // MARK: Public

  /// Fewer characters find little and only cost requests.
  public static let minimumQueryLength = 3

  public var organization: String {
    client.organization
  }

  /// Whether typed text is long enough to search for work items: at least `minimumQueryLength`
  /// characters, a leading `#` not counted (`#123`, not `#12`).
  public static func isSearchable(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let counted = trimmed.hasPrefix("#") ? trimmed.dropFirst() : Substring(trimmed)
    return counted.count >= minimumQueryLength
  }

  /// `#1234` or a plain number.
  public static func workItemID(in text: String) -> Int? {
    let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
    guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
    return Int(digits)
  }

  /// `#1234`, `1234` or text (DO-10).
  public func search(_ query: String) async throws -> [WorkItemLink] {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    if let id = Self.workItemID(in: text) {
      return try await client.workItems([id], seenAt: clock.now())
    }
    return try await client.workItems(try await ids(matching: text), seenAt: clock.now())
  }

  /// Without input: assigned to me in the current iteration of all my teams, then recently
  /// changed by me (PRD "Vorgeschlagene Items" 1 and 3). `projects` are the Azure DevOps projects to look in.
  public func suggestions(projects: [String]) async throws -> [WorkItemLink] {
    let client = client
    let teams = await Self.orderedMap(projects) { (project: String) async -> [String] in
      (try? await client.myTeams(in: project)) ?? []
    }
    let teamQueries = zip(projects, teams).flatMap { project, teams in
      teams.map { TeamQuery(project: project, team: $0) }
    }
    let teamIDs = await Self.orderedMap(teamQueries) { (query: TeamQuery) async -> [Int] in
      (try? await client.wiql(
        """
        SELECT [System.Id] FROM WorkItems
        WHERE [System.AssignedTo] = @Me AND [System.IterationPath] = @CurrentIteration
        AND [System.State] IN ('Active', 'In Progress', 'Committed', 'Doing')
        ORDER BY [Microsoft.VSTS.Common.Priority], [System.ChangedDate] DESC
        """,
        project: query.project,
        team: query.team,
        top: 10,
      )) ?? []
    }
    var ids = teamIDs.flatMap(\.self)
    ids += try await client.wiql(
      """
      SELECT [System.Id] FROM WorkItems
      WHERE [System.ChangedBy] = @Me AND [System.ChangedDate] >= @Today - 14
      ORDER BY [System.ChangedDate] DESC
      """,
      top: 10,
    )
    var seen = Set<Int>()
    let unique = ids.filter { seen.insert($0).inserted }
    return try await client.workItems(Array(unique.prefix(15)), seenAt: clock.now())
  }

  // MARK: Private

  private struct TeamQuery: Sendable {
    var project: String
    var team: String
  }

  /// Requests `suggestions` keeps in flight at once.
  private static let maxConcurrentRequests = 4

  private let client: ADOClient
  private let clock: any TaktClock
  private var fullTextAvailable: Bool?

  /// `transform` of every element, with at most `maxConcurrentRequests` running at once; the
  /// results keep the order of `elements`.
  private static func orderedMap<Element: Sendable, Output: Sendable>(
    _ elements: [Element],
    _ transform: @escaping @Sendable (Element) async -> Output,
  ) async -> [Output] {
    await withTaskGroup(of: (index: Int, result: Output).self) { group in
      var results = [Int: Output]()
      for (index, element) in elements.enumerated() {
        if index >= maxConcurrentRequests, let finished = await group.next() {
          results[finished.index] = finished.result
        }
        group.addTask { (index, await transform(element)) }
      }
      for await finished in group {
        results[finished.index] = finished.result
      }
      return elements.indices.compactMap { results[$0] }
    }
  }

  private func ids(matching text: String) async throws -> [Int] {
    if fullTextAvailable != false {
      do {
        let ids = try await client.fullTextSearch(text)
        fullTextAvailable = true
        return ids
      } catch ADOError.notFound {
        // The search extension is not installed: use WIQL from now on.
        fullTextAvailable = false
      } catch ADOError.server(status: 400), ADOError.unauthorized {
        // The query or the token was rejected, which says nothing about search being installed:
        // WIQL for this query only.
      }
    }
    let escaped = text.replacingOccurrences(of: "'", with: "''")
    return try await client.wiql(
      "SELECT [System.Id] FROM WorkItems WHERE [System.Title] CONTAINS '\(escaped)' ORDER BY [System.ChangedDate] DESC"
    )
  }

}
