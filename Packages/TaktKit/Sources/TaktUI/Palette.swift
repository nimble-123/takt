import SwiftUI

/// Color tokens from docs/DESIGN.md, with light and dark variants in the asset catalog.
public enum Palette {
  public static let accent = Color("accent", bundle: .module)
  public static let accentText = Color("accentText", bundle: .module)
  public static let accentSurface = Color("accentSurface", bundle: .module)
  public static let onAccent = Color("onAccent", bundle: .module)
  public static let warning = Color("warning", bundle: .module)
  public static let warningSurface = Color("warningSurface", bundle: .module)
  public static let danger = Color("danger", bundle: .module)
  public static let textPrimary = Color("textPrimary", bundle: .module)
  public static let textSecondary = Color("textSecondary", bundle: .module)
  public static let separator = Color("separator", bundle: .module)
}
