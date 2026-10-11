import SwiftUI

// MARK: - ThemeSection

/// Settings → Appearance: the theme as cards with a small preview, and light, dark or the system's
/// appearance (HW-07).
struct ThemeSection: View {

  // MARK: Internal

  @Bindable var settings: AppSettings

  var body: some View {
    let theme = Theme.named(settings.theme)
    Section {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
        ForEach(Theme.all) { theme in
          ThemeCard(theme: theme, isSelected: theme.id == settings.theme) {
            settings.theme = theme.id
          }
        }
      }
      .padding(.vertical, 4)
      .managed(settings.isLocked(.theme))
      Picker(String(localized: "Appearance", bundle: .module), selection: appearance(theme)) {
        Text("System", bundle: .module).tag(Theme.Appearance.system)
        Text("Light", bundle: .module).tag(Theme.Appearance.light)
        Text("Dark", bundle: .module).tag(Theme.Appearance.dark)
      }
      .pickerStyle(.segmented)
      .disabled(theme.fixedAppearance != nil)
      .managed(settings.isLocked(.appearance))
    } header: {
      Text("Theme", bundle: .module)
    } footer: {
      if theme.fixedAppearance == .dark {
        Text("\(theme.name) has a dark variant only.", bundle: .module)
          .font(.system(size: 11))
          .foregroundStyle(Palette.textSecondary)
      }
    }
  }

  // MARK: Private

  /// A theme with one variant shows that one; the choice is kept for the next theme.
  private func appearance(_ theme: Theme) -> Binding<Theme.Appearance> {
    Binding(get: { theme.appearance(settings.appearance) }) { settings.appearance = $0 }
  }
}

// MARK: - ThemeCard

private struct ThemeCard: View {

  // MARK: Internal

  let theme: Theme
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 0) {
          ForEach(variants, id: \.isDark) { variant in
            preview(variant.tokens, isDark: variant.isDark)
          }
        }
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isSelected ? Palette.accent : Palette.separator, lineWidth: isSelected ? 2.5 : 1)
        }
        HStack(spacing: 4) {
          VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: theme.name)
              .font(.system(size: 12, weight: .medium))
              .lineLimit(1)
            Text(verbatim: subtitle)
              .font(.system(size: 11))
              .foregroundStyle(Palette.textSecondary)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(Palette.accent)
          }
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(Text(verbatim: variantNames))
    .accessibilityLabel(Text(verbatim: "\(theme.name), \(subtitle)"))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  // MARK: Private

  private var variants: [(tokens: Theme.Tokens, isDark: Bool)] {
    [theme.light.map { ($0, false) }, theme.dark.map { ($0, true) }].compactMap(\.self)
  }

  private var subtitle: String {
    variants.count == 2 ? String(localized: "Light · Dark", bundle: .module) : String(localized: "Dark", bundle: .module)
  }

  /// The variants' own names, e.g. "Morning Horizon · Evening Horizon".
  private var variantNames: String {
    variants.map(\.tokens.name).joined(separator: " · ")
  }

  /// A miniature window: sidebar, a running timer in the accent color, text lines and a warning.
  private func preview(_ tokens: Theme.Tokens, isDark: Bool) -> some View {
    let background = tokens.background ?? (isDark ? 0x1E1E1E : 0xFFFFFF)
    let sidebar = tokens.sidebar ?? (isDark ? 0x2A2A2A : 0xECECEC)
    return HStack(spacing: 0) {
      ThemeColor.rgb(sidebar)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 5) {
        Capsule().fill(ThemeColor.rgb(tokens.accent)).frame(width: 34, height: 6)
        Capsule().fill(ThemeColor.rgb(tokens.textPrimary)).frame(width: 40, height: 4)
        Capsule().fill(ThemeColor.rgb(tokens.textSecondary)).frame(width: 28, height: 4)
        HStack(spacing: 3) {
          RoundedRectangle(cornerRadius: 2).fill(ThemeColor.rgb(tokens.accentSurface)).frame(width: 16, height: 10)
          RoundedRectangle(cornerRadius: 2).fill(ThemeColor.rgb(tokens.warning)).frame(width: 10, height: 10)
          RoundedRectangle(cornerRadius: 2).fill(ThemeColor.rgb(tokens.danger)).frame(width: 10, height: 10)
        }
      }
      .padding(8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(ThemeColor.rgb(background))
    }
    .accessibilityHidden(true)
  }
}
