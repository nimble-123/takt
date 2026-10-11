import AppKit
import WebKit

// MARK: - WebAuthenticator

/// Shows the Entra sign-in page in a small window of its own and returns the callback URL, like
/// MSAL's embedded web view on macOS. The web view keeps no cookies and does not share Safari's:
/// a cached session of a personal Microsoft account with the same address would otherwise be
/// picked and rejected by the tenant.
@MainActor
public final class WebAuthenticator: NSObject {

  // MARK: Public

  /// Loads `url` and waits until the page redirects to `callbackScheme`. Closing the window
  /// cancels with `EntraError.cancelled`.
  public func authenticate(url: URL, callbackScheme: String, title: String) async throws -> URL {
    finish(.failure(EntraError.cancelled))
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      self.callbackScheme = callbackScheme
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      let webView = WKWebView(frame: NSRect(origin: .zero, size: Self.size), configuration: configuration)
      webView.navigationDelegate = self
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: Self.size),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false,
      )
      window.title = title
      window.contentView = webView
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.center()
      self.window = window
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
      webView.load(URLRequest(url: url))
    }
  }

  // MARK: Private

  /// Enough for Microsoft's sign-in form without scrolling.
  private static let size = NSSize(width: 480, height: 640)

  private var continuation: CheckedContinuation<URL, any Error>?
  private var callbackScheme = ""
  private var window: NSWindow?

  /// Resumes the waiting sign-in once and closes the window.
  private func finish(_ result: Result<URL, any Error>) {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
    if let window {
      self.window = nil
      window.delegate = nil
      window.close()
    }
  }
}

// MARK: WKNavigationDelegate

extension WebAuthenticator: WKNavigationDelegate {
  public func webView(
    _: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
  ) async -> WKNavigationActionPolicy {
    guard let url = navigationAction.request.url, url.scheme == callbackScheme else { return .allow }
    finish(.success(url))
    return .cancel
  }

  public func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError error: any Error) {
    // Cancelling the callback navigation above reports an error as well; only real failures count.
    guard continuation != nil, (error as? URLError)?.code != .cancelled else { return }
    finish(.failure(error))
  }
}

// MARK: NSWindowDelegate

extension WebAuthenticator: NSWindowDelegate {
  public func windowWillClose(_: Notification) {
    finish(.failure(EntraError.cancelled))
  }
}
