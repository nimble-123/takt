import AppKit
import Observation
import SwiftUI
import TaktCore
import TaktStore

// MARK: - PaletteItem

/// One thing the palette can do.
public struct PaletteItem: Identifiable {
  public var id: String
  public var title: String
  public var subtitle: String?
  public var symbol: String
  /// Shown right-aligned, e.g. `⌘N`.
  public var shortcut: String?
  /// Further words the fuzzy search matches.
  public var keywords = [String]()
  public var perform: @MainActor () async -> Void
}

// MARK: - CommandPaletteModel

/// State of the command palette (HW-05): actions plus hits from the full-text search and work items.
@MainActor
@Observable
public final class CommandPaletteModel {

  // MARK: Lifecycle

  public init(window: MainWindowModel) {
    self.window = window
  }

  // MARK: Public

  public var selection = 0
  public private(set) var hits = [PaletteItem]()

  public var isPresented = false {
    didSet {
      if isPresented {
        query = ""
        selection = 0
      }
    }
  }

  public var query = "" {
    didSet {
      selection = 0
      loadHits()
    }
  }

  /// Matching actions first, then entries and work items from the search.
  public var items: [PaletteItem] {
    let text = query.trimmingCharacters(in: .whitespaces)
    let actions = actions()
    guard !text.isEmpty else { return actions }
    var scored = actions.compactMap { item -> (PaletteItem, Int)? in
      let best = ([item.title] + item.keywords).compactMap { FuzzyMatch.score(text, in: $0) }.max()
      return best.map { (item, $0) }
    }
    scored.sort { $0.1 > $1.1 }
    // The typed text may carry tokens: `@category`, `/project/task`, `#tag` (MB-09).
    let input = StartInput.parse(text)
    guard !input.title.isEmpty else { return scored.map(\.0) + hits }
    let tokens = StartTokens(input, catalog: window.catalog)
    let start = PaletteItem(
      id: "start-typed",
      title: String(localized: "Start Timer “\(input.title)”", bundle: .module),
      subtitle: tokens.chips.isEmpty ? nil : tokens.chips.map(\.label).joined(separator: " · "),
      symbol: "play.circle",
      shortcut: "↩",
    ) { [window] in
      await window.startTimer(tokens.applied(to: EntryDraft(title: input.title)), tags: tokens.tags)
    }
    return scored.map(\.0) + [start] + hits
  }

  public func moveSelection(by offset: Int) {
    let count = items.count
    guard count > 0 else { return }
    selection = (selection + offset + count) % count
  }

  public func runSelected() async {
    let items = items
    guard items.indices.contains(selection) else { return }
    isPresented = false
    await items[selection].perform()
  }

  // MARK: Internal

  /// Saves an export; provided by the view, which owns the save panel.
  @ObservationIgnored var export: ((AnalyticsModel.ExportFormat) -> Void)?

  // MARK: Private

  private let window: MainWindowModel
  @ObservationIgnored private var hitTask: Task<Void, Never>?

  private func actions() -> [PaletteItem] {
    var items: [PaletteItem] = [
      PaletteItem(
        id: "pause-all",
        title: String(localized: "Pause or Resume All", bundle: .module),
        symbol: "pause.circle",
        shortcut: "⌥⇧P",
        keywords: ["pause", "resume", "fortsetzen"],
      ) { [window] in await window.togglePauseAll() },
      PaletteItem(
        id: "stop-all",
        title: String(localized: "Stop All Timers", bundle: .module),
        symbol: "stop.circle",
        keywords: ["stop", "beenden"],
      ) { [window] in await window.stopAll() },
      PaletteItem(
        id: "new-entry",
        title: String(localized: "New Entry", bundle: .module),
        symbol: "plus",
        shortcut: "⌘N",
        keywords: ["create", "anlegen"],
      ) { [window] in await window.createRecentEntry() },
      PaletteItem(
        id: "today",
        title: String(localized: "Go to Today", bundle: .module),
        symbol: "calendar.badge.clock",
      ) { [window] in window.showToday() },
      PaletteItem(
        id: "previous",
        title: String(localized: "Previous Day or Week", bundle: .module),
        symbol: "chevron.left",
      ) { [window] in window.step(by: -1) },
      PaletteItem(
        id: "next",
        title: String(localized: "Next Day or Week", bundle: .module),
        symbol: "chevron.right",
      ) { [window] in window.step(by: 1) },
    ]
    for section in window.sections {
      items.append(
        PaletteItem(
          id: "section-\(section.rawValue)",
          title: String(localized: "Show \(section.title)", bundle: .module),
          symbol: section.symbol,
        ) { [window] in window.section = section }
      )
    }
    if window.analytics != nil {
      items.append(
        PaletteItem(
          id: "export-csv",
          title: String(localized: "Export as CSV …", bundle: .module),
          symbol: "square.and.arrow.up",
          keywords: ["export"],
        ) { [weak self] in self?.export?(.csv) }
      )
      items.append(
        PaletteItem(
          id: "export-json",
          title: String(localized: "Export as JSON …", bundle: .module),
          symbol: "square.and.arrow.up",
          keywords: ["export"],
        ) { [weak self] in self?.export?(.json) }
      )
      items.append(
        PaletteItem(
          id: "export-pdf",
          title: String(localized: "Export as PDF Report …", bundle: .module),
          symbol: "doc.richtext",
          keywords: ["export", "report", "bericht"],
        ) { [weak self] in self?.export?(.pdf) }
      )
    }
    if let booking = window.booking {
      items.append(
        PaletteItem(
          id: "book-day",
          title: String(localized: "Book the Day", bundle: .module),
          symbol: "checkmark.seal",
          keywords: ["azure devops", "buchen", "tagesabschluss"],
        ) { [window] in
          if let lines = try? await booking.lines(for: window.dayRange) {
            await booking.book(lines.filter { $0.difference != 0 && $0.inFlight == 0 })
          }
          window.section = .dayClose
        }
      )
    }
    return items
  }

