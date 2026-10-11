import SwiftUI

/// Color tokens from docs/DESIGN.md, resolved from the active theme (HW-07) and its light or dark
/// variant.
public enum Palette {
  public static let accent = Color(ThemeColor(token: .accent))
  public static let accentText = Color(ThemeColor(token: .accentText))
  public static let accentSurface = Color(ThemeColor(token: .accentSurface))
  public static let onAccent = Color(ThemeColor(token: .onAccent))
  public static let warning = Color(ThemeColor(token: .warning))
  public static let warningSurface = Color(ThemeColor(token: .warningSurface))
  public static let danger = Color(ThemeColor(token: .danger))
  public static let textPrimary = Color(ThemeColor(token: .textPrimary))
  public static let textSecondary = Color(ThemeColor(token: .textSecondary))
  public static let separator = Color(ThemeColor(token: .separator))
  /// Window background; clear in the standard theme, which keeps the system's materials.
  public static let background = Color(ThemeColor(token: .background))
  /// Sidebar background; clear in the standard theme.
  public static let sidebar = Color(ThemeColor(token: .sidebar))
}
