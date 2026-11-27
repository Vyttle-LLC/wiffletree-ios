import Foundation
import Testing
@testable import WiffletreeKit

/// The desktop's `crates/workspace-desktop/src/file_links.rs` cases, as the iPhone reads them.
struct FileLinksTests {
    /// `markdown` linked as the host would answer, finding a file for each reference `found` names.
    private func link(_ markdown: String, _ found: (String) -> String?) -> String {
        let files = FileLinks.references(in: markdown).reduce(into: [String: String]()) { files, reference in
            files[reference] = found(reference)
        }
        return FileLinks.linked(markdown, files: files)
    }

    /// The destination a link to `path` is written with.
    private func to(_ path: String) -> String { "<\(FileLinks.url(for: path).absoluteString)>" }

    @Test func pathsWithLocationsAreReferences() {
        #expect(FileLinks.reference("crates/foo/src/bar.rs") == "crates/foo/src/bar.rs")
        #expect(FileLinks.reference("bar.rs:63") == "bar.rs")
        #expect(FileLinks.reference("bar.rs:63:5") == "bar.rs")
        #expect(FileLinks.reference("bar.rs:63-70") == "bar.rs")
        #expect(FileLinks.reference("/abs/bar.rs") == "/abs/bar.rs")
        #expect(FileLinks.reference("~/notes.md") == "~/notes.md")
        #expect(FileLinks.reference(" README.md, ") == "README.md")
        #expect(FileLinks.reference("bar.rs:63.") == "bar.rs")
    }

    @Test func urlsAndShellSyntaxAreNotReferences() {
        #expect(FileLinks.reference("cargo test | tail") == nil)
        #expect(FileLinks.reference("https://example.com/a.rs") == nil)
        #expect(FileLinks.reference("`bar.rs`") == nil)
        #expect(FileLinks.reference("echo $HOME/x.rs") == nil)
        #expect(FileLinks.reference("..") == nil)
        #expect(FileLinks.reference("~") == nil)
    }

    @Test func onlyCodeNamingAFileBecomesALink() {
        let found = { (reference: String) in ["src/a b.rs", "x.rs"].contains(reference) ? "/w/\(reference)" : nil }
        #expect(link("See `src/a b.rs:63`, then run `cargo test`.", found) == "See [`src/a b.rs:63`](\(to("/w/src/a b.rs"))), then run `cargo test`.")
        #expect(link("`missing.rs` stays", found) == "`missing.rs` stays")
        #expect(link("[`x.rs`](https://example.com) and ``x.rs``", found) == "[`x.rs`](https://example.com) and [``x.rs``](\(to("/w/x.rs")))")
        #expect(link("```\n`x.rs`\n```", found) == "```\n`x.rs`\n```")
        #expect(link("Wow!`x.rs`", found) == "Wow!`x.rs`")
    }

    @Test func absoluteAndHomePathsInProseLinkWithoutTheirPunctuation() {
        let found = { (reference: String) in
            ["/w/mockup.html", "~/notes.md", "/w/a.rs"].contains(reference) ? reference.replacingOccurrences(of: "~", with: "/Users/m") : nil
        }
        #expect(link("See this mockup: /w/mockup.html.", found) == "See this mockup: [/w/mockup.html](\(to("/w/mockup.html"))).")
        #expect(link("Read ~/notes.md, then (/w/a.rs:12): done", found) == "Read [~/notes.md](\(to("/Users/m/notes.md"))), then ([/w/a.rs:12](\(to("/w/a.rs")))): done")
        #expect(link("- '/w/a.rs' and **/w/mockup.html**", found) == "- '[/w/a.rs](\(to("/w/a.rs")))' and **[/w/mockup.html](\(to("/w/mockup.html")))**")
    }

