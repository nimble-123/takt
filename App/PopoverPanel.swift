import AppKit
import SwiftUI

/// A borderless panel below the status item that takes keyboard input without activating
/// the app, and closes when it loses key status (click outside, Esc).
final class PopoverPanel: NSPanel {

  // MARK: Lifecycle

  init(rootView: some View) {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: true,
    )
    isFloatingPanel = true
    level = .popUpMenu
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

    let hosting = NSHostingView(
      rootView:
      rootView
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    )
    hosting.sizingOptions = [.preferredContentSize]
    contentView = hosting
  }

  // MARK: Internal

  override var canBecomeKey: Bool {
    true
  }

  override func resignKey() {
    super.resignKey()
    orderOut(nil)
  }

  override func cancelOperation(_: Any?) {
    orderOut(nil)
  }

  /// Keeps the top edge under the status item while the content grows or shrinks.
  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    var frame = frameRect
    if let topEdge {
      frame.origin.y = topEdge - frame.height
    }
    super.setFrame(frame, display: flag)
  }

  /// Shows the panel centred below `button`, kept inside the visible screen area.
  func show(below button: NSStatusBarButton) {
    guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }
    let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let size = contentView?.fittingSize ?? frame.size
    topEdge = anchor.minY - 4
    let x = min(
      max(anchor.midX - size.width / 2, screen.visibleFrame.minX + 8),
      screen.visibleFrame.maxX - size.width - 8,
    )
    setFrame(NSRect(x: x, y: 0, width: size.width, height: size.height), display: true)
    makeKeyAndOrderFront(nil)
  }

  // MARK: Private

  private var topEdge: CGFloat?

}
