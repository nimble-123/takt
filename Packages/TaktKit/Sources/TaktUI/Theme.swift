import SwiftUI

// MARK: - Theme

/// A color scheme for the whole app (HW-07): the tokens from docs/DESIGN.md for a light and/or a
/// dark variant. The standard theme keeps the system's window materials; the others paint the
/// window in their background color, after the VS Code themes of the same name.
nonisolated public struct Theme: Hashable, Sendable, Identifiable {

  // MARK: Public

  public enum ID: String, CaseIterable, Sendable {
    case standard
    case github
    case fioriHorizon
    case tokyoNight
    case auraDark
    case panda
    case dracula
    case oneDark
    case nord
    case catppuccinMocha
  }

  /// Light, dark or following the system (`appearance` setting).
  public enum Appearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
  }

  /// One variant's colors as `0xRRGGBB` (sRGB).
  public struct Tokens: Hashable, Sendable {
    /// Name of the variant, e.g. "GitHub Light".
    public var name: String
    /// Window background; `nil` keeps the system's material.
    public var background: UInt32?
    /// Sidebar background; `nil` keeps the system's material.
    public var sidebar: UInt32?
    public var accent: UInt32
    public var accentText: UInt32
    public var accentSurface: UInt32
    public var onAccent: UInt32
    public var warning: UInt32
    public var warningSurface: UInt32
    public var danger: UInt32
    public var textPrimary: UInt32
    public var textSecondary: UInt32
    public var separator: UInt32
  }

  public static let standard = Theme(id: .standard, name: "Takt", light: taktLight, dark: taktDark)

  /// In the order of the settings. Colors after the themes' published palettes (all MIT, SAP Fiori
  /// Horizon from SAP's theming-base-content, Apache 2.0); muted text and surfaces are lightened or
  /// darkened where the original misses 4.5:1.
  public static let all: [Theme] = [
    standard,
    Theme(
      id: .github,
      name: "GitHub",
      light: Tokens(
        name: "GitHub Light",
        background: 0xFFFFFF,
        sidebar: 0xF6F8FA,
        accent: 0x0969DA,
        accentText: 0x0969DA,
        accentSurface: 0xDDF4FF,
        onAccent: 0xFFFFFF,
        warning: 0x9A6700,
        warningSurface: 0xFFF8C5,
        danger: 0xD1242F,
        textPrimary: 0x1F2328,
        textSecondary: 0x59636E,
        separator: 0xD1D9E0,
      ),
      dark: Tokens(
        name: "GitHub Dark",
        background: 0x0D1117,
        sidebar: 0x010409,
        accent: 0x1F6FEB,
        accentText: 0x4493F8,
        accentSurface: 0x15243A,
        onAccent: 0xFFFFFF,
        warning: 0xD29922,
        warningSurface: 0x2B2111,
        danger: 0xF85149,
        textPrimary: 0xE6EDF3,
        textSecondary: 0x9198A1,
        separator: 0x30363D,
      ),
    ),
    Theme(
      id: .fioriHorizon,
      name: "SAP Fiori Horizon",
      light: Tokens(
        name: "Morning Horizon",
        background: 0xF5F6F7,
        sidebar: 0xFFFFFF,
        accent: 0x0070F2,
        accentText: 0x0064D9,
        accentSurface: 0xE8F3FF,
        onAccent: 0xFFFFFF,
        warning: 0xAA5808,
        warningSurface: 0xFFF8D6,
        danger: 0xAA0808,
        textPrimary: 0x1D2D3E,
        textSecondary: 0x556B82,
        separator: 0xD9D9D9,
      ),
      dark: Tokens(
        name: "Evening Horizon",
        background: 0x12171C,
        sidebar: 0x1D232A,
        accent: 0x4DB1FF,
        accentText: 0x4DB1FF,
        accentSurface: 0x1C3954,
        onAccent: 0x12171C,
        warning: 0xFABD64,
        warningSurface: 0x3B2E17,
        danger: 0xFF8888,
        textPrimary: 0xEAECEE,
        textSecondary: 0xA9B4BE,
        separator: 0x34404C,
      ),
    ),
    dark(
      .tokyoNight,
      "Tokyo Night",
      Tokens(
        name: "Tokyo Night",
        background: 0x1A1B26,
        sidebar: 0x16161E,
        accent: 0x7AA2F7,
        accentText: 0x7AA2F7,
        accentSurface: 0x283457,
        onAccent: 0x1A1B26,
        warning: 0xE0AF68,
        warningSurface: 0x3B3122,
        danger: 0xF7768E,
        textPrimary: 0xC0CAF5,
        textSecondary: 0x9AA5CE,
        separator: 0x292E42,
      ),
    ),
    dark(
      .auraDark,
      "Aura Dark",
      Tokens(
        name: "Aura Dark",
        background: 0x15141B,
        sidebar: 0x110F18,
        accent: 0xA277FF,
        accentText: 0xA277FF,
        accentSurface: 0x2A2342,
        onAccent: 0x15141B,
        warning: 0xFFCA85,
        warningSurface: 0x3A2F22,
        danger: 0xFF6767,
        textPrimary: 0xEDECEE,
        textSecondary: 0xADACAE,
        separator: 0x29263C,
      ),
    ),
    dark(
      .panda,
      "Panda",
      Tokens(
        name: "Panda",
        background: 0x292A2B,
        sidebar: 0x242526,
        accent: 0xFF75B5,
        accentText: 0xFF75B5,
        accentSurface: 0x47303D,
        onAccent: 0x292A2B,
        warning: 0xFFB86C,
        warningSurface: 0x45382A,
        danger: 0xFF4B82,
        textPrimary: 0xE6E6E6,
        textSecondary: 0xB3B5B8,
        separator: 0x3E4045,
      ),
    ),
    dark(
      .dracula,
      "Dracula",
      Tokens(
        name: "Dracula",
        background: 0x282A36,
        sidebar: 0x21222C,
        accent: 0xBD93F9,
        accentText: 0xBD93F9,
        accentSurface: 0x3A3550,
        onAccent: 0x282A36,
        warning: 0xFFB86C,
        warningSurface: 0x45392D,
        danger: 0xFF5555,
        textPrimary: 0xF8F8F2,
        textSecondary: 0xBFC2D4,
        separator: 0x343746,
      ),
    ),
    dark(
      .oneDark,
      "One Dark",
      Tokens(
        name: "One Dark",
        background: 0x282C34,
        sidebar: 0x21252B,
        accent: 0x61AFEF,
        accentText: 0x61AFEF,
        accentSurface: 0x2C3A4A,
        onAccent: 0x282C34,
        warning: 0xE5C07B,
        warningSurface: 0x3E3A2D,
        danger: 0xEF7B85,
        textPrimary: 0xD7DAE0,
        textSecondary: 0x9DA5B4,
        separator: 0x3E4451,
      ),
    ),
    dark(
      .nord,
      "Nord",
      Tokens(
        name: "Nord",
        background: 0x2E3440,
        sidebar: 0x2A2F3A,
        accent: 0x88C0D0,
        accentText: 0x88C0D0,
        accentSurface: 0x3B4A58,
        onAccent: 0x2E3440,
        warning: 0xEBCB8B,
        warningSurface: 0x4A4536,
        danger: 0xE8848D,
        textPrimary: 0xECEFF4,
        textSecondary: 0xB4BCCC,
        separator: 0x3B4252,
      ),
    ),
    dark(
      .catppuccinMocha,
      "Catppuccin Mocha",
      Tokens(
        name: "Catppuccin Mocha",
        background: 0x1E1E2E,
        sidebar: 0x181825,
        accent: 0xCBA6F7,
        accentText: 0xCBA6F7,
        accentSurface: 0x36304A,
        onAccent: 0x1E1E2E,
        warning: 0xF9E2AF,
        warningSurface: 0x3E3832,
        danger: 0xF38BA8,
        textPrimary: 0xCDD6F4,
        textSecondary: 0xA6ADC8,
        separator: 0x313244,
      ),
    ),
  ]

  public let id: ID
  public let name: String
  public let light: Tokens?
  public let dark: Tokens?

  /// The standard theme leaves the window's materials, tint and text colors to the system.
  public var isStandard: Bool {
    id == .standard
  }

  /// A theme with a single variant fixes the appearance.
  public var fixedAppearance: Appearance? {
    switch (light, dark) {
    case (nil, _): .dark
    case (_, nil): .light
    default: nil
    }
  }

  public static func named(_ id: ID) -> Theme {
    all.first { $0.id == id } ?? standard
  }

  /// The appearance the app uses: the theme's only variant, otherwise the chosen one.
  public func appearance(_ chosen: Appearance) -> Appearance {
    fixedAppearance ?? chosen
  }

  public func tokens(isDark: Bool) -> Tokens {
    (isDark ? dark ?? light : light ?? dark) ?? Self.taktLight
  }

  // MARK: Private

  private static let taktLight = Tokens(
    name: "Takt",
    accent: 0x0F766E,
    accentText: 0x0F766E,
    accentSurface: 0xE8F4F2,
    onAccent: 0xFFFFFF,
    warning: 0xB45309,
    warningSurface: 0xFEF3E2,
    danger: 0xB91C1C,
    textPrimary: 0x1C1C1E,
    textSecondary: 0x55555A,
    separator: 0xE5E5EA,
  )

  private static let taktDark = Tokens(
    name: "Takt",
    accent: 0x2DD4BF,
    accentText: 0x5EEAD4,
    accentSurface: 0x12332F,
    onAccent: 0x042F2E,
    warning: 0xFBBF24,
    warningSurface: 0x4A3510,
    danger: 0xF87171,
    textPrimary: 0xF5F5F7,
    textSecondary: 0xAEAEB2,
    separator: 0x3A3A3C,
  )

  private static func dark(_ id: ID, _ name: String, _ tokens: Tokens) -> Theme {
    Theme(id: id, name: name, light: nil, dark: tokens)
  }

}

