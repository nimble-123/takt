import SwiftUI
import TaktCore
import TaktStore

// MARK: - MainWindowView

/// The main window: sidebar, content and inspector (docs/DESIGN.md, "Hauptfenster").
public struct MainWindowView: View {

  // MARK: Lifecycle

  public init(model: MainWindowModel) {
    self.model = model
    _palette = State(initialValue: CommandPaletteModel(window: model))
  }

  // MARK: Public

  public var body: some View {
    NavigationSplitView {
      List(model.sections, selection: sectionBinding) { section in
        Label(section.title, systemImage: section.symbol)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 180)
    } detail: {
      // Only screens that show entries carry the inspector, bound directly to the user's choice.
      // A binding that read `showsInspector` but wrote `isInspectorShown` let the closing inspector
      // overwrite the choice and coincided with a constraint update loop crash.
      if model.hasInspector {
        detail
          .inspector(isPresented: $model.isInspectorShown) {
            EntryInspector(model: model)
              .inspectorColumnWidth(min: 260, ideal: 300)
          }
      } else {
        detail
      }
    }
    .modifier(SearchField(model: model))
    .sheet(isPresented: $palette.isPresented) {
      CommandPaletteView(model: palette)
    }
    .alert(
      Text("Reason for the Correction", bundle: .module),
      isPresented: Binding(get: { model.correctionReasonRequest != nil }) { shown in
        if !shown { model.answerCorrectionReason(nil) }
      },
    ) {
      TextField(String(localized: "Reason (optional)", bundle: .module), text: $correctionReason)
      Button(String(localized: "Save", bundle: .module)) {
        model.answerCorrectionReason(correctionReason)
        correctionReason = ""
      }
      Button(String(localized: "Without Reason", bundle: .module), role: .cancel) {
        model.answerCorrectionReason(nil)
        correctionReason = ""
      }
    } message: {
      Text(
        "You are changing times older than 7 days. A reason makes the correction traceable.",
        bundle: .module,
      )
    }
    .background {
      // ⌘K: every action is one search away (HW-05).
      Button("") { palette.isPresented.toggle() }
        .keyboardShortcut("k", modifiers: .command)
        .hidden()
    }
    .onAppear {
      #if DEBUG
      // `-paletteQuery text` opens the palette with a query, for screenshots and UI tests.
      if let query = UserDefaults.standard.string(forKey: "paletteQuery") {
        palette.isPresented = true
        palette.query = query
      }
      #endif
      palette.export = { [model] format in
        guard let analytics = model.analytics else { return }
        // The analysis may not have been opened yet: load the shown period first.
        Task {
          await analytics.reload()
          AnalyticsScreen.saveExport(analytics, format)
        }
      }
      palette.exportTimeRecord = { [model] csv in
        guard let analytics = model.analytics else { return }
        Task {
          await analytics.reload()
          AnalyticsScreen.saveTimeRecord(analytics, csv: csv)
        }
      }
    }
    .navigationTitle(title)
    .toolbar {
      ToolbarItemGroup(placement: .navigation) {
        Button {
          model.step(by: -1)
        } label: {
          Label(String(localized: "Previous", bundle: .module), systemImage: "chevron.left")
        }
        Button(String(localized: "Today", bundle: .module)) { model.showToday() }
        Button {
          model.step(by: 1)
        } label: {
          Label(String(localized: "Next", bundle: .module), systemImage: "chevron.right")
        }
      }
      ToolbarItem {
        Button {
          Task { await model.createRecentEntry() }
        } label: {
          Label(String(localized: "New Entry", bundle: .module), systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
      }
      ToolbarItem {
        Button {
          model.isInspectorShown.toggle()
        } label: {
          Label(String(localized: "Inspector", bundle: .module), systemImage: "sidebar.trailing")
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(!model.hasInspector)
      }
    }
    .onDeleteCommand {
      Task { await model.deleteSelection() }
    }
    .onAppear { model.undoManager = undoManager }
    .onChange(of: undoManager) { model.undoManager = undoManager }
    .task { await model.reload() }
    .frame(minWidth: 820, minHeight: 520)
  }

  // MARK: Internal

  @Bindable var model: MainWindowModel

  // MARK: Private

  @Environment(\.undoManager) private var undoManager
  @State private var palette: CommandPaletteModel
  @State private var correctionReason = ""

  private var detail: some View {
    VStack(spacing: 0) {
      if let message = model.errorMessage {
        Text(message)
          .font(.system(size: 12))
          .foregroundStyle(Palette.danger)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .background(Palette.warningSurface)
      }
      if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
        SearchResultsScreen(model: model)
      } else {
        sectionContent
      }
    }
  }

  @ViewBuilder
  private var sectionContent: some View {
    switch model.section {
    case .today: DayScreen(model: model)
    case .dayClose:
      if let booking = model.booking { DayCloseScreen(model: model, booking: booking) }
    case .week: WeekScreen(model: model)
    case .entries: EntryListScreen(model: model)
    case .analytics:
      if let analytics = model.analytics { AnalyticsScreen(model: analytics) }
    case .projects: CatalogScreen(catalog: model.catalog, rules: model.rules)
    case .settings:
      if let settings = model.settings { SettingsScreen(settings: settings, model: model) }
    }
  }

  private var sectionBinding: Binding<MainWindowModel.Section?> {
    Binding(get: { model.section }, set: { if let section = $0 { model.section = section } })
  }

  private var title: String {
    switch model.section {
    case .today, .dayClose:
      // The holiday follows the date, e.g. "Thursday, 4 June 2026 · Corpus Christi" (AZ-03).
      [
        model.dayRange.lowerBound.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()),
        model.holiday(on: model.dayRange.lowerBound)?.name,
        model.absence(on: model.dayRange.lowerBound)?.name,
      ]
      .compactMap(\.self)
      .joined(separator: " · ")

    case .projects:
      String(localized: "Projects", bundle: .module)

    case .analytics:
      String(localized: "Analytics", bundle: .module)

    case .settings:
      String(localized: "Settings", bundle: .module)

    case .week, .entries:
      String(
        localized: "Week \(model.weekRange.lowerBound.date.formatted(.dateTime.week()))",
        bundle: .module,
      )
    }
  }

}

// MARK: - SearchField

/// The window's search field (HW-06), only when a search index is available.
private struct SearchField: ViewModifier {
  @Bindable var model: MainWindowModel

  func body(content: Content) -> some View {
    if model.search != nil {
      content.searchable(
        text: $model.searchText,
        placement: .toolbar,
        prompt: Text("Entries, notes, projects, work items", bundle: .module),
      )
    } else {
      content
    }
  }
}

extension MainWindowModel.Section {
  var title: String {
    switch self {
    case .today: String(localized: "Today", bundle: .module)
    case .dayClose: String(localized: "Day Close", bundle: .module)
    case .week: String(localized: "Week", bundle: .module)
    case .entries: String(localized: "Entries", bundle: .module)
    case .analytics: String(localized: "Analytics", bundle: .module)
    case .projects: String(localized: "Projects", bundle: .module)
    case .settings: String(localized: "Settings", bundle: .module)
    }
  }

  var symbol: String {
    switch self {
    case .today: "sun.max"
    case .dayClose: "checkmark.seal"
    case .week: "calendar"
    case .entries: "list.bullet"
    case .analytics: "chart.bar.xaxis"
    case .projects: "folder"
    case .settings: "gearshape"
    }
  }
}
