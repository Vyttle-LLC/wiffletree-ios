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

/// GitHub's branch patterns: `*` matches within one path segment, `**` across segments and `?`
/// one character other than `/`; anything else matches itself.
enum BranchPattern {
    static func matches(_ pattern: String, _ branch: String) -> Bool {
        let pattern = Array(pattern), name = Array(branch)
        // matched[i][j]: pattern[i...] matches name[j...].
        var matched = Array(repeating: Array(repeating: false, count: name.count + 1), count: pattern.count + 1)
        matched[pattern.count][name.count] = true
        for i in stride(from: pattern.count - 1, through: 0, by: -1) {
            let isDoubleStar = pattern[i] == "*" && i + 1 < pattern.count && pattern[i + 1] == "*"
            for j in stride(from: name.count, through: 0, by: -1) {
                switch pattern[i] {
                case "*" where isDoubleStar:
                    matched[i][j] = matched[i + 2][j] || (j < name.count && matched[i][j + 1])
                case "*":
                    matched[i][j] = matched[i + 1][j] || (j < name.count && name[j] != "/" && matched[i][j + 1])
                case "?":
                    matched[i][j] = j < name.count && name[j] != "/" && matched[i + 1][j + 1]
                default:
                    matched[i][j] = j < name.count && name[j] == pattern[i] && matched[i + 1][j + 1]
                }
            }
        }
        return matched[0][0]
    }
}
