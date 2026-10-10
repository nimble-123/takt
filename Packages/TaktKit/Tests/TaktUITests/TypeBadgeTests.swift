import Testing

@testable import TaktUI

/// Work item type colours as in Azure DevOps.
struct TypeBadgeTests {
  @Test
  func featuresArePurpleAndEpicsOrange() {
    #expect(TypeBadge.hex(for: "Feature") == "#7E22CE")
    #expect(TypeBadge.hex(for: "Epic") == "#EA580C")
    #expect(TypeBadge.hex(for: "Bug") == "#B91C1C")
    #expect(TypeBadge.hex(for: "Product Backlog Item") == "#0369A1")
    #expect(TypeBadge.hex(for: "technical Story") == "#475569")
  }
}
