import Foundation
import os
import TaktCore

// MARK: - ADOError

public enum ADOError: Error, Equatable {
  /// 401/403: the token is wrong, expired or lacks the scope.
  case unauthorized
  case notFound
  /// 412 or a failed `test /rev`: the work item changed in the meantime.
  case conflict
  /// No network or the server did not answer.
  case offline
  /// 429/503 with an optional wait time from `Retry-After`.
  case throttled(retryAfter: TimeInterval?)
  case server(status: Int)
  case invalidResponse
}

// MARK: - ADOClient

/// REST client for one Azure DevOps organization (`api-version=7.1`).
public struct ADOClient: Sendable {

  // MARK: Lifecycle

  public init(
    organization: String,
    authorization: any AuthorizationProvider,
    session: URLSession = .shared,
    baseURL: URL = ADOClient.defaultBaseURL,
    searchBaseURL: URL = ADOClient.defaultSearchBaseURL,
  ) {
    self.organization = organization
    self.authorization = authorization
    self.session = session
    self.baseURL = baseURL
    self.searchBaseURL = searchBaseURL
  }

  // MARK: Public

  public static let apiVersion = "7.1"
  /// `https://dev.azure.com`
  public static let defaultBaseURL = url(host: "dev.azure.com")
  /// Work item search lives on its own host.
  public static let defaultSearchBaseURL = url(host: "almsearch.dev.azure.com")

  public let organization: String

  // MARK: Internal

  /// For resources that only exist as a preview, such as `_apis/connectionData`.
  static let previewAPIVersion = "7.1-preview"

  /// `path` is relative to the organization, e.g. `_apis/projects`.
  func get<Response: Decodable>(
    _ path: String,
    query: [URLQueryItem] = [],
    apiVersion: String = ADOClient.apiVersion,
  ) async throws -> Response {
    try await send(request("GET", path, query: query, apiVersion: apiVersion))
  }

  func post<Response: Decodable>(
    _ path: String,
    query: [URLQueryItem] = [],
    body: some Encodable,
    contentType: String = "application/json",
    onSearchHost: Bool = false,
  ) async throws -> Response {
    var request = try await request("POST", path, query: query, onSearchHost: onSearchHost)
    request.httpBody = try JSONEncoder().encode(body)
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    return try await send(request)
  }

  func patch<Response: Decodable>(
    _ path: String,
    body: some Encodable,
    contentType: String,
  ) async throws -> Response {
    var request = try await request("PATCH", path)
    request.httpBody = try JSONEncoder().encode(body)
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    return try await send(request)
  }

  // MARK: Private

  private let authorization: any AuthorizationProvider
  private let session: URLSession
  private let baseURL: URL
  private let searchBaseURL: URL
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "ado")

  private static func url(host: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    return components.url ?? URL(filePath: "/")
  }

  private func request(
    _ method: String,
    _ path: String,
    query: [URLQueryItem] = [],
    onSearchHost: Bool = false,
    apiVersion: String = ADOClient.apiVersion,
  ) async throws -> URLRequest {
    let base = onSearchHost ? searchBaseURL : baseURL
    var components = URLComponents(
      url: base.appending(path: organization).appending(path: path),
      resolvingAgainstBaseURL: false,
    )
    components?.queryItems = query + [URLQueryItem(name: "api-version", value: apiVersion)]
    guard let url = components?.url else { throw ADOError.invalidResponse }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = method
    request.setValue(try await authorization.authorizationHeader(), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError {
      logger.error("Request failed: \(error.code.rawValue, privacy: .public)")
      throw ADOError.offline
    }
    guard let http = response as? HTTPURLResponse else { throw ADOError.invalidResponse }
    switch http.statusCode {
    case 200..<300:
      do {
        return try JSONDecoder.ado.decode(Response.self, from: data)
      } catch {
        logger.error("Unexpected response: \(String(describing: error), privacy: .public)")
        throw ADOError.invalidResponse
      }

    // ADO answers an invalid PAT with a 203 sign-in page in some setups; 401 and 403 otherwise.
    case 401, 403: throw ADOError.unauthorized

    case 404: throw ADOError.notFound

    case 409, 412: throw ADOError.conflict

    case 429, 503:
      throw ADOError.throttled(
        retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
      )

    default:
      // A failed `test` operation in a JSON patch comes back as 400 with this type.
      if http.statusCode == 400, String(decoding: data, as: UTF8.self).contains("TestOperationFailed") {
        throw ADOError.conflict
      }
      throw ADOError.server(status: http.statusCode)
    }
  }
}

extension JSONDecoder {
  static let ado: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let string = try decoder.singleValueContainer().decode(String.self)
      let formats: [Date.ISO8601FormatStyle] = [
        .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted),
        .iso8601,
      ]
      for format in formats {
        if let date = try? Date(string, strategy: format) { return date }
      }
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: string))
    }
    return decoder
  }()
}

// MARK: Account and projects (DO-01, DO-02, ST-03)

extension ADOClient {
  public struct Identity: Hashable, Sendable {
    public var id: String
    public var displayName: String
  }

  public struct RemoteProject: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
  }

  /// Checks the token; returns who it belongs to.
  public func verify() async throws -> Identity {
    struct ConnectionData: Decodable {
      struct User: Decodable {
        var id: String
        var providerDisplayName: String?
        var customDisplayName: String?
      }

      var authenticatedUser: User
    }
    let data: ConnectionData = try await get("_apis/connectionData", apiVersion: Self.previewAPIVersion)
    // An anonymous identity means the token was not accepted.
    guard
      let name = data.authenticatedUser.customDisplayName ?? data.authenticatedUser.providerDisplayName,
      name != "Anonymous"
    else { throw ADOError.unauthorized }
    return Identity(id: data.authenticatedUser.id, displayName: name)
  }

  public func projects() async throws -> [RemoteProject] {
    struct List: Decodable {
      struct Item: Decodable {
        var id: String
        var name: String
      }

      var value: [Item]
    }
    let list: List = try await get("_apis/projects", query: [URLQueryItem(name: "$top", value: "500")])
    return list.value.map { RemoteProject(id: $0.id, name: $0.name) }.sorted { $0.name < $1.name }
  }

  /// Area paths of a project, e.g. `Portal\Team A`, up to two levels below the root.
  public func areaPaths(of project: String) async throws -> [String] {
    struct Node: Decodable {
      var name: String
      var children: [Node]?
    }
    let root: Node = try await get(
      "\(project)/_apis/wit/classificationnodes/areas",
      query: [URLQueryItem(name: "$depth", value: "2")],
    )
    func flatten(_ node: Node, prefix: String) -> [String] {
      let path = prefix.isEmpty ? node.name : "\(prefix)\\\(node.name)"
      return [path] + (node.children ?? []).flatMap { flatten($0, prefix: path) }
    }
    return flatten(root, prefix: "")
  }
}
