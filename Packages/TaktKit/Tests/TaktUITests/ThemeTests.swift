import Foundation
import Testing

@testable import TaktUI

// MARK: - ThemeTests

@MainActor
struct ThemeTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults("takt-theme")
  }

  // MARK: Internal

  /// HW-07: text 4.5:1 on its ground, the accent as a control 3:1, in every theme and variant. The
  /// standard theme is checked against white and the dark window background.
  @Test(arguments: Theme.all.flatMap { theme in
    [theme.light, theme.dark].compactMap(\.self).map { (theme.id, $0) }
  })
  func everyThemeReachesTheContrastOfTheDesign(id: Theme.ID, tokens: Theme.Tokens) {
    let isDark = tokens == Theme.named(id).dark
    let background = tokens.background ?? (isDark ? 0x1E1E1E : 0xFFFFFF)
    let pairs: [(String, UInt32, UInt32, Double)] = [
      ("text", tokens.textPrimary, background, 4.5),
      ("text on sidebar", tokens.textPrimary, tokens.sidebar ?? background, 4.5),
      ("secondary text", tokens.textSecondary, background, 4.5),
      ("secondary text on sidebar", tokens.textSecondary, tokens.sidebar ?? background, 4.5),
      ("accent text", tokens.accentText, background, 4.5),
      ("accent text on selection", tokens.accentText, tokens.accentSurface, 4.5),
      ("text on selection", tokens.textPrimary, tokens.accentSurface, 4.5),
      ("label on accent", tokens.onAccent, tokens.accent, 4.5),
      ("accent", tokens.accent, background, 3),
      ("warning", tokens.warning, background, 4.5),
      ("warning on its surface", tokens.warning, tokens.warningSurface, 4.5),
      ("danger", tokens.danger, background, 4.5),
    ]
    for (name, foreground, ground, minimum) in pairs {
      let ratio = CategoryColors.contrast(hex(foreground), hex(ground))
      #expect(ratio >= minimum, "\(tokens.name): \(name) \(ratio)")
    }
  }

  /// The standard theme keeps the colors of the former asset catalog (docs/DESIGN.md).
  @Test
  func standardThemeKeepsTheDesignTokens() throws {
    let light = try #require(Theme.standard.light)
    let dark = try #require(Theme.standard.dark)
    #expect([light.accent, light.accentText, light.textSecondary, light.warning] == [0x0F766E, 0x0F766E, 0x55555A, 0xB45309])
    #expect([dark.accent, dark.accentText, dark.textSecondary, dark.warning] == [0x2DD4BF, 0x5EEAD4, 0xAEAEB2, 0xFBBF24])
    #expect(light.background == nil && dark.sidebar == nil)
    #expect(Theme.standard.isStandard)
  }

  @Test
  func singleVariantThemesFixTheAppearance() {
    let tokyoNight = Theme.named(.tokyoNight)
    #expect(tokyoNight.fixedAppearance == .dark)
    #expect(tokyoNight.appearance(.light) == .dark)
    #expect(tokyoNight.tokens(isDark: false).name == "Tokyo Night")

    let github = Theme.named(.github)
    #expect(github.fixedAppearance == nil)
    #expect(github.appearance(.light) == .light)
    #expect(github.appearance(.system) == .system)
    #expect(github.tokens(isDark: true).name == "GitHub Dark")
    #expect(Theme.named(.fioriHorizon).tokens(isDark: false).name == "Morning Horizon")
    #expect(Set(Theme.all.map(\.id)) == Set(Theme.ID.allCases))
  }

  @Test
  func themeAndAppearanceArePersisted() {
    let store = testDefaults.defaults
    let settings = AppSettings(defaults: store)
    #expect(settings.theme == .standard)
    #expect(settings.appearance == .system)

    settings.theme = .tokyoNight
    settings.appearance = .dark

    #expect(store.string(forKey: "theme") == "tokyoNight")
    #expect(store.string(forKey: "appearance") == "dark")
    let reloaded = AppSettings(defaults: store)
    #expect(reloaded.theme == .tokyoNight)
    #expect(reloaded.appearance == .dark)
  }

  @Test
  func unknownStoredThemeFallsBackToTheStandard() {
    let store = testDefaults.defaults
    store.set("solarized", forKey: "theme")
    store.set("sepia", forKey: "appearance")
    let settings = AppSettings(defaults: store)
    #expect(settings.theme == .standard)
    #expect(settings.appearance == .system)
  }

  // MARK: Private

  private let testDefaults: TestDefaults

  private func hex(_ value: UInt32) -> String {
    "#" + String(value, radix: 16, uppercase: true).leftPadded(to: 6)
  }
}

extension String {
  fileprivate func leftPadded(to length: Int) -> String {
    String(repeating: "0", count: max(0, length - count)) + self
  }
}
