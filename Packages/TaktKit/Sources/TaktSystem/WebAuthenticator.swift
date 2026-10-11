import AppKit
import AuthenticationServices

// MARK: - WebAuthenticator

/// Shows the Entra sign-in page in the system's web authentication sheet and returns the
/// callback URL. The sheet does not share Safari's cookies: a cached session of a personal
/// Microsoft account with the same address would otherwise be picked and rejected by the tenant.
@MainActor
public final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {

  // MARK: Public

  public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      // AuthenticationServices calls this on an XPC queue, not the main actor; it must not
      // inherit the class's isolation, or the runtime's isolation check traps.
      let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) {
        @Sendable callback, error in
        if let callback {
          continuation.resume(returning: callback)
        } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
          continuation.resume(throwing: EntraError.cancelled)
        } else {
          continuation.resume(throwing: error ?? EntraError.invalidCallback)
        }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = true
      self.session = session
      if !session.start() {
        continuation.resume(throwing: EntraError.invalidCallback)
      }
    }
  }

  public nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
    }
  }

  // MARK: Private

  /// Kept alive until the sheet closes.
  private var session: ASWebAuthenticationSession?
}
