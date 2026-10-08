import AppKit
import SwiftUI
import TaktCore
import TaktStore

// MARK: - DayTimeline

/// Vertical timeline of one day with parallel lanes (HW-01). Interactive: draw a new entry on
/// empty space, drag a block to move it, drag its edges to change start or end (HW-02).
struct DayTimeline: View {

  // MARK: Internal

  static let snap: TimeInterval = 5 * 60

  let model: MainWindowModel
  let day: Range<Timestamp>
  var interactive = true
  var hourHeight: CGFloat = 56
  var gutter: CGFloat = 52

  var body: some View {
    TimelineView(.everyMinute) { context in
      let now = Timestamp(context.date)
      let layout = TimelineLayout(entries: model.data.entries, day: day, now: now)
      GeometryReader { proxy in
        let width = max(0, proxy.size.width - gutter)
        ZStack(alignment: .topLeading) {
          hourGrid(width: proxy.size.width)
          idleBands(width: width, now: now)
          if interactive {
            Color.clear
              .contentShape(Rectangle())
              .frame(width: width, height: height(dayLength))
              .offset(x: gutter)
              .gesture(createGesture)
              .onTapGesture { model.selection = [] }
          }
          ForEach(layout.items) { item in
            block(item, width: width, now: now)
          }
          if day.contains(now) {
            nowLine(at: now, width: proxy.size.width)
          }
          dragPreview(width: width)
        }
      }
      .frame(height: height(dayLength))
    }
    .coordinateSpace(.named(Self.space))
  }

  static func snapped(_ time: Timestamp) -> Timestamp {
    let step = Int64(snap * 1000)
    return Timestamp(milliseconds: (time.milliseconds + step / 2) / step * step)
  }

  // MARK: Private

  private enum Drag: Equatable {
    case create(from: Timestamp, to: Timestamp)
    case move(Segment, by: TimeInterval)
    case resize(Segment, start: Timestamp, end: Timestamp?)
  }

  private static let space = "timeline"

  /// A second `onTapGesture(count: 2)` would delay every single click; the click count of the event does not.
  private static var isDoubleClick: Bool {
    NSApp.currentEvent?.clickCount == 2
  }

  @State private var drag: Drag?

  private var dayLength: TimeInterval {
    day.upperBound.seconds(since: day.lowerBound)
  }

