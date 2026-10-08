import AppKit
import SwiftUI
import Synchronization

// MARK: - CategoryColors

/// Colors for projects and categories. A stored hex picks a light/dark pair from this palette;
/// unknown hex values are used as they are (ST-02, docs/DESIGN.md "Kategorien").
public enum CategoryColors {

  // MARK: Public

  public struct Swatch: Hashable, Sendable {
    public var hex: String

    var dark: String
    var surfaceLight: String
    var surfaceDark: String
  }

  /// The first four are the default categories from the design.
  public static let swatches: [Swatch] = [
    Swatch(hex: "#2563EB", dark: "#60A5FA", surfaceLight: "#DBEAFE", surfaceDark: "#1E2B4D"),
    Swatch(hex: "#C2410C", dark: "#FB923C", surfaceLight: "#FFEDD5", surfaceDark: "#41281A"),
    Swatch(hex: "#7C3AED", dark: "#A78BFA", surfaceLight: "#EDE9FE", surfaceDark: "#2E2650"),
    Swatch(hex: "#DB2777", dark: "#F472B6", surfaceLight: "#FCE7F3", surfaceDark: "#4A1D35"),
    Swatch(hex: "#0F766E", dark: "#2DD4BF", surfaceLight: "#E8F4F2", surfaceDark: "#12332F"),
    Swatch(hex: "#15803D", dark: "#4ADE80", surfaceLight: "#DCFCE7", surfaceDark: "#14361F"),
    Swatch(hex: "#A16207", dark: "#FACC15", surfaceLight: "#FEF9C3", surfaceDark: "#3D3410"),
    Swatch(hex: "#475569", dark: "#94A3B8", surfaceLight: "#E2E8F0", surfaceDark: "#262D38"),
  ]

  /// Stroke and text color.
  public static func color(_ hex: String) -> Color {
    if let cached = colors.withLock({ $0[hex] }) { return cached }
    let swatch = swatches.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    let color = dynamic(light: hex, dark: swatch?.dark ?? hex)
    colors.withLock { $0[hex] = color }
    return color
  }

  /// Fill of timeline blocks.
  public static func surface(_ hex: String) -> Color {
    if let cached = surfaces.withLock({ $0[hex] }) { return cached }
    let surface =
      if let swatch = swatches.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }) {
        dynamic(light: swatch.surfaceLight, dark: swatch.surfaceDark)
      } else {
        color(hex).opacity(0.18)
      }
    surfaces.withLock { $0[hex] = surface }
    return surface
  }

  // MARK: Private

  /// Every timeline block and chart asks for its color on each redraw; the dynamic colors are
  /// built once per hex.
  private static let colors = Mutex([String: Color]())
  private static let surfaces = Mutex([String: Color]())

  private static func dynamic(light: String, dark: String) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(hex: isDark ? dark : light) ?? .controlAccentColor
      }
    )
  }
}

extension NSColor {
  /// `#RRGGBB`
  convenience init?(hex: String) {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
    self.init(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1,
    )
  }
}
