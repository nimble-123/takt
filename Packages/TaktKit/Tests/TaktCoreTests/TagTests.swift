import Foundation
import Testing

@testable import TaktCore

struct TagTests {
  @Test
  func commaSeparatedNamesAreTrimmedAndEmptyOnesDropped() {
    #expect(Tag.names(fromCommaSeparated: " fix, Kunde ,, \n,review") == ["fix", "Kunde", "review"])
  }

  @Test
  func blankTextHasNoNames() {
    #expect(Tag.names(fromCommaSeparated: "  , ").isEmpty)
  }
}
