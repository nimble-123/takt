import Foundation
import TaktCore
import Testing

@testable import TaktUI

struct InspectorFieldsTests {

  // MARK: Internal

  @Test
  func typedTitleSurvivesASaveOfAnotherField() {
    var fields = InspectorFields(entry)
    fields.title = "Typed"
    var saved = entry
    saved.categoryID = CategoryID()
    saved.weight = 2

    fields.reload(from: entry, to: saved)

    #expect(fields.title == "Typed")
    #expect(fields.weight == 2)
  }

  @Test
  func storedChangesReplaceTheFields() {
    var fields = InspectorFields(entry)
    fields.note = "Typed"
    var saved = entry
    saved.title = "Renamed"
    saved.note = "Undone"

    fields.reload(from: entry, to: saved)

    #expect(fields == InspectorFields(saved))
  }

  // MARK: Private

  private let entry = TimeEntry(
    title: "Review",
    note: "Old",
    createdAt: Timestamp(milliseconds: 0),
    updatedAt: Timestamp(milliseconds: 0),
  )

}
