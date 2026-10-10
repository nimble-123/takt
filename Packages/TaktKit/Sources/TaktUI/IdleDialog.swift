import SwiftUI
import TaktCore

// MARK: - IdleDialog

/// "Inaktivität erkannt": mini timeline with hatched inactivity and four choices,
/// "count as pause" preselected (docs/DESIGN.md).
struct IdleDialog: View {

  // MARK: Internal

  enum Choice: Hashable, CaseIterable {
    case pause
    case keep
    case discard
    case reassign
  }

  let model: MenuBarModel
  let event: IdleEvent

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: "moon.zzz.fill")
          .foregroundStyle(Palette.warning)
          .accessibilityHidden(true)
        Text("You were away for \(DurationText.span(duration))", bundle: .module)
          .font(.system(size: 13, weight: .semibold))
      }
      Text(intro)
        .font(.system(size: 12))
        .foregroundStyle(Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      IdleTimeline(event: event)
        .frame(height: 10)
      IdleTimeLabels(event: event)

      VStack(alignment: .leading, spacing: 4) {
        ForEach(Choice.allCases, id: \.self) { option in
          optionRow(option)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text("Handle inactivity", bundle: .module))

      Toggle(isOn: Bindable(model.settings).lockCountsAsPause) {
        Text("Count a screen lock as a pause from now on", bundle: .module)
          .font(.system(size: 12))
          .foregroundStyle(Palette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .toggleStyle(.checkbox)
      .disabled(model.settings.isLocked(.lockCountsAsPause))

      HStack {
        Spacer()
        Button {
          model.postponeIdle()
        } label: {
          Text("Later", bundle: .module)
            .padding(.horizontal, 6)
        }
        .keyboardShortcut(.cancelAction)
        Button {
          Task { await model.resolveIdle(decision) }
        } label: {
          Text("Apply", bundle: .module)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.accent)
        .keyboardShortcut(.defaultAction)
        .disabled(choice == .reassign && reassignTitle.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(10)
    .background(Palette.warningSurface, in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: Private

  @State private var choice = Choice.pause
  @State private var reassignTitle = ""

  private var duration: TimeInterval {
    event.end.seconds(since: event.start)
  }

  /// "From 13:41 to 14:04 “Login-Flow” ran without input. How should the time count?"
  private var intro: String {
    let format = Date.FormatStyle.dateTime.hour().minute()
    let titles = model.snapshot.entries
      .filter { event.entryIDs.contains($0.id) }
      .map { "„\($0.entry.title)“" }
      .formatted(.list(type: .and))
    let from = event.start.date.formatted(format)
    let to = event.end.date.formatted(format)
    return titles.isEmpty
      ? String(localized: "From \(from) to \(to) there was no input. How should the time count?", bundle: .module)
      : String(localized: "From \(from) to \(to) \(titles) ran without input. How should the time count?", bundle: .module)
  }

  private var decision: IdleDecision {
    switch choice {
    case .keep: .keep
    case .pause: .pause
    case .discard: .discard
    case .reassign: .reassign(EntryDraft(title: reassignTitle.trimmingCharacters(in: .whitespaces)))
    }
  }

  private func title(_ option: Choice) -> Text {
    switch option {
    case .pause: Text("Count as pause", bundle: .module)
    case .keep: Text("Keep as work time", bundle: .module)
    case .discard: Text("Discard", bundle: .module)
    case .reassign: Text("Assign to another task", bundle: .module)
    }
  }

  /// What the option does, as the engine applies it (TM-06).
  private func explanation(_ option: Choice) -> String {
    let span = DurationText.span(duration)
    let end = event.end.date.formatted(.dateTime.hour().minute())
    return switch option {
    case .pause: String(localized: "The \(span) do not count, the timer stays paused", bundle: .module)
    case .keep: String(localized: "I worked on it anyway, e.g. at the whiteboard", bundle: .module)
    case .discard: String(localized: "The \(span) do not count, the timer continues from \(end)", bundle: .module)
    case .reassign: String(localized: "The \(span) go to another task, the timer continues", bundle: .module)
    }
  }

  private func optionRow(_ option: Choice) -> some View {
    let selected = choice == option
    return VStack(alignment: .leading, spacing: 6) {
      Button {
        choice = option
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Image(systemName: selected ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(selected ? Palette.accent : Palette.textSecondary)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
              title(option).fontWeight(.semibold)
              if option == .pause {
                Text("· recommended", bundle: .module).foregroundStyle(Palette.accentText)
              }
            }
            Text(explanation(option))
              .font(.system(size: 11))
              .foregroundStyle(Palette.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(selected ? [.isSelected] : [])
      if option == .reassign, selected {
        TextField(String(localized: "Task", bundle: .module), text: $reassignTitle)
          .textFieldStyle(.roundedBorder)
          .padding(.leading, 22)
          .onAppear {
            if reassignTitle.isEmpty { reassignTitle = model.recents.first?.title ?? "" }
          }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(selected ? Palette.accentSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(selected ? Palette.accent : Palette.separator, lineWidth: selected ? 1.5 : 1)
    }
  }
}

// MARK: - IdleTimeLabels

/// Times below the mini timeline: start of the shown work, start of the inactivity, its end.
struct IdleTimeLabels: View {
  let event: IdleEvent

  var body: some View {
    let idle = event.end.seconds(since: event.start)
    let before = IdleTimeline.shownBefore(idle)
    let format = Date.FormatStyle.dateTime.hour().minute()
    GeometryReader { proxy in
      let split = proxy.size.width * before / (before + idle)
      ZStack(alignment: .topLeading) {
        Text(event.start.adding(seconds: -before).date, format: format)
        Text(event.start.date, format: format)
          .fixedSize()
          .alignmentGuide(.leading) { $0.width / 2 - split }
        Text(event.end.date, format: format)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .font(.system(size: 11, design: .monospaced))
    .foregroundStyle(Palette.textSecondary)
    .frame(height: 14)
    .accessibilityHidden(true)
  }
}

// MARK: - IdleTimeline

/// Tracked time before the inactivity, then the inactivity hatched in amber.
struct IdleTimeline: View {
  let event: IdleEvent

  var body: some View {
    Canvas { context, size in
      let idle = event.end.seconds(since: event.start)
      let before = Self.shownBefore(idle)
      let split = size.width * before / (before + idle)
      let bar = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
      context.clip(to: bar)
      context.fill(Path(CGRect(x: 0, y: 0, width: split, height: size.height)), with: .color(Palette.accent))
      let idleRect = CGRect(x: split, y: 0, width: size.width - split, height: size.height)
      context.fill(Path(idleRect), with: .color(Palette.warningSurface))
      var hatch = Path()
      var x = split - size.height
      while x < size.width {
        hatch.move(to: CGPoint(x: x, y: size.height))
        hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
        x += 5
      }
      context.clip(to: Path(idleRect))
      context.stroke(hatch, with: .color(Palette.warning), lineWidth: 1.5)
    }
    .accessibilityHidden(true)
  }

  /// Shows at least as much tracked time before as the inactivity lasted, capped at 1 h.
  static func shownBefore(_ idle: TimeInterval) -> TimeInterval {
    min(max(idle, 15 * 60), 3600)
  }

}