    @Test func pathsInCodeLinksAndURLsStayAsWritten() {
        for body in [
            "```\n/w/a.rs\n```",
            "[see /w/a.rs](https://example.com)",
            "<file:///w/a.rs>",
            "https://example.com/w/a.rs and www.example.com/w/a.rs",
            "`file:///w/a.rs` and ```file:///w/a.rs```",
            "[file:///w/a.rs](https://example.com) and see/w/a.rs",
            "https://example.com/?next=file:///w/a.rs and xfile:///w/a.rs",
            "and/or, 1/2, / alone, ~ and ~user/a.rs",
            "![screenshot](/w/shot.png)",
        ] {
            #expect(link(body) { "/w/\($0)" } == body)
        }
    }

    @Test func bareFileURLsInProseLinkAsOneLinkWithoutTheirPunctuation() {
        let found = { (reference: String) in ["/w/mockup.html", "/tmp/a b.md", "/w/a.rs"].contains(reference) ? reference : nil }
        #expect(link("It is at file:///w/mockup.html, beside it.", found) == "It is at [file:///w/mockup.html](\(to("/w/mockup.html"))), beside it.")
        #expect(link("Open (file:///w/a.rs:12). Then file:///tmp/a%20b.md.", found) == "Open ([file:///w/a.rs:12](\(to("/w/a.rs")))). Then [file:///tmp/a%20b.md](\(to("/tmp/a b.md"))).")
        #expect(link("see file:///w/gone.rs and file://host/w/a.rs and file://", found) == "see file:///w/gone.rs and file://host/w/a.rs and file://")
    }

    @Test func markdownLinksToPathsLinkToTheFileOrLoseTheirLink() {
        let found = { (reference: String) -> String? in
            switch reference {
            case "/Users/me/project/mockup.html", "/tmp/a b.md": reference
            case "docs/PRD.md": "/w/docs/PRD.md"
            default: nil
            }
        }
        #expect(link("See [mockup.html](/Users/me/project/mockup.html).", found) == "See [mockup.html](\(to("/Users/me/project/mockup.html"))).")
        #expect(link("[the PRD](docs/PRD.md#formatting) and [notes](<file:///tmp/a%20b.md>)", found) == "[the PRD](\(to("/w/docs/PRD.md"))) and [notes](\(to("/tmp/a b.md")))")
        #expect(link("[a b](</tmp/a b.md>)", found) == "[a b](\(to("/tmp/a b.md")))")
        #expect(link("[gone](/w/gone.md) and [web](https://example.com/a.md)", found) == "gone and [web](https://example.com/a.md)")
    }

    @Test func eachReferenceIsAskedAboutOnce() {
        let body = "`a.rs` and /w/b.md, then `a.rs:4` again and [b](/w/b.md); `https://x.y` is not a path."
        #expect(FileLinks.references(in: body) == ["a.rs", "/w/b.md"])
    }

    @Test func linkTargetsTellLocalPathsFromWebURLs() {
        #expect(FileLinks.localTarget("https://github.com/x") == nil)
        #expect(FileLinks.localTarget("mailto:a@b.c") == nil)
        #expect(FileLinks.localTarget("#heading") == nil)
        #expect(FileLinks.localTarget("file:///tmp/a%20b.md") == "/tmp/a b.md")
        #expect(FileLinks.localTarget("/tmp/a%20b.md") == "/tmp/a b.md")
        #expect(FileLinks.localTarget("LICENSE:12") == "LICENSE:12")
        #expect(FileLinks.localTarget("src/main.rs#L12") == "src/main.rs")
        #expect(FileLinks.localTarget("docs/a.md?plain=1") == "docs/a.md")
    }

    @Test func aFileLinkCarriesItsPathThroughTheURL() {
        for path in ["/Users/me/a b #1%.md", "/w/(draft) é.png"] {
            #expect(FileLinks.path(of: FileLinks.url(for: path)) == path)
        }
        #expect(FileLinks.path(of: URL(string: "https://example.com/a.md")!) == nil)
    }

    @Test func imagesAreKnownByTheirExtension() {
        for path in ["/w/a.png", "/w/b.JPG", "/w/c.jpeg", "/w/d.gif", "/w/e.heic", "/w/f.webp"] {
            #expect(FileLinks.isImage(path))
        }
        for path in ["/w/a.html", "/w/b.md", "/w/png", "/w/c.svg"] {
            #expect(!FileLinks.isImage(path))
        }
    }
}
