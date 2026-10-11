import SwiftUI

// MARK: - MicrosoftAccountSection

/// Sign in or out with the work account (DO-01, CA-02).
struct MicrosoftAccountSection: View {

  let model: MicrosoftAccountModel

  var body: some View {
    Section {
      if let account = model.account {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(account.name.isEmpty ? account.username : account.name)
              .font(.system(size: 13, weight: .semibold))
            if !account.name.isEmpty {
              Text(account.username)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
            }
          }
          Spacer()
          Button(String(localized: "Sign Out", bundle: .module), role: .destructive) {
            Task { await model.signOut() }
          }
        }
      } else {
        HStack {
          Text("Not signed in", bundle: .module)
            .foregroundStyle(Palette.textSecondary)
          Spacer()
          if model.isWorking { ProgressView().controlSize(.small) }
          Button(String(localized: "Sign In with Microsoft …", bundle: .module)) {
            Task { await model.signIn() }
          }
          .buttonStyle(.borderedProminent)
          .themeTint()
          .disabled(model.isWorking)
        }
      }
      if let message = model.errorMessage {
        Text(message)
          .font(.system(size: 12))
          .foregroundStyle(Palette.danger)
      }
    } header: {
      Text("Microsoft Account", bundle: .module)
    } footer: {
      Text(
        "Your organization's work account. Takt reads your calendar with it; the sign-in stays in the keychain.",
        bundle: .module,
      )
      .font(.system(size: 11))
      .foregroundStyle(Palette.textSecondary)
    }
    .task { await model.load() }
  }
}
