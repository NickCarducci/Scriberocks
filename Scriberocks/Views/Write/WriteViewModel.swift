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

    /// Saves the draft as a new rock and clears it. Nil if empty.
    @discardableResult
    func save() -> Rock? {
        guard let rock = store.add(text: draft) else { return nil }
        draft = ""
        return rock
    }
}
