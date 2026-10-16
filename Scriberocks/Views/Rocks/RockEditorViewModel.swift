import Foundation
import Combine

final class RockEditorViewModel: ObservableObject {
    /// The text being edited; becomes a new revision on commit.
    @Published var text: String
    @Published var isDiamond: Bool {
        didSet {
            if let rock, rock.isDiamond != isDiamond { store.toggleDiamond(rock) }
        }
    }
    @Published private(set) var isDeleted = false

    let rockID: Rock.ID
    let store: RockStore
    private var cancellables = Set<AnyCancellable>()

    init(rockID: Rock.ID, store: RockStore) {
        self.rockID = rockID
        self.store = store
        let rock = store.rocks.first { $0.id == rockID }
        text = rock?.text ?? ""
        isDiamond = rock?.isDiamond ?? false
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var rock: Rock? { store.rocks.first { $0.id == rockID } }
    var exists: Bool { rock != nil && !isDeleted }
    var createdAt: Date? { rock?.createdAt }

    // MARK: - History (‹ ›)

    var canGoBack: Bool { rock?.canGoBack ?? false }
    var canGoForward: Bool { rock?.canGoForward ?? false }

    /// "3 of 5", or nil when there's only one revision.
    var revisionLabel: String? {
        guard let rock, rock.revisions.count > 1 else { return nil }
        return "\(rock.revisionIndex + 1) of \(rock.revisions.count)"
    }

    func goBack() { step(-1) }
    func goForward() { step(1) }

    private func step(_ delta: Int) {
        commit()
        guard let rock else { return }
        store.showRevision(rockID, index: rock.revisionIndex + delta)
        text = self.rock?.text ?? text
    }

    // MARK: - Changes

    /// Saves typed changes as a new revision. Empty text is not saved.
    func commit() {
        guard let rock, !isDeleted, text != rock.text else { return }
        store.revise(rockID, to: text, source: .edited)
    }

    /// Replaces the text with an accepted suggestion (a new revision).
    func accept(suggestion: String) {
        commit()
        store.revise(rockID, to: suggestion, source: .suggestion)
        text = rock?.text ?? suggestion
    }

    func delete() {
        store.delete([rockID])
        isDeleted = true
    }
}
