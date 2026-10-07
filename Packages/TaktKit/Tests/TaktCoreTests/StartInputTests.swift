import Testing

@testable import TaktCore

struct StartInputTests {
    @Test func splitsTitleAndTokens() {
        let input = StartInput.parse("Doku überarbeiten /kunden @review #release")
        #expect(input.title == "Doku überarbeiten")
        #expect(input.category == "review")
        #expect(input.project == "kunden")
        #expect(input.task == nil)
        #expect(input.tags == ["release"])
    }

    @Test func orderDoesNotMatterAndSpacesAreCollapsed() {
        let input = StartInput.parse("  @meet   Daily   #team  Standup ")
        #expect(input.title == "Daily Standup")
        #expect(input.category == "meet")
        #expect(input.tags == ["team"])
    }

    @Test func projectWithTask() {
        let input = StartInput.parse("Fix /kunden/api")
        #expect(input.project == "kunden")
        #expect(input.task == "api")
    }

    @Test func tokensOnlyCountAtTheStartOfAWord() {
        let input = StartInput.parse("Mail an max@example.com wegen 1/2 Tag")
        #expect(input.title == "Mail an max@example.com wegen 1/2 Tag")
        #expect(!input.hasTokens)
    }

    @Test func workItemNumbersStayInTheTitle() {
        let input = StartInput.parse("#4711 Review #q3")
        #expect(input.title == "#4711 Review")
        #expect(input.tags == ["q3"])
    }

    @Test func bareMarkersAreText() {
        let input = StartInput.parse("A / B @ C #")
        #expect(input.title == "A / B @ C #")
        #expect(!input.hasTokens)
    }

    @Test func laterTokensWinAndTagsAreUnique() {
        let input = StartInput.parse("X @meet @review /a /b #Tag #tag #other")
        #expect(input.category == "review")
        #expect(input.project == "b")
        #expect(input.tags == ["Tag", "other"])
    }

    @Test func partialTokenAtTheEnd() {
        #expect(StartInput.partial(in: "Doku @rev") == .category("rev"))
        #expect(StartInput.partial(in: "Doku @") == .category(""))
        #expect(StartInput.partial(in: "Doku /kun") == .project("kun", task: nil))
        #expect(StartInput.partial(in: "Doku /kunden/a") == .project("kunden", task: "a"))
        #expect(StartInput.partial(in: "Doku #rel") == .tag("rel"))
        #expect(StartInput.partial(in: "Doku #47") == nil)
        #expect(StartInput.partial(in: "Doku @review ") == nil)
        #expect(StartInput.partial(in: "Doku") == nil)
        #expect(StartInput.partial(in: "") == nil)
    }

    @Test func completingReplacesTheLastWord() {
        #expect(StartInput.completing("Doku @rev", with: .category("Code Review")) == "Doku @CodeReview ")
        #expect(StartInput.completing("Doku /kun", with: .project("Kundenportal", task: nil)) == "Doku /Kundenportal ")
        #expect(
            StartInput.completing("Doku /kunden/a", with: .project("Kundenportal", task: "API-Doku"))
                == "Doku /Kundenportal/API-Doku ")
        #expect(StartInput.completing("#rel", with: .tag("release")) == "#release ")
    }
}
