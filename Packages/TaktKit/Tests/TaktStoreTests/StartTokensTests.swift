import TaktCore
import Testing

@testable import TaktStore

/// Resolving a start input against the catalog without the app, e.g. for the command line (MB-09).
struct StartTokensTests {

  // MARK: Lifecycle

  init() {
    api = ProjectTask(projectID: portal.id, name: "API")
  }

  // MARK: Internal

  @Test
  func tokensResolveExactlyThenFuzzilyAndSkipArchivedItems() {
    let tokens = StartTokens(StartInput.parse("Login @dev /portal/api #Auth"), catalog: catalog)

    #expect(tokens.categoryID == development.id)
    #expect(tokens.projectID == portal.id)
    #expect(tokens.taskID == api.id)
    // An existing tag keeps its spelling.
    #expect(tokens.tags == ["auth"])
    #expect(tokens.chips.map(\.resolved) == [true, true, true, true])

    let archived = StartTokens(StartInput.parse("x /archive"), catalog: catalog)
    #expect(archived.projectID == nil)
    #expect(archived.chips.map(\.resolved) == [false])
  }

  @Test
  func completionsOfferANewTagOnlyWhenNoneMatches() {
    let completions = StartTokens.completions(for: .tag("cust"), catalog: catalog, newTagHint: "new")
    #expect(completions.map(\.title) == ["cust"])
    #expect(completions.first?.subtitle == "new")
    #expect(StartTokens.completions(for: .tag("AUTH"), catalog: catalog, newTagHint: "new").map(\.title) == ["auth"])
  }

  @Test
  func workItemDraftTakesTheProjectWithoutAreaPath() {
    let item = WorkItemLink(organization: "contoso", project: "Portal", workItemID: 4821, cachedTitle: "Login")
    let draft = catalog.draft(for: item)
    #expect(draft.title == "Login")
    #expect(draft.projectID == ado.id)
    #expect(draft.workItemLinkID == item.id)
  }

  // MARK: Private

  private let development = EntryCategory(name: "Development", color: "#2563EB")
  private let portal = Project(name: "Portal", color: "#0F766E", createdAt: Timestamp(milliseconds: 0))
  private let old = Project(name: "Archive", color: "#0F766E", archived: true, createdAt: Timestamp(milliseconds: 0))
  private let ado = Project(
    name: "Portal (ADO)",
    color: "#0F766E",
    source: .ado,
    adoOrganization: "contoso",
    adoProject: "Portal",
    createdAt: Timestamp(milliseconds: 0),
  )
  private let api: ProjectTask

  private var catalog: Catalog {
    Catalog(
      projects: [portal, old, ado],
      tasks: [api],
      categories: [development, EntryCategory(name: "Meeting", color: "#C2410C")],
      tags: [Tag(name: "auth")],
    )
  }

}
