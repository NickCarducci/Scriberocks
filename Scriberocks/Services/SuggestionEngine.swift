import Foundation
import Combine
import ScribeCore

/// Loads the on-device language engine (bundled `Models/`) once, off the main thread.
final class SuggestionEngine: ObservableObject {
    enum State {
        case loading
        case ready
        case unavailable(String)
    }

    @Published private(set) var state: State = .loading
    private var engine: ScribeEngine?

    init(modelsURL: URL? = Bundle.main.url(forResource: "Models", withExtension: nil)) {
        guard let path = modelsURL?.path() else {
            state = .unavailable("Language models aren't bundled in this build.")
            return
        }
        Task { [weak self] in
            // Load off the main thread; apply the result back on the main actor.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ScribeEngine(modelsDir: path) }
            }.value
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
    func variants(for text: String, limit: UInt32 = 40) -> [RockVariant] {
        engine?.variants(rock: text, limit: limit) ?? []
    }
}
