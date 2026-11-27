import Foundation

/// File references in a message's Markdown, found by the rules of the desktop's `file_links.rs`:
/// inline code naming a file, such as `` `src/bar.rs:63` ``, an absolute or `~/` path or a
/// `file:///` URL written in prose, and a Markdown link to a local path. Only the host knows which
/// are files, so a message asks it with `ResolvePathsCommand` about `references(in:)`, then shows
/// `linked(_:files:)`. Fenced code, web links and autolinks are left as written.
public enum FileLinks {
    /// The URL scheme of a link to a file on the host.
    public static let scheme = "wiffletree-file"

    /// Each path the Markdown may refer to, once, in order: what to ask the host about.
    public static func references(in markdown: String) -> [String] {
        var seen = Set<String>()
        return candidates(in: markdown).map(\.reference).filter { seen.insert($0).inserted }
    }

    /// The Markdown with each reference the host found in `files`, by reference, linked to its
    /// file. A Markdown link to a local path that is not in `files` loses its link and keeps its
    /// text; any other reference not in `files` stays as written.
    public static func linked(_ markdown: String, files: [String: String]) -> String {
        var linked = ""
        var copied = markdown.startIndex
        for candidate in candidates(in: markdown) {
            let file = files[candidate.reference]
            let written = markdown[candidate.range]
            let replacement: String
            switch (candidate.kind, file) {
            case (.link(let label), let file?):
                replacement = "[\(markdown[label])](<\(url(for: file).absoluteString)>)"
            case (.link(let label), nil):
                replacement = String(markdown[label])
            case (_, let file?):
                replacement = "[\(written)](<\(url(for: file).absoluteString)>)"
            case (_, nil):
                continue
            }
            linked += markdown[copied..<candidate.range.lowerBound] + replacement
            copied = candidate.range.upperBound
        }
        return linked + markdown[copied...]
    }

    /// The link to a file at `path` on the host.
    public static func url(for path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.path = path
        return components.url!
    }

    /// The host path a file link points at; nil for any other URL.
    public static func path(of url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }

