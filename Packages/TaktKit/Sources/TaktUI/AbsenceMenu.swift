import SwiftUI
import TaktCore

/// Marks a day as vacation, sick or off (AZ-05); for context menus on a day.
struct AbsenceMenu: View {
  let model: MainWindowModel
  let day: Timestamp

  var body: some View {
    let current = model.absence(on: day)
    Menu(String(localized: "Absence", bundle: .module)) {
      ForEach(AbsenceKind.allCases, id: \.self) { kind in
        Toggle(kind.name, isOn: Binding(get: { current == kind }) { on in
          Task { await model.setAbsence(on ? kind : nil, on: day) }
        })
      }
      if current != nil {
        Divider()
        Button(String(localized: "No Absence", bundle: .module)) {
          Task { await model.setAbsence(nil, on: day) }
        }
      }
    }
  }
}
