import Foundation
import Combine
import ScribeCore

/// Loads the on-device language engine (bundled `Models/`) once, off the main
/// thread, and serves suggestions from a cache. Suggestions for what you're
/// likely to look at next (a rock's other versions, the neighboring rocks) are
/// prepared in the background, so swiping to them is instant.
final class SuggestionEngine: ObservableObject {
    enum State {
        case loading
        case ready
        case unavailable(String)
    }

    @Published private(set) var state: State = .loading
    /// Bumped when background work adds to the cache, so views re-read it.
    @Published private(set) var cacheVersion = 0
    private var engine: ScribeEngine?
    private var cache = SuggestionCache<[RockVariant]>(capacity: 64)
    private var prefetching: Task<Void, Never>?
    nonisolated static let limit: UInt32 = 40
    /// The loading animation shows at least this long, so it never just flashes.
    static let minimumLoading: Duration = .milliseconds(500)

    init(modelsURL: URL? = Bundle.main.url(forResource: "Models", withExtension: nil)) {
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
                self.state = .ready
            case .failure(let error):
                self.state = .unavailable(error.localizedDescription)
            }
        }
    }

    /// Other cuts of `text`, best first. Empty until the engine is ready.
    func variants(for text: String) -> [RockVariant] {
        guard let engine else { return [] }
        if let hit = cache[text] { return hit }
        let result = engine.variants(rock: text, limit: Self.limit)
        cache[text] = result
        return result
    }

    /// Prepares suggestions for `texts` in the background, one at a time,
    /// skipping any already cached. A new call replaces the previous queue.
    func prefetch(_ texts: [String]) {
        guard let engine else { return }
        let todo = texts.filter { cache.peek($0) == nil }
        prefetching?.cancel()
        guard !todo.isEmpty else { return }
        let worker = engine
        prefetching = Task { [weak self] in
            for text in todo {
                if Task.isCancelled { return }
                let result = await Task.detached(priority: .utility) {
                    worker.variants(rock: text, limit: SuggestionEngine.limit)
                }.value
                guard let self, !Task.isCancelled else { return }
                if self.cache.peek(text) == nil {
                    self.cache[text] = result
                    self.cacheVersion += 1
                }
            }
        }
    }
}
