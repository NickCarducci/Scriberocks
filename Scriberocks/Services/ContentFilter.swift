import Foundation
import FoundationModels

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

    /// The app's filter: the word list everywhere, then Apple's on-device
    /// model where Apple Intelligence is available.
    static let standard = LayeredFilter(layers: [WordListFilter(), OnDeviceModelFilter()])
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

    /// Severe slurs, threats and incitement to self-harm. Kept short on
    /// purpose: the on-device model handles context; this list is the floor
    /// on every device.
    static let defaultTerms: [String] = [
        // Incitement to self-harm and threats
        "kys", "kill yourself", "go die", "hang yourself", "i will kill you", "im going to kill you",
        // Severe slurs
        "nigger", "nigga", "faggot", "fag", "retard", "tranny", "kike", "spic", "chink", "wetback", "gook", "dyke",
    ]
}

/// Apple's on-device language model (Foundation Models, content-tagging use
/// case) as a moderation check. Text the model's own guardrails refuse to
/// process is flagged too. Where Apple Intelligence isn't available this
/// filter allows everything and the word list stands alone.
nonisolated struct OnDeviceModelFilter: ContentFilter {
    func check(_ text: String) async -> FilterVerdict {
        let model = SystemLanguageModel(useCase: .contentTagging)
        guard case .available = model.availability else { return .allowed }
        let session = LanguageModelSession(model: model, instructions: """
            You moderate posts in a writing community. Answer with exactly one word: \
            FLAG if the post harasses, threatens, sexually exploits, or demeans people for who they are, \
            or encourages self-harm; otherwise OK. Strong language, sad or dark writing, and fiction are OK.
            """)
        do {
            let answer = try await session.respond(to: "Post:\n\(text)").content
            return answer.uppercased().contains("FLAG") ? .flagged("This may break the community terms. Try rephrasing.") : .allowed
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                return .flagged("This may break the community terms. Try rephrasing.")
            default:
                return .allowed
            }
        } catch {
            return .allowed
        }
    }
}
