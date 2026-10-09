import Testing

@testable import TaktCore

struct AppIdentityTests {
  @Test
  func logSubsystemMatchesBundleIdentifier() {
    #expect(AppIdentity.logSubsystem == "de.nilslutz.takt")
    #expect(AppIdentity.bundleIdentifier == AppIdentity.logSubsystem)
  }

  @Test
  func logSummaryNamesTypeAndCodeButNoContent() {
    struct Failure: Error {
      var title: String
    }
    enum Outcome: Error {
      case first
      case second(note: String)
    }

    let summary = Failure(title: "Kunde Müller").logSummary
    #expect(summary.hasSuffix("Failure 1"))
    #expect(!summary.contains("Müller"))
    #expect(Outcome.second(note: "geheim").logSummary.contains("Outcome"))
    #expect(!Outcome.second(note: "geheim").logSummary.contains("geheim"))
  }
}
