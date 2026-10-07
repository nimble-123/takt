import AppKit
import SwiftUI
import TaktADO

/// Form to connect an organization with a Personal Access Token (DO-01, DO-03).
struct ConnectForm: View {
    let model: AzureDevOpsModel
    @State private var organization = ""
    @State private var token = ""
    @State private var hasExpiry = true
    @State private var expires = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(String(localized: "Organization", bundle: .module), text: $organization, prompt: Text("contoso"))
                .disabled(model.managedOrganization != nil)
            SecureField(String(localized: "Personal Access Token", bundle: .module), text: $token)
            HStack {
                Toggle(String(localized: "Expires on", bundle: .module), isOn: $hasExpiry)
                DatePicker("", selection: $expires, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!hasExpiry)
            }
            Text(
                "Create the token in Azure DevOps under User settings → Personal access tokens with the scope “Work Items: Read & Write” and copy its expiry date. Takt keeps it in the keychain only.",
                bundle: .module
            )
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    if let url = tokenURL { NSWorkspace.shared.open(url) }
                } label: {
                    Text("Create token in Azure DevOps …", bundle: .module)
                }
                .disabled(tokenURL == nil)
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button(String(localized: "Connect", bundle: .module)) {
                    Task {
                        if await model.connect(
                            organization: organization, token: token, expires: hasExpiry ? expires : nil)
                        {
                            token = ""
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(organization.trimmed.isEmpty || token.trimmed.isEmpty || model.isWorking)
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if organization.isEmpty { organization = model.managedOrganization ?? "" }
        }
    }

    private var tokenURL: URL? {
        let organization = ADOAccounts.normalized(organization)
        guard !organization.isEmpty else { return nil }
        return URL(string: "https://dev.azure.com/\(organization)/_usersSettings/tokens")
    }
}

/// Lists the organization's projects; each project and area path can be taken over (ST-03).
struct ProjectImport: View {
    let model: AzureDevOpsModel
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.remoteProjects) { project in
                DisclosureGroup(isExpanded: binding(project.name)) {
                    ForEach((model.areaPaths[project.name] ?? []).dropFirst(), id: \.self) { path in
                        row(
                            path.split(separator: "\\").dropFirst().joined(separator: " › "), project.name,
                            areaPath: path)
                    }
                } label: {
                    row(project.name, project.name, areaPath: nil)
                }
            }
        }
    }

    private func binding(_ project: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(project) }) { open in
            if open {
                expanded.insert(project)
                Task { await model.loadAreaPaths(of: project) }
            } else {
                expanded.remove(project)
            }
        }
    }

    private func row(_ title: String, _ project: String, areaPath: String?) -> some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer()
            if model.isTakenOver(project, areaPath: areaPath) {
                Label(String(localized: "Taken over", bundle: .module), systemImage: "checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accentText)
            } else {
                Button(String(localized: "Take over", bundle: .module)) {
                    Task { await model.takeOver(project, areaPath: areaPath) }
                }
                .controlSize(.small)
            }
        }
    }
}

/// Settings section: connections, expiry warning, connecting and taking over projects.
struct AzureDevOpsSettings: View {
    let model: AzureDevOpsModel
    @State private var addingConnection = false

    var body: some View {
        Section(String(localized: "Azure DevOps", bundle: .module)) {
            ForEach(model.connections) { connection in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.organization).font(.system(size: 13, weight: .semibold))
                        Text(details(connection))
                            .font(.system(size: 11))
                            .foregroundStyle(
                                connection.tokenExpiresSoon(at: model.now) ? Palette.warning : Palette.textSecondary)
                    }
                    Spacer()
                    Button(String(localized: "Projects …", bundle: .module)) {
                        model.importOrganization = connection.organization
                        Task { await model.loadProjects() }
                    }
                    Button(String(localized: "Disconnect", bundle: .module), role: .destructive) {
                        model.disconnect(connection.organization)
                    }
                }
            }
            if model.importOrganization != nil, !model.remoteProjects.isEmpty {
                ProjectImport(model: model)
            }
            if model.connections.isEmpty || addingConnection {
                ConnectForm(model: model)
            } else {
                Button(String(localized: "Connect Another Organization …", bundle: .module)) { addingConnection = true }
            }
        }
    }

    private func details(_ connection: ADOConnection) -> String {
        let user = connection.userName
        guard let expires = connection.tokenExpires else { return user }
        let date = expires.formatted(date: .abbreviated, time: .omitted)
        return connection.tokenExpiresSoon(at: model.now)
            ? String(localized: "\(user) · token expires on \(date) – renew it", bundle: .module)
            : String(localized: "\(user) · token valid until \(date)", bundle: .module)
    }
}

/// Onboarding step 1: connect, then take over projects.
struct AzureDevOpsOnboarding: View {
    let model: AzureDevOpsModel

    var body: some View {
        if let connection = model.connections.first {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Connected to \(connection.organization) as \(connection.userName).", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                }
                Text("Take over the projects you work on:", bundle: .module)
                    .foregroundStyle(Palette.textSecondary)
                ScrollView {
                    ProjectImport(model: model)
                }
                .frame(maxHeight: 200)
            }
            .task {
                if model.remoteProjects.isEmpty {
                    model.importOrganization = connection.organization
                    await model.loadProjects()
                }
            }
        } else {
            ConnectForm(model: model)
        }
    }
}
