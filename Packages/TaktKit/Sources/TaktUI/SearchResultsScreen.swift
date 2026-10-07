import AppKit
import SwiftUI
import TaktADO
import TaktCore
import TaktStore

/// Results of the window's search field (HW-06): matching entries as a filtered list, then
/// projects, tasks, categories, tags and work items.
struct SearchResultsScreen: View {
    let model: MainWindowModel

    var body: some View {
        let results = model.searchResults
        List {
            if results.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
            if !results.entries.isEmpty {
                Section(String(localized: "Entries", bundle: .module)) {
                    ForEach(results.entries) { hit in
                        Button {
                            model.reveal(hit.entry)
                        } label: {
                            EntryHitRow(hit: hit, now: model.now)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ForEach(groups, id: \.kind) { group in
                Section(group.kind.title) {
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
                                        Text(highlighted(snippet))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var groups: [(kind: SearchHit.Kind, hits: [SearchHit])] {
        let order: [SearchHit.Kind] = [.workItem, .project, .task, .category, .tag]
        let grouped = Dictionary(grouping: model.searchResults.others, by: \.kind)
        return order.compactMap { kind in grouped[kind].map { (kind, $0) } }
    }

    private func open(_ hit: SearchHit) {
        switch hit.kind {
        case .workItem:
            Task {
                guard let id = WorkItemLinkID(uuidString: hit.ref) else { return }
                var link = model.workItemLinks[id]
                if link == nil { link = try? await model.queries.workItemLinks()[id] }
                if let link { NSWorkspace.shared.open(ADOClient.webURL(of: link)) }
            }
        default:
            model.searchText = ""
            model.section = .projects
        }
    }
}

private struct EntryHitRow: View {
    let hit: MainWindowModel.EntryHit
    let now: Timestamp

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(
                hit.entry.segments.first?.start.date ?? now.date,
                format: .dateTime.weekday(.abbreviated).day().month().year()
            )
            .monospacedDigit()
            .foregroundStyle(Palette.textSecondary)
            .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.entry.entry.title)
                if let snippet = hit.snippet {
                    Text(highlighted(snippet))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(DurationText.hoursMinutes(hit.entry.duration(at: now)))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

/// `**hit**` from the index becomes bold.
func highlighted(_ snippet: String) -> AttributedString {
    var result = AttributedString()
    for (index, part) in snippet.components(separatedBy: "**").enumerated() {
        var piece = AttributedString(part)
        if index % 2 == 1 { piece.inlinePresentationIntent = .stronglyEmphasized }
        result += piece
    }
    return result
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
