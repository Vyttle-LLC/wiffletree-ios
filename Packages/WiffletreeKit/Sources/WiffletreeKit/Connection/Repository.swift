import Foundation

/// A repository on the host, with what decides which branches only the human merges into.
public struct Repository: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Such as `origin/main`.
    public let base: String
    public let github: GitHubRepository?
    /// The human's own entries: exact names and patterns.
    public let protectedBranches: [String]

    private enum CodingKeys: String, CodingKey { case id, name, base, github, protectedBranches }

    init(id: String, name: String, base: String, github: GitHubRepository? = nil, protectedBranches: [String] = []) {
        self.id = id
        self.name = name
        self.base = base
        self.github = github
        self.protectedBranches = protectedBranches
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        base = try container.decode(String.self, forKey: .base)
        github = try container.decodeIfPresent(GitHubRepository.self, forKey: .github)
        protectedBranches = try container.decodeIfPresent([String].self, forKey: .protectedBranches) ?? []
    }

    /// Whether the branch is protected as the host decides it: the repository's base, GitHub's
    /// default branch, one of the human's entries, a GitHub ruleset or branch protection rule.
    public func protects(_ branch: String) -> Bool {
        let branches = github?.facts?.branches
        let defaultBranch = branches?.defaultBranch
        let originBase = base.hasPrefix("origin/") ? String(base.dropFirst("origin/".count)) : nil
        return branch == defaultBranch
            || branch == originBase
            || protectedBranches.contains { BranchPattern.matches($0, branch) }
            || (branches?.rulesets ?? []).contains { $0.applies(to: branch, defaultBranch: defaultBranch) }
            || (branches?.protectionRules ?? []).contains { BranchPattern.matches($0, branch) }
    }
}

public struct GitHubRepository: Decodable, Sendable {
    /// Nil until GitHub has answered.
    public let facts: Facts?

    public struct Facts: Decodable, Sendable {
        public let branches: Branches?
    }

    public struct Branches: Decodable, Sendable {
        public let defaultBranch: String?
        public let rulesets: [BranchRuleset]?
        public let protectionRules: [String]?
    }
}

/// A GitHub ruleset's branch conditions.
public struct BranchRuleset: Decodable, Sendable {
    public let name: String
    public let include: [String]
    public let exclude: [String]

    private enum CodingKeys: String, CodingKey { case name, include, exclude }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        include = try container.decode([String].self, forKey: .include)
        exclude = try container.decodeIfPresent([String].self, forKey: .exclude) ?? []
    }

    func applies(to branch: String, defaultBranch: String?) -> Bool {
        targets(include, branch, defaultBranch) && !targets(exclude, branch, defaultBranch)
    }

    private func targets(_ conditions: [String], _ branch: String, _ defaultBranch: String?) -> Bool {
        conditions.contains { condition in
            switch condition {
            case "~ALL": true
            case "~DEFAULT_BRANCH": branch == defaultBranch
            default:
                BranchPattern.matches(condition.hasPrefix("refs/heads/") ? String(condition.dropFirst("refs/heads/".count)) : condition, branch)
            }
        }
    }
}

/// GitHub's branch patterns, as the host's `protected.rs` matches them: `*` matches a run
/// within one folder, `**` any run (and `**/` no folder at all), `?` and `[...]` one character
/// other than `/`; anything else matches itself. A pattern that cannot be read matches nothing.
enum BranchPattern {
    private enum Token: Equatable {
        case char(Character)
        case one
        case star
        case deepStar
        case `class`(negated: Bool, ranges: [ClosedRange<Character>])
    }

    static func matches(_ pattern: String, _ branch: String) -> Bool {
        guard let tokens = parse(pattern) else { return false }
        let name = Array(branch)
        // matched[t][i]: tokens[t...] match name[i...]. Filled from the end, so each is decided once.
        var matched = Array(repeating: Array(repeating: false, count: name.count + 1), count: tokens.count + 1)
        matched[tokens.count][name.count] = true
        for t in tokens.indices.reversed() {
            // Whether the next token matches from some position at or after i, for `**`.
            var nextFromHereOn = false
            for i in (0...name.count).reversed() {
                nextFromHereOn = nextFromHereOn || matched[t + 1][i]
                let next = i < name.count ? name[i] : nil
                let one = next.map { $0 != "/" } ?? false
                switch tokens[t] {
                case .char(let c):
                    matched[t][i] = next == c && matched[t + 1][i + 1]
                case .one:
                    matched[t][i] = one && matched[t + 1][i + 1]
                case .class(let negated, let ranges):
                    matched[t][i] = one && ranges.contains { $0.contains(next!) } != negated && matched[t + 1][i + 1]
                case .star:
                    matched[t][i] = matched[t + 1][i] || (one && matched[t][i + 1])
                case .deepStar:
                    let noFolder = t + 1 < tokens.count && tokens[t + 1] == .char("/") && matched[t + 2][i]
                    matched[t][i] = noFolder || nextFromHereOn
                }
            }
        }
        return matched[0][0]
    }

    private static func parse(_ pattern: String) -> [Token]? {
        var tokens: [Token] = []
        var chars = pattern.makeIterator()
        var peeked: Character?
        func next() -> Character? {
            defer { peeked = nil }
            return peeked ?? chars.next()
        }
        func peek() -> Character? {
            if peeked == nil { peeked = chars.next() }
            return peeked
        }
        while let c = next() {
            switch c {
            case "*" where peek() == "*":
                _ = next()
                tokens.append(.deepStar)
            case "*":
                tokens.append(.star)
            case "?":
                tokens.append(.one)
            case "[":
                let negated = peek() == "!" || peek() == "^"
                if negated { _ = next() }
                var ranges: [ClosedRange<Character>] = []
                // A `]` first in the class is one of its characters.
                var first = true
                while true {
                    guard let c = next() else { return nil }
                    if c == "]" && !first { break }
                    first = false
                    var end = c
                    if peek() == "-" {
                        _ = next()
                        if let after = peek(), after != "]" {
                            end = next()!
                        } else {
                            ranges.append("-"..."-")
                        }
                    }
                    // A reversed range, such as `z-a`, holds nothing, as on the host.
                    if c <= end { ranges.append(c...end) }
                }
                tokens.append(.class(negated: negated, ranges: ranges))
            default:
                tokens.append(.char(c))
            }
        }
        return tokens
    }
}
