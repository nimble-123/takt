import SwiftUI
import TaktCore
import TaktStore

// MARK: - CatalogScreen

/// Projects with tasks, categories and tags (ST-01–ST-04). Archive instead of delete.
struct CatalogScreen: View {

  // MARK: Internal

  let catalog: CatalogModel
  var rules: RulesModel?

  var body: some View {
    Form {
      Section {
        ForEach(projects) { project in
          ProjectRow(catalog: catalog, project: project, showArchived: showArchived)
        }
        TextField(
          String(localized: "New project", bundle: .module),
          text: $newProject,
          prompt: Text("New project", bundle: .module),
        )
        .labelsHidden()
        .multilineTextAlignment(.leading)
        .onSubmit {
          Task {
            if await catalog.addProject(named: newProject) != nil { newProject = "" }
          }
        }
      } header: {
        Text("Projects", bundle: .module)
      }

      Section {
        ForEach(categories) { category in
          CategoryRow(catalog: catalog, category: category)
        }
        TextField(
          String(localized: "New category", bundle: .module),
          text: $newCategory,
          prompt: Text("New category", bundle: .module),
        )
        .labelsHidden()
        .multilineTextAlignment(.leading)
        .onSubmit {
          Task {
            if await catalog.addCategory(named: newCategory) != nil { newCategory = "" }
          }
        }
      } header: {
        Text("Categories", bundle: .module)
      }

      if let rules {
        RulesSection(rules: rules, catalog: catalog)
      }

      Section {
        if catalog.catalog.tags.isEmpty {
          Text("Tags are created when you add them to an entry.", bundle: .module)
            .foregroundStyle(Palette.textSecondary)
        } else {
          Text(catalog.catalog.tags.map(\.name).joined(separator: " · "))
        }
      } header: {
        Text("Tags", bundle: .module)
      }

      if let message = catalog.errorMessage {
        Text(message).foregroundStyle(Palette.danger)
      }
    }
    .formStyle(.grouped)
    .toolbar {
      ToolbarItem {
        Toggle(String(localized: "Show Archived", bundle: .module), isOn: $showArchived)
      }
    }
    .task { await catalog.reload() }
  }

  // MARK: Private

  @State private var showArchived = false
  @State private var newProject = ""
  @State private var newCategory = ""

  private var projects: [Project] {
    catalog.catalog.projects.filter { showArchived || !$0.archived }
  }

  private var categories: [EntryCategory] {
    catalog.catalog.categories.filter { showArchived || !$0.archived }
  }
}

// MARK: - ProjectRow

private struct ProjectRow: View {

  // MARK: Internal

  let catalog: CatalogModel
  let project: Project
  let showArchived: Bool

  var body: some View {
    DisclosureGroup {
      ForEach(catalog.catalog.tasks(of: project.id).filter { showArchived || !$0.archived }) { task in
        TaskRow(catalog: catalog, task: task)
      }
      TextField(
        String(localized: "New task", bundle: .module),
        text: $newTask,
        prompt: Text("New task", bundle: .module),
      )
      .labelsHidden()
      .multilineTextAlignment(.leading)
      .onSubmit {
        Task {
          if await catalog.addTask(named: newTask, to: project.id) != nil { newTask = "" }
        }
      }
    } label: {
      HStack(spacing: 8) {
        AppearanceMenu(hex: project.color, icon: project.icon) { hex, icon in
          var edited = project
          edited.color = hex
          edited.icon = icon
          Task { await catalog.save(edited) }
        }
        TextField(String(localized: "Name", bundle: .module), text: $name)
          .labelsHidden()
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textFieldStyle(.plain)
          .commitsOnBlur(name) { value in
            guard let new = value.nilIfBlank, new != project.name else { return }
            var edited = project
            edited.name = new
            Task { await catalog.save(edited) }
          }
          .foregroundStyle(project.archived ? Palette.textSecondary : Palette.textPrimary)
        if project.source == .ado {
          Text("Azure DevOps", bundle: .module)
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
        }
        ArchiveButton(archived: project.archived) {
          var edited = project
          edited.archived.toggle()
          Task { await catalog.save(edited) }
        }
      }
    }
    .onAppear { name = project.name }
    .onChange(of: project.name) { name = project.name }
  }

  // MARK: Private

  @State private var name = ""
  @State private var newTask = ""

}

// MARK: - TaskRow

private struct TaskRow: View {

  // MARK: Internal

  let catalog: CatalogModel
  let task: ProjectTask

