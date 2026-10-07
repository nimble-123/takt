import SwiftUI
import TaktCore
import TaktStore

/// Rules in the projects screen (ST-05): order is priority, each can be switched off.
struct RulesSection: View {
    let rules: RulesModel
    let catalog: CatalogModel
    @State private var editing: Rule?

    var body: some View {
        Section {
            ForEach(Array(rules.rules.enumerated()), id: \.element.id) { index, rule in
                HStack(spacing: 8) {
                    Toggle(
                        String(localized: "Enabled", bundle: .module),
                        isOn: Binding(get: { rule.isEnabled }) { enabled in
                            var changed = rule
                            changed.isEnabled = enabled
                            Task { await rules.save(changed) }
                        }
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    VStack(alignment: .leading, spacing: 2) {
                        if !rule.name.isEmpty { Text(rule.name).font(.system(size: 13, weight: .semibold)) }
                        Text(summary(rule))
                            .font(.system(size: 12))
                            .foregroundStyle(rule.isEnabled ? Palette.textPrimary : Palette.textSecondary)
                    }
                    Spacer()
                    iconButton("chevron.up", String(localized: "Move Up", bundle: .module), disabled: index == 0) {
                        Task { await rules.move(rule.id, by: -1) }
                    }
                    iconButton(
                        "chevron.down", String(localized: "Move Down", bundle: .module),
                        disabled: index == rules.rules.count - 1
                    ) {
                        Task { await rules.move(rule.id, by: 1) }
                    }
                    iconButton("pencil", String(localized: "Edit", bundle: .module)) { editing = rule }
                    iconButton("trash", String(localized: "Delete", bundle: .module)) {
                        Task { await rules.delete(rule.id) }
                    }
                }
            }
            HStack {
                Button(String(localized: "New Rule …", bundle: .module)) {
                    editing = Rule(conditions: [.workItemType("")])
                }
                if rules.rules.isEmpty {
                    Button(String(localized: "Add Example “Bug → Support”", bundle: .module)) {
                        Task { await rules.addExample(categories: catalog.activeCategories) }
                    }
                }
            }
        } header: {
            Text("Rules", bundle: .module)
        } footer: {
            Text(
                "Rules fill in category, project and tags when a timer starts or a work item is linked. Choices you make yourself always win; the first matching rule wins per field.",
                bundle: .module
            )
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, catalog: catalog) { saved in
                Task { await rules.save(saved) }
            }
        }
        .task { await rules.reload() }
    }

    private func iconButton(
        _ symbol: String, _ label: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }

    /// "Type is Bug and title contains Login → Support, Portal, #fix"
    private func summary(_ rule: Rule) -> String {
        let conditions = rule.conditions.map(\.summary).joined(separator: String(localized: " and ", bundle: .module))
        var actions: [String] = []
        if let category = catalog.catalog.category(rule.categoryID) { actions.append(category.name) }
        if let project = catalog.catalog.project(rule.projectID) { actions.append(project.name) }
        actions += rule.tags.map { "#\($0)" }
        return "\(conditions) → \(actions.isEmpty ? "–" : actions.joined(separator: ", "))"
    }
}

extension Rule.Condition {
    enum Kind: String, CaseIterable, Identifiable {
        case workItemType, adoProject, titleContains, workItemTag
        var id: Self { self }

        var title: String {
            switch self {
            case .workItemType: String(localized: "Work item type is", bundle: .module)
            case .adoProject: String(localized: "Azure DevOps project is", bundle: .module)
            case .titleContains: String(localized: "Title contains", bundle: .module)
            case .workItemTag: String(localized: "Work item has tag", bundle: .module)
            }
        }
    }

    var kind: Kind {
        switch self {
        case .workItemType: .workItemType
        case .adoProject: .adoProject
        case .titleContains: .titleContains
        case .workItemTag: .workItemTag
        }
    }

    var value: String {
        switch self {
        case .workItemType(let value), .adoProject(let value), .titleContains(let value), .workItemTag(let value): value
        }
    }

    init(kind: Kind, value: String) {
        switch kind {
        case .workItemType: self = .workItemType(value)
        case .adoProject: self = .adoProject(value)
        case .titleContains: self = .titleContains(value)
        case .workItemTag: self = .workItemTag(value)
        }
    }

    var summary: String { "\(kind.title) „\(value)“" }
}

/// Edits one rule in a sheet.
private struct RuleEditor: View {
    @State var rule: Rule
    let catalog: CatalogModel
    let onSave: (Rule) -> Void
    @State private var tags = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField(String(localized: "Name", bundle: .module), text: $rule.name)
            Section(String(localized: "If", bundle: .module)) {
                ForEach(rule.conditions.indices, id: \.self) { index in
                    HStack {
                        Picker("", selection: kindBinding(index)) {
                            ForEach(Rule.Condition.Kind.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        TextField(
                            "", text: valueBinding(index),
                            prompt: Text(verbatim: prompt(for: rule.conditions[index].kind))
                        )
                        .labelsHidden()
                        Button {
                            rule.conditions.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(rule.conditions.count == 1)
                        .accessibilityLabel(Text("Remove condition", bundle: .module))
                    }
                }
                Button(String(localized: "Add Condition", bundle: .module)) {
                    rule.conditions.append(.titleContains(""))
                }
            }
            Section(String(localized: "Then", bundle: .module)) {
                Picker(String(localized: "Category", bundle: .module), selection: $rule.categoryID) {
                    Text("Unchanged", bundle: .module).tag(CategoryID?.none)
                    ForEach(catalog.activeCategories) { Text($0.name).tag(CategoryID?.some($0.id)) }
                }
                Picker(String(localized: "Project", bundle: .module), selection: $rule.projectID) {
                    Text("Unchanged", bundle: .module).tag(ProjectID?.none)
                    ForEach(catalog.activeProjects) { Text($0.name).tag(ProjectID?.some($0.id)) }
                }
                TextField(
                    String(localized: "Tags", bundle: .module), text: $tags,
                    prompt: Text("comma separated", bundle: .module)
                )
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save", bundle: .module)) {
                    rule.tags = tags.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
                    rule.conditions = rule.conditions.filter { !$0.value.trimmed.isEmpty }
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.conditions.allSatisfy { $0.value.trimmed.isEmpty })
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(8)
        .onAppear { tags = rule.tags.joined(separator: ", ") }
    }

    private func prompt(for kind: Rule.Condition.Kind) -> String {
        switch kind {
        case .workItemType: "Bug"
        case .adoProject: "Kundenportal"
        case .titleContains: "Daily"
        case .workItemTag: "Kunde"
        }
    }

    private func kindBinding(_ index: Int) -> Binding<Rule.Condition.Kind> {
        Binding(get: { rule.conditions[index].kind }) { kind in
            rule.conditions[index] = Rule.Condition(kind: kind, value: rule.conditions[index].value)
        }
    }

    private func valueBinding(_ index: Int) -> Binding<String> {
        Binding(get: { rule.conditions[index].value }) { value in
            rule.conditions[index] = Rule.Condition(kind: rule.conditions[index].kind, value: value)
        }
    }
}
