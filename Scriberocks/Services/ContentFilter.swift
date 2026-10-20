import Foundation

nonisolated enum FilterVerdict: Equatable, Sendable {
    case allowed
    /// Not posted; the writer is asked to rephrase. The reason is for them.
    case flagged(String)
}

/// Screens text before it's shared to a group (Guideline 1.2: "a method for
/// filtering objectionable material from being posted").
protocol ContentFilter: Sendable {
    func check(_ text: String) async -> FilterVerdict
}

/// Runs filters in order; the first flag wins.
nonisolated struct LayeredFilter: ContentFilter {
    var layers: [any ContentFilter]

    func check(_ text: String) async -> FilterVerdict {
        for layer in layers {
            let verdict = await layer.check(text)
            if verdict != .allowed { return verdict }
        }
        return .allowed
    }

    /// The app's filter. No Apple on-device models (Foundation Models): the
    /// language engine stays usable on older iOS, and filtering doesn't depend
    /// on Apple Intelligence. Another layer (e.g. a scribe-based classifier)
    /// can be added here.
    static let standard = LayeredFilter(layers: [WordListFilter()])
}

/// Whole words and phrases from a list, matched case-insensitively after
/// undoing common character swaps (0→o, 1→i, $→s, …). Matching is by whole
/// tokens, so innocent words that contain a listed one aren't flagged.
nonisolated struct WordListFilter: ContentFilter {
    private let phrases: [[String]]

    init(terms: [String] = WordListFilter.defaultTerms) {
        phrases = terms.map(Self.tokens).filter { !$0.isEmpty }
    }

    func check(_ text: String) async -> FilterVerdict {
        let words = Self.tokens(text)
        for phrase in phrases where phrase.count <= words.count {
            for start in 0...(words.count - phrase.count) where Array(words[start..<start + phrase.count]) == phrase {
                return .flagged("This includes language that isn't allowed in groups.")
            }
        }
        return .allowed
    }

    static func tokens(_ text: String) -> [String] {
        let swaps: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"]
        let mapped = String(text.lowercased().map { swaps[$0] ?? $0 })
        return mapped.split { !$0.isLetter }.map(String.init)
    }

    /// Severe slurs, threats and incitement to self-harm, matched as whole
    /// words or phrases (short on purpose, to avoid false positives); reports
    /// and moderation catch what a list can't.
    static let defaultTerms: [String] = [
        // Incitement to self-harm and threats
        "kys", "kill yourself", "go die", "hang yourself", "i will kill you", "im going to kill you",
        // Severe slurs
        "nigger", "nigga", "faggot", "fag", "retard", "tranny", "kike", "spic", "chink", "wetback", "gook", "dyke",
    ]
}