    /// Whether the file is an image the chat shows a thumbnail of.
    public static func isImage(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp"]

    // MARK: - Finding references

    struct Candidate: Equatable {
        enum Kind: Equatable {
            case code
            case prose
            /// A Markdown link, with its text's range.
            case link(label: Range<String.Index>)
        }

        /// Where it is written in the Markdown.
        let range: Range<String.Index>
        /// The path it names, without a `:line` location.
        let reference: String
        let kind: Kind
    }

    /// Characters that never appear in a file reference, so code holding them is not looked up.
    private static let notInPaths: Set<Character> = ["`", "*", "?", "|", ";", "$", "\"", "<", ">", "\\"]
    /// Characters that end a path written in prose, besides those never in a path and spaces.
    private static let aroundPaths: Set<Character> = ["(", ")", "[", "]", "{", "}", "'"]
    /// Sentence punctuation after a reference, which is not part of it.
    private static let trailing: Set<Character> = [".", ",", ";", ":", "!", "?"]
    /// What may come just before a path written in prose.
    private static let beforeWords: Set<Character> = ["(", "[", "{", "'", "\"", "*", "_"]
    private static let fileURL = "file:///"

    /// Every reference outside fenced code, in order. Fences open and close as `MarkdownBlock`
    /// reads them, and each other line is read on its own.
    static func candidates(in markdown: String) -> [Candidate] {
        var candidates: [Candidate] = []
        var inFence = false
        var lineStart = markdown.startIndex
        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(where: \.isNewline) ?? markdown.endIndex
            let line = markdown[lineStart..<lineEnd]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
            } else if !inFence {
                candidates += inline(line, of: markdown)
            }
            lineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : lineEnd
        }
        return candidates
    }

    /// The references in one line of inline Markdown.
    private static func inline(_ line: Substring, of markdown: String) -> [Candidate] {
        var candidates: [Candidate] = []
        var at = line.startIndex
        while at < line.endIndex {
            let rest = line[at...]
            let previous = at > line.startIndex ? line[line.index(before: at)] : nil
            switch line[at] {
            case "\\":
                at = line.index(at, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
            case "`":
                let (content, end) = codeSpan(rest)
                // `!` before the new link would make it an image.
                if let content, previous != "!", let path = reference(String(content)) {
                    candidates.append(Candidate(range: at..<end, reference: path, kind: .code))
                }
                at = end
            case "!" where rest.dropFirst().first == "[":
                // An image keeps its own target.
                at = link(rest.dropFirst())?.end ?? line.index(after: at)
            case "[":
                if let link = link(rest) {
                    if let target = localTarget(String(link.destination)) {
                        let path = withoutLocation(target)
                        candidates.append(Candidate(range: at..<link.end, reference: path, kind: .link(label: link.label)))
                    }
                    at = link.end
                } else {
                    at = line.index(after: at)
                }
            case "<":
                at = autolinkEnd(rest) ?? line.index(after: at)
            default:
                if let (candidate, end) = prosePath(rest, after: previous) {
                    if let candidate { candidates.append(candidate) }
                    at = end
                } else {
                    at = line.index(after: at)
                }
            }
        }
        return candidates
    }

    /// The code span starting `text`, with its end, or nil and the end of its opening backticks
    /// when no run of as many closes it.
    private static func codeSpan(_ text: Substring) -> (content: Substring?, end: String.Index) {
        let ticks = text.prefix { $0 == "`" }
        var search = ticks.endIndex
        while let close = text[search...].firstIndex(of: "`") {
            let run = text[close...].prefix { $0 == "`" }
            if run.count == ticks.count {
                var content = text[ticks.endIndex..<close]
                if content.count > 1, content.first == " ", content.last == " " { content = content.dropFirst().dropLast() }
                return (content, run.endIndex)
            }
            search = run.endIndex
        }
        return (nil, ticks.endIndex)
    }

    /// The inline link `[label](destination "title")` starting `text`, or nil when there is none.
    private static func link(_ text: Substring) -> (label: Range<String.Index>, destination: Substring, end: String.Index)? {
        guard let labelEnd = closingBracket(text) else { return nil }
        let label = text.index(after: text.startIndex)..<labelEnd
        let open = text.index(after: labelEnd)
        guard open < text.endIndex, text[open] == "(" else { return nil }
        var rest = text[text.index(after: open)...].drop { $0 == " " }
        let destination: Substring
        if rest.first == "<" {
            guard let close = rest.firstIndex(of: ">") else { return nil }
            destination = rest[rest.index(after: rest.startIndex)..<close]
            rest = rest[rest.index(after: close)...]
        } else {
            var parens = 0
            let end = rest.firstIndex { c in
                if c == "(" { parens += 1 } else if c == ")" { if parens == 0 { return true }; parens -= 1 }
                return c == " "
            } ?? rest.endIndex
            destination = rest[..<end]
            rest = rest[end...]
        }
        guard let close = rest.firstIndex(of: ")") else { return nil }
        return (label, destination, text.index(after: close))
    }

    /// The `]` matching the `[` that starts `text`, past nested brackets and escapes.
    private static func closingBracket(_ text: Substring) -> String.Index? {
        guard text.first == "[" else { return nil }
        var depth = 0
        var escaped = false
        for index in text.indices {
            if escaped {
                escaped = false
                continue
            }
            switch text[index] {
            case "\\": escaped = true
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }

    /// The end of the autolink, such as `<https://example.com>`, starting `text`.
    private static func autolinkEnd(_ text: Substring) -> String.Index? {
        guard let match = text.prefixMatch(of: /<[A-Za-z][A-Za-z0-9+.\-]*:[^<>\s]*>/) else { return nil }
        return match.range.upperBound
    }

    /// An absolute or `~/` path or a `file:///` URL starting a word at `text`, up to a space or a
    /// character no path holds, without trailing sentence punctuation, with the end of the word.
    /// Nil when no such word starts here; a nil candidate when its text cannot be a path.
    private static func prosePath(_ text: Substring, after previous: Character?) -> (Candidate?, String.Index)? {
        let startsWord = previous.map { $0.isWhitespace || beforeWords.contains($0) } ?? true
        let isURL = text.hasPrefix(fileURL)
        guard startsWord, isURL || text.hasPrefix("/") || text.hasPrefix("~/") else { return nil }
        let wordEnd = text.firstIndex { $0.isWhitespace || notInPaths.contains($0) || aroundPaths.contains($0) } ?? text.endIndex
        let word = text[..<wordEnd]
        let written = word[..<(word.lastIndex { !trailing.contains($0) }.map(word.index(after:)) ?? word.startIndex)]
        let path = isURL ? percentDecoded(String(written.dropFirst("file://".count))) : String(written)
        let candidate = reference(path).map { Candidate(range: written.startIndex..<written.endIndex, reference: $0, kind: .prose) }
        return (candidate, wordEnd)
    }

    /// The path that inline code or a prose path may refer to, without a trailing `:line` or
    /// `:line:col`; nil when the text cannot be a path, such as a URL or a shell pipeline.
    static func reference(_ code: String) -> String? {
        var code = Substring(code.trimmingCharacters(in: .whitespacesAndNewlines))
        while let last = code.last, trailing.contains(last) { code = code.dropLast() }
        let path = withoutLocation(String(code))
        let plausible = !path.contains("://")
            && !path.contains(where: notInPaths.contains)
            && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !path.trimmingCharacters(in: CharacterSet(charactersIn: "./~")).isEmpty
        return plausible ? path : nil
    }

    /// `code` without a trailing `:63`, `:63:5` or `:63-70`.
    static func withoutLocation(_ code: String) -> String {
        var path = Substring(code)
        for _ in 0..<2 {
            guard let colon = path.lastIndex(of: ":") else { break }
            let location = path[path.index(after: colon)...]
            guard location.first?.isASCII == true, location.first?.isNumber == true,
                  location.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") })
            else { break }
            path = path[..<colon]
        }
        return String(path)
    }

    /// The local path a link points at, without a `#fragment` or `?query` and percent-decoded;
    /// nil for a web or other URL.
    static func localTarget(_ url: String) -> String? {
        if url.hasPrefix("file://") { return percentDecoded(String(url.dropFirst("file://".count))) }
        // `LICENSE:12` is a file and line, not a `LICENSE:` URL.
        let scheme = withoutLocation(url).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let hasScheme = scheme.count == 2 && scheme[0].first?.isLetter == true && scheme[0].first?.isASCII == true
            && scheme[0].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-") }
        let path = url.prefix { $0 != "#" && $0 != "?" }
        return !hasScheme && !path.isEmpty ? percentDecoded(String(path)) : nil
    }

    /// `text` with each `%` and two hex digits replaced by the byte they name.
    static func percentDecoded(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var decoded: [UInt8] = []
        var at = 0
        while at < bytes.count {
            if bytes[at] == UInt8(ascii: "%"), at + 2 < bytes.count,
               let byte = UInt8(String(decoding: bytes[at + 1...at + 2], as: UTF8.self), radix: 16) {
                decoded.append(byte)
                at += 3
            } else {
                decoded.append(bytes[at])
                at += 1
            }
        }
        return String(decoding: decoded, as: UTF8.self)
    }
}
