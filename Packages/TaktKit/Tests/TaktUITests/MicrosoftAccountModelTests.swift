import Foundation
import TaktCore
import TaktSystem
import Testing

@testable import TaktUI

// MARK: - MicrosoftAccountModelTests

@MainActor
struct MicrosoftAccountModelTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults()
  }

  // MARK: Internal

  @Test
  func enteredIDsAreKeptInTheDefaults() {
    let model = makeModel()
    #expect(model.configuration == nil)
    model.clientID = " client "
    model.tenantID = "contoso.onmicrosoft.com"
    #expect(testDefaults.defaults.string(forKey: MicrosoftAccountModel.clientIDKey) == "client")
    #expect(model.configuration?.tenantID == "contoso.onmicrosoft.com")
    #expect(makeModel().clientID == "client")
    model.clientID = ""
    #expect(testDefaults.defaults.object(forKey: MicrosoftAccountModel.clientIDKey) == nil)
  }

  @Test
  func idsFromTheProfileAreLocked() {
    testDefaults.defaults.set("managed-client", forKey: MicrosoftAccountModel.clientIDKey)
    let model = makeModel { $0 == MicrosoftAccountModel.clientIDKey }
    #expect(model.isClientIDLocked)
    #expect(!model.isTenantIDLocked)
    model.clientID = "other"
    #expect(testDefaults.defaults.string(forKey: MicrosoftAccountModel.clientIDKey) == "managed-client")
  }

  @Test
  func signInWithoutIDsAsksForThem() async {
    let model = makeModel()
    await model.signIn()
    #expect(model.account == nil)
    #expect(model.errorMessage != nil)
  }

  // MARK: Private

  private struct NoStore: EntraTokenStore {
    func read() throws -> String? {
      nil
    }

    func write(_: String) throws { }
    func delete() throws { }
  }

  private let testDefaults: TestDefaults

  private func makeModel(isForced: ((String) -> Bool)? = nil) -> MicrosoftAccountModel {
    MicrosoftAccountModel(
      session: EntraSession(configuration: nil, store: NoStore(), clock: ManualClock()),
      defaults: testDefaults.defaults,
      isForced: isForced ?? { _ in false },
    )
  }
}
