import Foundation
import Combine

final class RockEditorViewModel: ObservableObject {
    /// The text being edited; becomes a new revision on commit.
    @Published var text: String
    @Published private(set) var isDeleted = false
    /// Inline suggestions: 0 is the current text, 1...n the engine's options.
    /// Swiping only previews; `saveOption` makes the previewed one a revision.
    @Published private(set) var optionIndex = 0

    let rockID: Rock.ID
    let store: RockStore
    private var cancellables = Set<AnyCancellable>()

    init(rockID: Rock.ID, store: RockStore) {
        self.rockID = rockID
        self.store = store
        let rock = store.rocks.first { $0.id == rockID }
        text = rock?.text ?? ""
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
        optionIndex = 0
    }

    // MARK: - Revisions by date

    struct RevisionChoice: Identifiable, Equatable {
        var index: Int
        var date: Date
        var isLatest: Bool
        var isShowing: Bool
        var id: Int { index }
    }

    /// Saved versions, newest first.
    var revisionChoices: [RevisionChoice] {
        guard let rock else { return [] }
        let last = rock.revisions.count - 1
        return rock.revisions.indices.reversed().map {
            RevisionChoice(index: $0, date: rock.revisions[$0].createdAt, isLatest: $0 == last, isShowing: $0 == rock.revisionIndex)
        }
    }

    /// The saved time of the revision `delta` steps from the one showing (for the pull hint).
    func revisionDate(offset delta: Int) -> Date? {
        guard let rock, rock.revisions.indices.contains(rock.revisionIndex + delta) else { return nil }
        return rock.revisions[rock.revisionIndex + delta].createdAt
    }

    func showRevision(_ index: Int) {
        guard let rock else { return }
        step(index - rock.revisionIndex)
    }

    /// A rock always opens on its newest version.
    func showLatest() {
        guard let rock, rock.canGoForward else { return }
        store.showRevision(rockID, index: rock.revisions.count - 1)
        text = self.rock?.text ?? text
        optionIndex = 0
    }

    // MARK: - One row of pages (stories-style)

    enum RowMove: Equatable {
        case option(Int)
        /// Before this rock's text: the newer rock.
        case previousRock
        /// Past this rock's last suggestion: the older rock.
        case nextRock
    }

    /// Where a swipe of `step` pages lands from page `index` (0 = text, 1...count = suggestions).
    static func rowMove(index: Int, step: Int, count: Int) -> RowMove {
        let target = index + step
        if target < 0 { return .previousRock }
        if target > count { return .nextRock }
        return .option(target)
    }

    // MARK: - Branching

    /// Showing an older revision (pulled down in history).
    var isViewingOlderRevision: Bool { canGoForward }

    /// Starts a new rock from `text` (acting on an older revision) and returns
    /// the original to its latest revision, untouched.
    func branch(to text: String) -> Rock.ID? {
        guard let rock else { return nil }
        let latest = rock.revisions.count - 1
        guard let branched = store.add(text: text) else { return nil }
        store.showRevision(rockID, index: latest)
        self.text = self.rock?.text ?? self.text
        optionIndex = 0
        return branched.id
    }

    // MARK: - Center button

    enum PrimaryAction: Equatable {
        /// On the current text: start a new rock.
        case newRock
        /// On a suggestion: keep it as a revision.
        case saveOption
        /// Typing: finish (saves the edit as a revision).
        case done
    }

    func primaryAction(isTyping: Bool) -> PrimaryAction {
        if isTyping { return .done }
        return canSaveOption ? .saveOption : .newRock
    }

    // MARK: - Inline options

    var canSaveOption: Bool { optionIndex > 0 }

    /// Previews option `index` (clamped to 0...count).
    func selectOption(_ index: Int, count: Int) {
        optionIndex = min(max(index, 0), max(count, 0))
    }

    func stepOption(_ delta: Int, count: Int) {
        selectOption(optionIndex + delta, count: count)
    }

    /// Saves the previewed option (`options[optionIndex - 1]`) as a revision.
    func saveOption(_ options: [String]) {
        guard canSaveOption, options.indices.contains(optionIndex - 1) else { return }
        accept(suggestion: options[optionIndex - 1])
    }

    // MARK: - Changes

    /// Saves typed changes as a new revision. Empty text is not saved.
    func commit() {
        // Edits on an older revision become a branch (explicit, confirmed), never
        // a silent revision of the original.
        guard let rock, !isDeleted, text != rock.text, !isViewingOlderRevision else { return }
        store.revise(rockID, to: text, source: .edited)
    }

    /// Replaces the text with an accepted suggestion (a new revision).
    func accept(suggestion: String) {
        commit()
        store.revise(rockID, to: suggestion, source: .suggestion)
        text = rock?.text ?? suggestion
        optionIndex = 0
    }

    func delete() {
        store.delete([rockID])
        isDeleted = true
    }
}
