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
  /// The popover shows the effort in the preview below the hits instead.
  var showsProgress = true

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
        if !compact, showsProgress, let progress {
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
    if let iteration = item.iterationName { parts.append(iteration) }
    if let parent = item.parentID { parts.append("↑ #\(parent)") }
    return parts.joined(separator: " · ")
  }

  private var progress: (fraction: Double, label: String)? {
    item.effort
  }
}

extension WorkItemLink {
  /// Completed share of completed plus remaining work, in hours.
  var effort: (fraction: Double, label: String)? {
    let completed = completedWork ?? 0
    let remaining = remainingWork ?? 0
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

  /// The last component of the iteration path, e.g. "Sprint 42".
  var iterationName: String? {
    iterationPath?.split(separator: "\\").last.map(String.init)
  }
}

// MARK: - WorkItemPreview

/// Compact preview below the search hits (DO-12): status, assignee, iteration and effort of the
/// highlighted work item.
struct WorkItemPreview: View {

  // MARK: Internal

  let item: WorkItemLink

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        TypeBadge(type: item.cachedType)
        VStack(alignment: .leading, spacing: 1) {
          Text(item.cachedTitle ?? "")
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(2)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
        }
      }
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
        GridRow {
          field(String(localized: "Status", bundle: .module), item.cachedState)
          field(String(localized: "Assigned to", bundle: .module), item.assignedTo)
        }
        GridRow {
          field(String(localized: "Iteration", bundle: .module), item.iterationName)
          field(String(localized: "Effort", bundle: .module), item.effort?.label)
        }
      }
      if let effort = item.effort {
        ProgressBar(value: effort.fraction)
          .frame(height: 6)
          .accessibilityHidden(true)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.separator))
    .accessibilityElement(children: .combine)
  }

  // MARK: Private

  /// E.g. "Task #4821 · Parent: #4702".
  private var subtitle: String {
    var parts = ["\(item.cachedType ?? "") #\(item.workItemID)".trimmingCharacters(in: .whitespaces)]
    if let parent = item.parentID { parts.append(String(localized: "Parent: #\(String(parent))", bundle: .module)) }
    return parts.joined(separator: " · ")
  }

  private func field(_ title: String, _ value: String?) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).foregroundStyle(Palette.textSecondary)
      Text(value ?? "–").fontWeight(.medium).lineLimit(1)
    }
    .font(.system(size: 12))
    .frame(maxWidth: .infinity, alignment: .leading)
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

  // MARK: Internal

  let type: String?

  var body: some View {
    Text(String((type ?? "?").prefix(1)).uppercased())
      .font(.system(size: 10, weight: .bold))
      // White on the light dark-mode variants was about 1.5:1 (#146).
      .foregroundStyle(CategoryColors.onColor(hex))
      .frame(width: 18, height: 18)
      .background(CategoryColors.color(hex), in: RoundedRectangle(cornerRadius: 4))
      .accessibilityLabel(Text(type ?? ""))
  }

  // MARK: Private

  private var hex: String {
    switch type?.lowercased() {
    case "task", "aufgabe": "#A16207"
    case "bug", "fehler": "#B91C1C"
    case "user story", "product backlog item", "requirement": "#0369A1"
    default: "#475569"
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
