import Foundation

/// Word-level comparison of the current text with an option, for the inline
/// preview: kept words plain, removed words struck through, added words
/// highlighted. Words and punctuation are separate tokens, so "loud." against
/// "loud and ... warm." keeps "loud" and the period. Line breaks are tokens
/// too, so paragraphs survive the preview.
enum InlineDiff {
    struct Part: Equatable {
        enum Kind: Equatable { case kept, removed, added }
        var text: String
        var kind: Kind
    }

    static func tokens(_ text: String) -> [String] {
        let pattern = #"\n[\s]*\n|\n|[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*|[^\s\p{L}\p{N}]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Longest common subsequence of tokens (case-sensitive); removals come
    /// before additions at each change.
    static func parts(from old: String, to new: String) -> [Part] {
        let a = tokens(old), b = tokens(new)
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [Part] = []
        var (i, j) = (0, 0)
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                out.append(Part(text: a[i], kind: .kept)); i += 1; j += 1
            } else if i < a.count, j == b.count || lcs[i + 1][j] >= lcs[i][j + 1] {
                out.append(Part(text: a[i], kind: .removed)); i += 1
            } else {
                out.append(Part(text: b[j], kind: .added)); j += 1
            }
        }
        return out
    }

    /// Tokens joined with spaces, except before closing punctuation and after
    /// opening punctuation.
    static func joined(_ tokens: [String]) -> String {
        var out = ""
        for (k, t) in tokens.enumerated() {
            if k > 0, spaced(tokens[k - 1], t) { out += " " }
            out += t
        }
        return out
    }

    /// Whether a space goes between two tokens when they're shown together.
    static func spaced(_ previous: String, _ next: String) -> Bool {
        !noSpaceBefore.contains(next) && !noSpaceAfter.contains(previous) && !previous.contains("\n") && !next.contains("\n")
    }

    static let noSpaceBefore: Set<String> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "'", "’", "”", "%"]
    static let noSpaceAfter: Set<String> = ["(", "[", "{", "“", "$"]
}
