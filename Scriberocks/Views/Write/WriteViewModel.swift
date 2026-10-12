import Foundation
import Combine

final class WriteViewModel: ObservableObject {
    @Published var draft: String {
        didSet { defaults.set(draft, forKey: Self.draftKey) }
    }

    private let store: RockStore
    private let defaults: UserDefaults
    private static let draftKey = "draft"

    init(store: RockStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        draft = defaults.string(forKey: Self.draftKey) ?? ""
    }

    var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Saves the draft as a new rock and clears it. Returns false if empty.
    @discardableResult
    func save() -> Bool {
        guard store.add(text: draft) != nil else { return false }
        draft = ""
        return true
    }
}
