import TaktCore
import Testing

@testable import TaktStore

struct RuleStoreTests {
  @Test
  func rulesKeepTheirOrder() async throws {
    let store = RuleStore(database: try AppDatabase.inMemory())
    #expect(try await store.load().isEmpty)
    let rules = [
      Rule(name: "B", conditions: [.workItemType("Bug")]),
      Rule(name: "A", conditions: [.titleContains("x")]),
    ]
    try await store.save(rules)
    #expect(try await store.load() == rules)
    try await store.save([rules[1]])
    #expect(try await store.load().map(\.name) == ["A"])
  }
}
