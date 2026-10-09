import SwiftUI
import TaktAnalytics

// MARK: - WorkTimeMarker

/// A small marker for the ArbZG findings of a day, details in the tooltip (AZ-02). Nothing shows
/// without findings.
struct WorkTimeMarker: View {

  // MARK: Internal

  let check: WorkDayCheck?

  var body: some View {
    if let check, let severity = check.severity {
      Image(systemName: severity == .notice ? "info.circle" : "exclamationmark.triangle.fill")
        .foregroundStyle(color(severity))
        .help(Self.details(check))
        .accessibilityLabel(Text("Working Hours Act", bundle: .module))
        .accessibilityValue(Self.details(check))
    }
  }

  /// One line per finding, then the rest period, which is always measured.
  static func details(_ check: WorkDayCheck) -> String {
    var lines = check.findings.map(text)
    if let rest = check.restBefore, !check.findings.contains(where: { $0.rule == .restPeriod }) {
      lines.append(String(localized: "Rest period before: \(DurationText.hoursMinutes(rest)) h", bundle: .module))
    }
    return lines.joined(separator: "\n")
  }

  // MARK: Private

  private static func text(_ finding: WorkTimeFinding) -> String {
    let measured = DurationText.hoursMinutes(finding.measured)
    let limit = DurationText.hoursMinutes(finding.limit ?? 0)
    return switch finding.rule {
    case .dailyEightHours:
      String(localized: "\(measured) h net, more than 8 h need compensation (§ 3 ArbZG)", bundle: .module)
    case .dailyTenHours:
      String(localized: "\(measured) h net, more than 10 h (§ 3 ArbZG)", bundle: .module)
    case .averageEightHours:
      String(localized: "Average over 24 weeks \(measured) h per working day, more than 8 h (§ 3 ArbZG)", bundle: .module)
    case .breaks:
      String(localized: "Breaks \(measured) h, at least \(limit) h needed (§ 4 ArbZG)", bundle: .module)
    case .continuousWork:
      String(localized: "\(measured) h without a break, at most 6 h (§ 4 ArbZG)", bundle: .module)
    case .restPeriod:
      String(localized: "Rest period \(measured) h, at least 11 h (§ 5 ArbZG)", bundle: .module)
    case .sundayOrHoliday:
      String(localized: "Work on a Sunday or public holiday: \(measured) h (§§ 9, 11 ArbZG)", bundle: .module)
    }
  }

  private func color(_ severity: WorkTimeFinding.Severity) -> Color {
    switch severity {
    case .notice: Palette.textSecondary
    case .warning: Palette.warning
    case .violation: Palette.danger
    }
  }
}