  var body: some View {
    HStack {
      TextField(String(localized: "Name", bundle: .module), text: $name)
        .labelsHidden()
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textFieldStyle(.plain)
        .commitsOnBlur(name) { value in
          guard let new = value.nilIfBlank, new != task.name else { return }
          var edited = task
          edited.name = new
          Task { await catalog.save(edited) }
        }
        .foregroundStyle(task.archived ? Palette.textSecondary : Palette.textPrimary)
      ArchiveButton(archived: task.archived) {
        var edited = task
        edited.archived.toggle()
        Task { await catalog.save(edited) }
      }
    }
    .onAppear { name = task.name }
    // Undo, an import or Azure DevOps may rename the task meanwhile.
    .onChange(of: task.name) { name = task.name }
  }

  // MARK: Private

  @State private var name = ""

}

// MARK: - CategoryRow

private struct CategoryRow: View {

  // MARK: Internal

  let catalog: CatalogModel
  let category: EntryCategory

  var body: some View {
    HStack(spacing: 8) {
      AppearanceMenu(hex: category.color, icon: category.icon) { hex, icon in
        var edited = category
        edited.color = hex
        edited.icon = icon
        Task { await catalog.save(edited) }
      }
      TextField(String(localized: "Name", bundle: .module), text: $name)
        .labelsHidden()
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textFieldStyle(.plain)
        .commitsOnBlur(name) { value in
          guard let new = value.nilIfBlank, new != category.name else { return }
          var edited = category
          edited.name = new
          Task { await catalog.save(edited) }
        }
        .foregroundStyle(category.archived ? Palette.textSecondary : Palette.textPrimary)
      ArchiveButton(archived: category.archived) {
        var edited = category
        edited.archived.toggle()
        Task { await catalog.save(edited) }
      }
    }
    .onAppear { name = category.name }
    .onChange(of: category.name) { name = category.name }
  }

  // MARK: Private

  @State private var name = ""

}

// MARK: - ArchiveButton

private struct ArchiveButton: View {
  let archived: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: archived ? "tray.and.arrow.up" : "archivebox")
        .frame(width: 24, height: 24)
    }
    .buttonStyle(.borderless)
    .help(archived ? Text("Restore", bundle: .module) : Text("Archive", bundle: .module))
    .accessibilityLabel(archived ? Text("Restore", bundle: .module) : Text("Archive", bundle: .module))
  }
}

// MARK: - AppearanceMenu

/// Color and SF Symbol of a project or category (ST-02).
struct AppearanceMenu: View {

  // MARK: Internal

  static let icons = [
    "folder",
    "tag",
    "chevron.left.forwardslash.chevron.right",
    "person.2",
    "eye",
    "lifepreserver",
    "hammer",
    "doc.text",
    "envelope",
    "phone",
    "chart.bar",
    "paintbrush",
    "book",
    "graduationcap",
    "airplane",
    "cart",
    "globe",
    "building.2",
    "wrench.and.screwdriver",
    "cup.and.saucer",
  ]

  let hex: String
  let icon: String?
  let onChange: (String, String?) -> Void

  var body: some View {
    Button {
      open = true
    } label: {
      Image(systemName: icon ?? "circle.fill")
        .foregroundStyle(CategoryColors.color(hex))
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(Text("Color and symbol", bundle: .module))
    .popover(isPresented: $open, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Color", bundle: .module).font(.system(size: 11, weight: .semibold))
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 8), spacing: 8) {
          ForEach(CategoryColors.swatches, id: \.hex) { swatch in
            Button {
              onChange(swatch.hex, icon)
            } label: {
              Circle()
                .fill(CategoryColors.color(swatch.hex))
                .frame(width: 20, height: 20)
                .overlay {
                  if swatch.hex == hex {
                    Image(systemName: "checkmark")
                      .font(.system(size: 10, weight: .bold))
                      .foregroundStyle(.white)
                  }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(swatch.hex))
          }
        }
        Text("Symbol", bundle: .module).font(.system(size: 11, weight: .semibold))
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 8), spacing: 8) {
          ForEach(Self.icons, id: \.self) { symbol in
            Button {
              onChange(hex, symbol)
            } label: {
              Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .background(
                  symbol == icon ? CategoryColors.surface(hex) : .clear,
                  in: RoundedRectangle(cornerRadius: 5),
                )
                .foregroundStyle(CategoryColors.color(hex))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(symbol))
          }
        }
      }
      .padding(12)
    }
  }

  // MARK: Private

  @State private var open = false

}
