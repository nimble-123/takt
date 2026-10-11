import SwiftUI

// MARK: - MicrosoftAccountSection

/// Sign in or out with the work account (DO-01, CA-02). While signed out, client and tenant ID
/// of the app registration can be entered unless a configuration profile sets them (#242).
struct MicrosoftAccountSection: View {

  @Bindable var model: MicrosoftAccountModel
  @Bindable var settings: AppSettings

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
        Toggle(String(localized: "Show Outlook events in the search", bundle: .module), isOn: $settings.calendarEnabled)
          .managed(settings.isLocked(.calendarEnabled))
      } else {
        TextField(
          String(localized: "Client ID", bundle: .module),
          text: $model.clientID,
          prompt: Text(verbatim: "00000000-0000-0000-0000-000000000000"),
        )
        .managed(model.isClientIDLocked)
        TextField(
          String(localized: "Tenant ID", bundle: .module),
          text: $model.tenantID,
          prompt: Text(verbatim: "contoso.onmicrosoft.com"),
        )
        .managed(model.isTenantIDLocked)
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
          .disabled(model.configuration == nil || model.isWorking)
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
      VStack(alignment: .leading, spacing: 4) {
        Text(
          "Your organization's work account. Takt reads your calendar with it; the sign-in stays in the keychain.",
          bundle: .module,
        )
        if model.account == nil {
          Text(
            "Client ID and tenant ID belong to the app registration for Takt in Microsoft Entra ID; your IT department provides them.",
            bundle: .module,
          )
        }
      }
      .font(.system(size: 11))
      .foregroundStyle(Palette.textSecondary)
    }
    .task { await model.load() }
  }
}
