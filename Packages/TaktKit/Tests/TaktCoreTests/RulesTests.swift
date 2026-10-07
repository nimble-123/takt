import Foundation
import Testing

@testable import TaktCore

struct RulesTests {
    let support = CategoryID()
    let development = CategoryID()
    let portal = ProjectID()

    private func bug(_ title: String = "Login fehlt", project: String = "Kundenportal", tags: [String] = [])
        -> WorkItemLink
    {
        WorkItemLink(
            organization: "o", project: project, workItemID: 1, cachedTitle: title, cachedType: "Bug", tags: tags)
    }

    @Test func bugBecomesSupport() {
        let rule = Rule(conditions: [.workItemType("bug")], categoryID: support)
        let (draft, _) = Rules.apply([rule], to: EntryDraft(title: "Login fehlt"), workItem: bug())
        #expect(draft.categoryID == support)
    }

    @Test func allConditionsMustMatch() {
        let rule = Rule(conditions: [.workItemType("Bug"), .adoProject("Backoffice")], categoryID: support)
        #expect(!rule.matches(title: "x", workItem: bug()))
        #expect(rule.matches(title: "x", workItem: bug(project: "backoffice")))
    }

    @Test func ruleWithoutConditionsOrDisabledNeverMatches() {
        #expect(!Rule(conditions: [], categoryID: support).matches(title: "x", workItem: bug()))
        #expect(!Rule(isEnabled: false, conditions: [.workItemType("Bug")]).matches(title: "x", workItem: bug()))
    }

    @Test func workItemConditionsNeedAWorkItem() {
        let rule = Rule(conditions: [.workItemType("Bug")], categoryID: support)
        #expect(!rule.matches(title: "Bug fixen", workItem: nil))
    }

    @Test func titleAndTagConditions() {
        #expect(Rule(conditions: [.titleContains("daily")]).matches(title: "Daily Standup", workItem: nil))
        #expect(Rule(conditions: [.titleContains("ubung")]).matches(title: "Übungsrunde", workItem: nil))
        #expect(Rule(conditions: [.workItemTag("Kunde")]).matches(title: "", workItem: bug(tags: ["kunde", "x"])))
    }

    @Test func firstMatchingRuleWinsPerField() {
        let rules = [
            Rule(conditions: [.workItemType("Bug")], categoryID: support, tags: ["fix"]),
            Rule(
                conditions: [.adoProject("Kundenportal")], categoryID: development, projectID: portal,
                tags: ["Fix", "portal"]),
        ]
        let result = Rules.evaluate(rules, title: "x", workItem: bug())
        #expect(result.categoryID == support)
        #expect(result.projectID == portal)
        #expect(result.tags == ["fix", "portal"])
    }

    @Test func manualChoiceWins() {
        let rule = Rule(conditions: [.workItemType("Bug")], categoryID: support, projectID: portal)
        let manual = CategoryID()
        let (draft, _) = Rules.apply([rule], to: EntryDraft(title: "x", categoryID: manual), workItem: bug())
        #expect(draft.categoryID == manual)
        #expect(draft.projectID == portal)
    }

    @Test func rulesRoundTripAsJSON() throws {
        let rule = Rule(
            name: "Bugs", conditions: [.workItemType("Bug"), .titleContains("x")], categoryID: support, tags: ["a"])
        let data = try JSONEncoder().encode([rule])
        #expect(try JSONDecoder().decode([Rule].self, from: data) == [rule])
    }
}
