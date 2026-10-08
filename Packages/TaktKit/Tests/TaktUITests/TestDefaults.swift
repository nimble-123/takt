import Foundation
import Testing

/// A throwaway `UserDefaults` suite. Fails the test instead of falling back to the real defaults,
/// and removes the suite when the test is done.
final class TestDefaults {

  // MARK: Lifecycle

  init(_ prefix: String = "takt-tests") throws {
    suiteName = "\(prefix)-\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suiteName))
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }

  // MARK: Internal

  let suiteName: String
  let defaults: UserDefaults

}
