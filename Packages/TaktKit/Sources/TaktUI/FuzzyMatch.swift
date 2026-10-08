import Foundation

/// Fuzzy matching for the command palette: the query's characters must appear in order.
/// Matches at word starts and runs of consecutive characters score higher (HW-05).
enum FuzzyMatch {

  // MARK: Internal

  /// `nil` if `text` does not contain the query's characters in order; otherwise a score,
  /// higher is better. Case and diacritics are ignored.
  static func score(_ query: String, in text: String) -> Int? {
    let needle = Array(normalized(query).filter { !$0.isWhitespace })
    guard !needle.isEmpty else { return 0 }
    let haystack = Array(normalized(text))
    var score = 0
    var index = 0
    var previousMatch: Int?
    for character in needle {
      guard let found = haystack[index...].firstIndex(of: character) else { return nil }
      score += 1
      if found == 0 || !haystack[found - 1].isLetter && !haystack[found - 1].isNumber { score += 5 }
      if let previousMatch, found == previousMatch + 1 { score += 3 }
      previousMatch = found
      index = found + 1
    }
    // Prefer short texts and matches that start early.
    return score * 10 - haystack.count / 4
  }

  // MARK: Private

  private static func normalized(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}