nonisolated extension Theme.Tokens {
  init(
    name: String,
    accent: UInt32,
    accentText: UInt32,
    accentSurface: UInt32,
    onAccent: UInt32,
    warning: UInt32,
    warningSurface: UInt32,
    danger: UInt32,
    textPrimary: UInt32,
    textSecondary: UInt32,
    separator: UInt32,
  ) {
    self.init(
      name: name,
      background: nil,
      sidebar: nil,
      accent: accent,
      accentText: accentText,
      accentSurface: accentSurface,
      onAccent: onAccent,
      warning: warning,
      warningSurface: warningSurface,
      danger: danger,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      separator: separator,
    )
  }
}

nonisolated extension EnvironmentValues {
  /// The active theme; the app sets it on each window's root view (`themed(_:)`).
  @Entry public var theme = Theme.standard
}

// MARK: - ThemeColor

/// A token of the active theme, resolved from the environment, so a theme change redraws every
/// view without rebuilding it.
nonisolated struct ThemeColor: ShapeStyle, Hashable {

  // MARK: Internal

  enum Token: Hashable {
    case background
    case sidebar
    case accent
    case accentText
    case accentSurface
    case onAccent
    case warning
    case warningSurface
    case danger
    case textPrimary
    case textSecondary
    case separator
  }

  var token: Token

  static func rgb(_ value: UInt32) -> Color {
    Color(
      .sRGB,
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255,
    )
  }

  func resolve(in environment: EnvironmentValues) -> Color.Resolved {
    let tokens = environment.theme.tokens(isDark: environment.colorScheme == .dark)
    guard let value = value(of: tokens) else { return Color.clear.resolve(in: environment) }
    return Self.rgb(value).resolve(in: environment)
  }

  // MARK: Private

  private func value(of tokens: Theme.Tokens) -> UInt32? {
    switch token {
    case .background: tokens.background
    case .sidebar: tokens.sidebar
    case .accent: tokens.accent
    case .accentText: tokens.accentText
    case .accentSurface: tokens.accentSurface
    case .onAccent: tokens.onAccent
    case .warning: tokens.warning
    case .warningSurface: tokens.warningSurface
    case .danger: tokens.danger
    case .textPrimary: tokens.textPrimary
    case .textSecondary: tokens.textSecondary
    case .separator: tokens.separator
    }
  }
}

