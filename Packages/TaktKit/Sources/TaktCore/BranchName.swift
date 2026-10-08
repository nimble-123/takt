import Foundation

/// Finds the Azure DevOps work item in a Git branch name (PRD "Vorgeschlagene Items" 4).
public enum BranchName {
  /// `AB#1234` and `#1234` anywhere; otherwise a path segment starting with at least two digits,
  /// e.g. `feature/1234-login` or `users/nils/1234`. Version numbers like `release/2.3.1` do not count.
  public static func workItemID(in branch: String) -> Int? {
    if let match = branch.firstMatch(of: #/(?:AB)?#(\d+)/#.ignoresCase()), let id = Int(match.1) { return id }
    for segment in branch.split(separator: "/").reversed() {
      if let match = segment.wholeMatch(of: #/(\d{2,})(?:[-_].*)?/#), let id = Int(match.1) { return id }
    }
    return nil
  }
}
