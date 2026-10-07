import Foundation
import TaktADO
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

@MainActor
struct AzureDevOpsModelTests {
    let clock = ManualClock()

    @Test func takingOverCreatesAzureDevOpsProjectsOnce() async throws {
        let database = try AppDatabase.inMemory()
        let catalog = CatalogModel(store: CatalogStore(database: database), clock: clock)
        let model = AzureDevOpsModel(
            accounts: ADOAccounts(secrets: NoSecrets(), suiteName: "takt-ado-ui-\(UUID().uuidString)"),
            catalog: catalog, clock: clock
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
}

private struct NoSecrets: SecretStore {
    func read(_ account: String) throws -> String? { nil }
    func write(_ secret: String, for account: String) throws {}
    func delete(_ account: String) throws {}
}
