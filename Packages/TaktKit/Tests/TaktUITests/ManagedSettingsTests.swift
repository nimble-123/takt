import Foundation
import TaktADO
import TaktCore
import TaktSystem
import Testing

@testable import TaktUI

/// The sample profile, docs/MDM.md and the app must agree on every key (#43).
@MainActor
struct ManagedSettingsTests {

  // MARK: Internal

  @Test
  func profileListsExactlyTheManagedKeysWithTheirTypes() throws {
    let payload = try profilePayload()
    #expect(Set(payload.keys) == Set(ManagedSettings.keys.map(\.name)))
    for key in ManagedSettings.keys {
      let value = payload[key.name]
      let matches: Bool =
        switch key.type {
        case .string: value is String
        case .integer: (value as? NSNumber).map { CFNumberIsFloatType($0) == false } ?? false
        case .real: value is Double
        case .boolean: (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        case .array: value is [Any]
        }
      #expect(matches, "\(key.name) should be \(key.type)")
    }
  }

  @Test
  func documentationMentionsEveryKey() throws {
    let text = try documentation()
    for key in ManagedSettings.keys {
      #expect(text.contains("`\(key.name)`"), "docs/MDM.md lacks \(key.name)")
    }
  }

  @Test
  func everySettingIsManageable() {
    let managed = Set(ManagedSettings.keys.map(\.name))
    for key in AppSettings.Key.allCases {
      #expect(managed.contains(key.rawValue), "\(key.rawValue) is missing in ManagedSettings")
    }
  }

  @Test
  func profileValuesAreReadAndLocked() throws {
    let testDefaults = try TestDefaults("takt-mdm")
    let suite = testDefaults.suiteName
    let defaults = testDefaults.defaults
    let payload = try profilePayload()
    for (key, value) in payload { defaults.set(value, forKey: key) }
    // Values different from the defaults, to see that they are really read.
    defaults.set("parallel", forKey: "startMode")
    defaults.set("full", forKey: "countingMode")
    defaults.set(25, forKey: "idleThresholdMinutes")
    defaults.set(true, forKey: "lockCountsAsPause")
    defaults.set("automatic", forKey: "bookingMode")
    defaults.set(false, forKey: "reduceRemainingWork")
    defaults.set(false, forKey: "bookingIncludesNote")
    defaults.set(7.5, forKey: "dailyGoalHours")
    defaults.set(32.0, forKey: "weeklyHours")
    defaults.set([1, 2, 3, 4], forKey: "workDays")
    defaults.set(false, forKey: "showElapsedInMenuBar")
    defaults.set(["/Users/x/src"], forKey: "gitFolders")
    defaults.set(true, forKey: "onboardingCompleted")

    let forced = Set(payload.keys)
    let settings = AppSettings(defaults: defaults) { forced.contains($0) }

    #expect(settings.startMode == .parallel)
    #expect(settings.countingMode == .full)
    #expect(settings.idleThresholdMinutes == 25)
    #expect(settings.lockCountsAsPause)
    #expect(settings.roundingMinutes == 15)
    #expect(settings.bookingMode == .automatic)
    #expect(!settings.reduceRemainingWork)
    #expect(!settings.bookingIncludesNote)
    #expect(settings.dailyGoalHours == 7.5)
    #expect(settings.weeklyHours == 32)
    #expect(settings.workDays == [1, 2, 3, 4])
    #expect(!settings.showElapsedInMenuBar)
    #expect(settings.gitFolders == ["/Users/x/src"])
    #expect(settings.onboardingCompleted)
    // The services read the same values (idle monitor, booking, Git branches).
    #expect(settings.snapshot.idle == IdleSettings(threshold: 25 * 60, lockCountsAsPause: true))
    #expect(!settings.snapshot.bookingOptions.reduceRemainingWork)
    #expect(!settings.snapshot.bookingOptions.includeNote)
    #expect(settings.snapshot.gitFolders == ["/Users/x/src"])
    #expect(ADOAccounts(suiteName: suite).managedOrganization == "contoso")

    for key in AppSettings.Key.allCases {
      #expect(settings.isLocked(key), "\(key.rawValue) should be locked")
    }
    // A locked value cannot be changed from the app.
    settings.roundingMinutes = 5
    #expect(defaults.integer(forKey: "roundingMinutes") == 15)
  }

  // MARK: Private

  /// docs/mdm/Takt.mobileconfig, found relative to this file.
  private func profilePayload() throws -> [String: Any] {
    let repository = URL(filePath: #filePath).deletingLastPathComponent() // TaktUITests
      .deletingLastPathComponent().deletingLastPathComponent() // Tests, TaktKit
      .deletingLastPathComponent().deletingLastPathComponent() // Packages, repository
    let data = try Data(contentsOf: repository.appending(path: "docs/mdm/Takt.mobileconfig"))
    let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let content = try #require(plist["PayloadContent"] as? [[String: Any]])
    let payload = try #require(content.first { $0["PayloadType"] as? String == AppIdentity.bundleIdentifier })
    return payload.filter { !$0.key.hasPrefix("Payload") }
  }

  private func documentation() throws -> String {
    let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: repository.appending(path: "docs/MDM.md"), encoding: .utf8)
  }

}
