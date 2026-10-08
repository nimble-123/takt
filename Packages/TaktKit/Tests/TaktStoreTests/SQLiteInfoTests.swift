import Testing

@testable import TaktStore

struct SQLiteInfoTests {
  @Test
  func linksSQLite3() throws {
    let version = try SQLiteInfo.version()
    #expect(version.hasPrefix("3."))
  }
}
