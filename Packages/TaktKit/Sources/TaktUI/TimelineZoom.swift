import SwiftUI

// MARK: - TimelineZoom

/// Hour heights of the timelines in Today and Week (#245): ⌘+ and ⌘− go through the steps, a
/// pinch may stop anywhere between the first and the last.
nonisolated enum TimelineZoom {

  static let steps: [Double] = [24, 32, 40, 56, 80, 120, 160]

  static var range: ClosedRange<Double> {
    (steps.first ?? 24)...(steps.last ?? 160)
  }

  static func standard(for section: MainWindowModel.Section) -> Double {
    section == .week ? 40 : 56
  }

  /// The next step up (positive `steps`) or down from `height`, which need not be a step itself.
  static func step(_ height: Double, by count: Int) -> Double {
    var result = clamped(height)
    for _ in 0..<abs(count) {
      result = count > 0
        ? steps.first { $0 > result + 0.5 } ?? result
        : steps.last { $0 < result - 0.5 } ?? result
    }
    return result
  }

  static func clamped(_ height: Double) -> Double {
    min(max(height, range.lowerBound), range.upperBound)
  }
}

// MARK: - ZoomableTimeline

/// Pinch to zoom the timeline in a scroll view (#245). The time under the fingers stays in place,
/// for ⌘+ and ⌘− the time in the middle.
struct ZoomableTimeline: ViewModifier {

  // MARK: Internal

  let model: MainWindowModel
  /// Space above the first hour inside the scroll content.
  var inset: CGFloat = 12

  func body(content: Content) -> some View {
    content
      .scrollPosition($position)
      .onScrollGeometryChange(for: CGRect.self, of: \.visibleRect) { _, rect in visible = rect }
      .simultaneousGesture(
        MagnifyGesture()
          .onChanged { value in
            let start = pinchStart ?? model.hourHeight(in: model.section)
            pinchStart = start
            anchor = value.startLocation.y
            model.setHourHeight(start * value.magnification)
          }
          .onEnded { _ in
            pinchStart = nil
            anchor = nil
          }
      )
      .onChange(of: model.hourHeight(in: model.section)) { old, new in
        keepAnchor(from: old, to: new)
      }
  }

  // MARK: Private

  @State private var position = ScrollPosition()
  @State private var visible = CGRect.zero
  @State private var pinchStart: Double?
  /// Where the pinch started, from the top of the visible area.
  @State private var anchor: CGFloat?

  private func keepAnchor(from old: Double, to new: Double) {
    guard old > 0, visible.height > 0 else { return }
    let anchorY = anchor ?? visible.height / 2
    let timelineY = visible.minY + anchorY - inset
    position.scrollTo(y: max(0, timelineY * new / old + inset - anchorY))
  }
}