  private var createGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
      .onChanged { value in
        let a = time(atY: value.startLocation.y)
        let b = time(atY: value.location.y)
        drag = .create(from: min(a, b), to: max(a, b))
      }
      .onEnded { _ in
        guard case .create(let from, let to) = drag else { return }
        drag = nil
        guard to.seconds(since: from) >= Self.snap else { return }
        Task { await model.createEntry(from: from, to: min(to, model.now)) }
      }
  }

  private var previewRange: (start: Timestamp, end: Timestamp)? {
    switch drag {
    case .create(let from, let to):
      (from, to)
    case .move(let segment, let delta):
      segment.end.map { (segment.start.adding(seconds: delta), $0.adding(seconds: delta)) }
    case .resize(_, let start, let end):
      (start, end ?? model.now)
    case nil:
      nil
    }
  }

  private func height(_ seconds: TimeInterval) -> CGFloat {
    CGFloat(seconds / 3600) * hourHeight
  }

  private func y(_ time: Timestamp) -> CGFloat {
    height(time.seconds(since: day.lowerBound))
  }

  private func time(atY y: CGFloat) -> Timestamp {
    let seconds = TimeInterval(y / hourHeight) * 3600
    return Self.snapped(day.lowerBound.adding(seconds: min(max(0, seconds), dayLength)))
  }

  /// Real rows (not offsets), so `ScrollViewReader.scrollTo(hour)` finds them.
  private func hourGrid(width: CGFloat) -> some View {
    VStack(spacing: 0) {
      ForEach(0..<Int((dayLength / 3600).rounded(.up)), id: \.self) { hour in
        let time = day.lowerBound.adding(seconds: TimeInterval(hour) * 3600)
        HStack(alignment: .top, spacing: 6) {
          if gutter > 0 {
            Text(time.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
              .font(.system(size: 10))
              .monospacedDigit()
              .foregroundStyle(Palette.textSecondary)
              .fixedSize()
              .frame(width: gutter - 6, alignment: .trailing)
              .offset(y: -6)
          }
          Rectangle()
            .fill(Palette.separator)
            .frame(height: 1)
        }
        .frame(width: width, height: hourHeight, alignment: .topLeading)
        .id(hour)
      }
    }
    .frame(height: height(dayLength), alignment: .top)
  }

  private func idleBands(width: CGFloat, now _: Timestamp) -> some View {
    ForEach(model.data.idleEvents) { event in
      let start = max(event.start, day.lowerBound)
      let end = min(event.end, day.upperBound)
      if end > start {
        Hatched(color: Palette.warning, background: Palette.warningSurface.opacity(0.6))
          .frame(width: width, height: height(end.seconds(since: start)))
          .offset(x: gutter, y: y(start))
          .accessibilityLabel(Text("Inactivity", bundle: .module))
      }
    }
  }

  private func nowLine(at now: Timestamp, width: CGFloat) -> some View {
    HStack(spacing: 0) {
      Circle().fill(Palette.danger).frame(width: 7, height: 7)
      Rectangle().fill(Palette.danger).frame(height: 1.5)
    }
    .frame(width: width - gutter + 4)
    .offset(x: gutter - 4, y: y(now) - 3.5)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func block(_ item: TimelineLayout.Item, width: CGFloat, now _: Timestamp) -> some View {
    let laneWidth = width / CGFloat(item.laneCount)
    let frame = CGRect(
      x: gutter + CGFloat(item.lane) * laneWidth + 2,
      y: y(item.start),
      width: max(4, laneWidth - 4),
      height: max(3, height(item.end.seconds(since: item.start))),
    )
    let entry = model.entry(item.entryID)
    let selected = model.selection.contains(item.entryID)
    switch item.kind {
    case .pause:
      Hatched(color: Palette.warning.opacity(0.7), background: .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .onTapGesture {
          if Self.isDoubleClick {
            model.openInspector(for: item.entryID)
          } else {
            model.selection = [item.entryID]
          }
        }
        .accessibilityLabel(Text("Pause", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.selection = [item.entryID] }
        .accessibilityAction(named: Text("Open in Inspector", bundle: .module)) {
          model.openInspector(for: item.entryID)
        }

    case .segment(let segment):
      let running = segment.isOpen
      BlockView(
        title: entry?.entry.title ?? "",
        colorHex: entry.flatMap { model.colorHex(of: $0.entry) },
        start: item.start,
        end: item.end,
        running: running,
        selected: selected,
        compact: !interactive,
      )
      .frame(width: frame.width, height: frame.height)
      .opacity(isDragging(segment) ? 0.35 : 1)
      .overlay(alignment: .top) {
        if interactive { edgeHandle(segment, edge: .top) }
      }
      .overlay(alignment: .bottom) {
        if interactive, !running { edgeHandle(segment, edge: .bottom) }
      }
      .offset(x: frame.minX, y: frame.minY)
      .onTapGesture { select(item.entryID) }
      .gesture(interactive && !running ? moveGesture(segment) : nil)
      // Opening needs a double-click, so VoiceOver gets it as a named action (#110).
      .accessibilityAction { model.selection = [item.entryID] }
      .accessibilityAction(named: Text("Open in Inspector", bundle: .module)) {
        model.openInspector(for: item.entryID)
      }
    }
  }

  private func select(_ id: EntryID) {
    if Self.isDoubleClick {
      model.openInspector(for: id)
    } else if NSEvent.modifierFlags.contains(.command) {
      model.selection.formSymmetricDifference([id])
    } else {
      model.selection = [id]
    }
  }

  private func isDragging(_ segment: Segment) -> Bool {
    switch drag {
    case .move(let dragged, _), .resize(let dragged, _, _): dragged.id == segment.id
    default: false
    }
  }

  private func edgeHandle(_ segment: Segment, edge: VerticalEdge) -> some View {
    Color.clear
      .frame(height: 6)
      .contentShape(Rectangle())
      .onHover { inside in
        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
      }
      .gesture(resizeGesture(segment, edge: edge))
  }

  private func moveGesture(_ segment: Segment) -> some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
      .onChanged { value in
        let seconds = TimeInterval(value.translation.height / hourHeight) * 3600
        let snappedStart = Self.snapped(segment.start.adding(seconds: seconds))
        drag = .move(segment, by: snappedStart.seconds(since: segment.start))
      }
      .onEnded { _ in
        guard case .move(let segment, let delta) = drag else { return }
        drag = nil
        guard delta != 0 else { return }
        Task { await model.move(segment, by: delta) }
      }
  }

  private func resizeGesture(_ segment: Segment, edge: VerticalEdge) -> some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
      .onChanged { value in
        let time = time(atY: value.location.y)
        drag =
          edge == .top
            ? .resize(segment, start: time, end: segment.end)
            : .resize(segment, start: segment.start, end: time)
      }
      .onEnded { _ in
        guard case .resize(let segment, let start, let end) = drag else { return }
        drag = nil
        Task { await model.setBounds(of: segment, start: start, end: end) }
      }
  }

  @ViewBuilder
  private func dragPreview(width: CGFloat) -> some View {
    if let range = previewRange {
      let top = y(range.start)
      let blockHeight = max(3, height(range.end.seconds(since: range.start)))
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        .background(Palette.accentSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .frame(width: width - 4, height: blockHeight)
        .offset(x: gutter + 2, y: top)
        .allowsHitTesting(false)
      Text(
        "\(range.start.date, format: .dateTime.hour().minute()) – \(range.end.date, format: .dateTime.hour().minute())"
      )
      .font(.system(size: 11, weight: .semibold))
      .monospacedDigit()
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(.thickMaterial, in: Capsule())
      .offset(x: gutter + 8, y: max(0, top - 24))
      .allowsHitTesting(false)
    }
  }

}

// MARK: - BlockView

/// One segment in the timeline.
struct BlockView: View {

  // MARK: Internal

  let title: String
  let colorHex: String?
  let start: Timestamp
  let end: Timestamp
  let running: Bool
  let selected: Bool
  var compact = false

  var body: some View {
    let tall = end.seconds(since: start) >= 25 * 60
    HStack(spacing: 0) {
      Rectangle()
        .fill(tint)
        .frame(width: 3)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: compact ? 10 : 12, weight: .semibold))
          .lineLimit(tall ? 2 : 1)
        if tall, !compact {
          Text(
            "\(start.date, format: .dateTime.hour().minute()) – \(end.date, format: .dateTime.hour().minute())"
          )
          .font(.system(size: 11))
          .monospacedDigit()
          .foregroundStyle(Palette.textSecondary)
        }
      }
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      Spacer(minLength: 0)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .background(running ? surface : surface.opacity(0.75))
    .clipShape(RoundedRectangle(cornerRadius: 5))
    .overlay(
      RoundedRectangle(cornerRadius: 5)
        .strokeBorder(selected ? tint : Palette.separator, lineWidth: selected ? 2 : 0.5)
    )
    .contentShape(Rectangle())
    // One element with the time, also when the block is too small or compact to show it (#110).
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }

  // MARK: Private

  private var accessibilityText: String {
    let style = Date.FormatStyle.dateTime.hour().minute()
    let range = "\(start.date.formatted(style)) – \(end.date.formatted(style))"
    let state = running ? [String(localized: "running", bundle: .module)] : []
    return ([title, range] + state).joined(separator: ", ")
  }

  private var tint: Color {
    colorHex.map(CategoryColors.color) ?? Palette.accent
  }

  private var surface: Color {
    colorHex.map(CategoryColors.surface) ?? Palette.accentSurface
  }
}

// MARK: - Hatched

/// Diagonal stripes for pauses and inactivity – never an empty gap (docs/DESIGN.md).
struct Hatched: View {
  let color: Color
  let background: Color

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
      var path = Path()
      var x: CGFloat = -size.height
      while x < size.width {
        path.move(to: CGPoint(x: x, y: size.height))
        path.addLine(to: CGPoint(x: x + size.height, y: 0))
        x += 6
      }
      context.stroke(path, with: .color(color), lineWidth: 1)
    }
  }
}
