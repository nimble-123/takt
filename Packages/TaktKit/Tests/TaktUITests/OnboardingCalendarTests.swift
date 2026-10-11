import Foundation
import Synchronization
import TaktCore
import TaktSystem
import Testing

@testable import TaktUI

// MARK: - OnboardingCalendarTests

@MainActor
struct OnboardingCalendarTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults()
    settings = AppSettings(defaults: testDefaults.defaults)
  }

  // MARK: Internal

  @Test
  func signedInUserCanTurnTheCalendarOnAndOff() async throws {
    let store = MemoryStore(#"{"refreshToken":"r","account":{"name":"Nils","username":"info@nilslutz.de"}}"#)
    let account = try makeAccount(store)
    await account.load()
    let model = OnboardingModel(settings: settings, microsoftAccount: account)

    await model.setCalendarEnabled(true)
    #expect(settings.calendarEnabled)
    await model.setCalendarEnabled(false)
    #expect(!settings.calendarEnabled)
  }

  @Test
  func withoutMicrosoftAccountTheCalendarStaysOff() async {
    let model = OnboardingModel(settings: settings)
    await model.setCalendarEnabled(true)
    #expect(!settings.calendarEnabled)
  }

  // MARK: Private

  private final class MemoryStore: EntraTokenStore {

    // MARK: Lifecycle

    init(_ value: String?) {
      stored = Mutex(value)
    }

    // MARK: Internal

    func read() throws -> String? {
      stored.withLock { $0 }
    }

    func write(_ value: String) throws {
      stored.withLock { $0 = value }
    }

    func delete() throws {
      stored.withLock { $0 = nil }
    }

    // MARK: Private

    private let stored: Mutex<String?>
  }

  private let testDefaults: TestDefaults
  private let settings: AppSettings

  private func makeAccount(_ store: MemoryStore) throws -> MicrosoftAccountModel {
    let configuration = try #require(EntraConfiguration(tenantID: "tenant", clientID: "client"))
    return MicrosoftAccountModel(
      session: EntraSession(configuration: configuration, store: store, clock: ManualClock()),
      defaults: testDefaults.defaults,
    )
  }
}
