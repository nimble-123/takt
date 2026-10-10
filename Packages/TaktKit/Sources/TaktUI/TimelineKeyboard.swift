import SwiftUI
import TaktCore

// MARK: - TimelineKeyboard

/// The timeline by keyboard (#171): ↑/↓ moves between blocks and selects, ⇧↑/⇧↓ extends the
/// selection, ↩ or Space opens the inspector, ⌥↑/⌥↓ moves the block by 5 min, ←/→ changes the
/// day in the week. ⌫ deletes through the window's delete command. The focused block stays in
/// view and VoiceOver announces it.
struct TimelineKeyboard: ViewModifier {

  // MARK: Internal

  let model: MainWindowModel
  /// The shown day, or the days of the week.
  let days: [Range<Timestamp>]
  let proxy: ScrollViewProxy

  func body(content: Content) -> some View {
    content
      .focusable()
      .focused($isFocused)
      .focusEffectDisabled()
      // macOS tabs into custom views only with "Keyboard navigation" on, so the timeline takes the
      // focus when it appears and on every click into it; the search field still takes it on ⌘F.
      .onAppear { isFocused = true }
      .simultaneousGesture(TapGesture().onEnded { isFocused = true })
      .onKeyPress(phases: .down) { press in
        handle(press) ? .handled : .ignored
      }
      .onChange(of: model.timelineFocus) {
        guard let item = model.focusedTimelineItem, let day = model.timelineFocus?.day else { return }
        withAnimation(.snappy(duration: 0.2)) {
          proxy.scrollTo(Int(item.start.seconds(since: day.lowerBound) / 3600), anchor: .center)
        }
        announce(item)
      }
      // A click elsewhere in the window ends the keyboard focus; the next arrow starts again.
      .onChange(of: isFocused) { _, focused in
        if !focused { model.timelineFocus = nil }
      }
  }

  // MARK: Private

  @FocusState private var isFocused: Bool

  private func handle(_ press: KeyPress) -> Bool {
    let shift = press.modifiers.contains(.shift)
    let option = press.modifiers.contains(.option)
    switch press.key {
    case .downArrow where option:
      Task { await model.moveFocusedBlock(by: DayTimeline.snap) }
      return true

    case .upArrow where option:
      Task { await model.moveFocusedBlock(by: -DayTimeline.snap) }
      return true

    case .downArrow:
      return model.moveTimelineFocus(.next, extend: shift, days: days)

    case .upArrow:
      return model.moveTimelineFocus(.previous, extend: shift, days: days)

    case .leftArrow where days.count > 1:
      return model.moveTimelineFocus(days: -1, in: days)

    case .rightArrow where days.count > 1:
      return model.moveTimelineFocus(days: 1, in: days)

    case .return, .space:
      guard model.focusedTimelineItem != nil else { return false }
      model.openFocusedInInspector()
      return true

    default:
      return false
    }
  }

  private func announce(_ item: TimelineLayout.Item) {
    let style = Date.FormatStyle.dateTime.hour().minute()
    let title = model.entry(item.entryID)?.entry.title ?? ""
    AccessibilityNotification.Announcement(
      "\(title), \(item.start.date.formatted(style)) – \(item.end.date.formatted(style))"
    ).post()
  }
}
