import Foundation

/// Finds the Azure DevOps work item in a Git branch name (PRD "Vorgeschlagene Items" 4).
public enum BranchName {
    /// `AB#1234` and `#1234` anywhere; otherwise a path segment starting with at least two digits,
    /// e.g. `feature/1234-login` or `users/nils/1234`. Version numbers like `release/2.3.1` do not count.
    public static func workItemID(in branch: String) -> Int? {
        if let id = firstMatch(#"(?:AB)?#(\d+)"#, in: branch) { return id }
        for segment in branch.split(separator: "/").reversed() {
            if let id = firstMatch(#"^(\d{2,})(?:[-_].*)?$"#, in: String(segment)) { return id }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[range])
    }
}
