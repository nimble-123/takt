import Foundation
import TaktADO
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

// MARK: - AzureDevOpsModelTests

@MainActor
struct AzureDevOpsModelTests {

  // MARK: Internal

  @Test
  func takingOverCreatesAzureDevOpsProjectsOnce() async throws {
    let database = try AppDatabase.inMemory()
    let catalog = CatalogModel(store: CatalogStore(database: database), clock: clock)
    let model = AzureDevOpsModel(
      accounts: ADOAccounts(secrets: NoSecrets(), suiteName: "takt-ado-ui-\(UUID().uuidString)"),
      catalog: catalog,
      clock: clock,
    )
    model.importOrganization = "contoso"

    await model.takeOver("Kundenportal")
    await model.takeOver("Kundenportal", areaPath: "Kundenportal\\Team Login")
    await model.takeOver("Kundenportal")

    let projects = catalog.catalog.projects
    #expect(projects.count == 2)
    #expect(projects.allSatisfy { $0.source == .ado && $0.adoOrganization == "contoso" })
    #expect(Set(projects.map(\.name)) == ["Kundenportal", "Team Login"])
    #expect(model.isTakenOver("Kundenportal", areaPath: "Kundenportal\\Team Login"))
  }

  // MARK: Private

  private let clock = ManualClock()

}

// MARK: - NoSecrets

private struct NoSecrets: SecretStore {
  func read(_: String) throws -> String? {
    nil
  }

  func write(_: String, for _: String) throws { }
  func delete(_: String) throws { }
}
