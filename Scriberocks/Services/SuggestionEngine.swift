import Foundation
import Combine
import ScribeCore

/// Loads the on-device language engine (bundled `Models/`) once, off the main
/// thread, and serves suggestions from a cache. Suggestions for what you're
/// likely to look at next (a rock's other versions, the neighboring rocks) are
/// prepared in the background, so swiping to them is instant. The writer's
/// options (prose style, variety, Generate) are saved and applied to the engine.
final class SuggestionEngine: ObservableObject {
    enum State {
        case loading
        case ready
        case unavailable(String)
    }

    @Published private(set) var state: State = .loading
    /// Bumped when background work adds to the cache, so views re-read it.
    @Published private(set) var cacheVersion = 0
    /// Prose styles whose judges are bundled ("casual", "publishable"); the app offers only these.
    @Published private(set) var availableStyles: [String] = []
    /// Prose styles with a bundled ScribeIE (Intent-conditioned Editing):
    /// Generate shows when the writer's style is one of these.
    @Published private(set) var generateStyles: [String] = []
    /// The writer's options; changing them re-runs suggestions.
    @Published var options: SuggestionOptions {
        didSet {
            guard options != oldValue else { return }
            options.save(to: defaults)
            applyOptions()
        }
    }
    private let defaults: UserDefaults
    private var engine: ScribeEngine?
    private var cache = SuggestionCache<[RockVariant]>(capacity: 64)
    private var prefetching: Task<Void, Never>?
    nonisolated static let limit: UInt32 = 40
    /// The loading animation shows at least this long, so it never just flashes.
    static let minimumLoading: Duration = .milliseconds(500)

    init(modelsURL: URL? = Bundle.main.url(forResource: "Models", withExtension: nil), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.options = SuggestionOptions(from: defaults)
        guard let path = modelsURL?.path() else {
            state = .unavailable("Language models aren't bundled in this build.")
            return
        }
        Task { [weak self] in
            let started = ContinuousClock.now
            // Load off the main thread; apply the result back on the main actor.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ScribeEngine(modelsDir: path) }
            }.value
            let elapsed = ContinuousClock.now - started
            if elapsed < Self.minimumLoading { try? await Task.sleep(for: Self.minimumLoading - elapsed) }
            guard let self else { return }
            switch result {
            case .success(let engine):
                self.engine = engine
                self.availableStyles = engine.availableStyles()
                self.generateStyles = engine.generateStyles()
                self.applyOptions()
                self.state = .ready
            case .failure(let error):
                self.state = .unavailable(error.localizedDescription)
            }
        }
    }

    /// Hands the options to the engine (dropping a style or Generate it can't
    /// serve) and stops background work prepared under the old ones. Cached
    /// suggestions are keyed by options, so switching back is instant.
    private func applyOptions() {
        guard let engine else { return }
        let effective = options.effective(availableStyles: availableStyles, generateStyles: generateStyles)
        _ = engine.setStyle(name: effective.style)
        engine.setVariety(value: Float(effective.variety))
        engine.setGenerate(enabled: effective.generate)
        prefetching?.cancel()
        cacheVersion += 1
    }

    private func key(_ text: String) -> String {
        options.effective(availableStyles: availableStyles, generateStyles: generateStyles).cacheKey(text)
    }

    /// Other cuts of `text`, best first. Empty until the engine is ready.
    func variants(for text: String) -> [RockVariant] {
        guard let engine else { return [] }
        let key = key(text)
        if let hit = cache[key] { return hit }
        let result = engine.variants(rock: text, limit: Self.limit)
        cache[key] = result
        return result
    }

    /// Suggestions for the struck sentences of a long rock (`StrikeBox`):
    /// only `text[struck]` is scored, and each suggestion is spliced back into
    /// the whole rock, which otherwise stays exactly as written. nil = all of it.
    func variants(for text: String, struck: Range<String.Index>?) -> [RockVariant] {
        guard let struck else { return variants(for: text) }
        return variants(for: String(text[struck])).map { StrikeBox.splice($0, into: text, at: struck) }
    }

    /// Prepares suggestions for `texts` in the background, one at a time,
    /// skipping any already cached. A new call replaces the previous queue.
    func prefetch(_ texts: [String]) {
        guard let engine else { return }
        let todo = texts.map { ($0, key($0)) }.filter { cache.peek($0.1) == nil }
        prefetching?.cancel()
        guard !todo.isEmpty else { return }
        let worker = engine
        prefetching = Task { [weak self] in
            // Cancelled (on the main actor) whenever the options change, so
            // nothing computed under other options is stored under these keys.
            for (text, key) in todo {
                if Task.isCancelled { return }
                let result = await Task.detached(priority: .utility) {
                    worker.variants(rock: text, limit: SuggestionEngine.limit)
                }.value
                guard let self, !Task.isCancelled else { return }
                if self.cache.peek(key) == nil {
                    self.cache[key] = result
                    self.cacheVersion += 1
                }
            }
        }
    }
}

/// The writer's suggestion options, saved in UserDefaults.
struct SuggestionOptions: Equatable {
    /// "" = the default judge; else a prose style ("casual", "publishable").
    var style = ""
    /// 0 = fewer, safer swaps … 1 = more, bolder ones. 0.5 is the engine's default cut-off.
    var variety = 0.5
    /// ScribeIE enhances each proposal. Off by default.
    var generate = false

    static let styleKey = "suggestions.style", varietyKey = "suggestions.variety", generateKey = "suggestions.generate"

    init(style: String = "", variety: Double = 0.5, generate: Bool = false) {
        self.style = style
        self.variety = variety
        self.generate = generate
    }

    init(from defaults: UserDefaults) {
        style = defaults.string(forKey: Self.styleKey) ?? ""
        variety = defaults.object(forKey: Self.varietyKey) as? Double ?? 0.5
        generate = defaults.bool(forKey: Self.generateKey)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(style, forKey: Self.styleKey)
        defaults.set(variety, forKey: Self.varietyKey)
        defaults.set(generate, forKey: Self.generateKey)
    }

    /// What the engine can serve: a style whose judge isn't bundled falls back
    /// to the default, Generate works only in a style with its own ScribeIE,
    /// variety is clamped.
    func effective(availableStyles: [String], generateStyles: [String]) -> SuggestionOptions {
        let style = availableStyles.contains(style) ? style : ""
        return SuggestionOptions(style: style,
                                 variety: min(max(variety, 0), 1),
                                 generate: generate && generateStyles.contains(style))
    }

    /// Whether the Generate switch applies to this style.
    func canGenerate(generateStyles: [String]) -> Bool { generateStyles.contains(style) }

    func cacheKey(_ text: String) -> String {
        "\(style)|\(Int((variety * 100).rounded()))|\(generate)|\(text)"
    }
}
