import SwiftUI
import TaktCore

// MARK: - WorkItemRow

/// Compact preview of a work item (DO-12): type badge, ID, title with the search hit in bold,
/// state, assignee, iteration, parent and completed against remaining work.
struct WorkItemRow: View {

  // MARK: Internal

  let item: WorkItemLink
  let query: String
  let selected: Bool
  var compact = false

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      TypeBadge(type: item.cachedType)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(verbatim: "#\(item.workItemID)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.textSecondary)
          Text(highlighted)
            .font(.system(size: 13))
            .lineLimit(1)
          Spacer(minLength: 4)
          if let state = item.cachedState {
            Text(state)
              .font(.system(size: 11))
              .foregroundStyle(Palette.textSecondary)
          }
        }
        if !compact, !details.isEmpty {
          Text(details)
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
        }
        if !compact, let progress {
          HStack(spacing: 6) {
            ProgressBar(value: progress.fraction)
              .frame(width: 80, height: 4)
            Text(progress.label)
              .font(.system(size: 11))
              .monospacedDigit()
              .foregroundStyle(Palette.textSecondary)
          }
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, compact ? 3 : 5)
    .background(selected ? Palette.accentSurface : .clear, in: RoundedRectangle(cornerRadius: 6))
    // The compact row is shorter than the minimum hit target; enlarge only the clickable area.
    .frame(minHeight: compact ? 28 : nil)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  // MARK: Private

  private var highlighted: AttributedString {
    var title = AttributedString(item.cachedTitle ?? "")
    let text = query.trimmingCharacters(in: .whitespaces)
    if !text.isEmpty, let range = title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) {
      title[range].font = .system(size: 13, weight: .bold)
    }
    return title
  }

  private var details: String {
    var parts = [String]()
    if let assignee = item.assignedTo { parts.append(assignee) }
    if let iteration = item.iterationPath?.split(separator: "\\").last { parts.append(String(iteration)) }
    if let parent = item.parentID { parts.append("↑ #\(parent)") }
    return parts.joined(separator: " · ")
  }

  /// Completed share of completed plus remaining work, in hours.
  private var progress: (fraction: Double, label: String)? {
    let completed = item.completedWork ?? 0
    let remaining = item.remainingWork ?? 0
    guard completed + remaining > 0 else { return nil }
    let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
    return (
      completed / (completed + remaining),
      String(
        localized: "\(completed.formatted(format)) h done · \(remaining.formatted(format)) h left",
        bundle: .module,
      ),
    )
  }
}

// MARK: - WorkItemDetail

/// Description excerpt and tags (DO-13, Space).
struct WorkItemDetail: View {
  let item: WorkItemLink

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(item.descriptionExcerpt ?? String(localized: "No description.", bundle: .module))
        .font(.system(size: 12))
        .foregroundStyle(item.descriptionExcerpt == nil ? Palette.textSecondary : Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      if !item.tags.isEmpty {
        HStack(spacing: 4) {
          ForEach(item.tags, id: \.self) { tag in
            Text(tag)
              .font(.system(size: 11))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Palette.separator, in: Capsule())
          }
        }
      }
      Text("⌘↩ opens it in Azure DevOps", bundle: .module)
        .font(.system(size: 11))
        .foregroundStyle(Palette.textSecondary)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    .padding(.leading, 34)
  }
}

// MARK: - TypeBadge

/// Letter badge in the type's color (docs/DESIGN.md "Work-Item-Typen").
struct TypeBadge: View {
  let type: String?

  var body: some View {
    Text(String((type ?? "?").prefix(1)).uppercased())
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 18, height: 18)
      .background(color, in: RoundedRectangle(cornerRadius: 4))
      .accessibilityLabel(Text(type ?? ""))
  }

  private var color: Color {
    switch type?.lowercased() {
    case "task", "aufgabe": CategoryColors.color("#A16207")
    case "bug", "fehler": CategoryColors.color("#B91C1C")
    case "user story", "product backlog item", "requirement": CategoryColors.color("#0369A1")
    default: CategoryColors.color("#475569")
    }
  }
}

// MARK: - ProgressBar

struct ProgressBar: View {
  let value: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Palette.separator)
        Capsule().fill(Palette.accent).frame(width: proxy.size.width * min(1, max(0, value)))
      }
    }
  }
}
