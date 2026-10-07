import Foundation

/// The text typed to start a timer, split into a title and tokens (MB-09):
/// `@category`, `/project` or `/project/task`, `#tag`.
///
/// Tokens only count at the start of a word, so `max@example.com` or `1/2` stay part of the
/// title. A `#` followed by digits only is a work item number (`#4711`) and stays in the title,
/// where the work item search picks it up. Names are matched against the catalog later; the
/// parser only returns what was typed.
public struct StartInput: Hashable, Sendable {
    public var title: String
    public var category: String?
    public var project: String?
    public var task: String?
    public var tags: [String]

    public init(
        title: String, category: String? = nil, project: String? = nil, task: String? = nil, tags: [String] = []
    ) {
        self.title = title
        self.category = category
        self.project = project
        self.task = task
        self.tags = tags
    }

    public var hasTokens: Bool { category != nil || project != nil || !tags.isEmpty }

    /// A token in the input.
    public enum Token: Hashable, Sendable {
        case category(String)
        case project(String, task: String?)
        case tag(String)
    }

    /// The token a word stands for, or `nil` if the word is part of the title.
    public static func token(_ word: Substring) -> Token? {
        guard let marker = word.first, word.count > 1 else { return nil }
        let name = word.dropFirst()
        switch marker {
        case "@":
            return .category(String(name))
        case "/":
            let parts = name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let project = parts.first, !project.isEmpty else { return nil }
            let task = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
            return .project(String(project), task: task)
        case "#":
            // `#4711` is a work item number, not a tag.
            guard name.contains(where: \.isLetter) else { return nil }
            return .tag(String(name))
        default:
            return nil
        }
    }

    /// Splits the input. Later category or project tokens replace earlier ones; tags are kept
    /// in order without case-insensitive duplicates.
    public static func parse(_ text: String) -> StartInput {
        var input = StartInput(title: "")
        var words: [Substring] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            switch token(word) {
            case .category(let name):
                input.category = name
            case .project(let name, let task):
                input.project = name
                input.task = task
            case .tag(let name):
                if !input.tags.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    input.tags.append(name)
                }
            case nil:
                words.append(word)
            }
        }
        input.title = words.joined(separator: " ")
        return input
    }

    /// The token being typed at the end of `text`, for completion; `nil` once a space follows it.
    public static func partial(in text: String) -> Token? {
        guard let last = text.last, !last.isWhitespace else { return nil }
        let word = text.split(whereSeparator: \.isWhitespace).last ?? ""
        switch word.first {
        case "@":
            return .category(String(word.dropFirst()))
        case "/":
            let name = word.dropFirst()
            guard let slash = name.firstIndex(of: "/") else { return .project(String(name), task: nil) }
            return .project(String(name[..<slash]), task: String(name[name.index(after: slash)...]))
        case "#":
            let name = word.dropFirst()
            // Digits only could still become a work item number; wait for a letter.
            return name.contains(where: \.isLetter) ? .tag(String(name)) : nil
        default:
            return nil
        }
    }

    /// `text` with its last word replaced by `token` and a trailing space, for accepting a completion.
    /// Spaces in names are dropped so the token stays one word.
    public static func completing(_ text: String, with token: Token) -> String {
        let compact = { (name: String) in name.filter { !$0.isWhitespace } }
        let word: String
        switch token {
        case .category(let name): word = "@" + compact(name)
        case .project(let name, let task): word = "/" + compact(name) + (task.map { "/" + compact($0) } ?? "")
        case .tag(let name): word = "#" + compact(name)
        }
        var head = text
        while let last = head.last, !last.isWhitespace { head.removeLast() }
        return head + word + " "
    }
}
