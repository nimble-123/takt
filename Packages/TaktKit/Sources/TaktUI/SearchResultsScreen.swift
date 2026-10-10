import AppKit
import SwiftUI
import TaktADO
import TaktCore
import TaktStore

// MARK: - SearchResultsScreen

/// Results of the window's search field (HW-06): matching entries as a filtered list, then
/// projects, tasks, categories, tags and work items.
struct SearchResultsScreen: View {

  // MARK: Internal

  let model: MainWindowModel

  var body: some View {
    let results = model.searchResults
    // A plain stack instead of `List`: the list measured the two-line work item rows as one
    // line and clipped their details (as in the day close, #78).
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if results.isEmpty {
          ContentUnavailableView.search(text: model.searchText)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
        if !results.entries.isEmpty {
          ResultSection(title: String(localized: "Entries", bundle: .module)) {
            ForEach(results.entries) { hit in
              Button {
                model.reveal(hit.entry)
              } label: {
                EntryHitRow(hit: hit, now: model.now)
              }
              .buttonStyle(.plain)
              Divider()
            }
          }
        }
        if !results.workItems.isEmpty {
          ResultSection(title: SearchHit.Kind.workItem.title) {
            ForEach(results.workItems) { item in
              Button {
                NSWorkspace.shared.open(ADOClient.webURL(of: item))
              } label: {
                WorkItemRow(item: item, query: model.searchText, selected: false, showsProgress: false, showsProject: true)
              }
              .buttonStyle(.plain)
              .help(Text("Open in Azure DevOps", bundle: .module))
              Divider()
            }
          }
        }
        ForEach(groups, id: \.kind) { group in
          ResultSection(title: group.kind.title) {
            ForEach(group.hits) { hit in
              Button {
                open(hit)
              } label: {
                HStack {
                  Image(systemName: group.kind.symbol)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 18)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                    if let snippet = hit.snippet {
                      Text(Self.highlighted(snippet))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    }
                  }
                  Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              Divider()
            }
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Fileprivate

  /// `**hit**` from the index becomes bold.
  fileprivate static func highlighted(_ snippet: String) -> AttributedString {
    var result = AttributedString()
    for (index, part) in snippet.components(separatedBy: "**").enumerated() {
      var piece = AttributedString(part)
      if index % 2 == 1 { piece.inlinePresentationIntent = .stronglyEmphasized }
      result += piece
    }
    return result
  }

  // MARK: Private

  private var groups: [(kind: SearchHit.Kind, hits: [SearchHit])] {
    let order: [SearchHit.Kind] = [.project, .task, .category, .tag]
    let grouped = Dictionary(grouping: model.searchResults.others, by: \.kind)
    return order.compactMap { kind in grouped[kind].map { (kind, $0) } }
  }

  private func open(_: SearchHit) {
    // Work items have their own section with the full row.
    model.searchText = ""
    model.section = .projects
  }
}

// MARK: - ResultSection

/// A group of hits with a small header, like a list section.
private struct ResultSection<Rows: View>: View {
  let title: String
  @ViewBuilder let rows: Rows

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Palette.textSecondary)
        .padding(.bottom, 6)
      Divider()
      rows
    }
  }
}

// MARK: - EntryHitRow

private struct EntryHitRow: View {
  let hit: MainWindowModel.EntryHit
  let now: Timestamp

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(
        hit.entry.segments.first?.start.date ?? now.date,
        format: .dateTime.weekday(.abbreviated).day().month().year(),
      )
      .monospacedDigit()
      .foregroundStyle(Palette.textSecondary)
      .frame(width: 110, alignment: .leading)
      VStack(alignment: .leading, spacing: 2) {
        Text(hit.entry.entry.title)
        if let snippet = hit.snippet {
          Text(SearchResultsScreen.highlighted(snippet))
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(2)
        }
      }
      Spacer()
      Text(DurationText.hoursMinutes(hit.entry.duration(at: now)))
        .monospacedDigit()
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
  }
}

extension SearchHit.Kind {
  var title: String {
    switch self {
    case .entry: String(localized: "Entries", bundle: .module)
    case .project: String(localized: "Projects", bundle: .module)
    case .task: String(localized: "Tasks", bundle: .module)
    case .category: String(localized: "Categories", bundle: .module)
    case .tag: String(localized: "Tags", bundle: .module)
    case .workItem: String(localized: "Work items", bundle: .module)
    }
  }

  var symbol: String {
    switch self {
    case .entry: "clock"
    case .project: "folder"
    case .task: "checklist"
    case .category: "tag"
    case .tag: "number"
    case .workItem: "link"
    }
  }
}
