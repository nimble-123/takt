import Foundation
import Synchronization

@testable import TaktADO

// MARK: - Stub

/// Answers requests of one test without network. Each test has its own `Stub`; requests find it
/// by a header, so tests can run in parallel.
final class Stub: Sendable {

  // MARK: Internal

  struct Response: Sendable {
    var status: Int
    var body: Data
    var headers = [String: String]()
  }

  typealias Handler = @Sendable (URLRequest) throws -> Response

  let id = UUID().uuidString

  var requests: [URLRequest] {
    recorded.withLock { $0 }
  }

  /// A session whose requests are answered by this stub.
  var session: URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Stub": id]
    StubProtocol.register(self)
    return URLSession(configuration: configuration)
  }

  /// The handler set by the last `respond`, so a test can wrap it.
  var currentHandler: Handler {
    handler.withLock { $0 } ?? { _ in Response(status: 500, body: Data()) }
  }

  /// A recorded response from `Fixtures/`.
  static func fixture(_ name: String) -> Data {
    guard
      let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      let data = try? Data(contentsOf: url)
    else { return Data() }
    return data
  }

  func respond(_ handler: @escaping Handler) {
    self.handler.withLock { $0 = handler }
  }

  // MARK: Fileprivate

  fileprivate func answer(_ request: URLRequest) throws -> Response {
    recorded.withLock { $0.append(request) }
    guard let handler = handler.withLock({ $0 }) else { return Response(status: 500, body: Data()) }
    return try handler(request)
  }

  // MARK: Private

  private let handler: Mutex<Handler?> = Mutex(nil)
  private let recorded: Mutex<[URLRequest]> = Mutex([])

}

// MARK: - StubProtocol

// URLProtocol is an Objective-C class the URL loading system subclasses; all shared state below is behind `Mutex`.
// swiftlint:disable:next no_unchecked_sendable
final class StubProtocol: URLProtocol, @unchecked Sendable {

  // MARK: Internal

  static func register(_ stub: Stub) {
    stubs.withLock { $0[stub.id] = stub }
  }

  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard
      let id = request.value(forHTTPHeaderField: "X-Stub"), let stub = Self.stubs.withLock({ $0[id] }),
      let url = request.url
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    do {
      var request = request
      if request.httpBody == nil, let stream = request.httpBodyStream {
        request.httpBody = Data(reading: stream)
      }
      let response = try stub.answer(request)
      let http = HTTPURLResponse(
        url: url,
        statusCode: response.status,
        httpVersion: "HTTP/1.1",
        headerFields: response.headers,
      )
      if let http { client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed) }
      client?.urlProtocol(self, didLoad: response.body)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() { }

  // MARK: Private

  /// `URLProtocol` is not Sendable; each instance handles one request on one thread.
  private static let stubs: Mutex<[String: Stub]> = Mutex([:])

}

extension Data {
  init(reading stream: InputStream) {
    self.init()
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      append(buffer, count: count)
    }
  }
}

// MARK: - MemorySecrets

/// Secrets in memory instead of the keychain.
final class MemorySecrets: SecretStore {

  // MARK: Internal

  func read(_ account: String) throws -> String? {
    values.withLock { $0[account] }
  }

  func write(_ secret: String, for account: String) throws {
    values.withLock { $0[account] = secret }
  }

  func delete(_ account: String) throws {
    _ = values.withLock { $0.removeValue(forKey: account) }
  }

  // MARK: Private

  private let values: Mutex<[String: String]> = Mutex([:])

}
