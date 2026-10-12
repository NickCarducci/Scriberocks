import Foundation
import Combine

final class RockEditorViewModel: ObservableObject {
    @Published var text: String
    @Published var isDiamond: Bool
    @Published private(set) var isDeleted = false

    private let store: RockStore
    private let original: Rock?

    init(rockID: Rock.ID, store: RockStore) {
        self.store = store
        original = store.rocks.first { $0.id == rockID }
        text = original?.text ?? ""
        isDiamond = original?.isDiamond ?? false
    }

    var exists: Bool { original != nil && !isDeleted }
    var createdAt: Date? { original?.createdAt }

    /// Writes edits back to the store. Empty text is not saved.
    func commit() {
        guard let original, !isDeleted else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var edited = original
        edited.text = trimmed
        edited.isDiamond = isDiamond
        store.update(edited)
    }

    func delete() {
        guard let original else { return }
        store.delete([original.id])
        isDeleted = true
    }
}
