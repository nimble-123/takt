import SwiftUI
import TaktAnalytics
import TaktCore

// MARK: - FlexAccountDetail

/// The flex account's popover (AZ-07): the quarter's payouts against the quota, the payouts of the
/// year and "Pay Out Overtime …".
struct FlexAccountDetail: View {

  // MARK: Internal

  let model: AnalyticsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Flex account", bundle: .module).font(.headline)
      if let quota = model.overtimeQuota {
        Text(OvertimePayoutText.quota(quota)).font(.callout).monospacedDigit()
      }
      if model.payouts.isEmpty {
        Text("No overtime paid out.", bundle: .module)
          .font(.callout)
          .foregroundStyle(Palette.textSecondary)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
          ForEach(model.payouts) { payout in
            GridRow {
              Text(OvertimePayoutText.day(payout.day)).monospacedDigit()
              Text(DurationText.hoursMinutes(payout.seconds)).monospacedDigit().gridColumnAlignment(.trailing)
              Text(payout.note ?? "").lineLimit(1).foregroundStyle(Palette.textSecondary)
              Button {
                Task { await model.removePayout(payout.id) }
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
              .help(Text("Remove Payout", bundle: .module))
              .accessibilityLabel(Text("Remove Payout", bundle: .module))
            }
          }
        }
        .font(.callout)
      }
      Button(String(localized: "Pay Out Overtime …", bundle: .module)) { isPayoutShown = true }
    }
    .padding(16)
    .frame(minWidth: 280, alignment: .leading)
    .sheet(isPresented: $isPayoutShown) {
      OvertimePayoutSheet(model: model)
    }
  }

  // MARK: Private

  @State private var isPayoutShown = false

}

// MARK: - OvertimePayoutSheet

/// Records a payout of overtime from the flex account (AZ-07). Hints on the quota and a negative
/// balance never block it.
struct OvertimePayoutSheet: View {

  // MARK: Internal

  let model: AnalyticsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Pay Out Overtime", bundle: .module).font(.headline)
      Form {
        HoursField(
          title: String(localized: "Hours", bundle: .module),
          value: $hours,
          range: AppSettings.overtimeQuotaRange,
        )
        DatePicker(String(localized: "Date", bundle: .module), selection: $date, displayedComponents: .date)
        TextField(String(localized: "Note (optional)", bundle: .module), text: $note)
      }
      ForEach(model.payoutHints(hours: hours, on: date), id: \.self) { hint in
        Label(OvertimePayoutText.hint(hint), systemImage: "exclamationmark.triangle")
          .font(.callout)
          .foregroundStyle(Palette.warning)
      }
      HStack {
        Spacer()
        Button(String(localized: "Cancel", bundle: .module), role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(String(localized: "Pay Out", bundle: .module)) {
          Task {
            await model.payOut(hours: hours, on: date, note: note)
            dismiss()
          }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(hours <= 0)
      }
    }
    .padding(20)
    .frame(width: 380)
  }

  // MARK: Private

  @Environment(\.dismiss) private var dismiss
  @State private var hours: Double = 0
  @State private var date = Date.now
  @State private var note = ""

}

// MARK: - OvertimePayoutText

enum OvertimePayoutText {
  /// E.g. "Paid out this quarter: 10:00 of 40:00 · 30:00 left".
  static func quota(_ quota: OvertimeQuota) -> String {
    let paid = DurationText.hoursMinutes(quota.paid)
    let limit = DurationText.hoursMinutes(quota.quota)
    return quota.remaining >= 0
      ? String(
        localized: "Paid out this quarter: \(paid) of \(limit) · \(DurationText.hoursMinutes(quota.remaining)) left",
        bundle: .module,
      )
      : String(
        localized: "Paid out this quarter: \(paid) of \(limit) · \(DurationText.hoursMinutes(-quota.remaining)) over",
        bundle: .module,
      )
  }

  static func hint(_ hint: AnalyticsModel.PayoutHint) -> String {
    switch hint {
    case .exceedsQuota(let seconds):
      String(localized: "Exceeds the quarterly quota by \(DurationText.hoursMinutes(seconds)).", bundle: .module)
    case .negativeBalance(let balance):
      String(
        localized: "The flex account goes negative: −\(DurationText.hoursMinutes(-balance)).",
        bundle: .module,
      )
    }
  }

  /// `YYYY-MM-DD` as a short local date.
  static func day(_ day: String) -> String {
    guard
      let parts = Timestamp.localDayParts(day),
      let date = Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    else { return day }
    return date.formatted(date: .numeric, time: .omitted)
  }
}