// MARK: - Themed

/// Puts the theme on a window's root view: its tokens, and for every theme but the standard one the
/// background, tint and text color (HW-07).
struct Themed: ViewModifier {

  // MARK: Internal

  let settings: AppSettings

  func body(content: Content) -> some View {
    let theme = Theme.named(settings.theme)
    content
      .foregroundStyle(theme.isStandard ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.textPrimary))
      .tint(theme.isStandard ? nil : ThemeColor.rgb(theme.tokens(isDark: colorScheme == .dark).accent))
      .scrollContentBackground(theme.isStandard ? .automatic : .hidden)
      .background(Palette.background)
      .environment(\.theme, theme)
  }

  // MARK: Private

  @Environment(\.colorScheme) private var colorScheme
}

// MARK: - ThemeTint

/// The accent as tint for controls that AppKit draws (switches, prominent buttons): they get the
/// color without the environment, so `Palette.accent` would fall back to the standard theme.
private struct ThemeTint: ViewModifier {
  func body(content: Content) -> some View {
    content.tint(ThemeColor.rgb(theme.tokens(isDark: colorScheme == .dark).accent))
  }

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

}

extension View {

  // MARK: Public

  /// The active theme from the settings for this window (HW-07).
  public func themed(_ settings: AppSettings) -> some View {
    modifier(Themed(settings: settings))
  }

  // MARK: Internal

  /// Tints controls in the theme's accent (HW-07).
  func themeTint() -> some View {
    modifier(ThemeTint())
  }

}
