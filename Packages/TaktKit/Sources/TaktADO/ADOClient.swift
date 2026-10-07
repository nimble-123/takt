import Foundation
import TaktCore
import os

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

/// REST client for one Azure DevOps organization (`api-version=7.1`).
public struct ADOClient: Sendable {
    public let organization: String
    private let authorization: any AuthorizationProvider
    private let session: URLSession
    private let baseURL: URL
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "ado")

    public static let apiVersion = "7.1"

    public init(
        organization: String,
        authorization: any AuthorizationProvider,
        session: URLSession = .shared,
        baseURL: URL = ADOClient.defaultBaseURL
    ) {
        self.organization = organization
        self.authorization = authorization
        self.session = session
        self.baseURL = baseURL
    }

    /// `https://dev.azure.com`
    public static let defaultBaseURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "dev.azure.com"
        return components.url ?? URL(filePath: "/")
    }()

    // MARK: Requests

    /// `path` is relative to the organization, e.g. `_apis/projects`.
    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await send(request("GET", path, query: query))
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String, query: [URLQueryItem] = [], body: Body, contentType: String = "application/json"
    ) async throws -> Response {
        var request = try await request("POST", path, query: query)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    func patch<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, contentType: String
    ) async throws -> Response {
        var request = try await request("PATCH", path)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appending(path: organization).appending(path: path), resolvingAgainstBaseURL: false
        )
        components?.queryItems = query + [URLQueryItem(name: "api-version", value: Self.apiVersion)]
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
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
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
        let data: ConnectionData = try await get("_apis/connectionData")
        // An anonymous identity means the token was not accepted.
        guard let name = data.authenticatedUser.customDisplayName ?? data.authenticatedUser.providerDisplayName,
            name != "Anonymous"
        else { throw ADOError.unauthorized }
        return Identity(id: data.authenticatedUser.id, displayName: name)
    }

    public struct RemoteProject: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
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
            "\(project)/_apis/wit/classificationnodes/areas", query: [URLQueryItem(name: "$depth", value: "2")]
        )
        func flatten(_ node: Node, prefix: String) -> [String] {
            let path = prefix.isEmpty ? node.name : "\(prefix)\\\(node.name)"
            return [path] + (node.children ?? []).flatMap { flatten($0, prefix: path) }
        }
        return flatten(root, prefix: "")
    }
}
