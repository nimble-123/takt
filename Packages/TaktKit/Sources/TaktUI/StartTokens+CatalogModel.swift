import TaktCore
import TaktStore

/// `StartTokens` against the app's live catalog (MB-09).
extension StartTokens {

  // MARK: Lifecycle

  init(_ input: StartInput, catalog: CatalogModel) {
    self.init(input, catalog: catalog.catalog)
  }

  // MARK: Internal

  static func completions(for partial: StartInput.Token, catalog: CatalogModel) -> [Completion] {
    completions(for: partial, catalog: catalog.catalog, newTagHint: String(localized: "New tag", bundle: .module))
  }
}
