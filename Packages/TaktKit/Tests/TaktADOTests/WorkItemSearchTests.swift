import Foundation
import TaktCore
import Testing

@testable import TaktADO

// MARK: - WorkItemSearchTests

struct WorkItemSearchTests {

  // MARK: Internal

  @Test
  func batchDecodesThePreviewFields() async throws {
    stub.respond { _ in Stub.Response(status: 200, body: Stub.fixture("workitemsbatch")) }

    let items = try await client.workItems([1234, 1200], seenAt: clock.now())

    let task = try #require(items.first)
    #expect(task.workItemID == 1234)
    #expect(task.organization == "contoso" && task.project == "Kundenportal")
    #expect(task.cachedType == "Task" && task.cachedState == "Active")
    #expect(task.assignedTo == "Nils Lutz")
    #expect(task.iterationPath == "Kundenportal\\Sprint 42")
    #expect(task.remainingWork == 2.75 && task.completedWork == 7.5)
    #expect(task.parentID == 1200)
    #expect(task.descriptionExcerpt == "Der Refresh-Token läuft ab, bevor der Interceptor greift.")
    #expect(task.tags == ["auth", "login"])
    #expect(items.last?.assignedTo == nil)
    #expect(body(try #require(stub.requests.first)).contains("\"errorPolicy\":\"omit\""))
  }

  @Test
  func duplicateIDsDoNotCrash() async throws {
    stub.respond { _ in Stub.Response(status: 200, body: Stub.fixture("workitemsbatch")) }

    let items = try await client.workItems([1234, 1200, 1234], seenAt: clock.now())

    #expect(items.map(\.workItemID) == [1234, 1200])
  }

  @Test
  func idSearchFetchesTheItemDirectly() async throws {
    stub.respond { request in
      #expect(request.url?.path() == "/contoso/_apis/wit/workitemsbatch")
      return Stub.Response(status: 200, body: Stub.fixture("workitemsbatch"))
    }
    _ = try await WorkItemSearch(client: client, clock: clock).search("#1234")
    #expect(stub.requests.count == 1)
    #expect(body(stub.requests[0]).contains("\"ids\":[1234]"))
  }

  @Test
  func fullTextSearchIsUsedWhenAvailable() async throws {
    stub.respond { request in
      if request.url?.host() == "almsearch.dev.azure.com" {
        return Stub.Response(status: 200, body: Stub.fixture("workitemsearch"))
      }
      return Stub.Response(status: 200, body: Stub.fixture("workitemsbatch"))
    }
    let items = try await WorkItemSearch(client: client, clock: clock).search("Token")
    #expect(items.first?.workItemID == 1234)
    #expect(stub.requests.first?.url?.path() == "/contoso/_apis/search/workitemsearchresults")
  }

  @Test
  func withoutSearchExtensionWIQLIsUsedFromThenOn() async throws {
    stub.respond { request in
      switch request.url?.path() {
      case "/contoso/_apis/search/workitemsearchresults": Stub.Response(status: 404, body: Data())
      case "/contoso/_apis/wit/wiql": Stub.Response(status: 200, body: Stub.fixture("wiql"))
      default: Stub.Response(status: 200, body: Stub.fixture("workitemsbatch"))
      }
    }
    let search = WorkItemSearch(client: client, clock: clock)

    let items = try await search.search("O'Brien")
    _ = try await search.search("Token")

    #expect(items.map(\.workItemID) == [1234, 1200])
    let paths = stub.requests.map { $0.url?.path() ?? "" }
    #expect(paths.count(where: { $0.hasSuffix("workitemsearchresults") }) == 1)
    let wiql = try #require(stub.requests.first { $0.url?.path() == "/contoso/_apis/wit/wiql" })
    #expect(body(wiql).contains("CONTAINS 'O''Brien'"))
    #expect(wiql.url?.query()?.contains("$top=20") == true)
  }

  @Test
  func suggestionsAskEveryTeamForTheCurrentIteration() async throws {
    stub.respond { request in
      switch request.url?.path(percentEncoded: false) {
      case "/contoso/_apis/projects/Kundenportal/teams": Stub.Response(status: 200, body: Stub.fixture("teams"))
      case "/contoso/Kundenportal/Team Login/_apis/wit/wiql", "/contoso/_apis/wit/wiql":
        Stub.Response(status: 200, body: Stub.fixture("wiql"))
      default: Stub.Response(status: 200, body: Stub.fixture("workitemsbatch"))
      }
    }
    let items = try await WorkItemSearch(client: client, clock: clock).suggestions(projects: ["Kundenportal"])

    #expect(items.map(\.workItemID) == [1234, 1200])
    let teamQuery = try #require(
      stub.requests.first {
        $0.url?.path(percentEncoded: false) == "/contoso/Kundenportal/Team Login/_apis/wit/wiql"
      }
    )
    #expect(body(teamQuery).contains("@CurrentIteration"))
    #expect(stub.requests.contains { body($0).contains("[System.ChangedBy] = @Me") })
  }

  @Test(arguments: [("#1234", 1234), ("1234", 1234), ("12a", nil), ("#", nil), ("Login", nil)])
  func workItemIDsAreRecognized(text: String, id: Int?) {
    #expect(WorkItemSearch.workItemID(in: text) == id)
  }

  @Test
  func webURLPointsToTheEditPage() {
    let item = WorkItemLink(organization: "contoso", project: "Kunden Portal", workItemID: 7)
    #expect(
      ADOClient.webURL(of: item).absoluteString
        == "https://dev.azure.com/contoso/Kunden%20Portal/_workitems/edit/7"
    )
  }

  // MARK: Private

  private let stub = Stub()
  private let clock = ManualClock()

  private var client: ADOClient {
    ADOClient(organization: "contoso", authorization: PATAuthorization(token: "t"), session: stub.session)
  }

  private func body(_ request: URLRequest) -> String {
    request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
  }

}

extension WorkItemSearchTests {
  @Test
  func entitiesAreDecoded() {
    #expect(
      ADOClient.decodeEntities("Gr&uuml;&szlig;e &#228; &#xE4; &amp;&unknown; & x") == "Grüße ä ä &&unknown; & x"
    )
  }
}