  private func loadHits() {
    hitTask?.cancel()
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else {
      hits = []
      return
    }
    hitTask = Task { [weak self, window] in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      var items = [PaletteItem]()
      if let search = window.search, let found = try? await search.search(text, limit: 8) {
        let ids = found.filter { $0.kind == .entry }.compactMap { EntryID(uuidString: $0.ref) }
        for entry in (try? await window.queries.entries(ids)) ?? [] {
          let date = entry.segments.first?.start.date.formatted(date: .abbreviated, time: .omitted)
          items.append(
            PaletteItem(id: "entry-\(entry.id)", title: entry.entry.title, subtitle: date, symbol: "clock") {
              window.reveal(entry)
            }
          )
        }
      }
      if let source = window.workItems, let found = try? await source.cached(text) {
        for item in found.prefix(5) {
          items.append(
            PaletteItem(
              id: "work-item-\(item.id)",
              title: item.cachedTitle ?? "#\(item.workItemID)",
              subtitle: String(localized: "Start timer for #\(String(item.workItemID))", bundle: .module),
              symbol: "link",
            ) {
              await window.startTimer(for: item)
            }
          )
        }
      }
      guard !Task.isCancelled else { return }
      self?.hits = items
    }
  }
}

// MARK: - CommandPaletteView

/// The palette sheet: search field, results, keyboard only.
struct CommandPaletteView: View {

  // MARK: Internal

  @Bindable var model: CommandPaletteModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "command")
          .foregroundStyle(Palette.textSecondary)
          .accessibilityHidden(true)
        TextField(String(localized: "Type a command or search", bundle: .module), text: $model.query)
          .textFieldStyle(.plain)
          .font(.system(size: 16))
          .focused($focused)
          .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
          }
          .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
          }
          .onKeyPress(.return) {
            Task { await model.runSelected() }
            return .handled
          }
          .onKeyPress(.escape) {
            model.isPresented = false
            return .handled
          }
          .accessibilityLabel(Text("Command palette", bundle: .module))
      }
      .padding(14)
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 2) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
              Button {
                model.selection = index
                Task { await model.runSelected() }
              } label: {
                row(item, selected: index == model.selection)
              }
              .buttonStyle(.plain)
              .id(index)
            }
          }
          .padding(6)
        }
        .onChange(of: model.selection) { proxy.scrollTo(model.selection) }
      }
      .frame(height: 320)
    }
    .frame(width: 520)
    .onAppear { focused = true }
  }

  // MARK: Private

  @FocusState private var focused: Bool

  private func row(_ item: PaletteItem, selected: Bool) -> some View {
    HStack(spacing: 10) {
      Image(systemName: item.symbol)
        .frame(width: 20)
        .foregroundStyle(selected ? Palette.accent : Palette.textSecondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title).lineLimit(1)
        if let subtitle = item.subtitle {
          Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
        }
      }
      Spacer()
      if let shortcut = item.shortcut {
        Text(shortcut).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
      }
    }
    .padding(.horizontal, 10)
    .frame(minHeight: 32)
    .background(selected ? Palette.accentSurface : .clear, in: RoundedRectangle(cornerRadius: 6))
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
