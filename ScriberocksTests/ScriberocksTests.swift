import Foundation
import Testing
import DeclaredAgeRange
@testable import Scriberocks

@MainActor
struct RockStoreTests {
    private func makeStore(defaults: UserDefaults) -> (RockStore, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "rocks-\(UUID()).json")
        return (RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: defaults), url)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func migratesLegacyRocksNewestFirst() {
        let defaults = freshDefaults()
        defaults.set(["first", "  ", "second", "third"], forKey: RockStore.legacyDefaultsKey)

        let (store, url) = makeStore(defaults: defaults)

        #expect(store.rocks.map(\.text) == ["third", "second", "first"])
        #expect(defaults.array(forKey: RockStore.legacyDefaultsKey) == nil)
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func persistsAcrossLaunches() {
        let defaults = freshDefaults()
        let (store, url) = makeStore(defaults: defaults)
        store.add(text: "  hello  ")
        store.add(text: "   ")

        let reloaded = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: defaults)
        #expect(reloaded.rocks.map(\.text) == ["hello"])
    }

    @Test func updateTouchesUpdatedAt() throws {
        let (store, _) = makeStore(defaults: freshDefaults())
        let rock = try #require(store.add(text: "draft"))
        store.revise(rock.id, to: "revised", source: .edited)
        let updated = try #require(store.rocks.first)
        #expect(updated.text == "revised")
        #expect(updated.updatedAt >= rock.updatedAt)
    }

    @Test func mergePrefersNewestAndUploadsLocalChanges() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let shared = UUID()
        let localOnly = Rock(text: "local only", createdAt: old)
        let remoteOnly = Rock(text: "remote only", createdAt: new)

        let local = [Rock(id: shared, text: "edited on phone", createdAt: old, updatedAt: new), localOnly]
        let remote = [Rock(id: shared, text: "stale", createdAt: old, updatedAt: old), remoteOnly]

        let result = RockStore.merge(local: local, remote: RemoteRocks(rocks: remote))

        #expect(result.rocks.count == 3)
        #expect(result.rocks.first { $0.id == shared }?.text == "edited on phone")
        #expect(Set(result.needsUpload.map(\.id)) == [shared, localOnly.id])
        #expect(result.rocks.first?.id == remoteOnly.id)
    }

    @Test func pendingLocalDeletionsKeepServerCopiesAway() {
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        let deletedWhileSignedOut = Rock(text: "gone", createdAt: t1)
        let editedElsewhereLater = Rock(text: "edited on web after", createdAt: t1, updatedAt: t2)

        let result = RockStore.merge(
            local: [],
            remote: RemoteRocks(rocks: [deletedWhileSignedOut, editedElsewhereLater]),
            localDeletions: [deletedWhileSignedOut.id: t2, editedElsewhereLater.id: t1]
        )

        #expect(result.rocks.map(\.id) == [editedElsewhereLater.id])
    }

    @Test func deletionsSurviveRelaunch() throws {
        let defaults = freshDefaults()
        let (store, url) = makeStore(defaults: defaults)
        let rock = try #require(store.add(text: "delete me offline"))
        store.delete([rock.id])

        let reloaded = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: defaults)
        let result = RockStore.merge(local: reloaded.rocks, remote: RemoteRocks(rocks: [rock]), localDeletions: [rock.id: .now])
        #expect(result.rocks.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("deletions.json").path()))
    }

    @Test func mergeAppliesDeletionsFromOtherDevices() {
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        let deletedOnWeb = Rock(text: "deleted on web", createdAt: t1)
        let editedAfterDelete = Rock(text: "edited after", createdAt: t1, updatedAt: t2)

        let result = RockStore.merge(
            local: [deletedOnWeb, editedAfterDelete],
            remote: RemoteRocks(tombstones: [deletedOnWeb.id: t2, editedAfterDelete.id: t1])
        )

        #expect(result.rocks.map(\.id) == [editedAfterDelete.id])
        #expect(result.needsUpload.map(\.id) == [editedAfterDelete.id])
    }
}

struct RevisionTests {
    @Test func reviseAppendsAndShowsLatest() {
        var rock = Rock(text: "first")
        rock.revise(to: "second", source: .edited)
        rock.revise(to: "third", source: .suggestion)
        #expect(rock.text == "third")
        #expect(rock.revisions.map(\.source) == [.written, .edited, .suggestion])
        #expect(rock.revisionIndex == 2)
    }

    @Test func steppingBackThenRevisingKeepsAllHistory() {
        var rock = Rock(text: "a")
        rock.revise(to: "b", source: .edited)
        rock.show(revision: 0)
        #expect(rock.text == "a" && rock.canGoForward && !rock.canGoBack)
        rock.revise(to: "c", source: .edited)
        #expect(rock.revisions.map(\.text) == ["a", "b", "c"])
        #expect(rock.revisionIndex == 2)
    }

    @Test func oldRocksDecodeWithOneRevision() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"legacy","createdAt":0,"updatedAt":0,"isDiamond":false}"#
        let rock = try JSONDecoder().decode(Rock.self, from: Data(json.utf8))
        #expect(rock.revisions.map(\.text) == ["legacy"])
        #expect(rock.revisionIndex == 0)
    }

    @Test @MainActor func storeRevisionsSurviveRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rocks-\(UUID()).json")
        let defaults = UserDefaults(suiteName: "rev-\(UUID())")!
        let store = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: defaults)
        let rock = try #require(store.add(text: "rough"))
        store.revise(rock.id, to: "polished", source: .suggestion)
        store.showRevision(rock.id, index: 0)

        let reloaded = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: defaults)
        let saved = try #require(reloaded.rocks.first)
        #expect(saved.text == "rough")
        #expect(saved.revisions.count == 2 && saved.revisionIndex == 0)
    }
}

struct RocksCSVTests {
    @Test func escapesCommasQuotesAndNewlines() {
        #expect(RocksCSV.escape("plain") == "plain")
        #expect(RocksCSV.escape("a,b") == "\"a,b\"")
        #expect(RocksCSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(RocksCSV.escape("line\nbreak") == "\"line\nbreak\"")
    }

    @Test func includesHeaderAndText() {
        let csv = RocksCSV(rocks: [Rock(text: "x")]).csv
        let lines = csv.split(separator: "\n")
        #expect(lines.first == "created_at,updated_at,text")
        #expect(lines.last?.hasSuffix(",x") == true)
    }
}

struct AgeBracketTests {
    @Test(arguments: [
        (nil as Int?, 12 as Int?, AgeBracket.under13),
        (13, 15, .teen13to15),
        (16, 17, .teen16to17),
        (18, nil, .adult),
        (nil, nil, .unknown),
    ])
    func mapsAppleRanges(lower: Int?, upper: Int?, expected: AgeBracket) {
        #expect(AgeBracket.from(lowerBound: lower, upperBound: upper) == expected)
    }

    @Test func nonceHashIsHexSHA256() {
        let nonce = AppleAuthService.randomNonce()
        #expect(nonce.count == 32)
        #expect(AppleAuthService.sha256(nonce).count == 64)
    }
}

/// Inline suggestions: option 0 is the current text; 1...n are the engine's
/// variants. Swiping only previews; Save makes the previewed option a revision.
@MainActor
struct InlineOptionTests {
    private func editor(_ text: String) throws -> (RockEditorViewModel, RockStore) {
        let url = FileManager.default.temporaryDirectory.appending(path: "rocks-\(UUID()).json")
        let store = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: UserDefaults(suiteName: "opt-\(UUID())")!)
        let rock = try #require(store.add(text: text))
        return (RockEditorViewModel(rockID: rock.id, store: store), store)
    }

    @Test func swipingPreviewsWithoutChangingTheRock() throws {
        let (vm, store) = try editor("the rough draft")
        #expect(vm.optionIndex == 0 && !vm.canSaveOption)
        vm.stepOption(1, count: 3)
        vm.stepOption(1, count: 3)
        #expect(vm.optionIndex == 2 && vm.canSaveOption)
        #expect(store.rocks.first?.revisions.count == 1)
    }

    @Test func steppingStaysWithinTheOptions() throws {
        let (vm, _) = try editor("draft")
        vm.stepOption(-1, count: 2)
        #expect(vm.optionIndex == 0)
        vm.selectOption(5, count: 2)
        #expect(vm.optionIndex == 2)
        vm.stepOption(1, count: 2)
        #expect(vm.optionIndex == 2)
    }

    @Test func saveMakesThePreviewedOptionARevision() throws {
        let (vm, store) = try editor("the rough draft")
        vm.selectOption(2, count: 2)
        vm.saveOption(["a rough draft", "the draft"])
        let rock = try #require(store.rocks.first)
        #expect(rock.text == "the draft")
        #expect(rock.revisions.map(\.source) == [.written, .suggestion])
        #expect(vm.text == "the draft" && vm.optionIndex == 0)
    }

    @Test func savingTheCurrentTextDoesNothing() throws {
        let (vm, store) = try editor("draft")
        vm.saveOption(["other draft"])
        #expect(store.rocks.first?.revisions.count == 1)
    }

    @Test func movingThroughHistoryReturnsToTheCurrentText() throws {
        let (vm, _) = try editor("one")
        vm.text = "two"
        vm.commit()
        vm.selectOption(1, count: 1)
        vm.goBack()
        #expect(vm.optionIndex == 0 && vm.text == "one")
    }
}

/// Word-level comparison for the inline preview: what an option keeps,
/// removes and adds relative to the current text.
struct InlineDiffTests {
    private func render(_ parts: [InlineDiff.Part]) -> String {
        parts.map { p in
            switch p.kind {
            case .kept: p.text
            case .removed: "[-\(p.text)]"
            case .added: "[+\(p.text)]"
            }
        }.joined(separator: " ")
    }

    @Test func aCutShowsTheRemovedWords() {
        let parts = InlineDiff.parts(from: "the river was loud and the evening was warm.", to: "the river was loud.")
        #expect(render(parts) == "the river was loud [-and] [-the] [-evening] [-was] [-warm] .")
    }

    @Test func aSwapShowsRemovedThenAdded() {
        let parts = InlineDiff.parts(from: "a big dog", to: "a large dog")
        #expect(render(parts) == "a [-big] [+large] dog")
    }

    @Test func identicalTextIsAllKept() {
        #expect(InlineDiff.parts(from: "same words", to: "same words").allSatisfy { $0.kind == .kept })
    }

    @Test func punctuationAttachesWithoutASpace() {
        #expect(InlineDiff.joined(["Well", ",", "it", "is", "(", "fine", ")", "."]) == "Well, it is (fine).")
    }
}

/// The option pager's swipe: latch an axis after a few points, lock the other
/// one, turn a page only on a clear horizontal swipe, resist past the ends.
struct PageSwipeTests {
    @Test func waitsForMovementBeforeLatching() {
        var swipe = PageSwipe()
        #expect(swipe.update(CGSize(width: 3, height: 2)) == nil)
        #expect(swipe.axis == .undecided)
        #expect(swipe.update(CGSize(width: -12, height: 4)) == -12)
        #expect(swipe.axis == .horizontal)
    }

    @Test func aVerticalLatchIgnoresLaterHorizontalMovement() {
        var swipe = PageSwipe()
        _ = swipe.update(CGSize(width: 2, height: 9))
        #expect(swipe.axis == .vertical)
        #expect(swipe.update(CGSize(width: -80, height: 10)) == nil)
    }

    @Test func turnsAPageOnlyOnAClearHorizontalSwipe() {
        var swipe = PageSwipe()
        _ = swipe.update(CGSize(width: -10, height: 0))
        #expect(swipe.step(translation: CGSize(width: -70, height: 5), predicted: CGSize(width: -90, height: 5), width: 400) == 1)
        #expect(swipe.step(translation: CGSize(width: 70, height: 5), predicted: CGSize(width: 90, height: 5), width: 400) == -1)
        #expect(swipe.step(translation: CGSize(width: -20, height: 0), predicted: CGSize(width: -40, height: 0), width: 400) == 0)
        #expect(swipe.step(translation: CGSize(width: -70, height: 60), predicted: CGSize(width: -90, height: 70), width: 400) == 0, "not 2:1 horizontal")
    }

    @Test func aFlickCountsByWhereItWouldLand() {
        var swipe = PageSwipe()
        _ = swipe.update(CGSize(width: -10, height: 0))
        #expect(swipe.step(translation: CGSize(width: -30, height: 0), predicted: CGSize(width: -200, height: 0), width: 400) == 1)
    }

    @Test func noPageTurnAfterAVerticalLatch() {
        var swipe = PageSwipe()
        _ = swipe.update(CGSize(width: 0, height: 10))
        #expect(swipe.step(translation: CGSize(width: -200, height: 10), predicted: CGSize(width: -300, height: 10), width: 400) == 0)
    }

    @Test func resistsPastTheFirstAndLastPages() {
        #expect(PageSwipe.offset(drag: 90, index: 0, count: 3) == 30)
        #expect(PageSwipe.offset(drag: -90, index: 3, count: 3) == -30)
        #expect(PageSwipe.offset(drag: -90, index: 1, count: 3) == -90)
    }

    @Test func resetForgetsTheLatch() {
        var swipe = PageSwipe()
        _ = swipe.update(CGSize(width: 20, height: 0))
        swipe.reset()
        #expect(swipe.axis == .undecided)
    }
}

/// Asking Apple for the age range: one request at a time, a time limit, and
/// failures reported instead of an endless wait.
@MainActor
struct AgeRangeRequestTests {
    private func manager() -> ChildSafetyManager {
        ChildSafetyManager(defaults: UserDefaults(suiteName: "age-\(UUID())")!)
    }

    @Test func overlappingRequestsShareOneCallToApple() async {
        let m = manager()
        var calls = 0
        let slow: ChildSafetyManager.AgeRequest = { _, _, _ in
            calls += 1
            try await Task.sleep(for: .milliseconds(200))
            return .declinedSharing
        }
        async let a = m.requestAgeRangeIfNeeded(using: slow, force: true)
        async let b = m.requestAgeRangeIfNeeded(using: slow, force: true)
        let (first, second) = await (a, b)
        #expect(calls == 1)
        #expect(first == .declined && second == .declined)
        #expect(m.ageBracket == .declined)
    }

    @Test func aRequestThatNeverAnswersTimesOut() async {
        let m = manager()
        let never: ChildSafetyManager.AgeRequest = { _, _, _ in
            try await Task.sleep(for: .seconds(60))
            return .declinedSharing
        }
        let outcome = await m.requestAgeRangeIfNeeded(using: never, force: true, timeout: .milliseconds(100))
        guard case .failed = outcome else { Issue.record("expected a failure, got \(String(describing: outcome))"); return }
        #expect(m.ageBracket == .unknown)
    }

    @Test func errorsAreReportedNotSwallowed() async {
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        let m = manager()
        let outcome = await m.requestAgeRangeIfNeeded(using: { _, _, _ in throw Boom() }, force: true)
        #expect(outcome == .failed("boom"))
    }

    @Test func aKnownAnswerIsNotRequestedAgainUnlessForced() async {
        let m = manager()
        var calls = 0
        let answer: ChildSafetyManager.AgeRequest = { _, _, _ in calls += 1; return .declinedSharing }
        _ = await m.requestAgeRangeIfNeeded(using: answer, force: true)
        #expect(await m.requestAgeRangeIfNeeded(using: answer) == nil)
        #expect(calls == 1)
    }
}

/// The home screen's center button does the one thing that fits the moment.
@MainActor
struct PrimaryActionTests {
    private func editor() throws -> RockEditorViewModel {
        let url = FileManager.default.temporaryDirectory.appending(path: "rocks-\(UUID()).json")
        let store = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: UserDefaults(suiteName: "pa-\(UUID())")!)
        let rock = try #require(store.add(text: "the rough draft"))
        return RockEditorViewModel(rockID: rock.id, store: store)
    }

    @Test func onTheCurrentTextItStartsANewRock() throws {
        #expect(try editor().primaryAction(isTyping: false) == .newRock)
    }

    @Test func onASuggestionItSavesIt() throws {
        let vm = try editor()
        vm.selectOption(1, count: 3)
        #expect(vm.primaryAction(isTyping: false) == .saveOption)
    }

    @Test func whileTypingItFinishes() throws {
        let vm = try editor()
        vm.selectOption(1, count: 3)
        #expect(vm.primaryAction(isTyping: true) == .done)
    }
}

/// One row, stories-style: a rock's text, then its suggestions; past the last
/// suggestion is the next (older) rock, before the text the previous (newer).
struct RowMoveTests {
    @Test func stepsWithinARockStayInIt() {
        #expect(RockEditorViewModel.rowMove(index: 0, step: 1, count: 3) == .option(1))
        #expect(RockEditorViewModel.rowMove(index: 2, step: -1, count: 3) == .option(1))
    }

    @Test func pastTheEndsMovesBetweenRocks() {
        #expect(RockEditorViewModel.rowMove(index: 3, step: 1, count: 3) == .nextRock)
        #expect(RockEditorViewModel.rowMove(index: 0, step: -1, count: 3) == .previousRock)
        #expect(RockEditorViewModel.rowMove(index: 0, step: 1, count: 0) == .nextRock, "no suggestions: straight to the next rock")
    }

    @Test func onlyTheOuterEndsResist() {
        #expect(PageSwipe.offset(drag: 90, atStart: true, atEnd: false) == 30)
        #expect(PageSwipe.offset(drag: 90, atStart: false, atEnd: false) == 90, "a newer rock is there")
        #expect(PageSwipe.offset(drag: -90, atStart: false, atEnd: true) == -30)
    }
}

/// Vertical pulls move through revision history (Populist's pull rules): only
/// once the drag latches vertical, only from the scroll edge, past a threshold.
struct RevisionPullTests {
    @Test func aPullDownAtTheTopGoesToTheOlderRevision() {
        var s = PageSwipe()
        _ = s.update(CGSize(width: 1, height: 12))
        #expect(s.pull(CGSize(width: 2, height: 80)) == 80)
        #expect(s.pullStep(translation: CGSize(width: 4, height: 130), atTop: true, atBottom: false) == -1)
    }

    @Test func aPullUpAtTheBottomGoesToTheNewerRevision() {
        var s = PageSwipe()
        _ = s.update(CGSize(width: 0, height: -12))
        #expect(s.pullStep(translation: CGSize(width: 0, height: -130), atTop: false, atBottom: true) == 1)
    }

    @Test func noPullMidScrollOrShortOrSideways() {
        var s = PageSwipe()
        _ = s.update(CGSize(width: 0, height: 12))
        #expect(s.pullStep(translation: CGSize(width: 0, height: 130), atTop: false, atBottom: false) == 0, "mid-scroll")
        #expect(s.pullStep(translation: CGSize(width: 0, height: 40), atTop: true, atBottom: false) == 0, "too short")
        var h = PageSwipe()
        _ = h.update(CGSize(width: 12, height: 0))
        #expect(h.pull(CGSize(width: 80, height: 10)) == nil, "a horizontal latch is not a pull")
        #expect(h.pullStep(translation: CGSize(width: 0, height: 130), atTop: true, atBottom: false) == 0)
    }
}

/// Acting on an older revision branches into a new rock; the original stays.
@MainActor
struct BranchTests {
    @Test func branchingStartsANewRockAndLeavesTheOriginalAtItsLatest() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rocks-\(UUID()).json")
        let store = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: UserDefaults(suiteName: "br-\(UUID())")!)
        let rock = try #require(store.add(text: "first"))
        store.revise(rock.id, to: "second", source: .edited)
        let vm = RockEditorViewModel(rockID: rock.id, store: store)
        vm.goBack()
        #expect(vm.isViewingOlderRevision && vm.text == "first")
        let newID = try #require(vm.branch(to: "first, then a fork"))
        #expect(store.rocks.first?.id == newID && store.rocks.first?.text == "first, then a fork")
        let original = try #require(store.rocks.first { $0.id == rock.id })
        #expect(original.text == "second" && original.revisions.count == 2, "original untouched, back at its latest")
    }

    @Test func onTheLatestRevisionThereIsNothingToBranchFrom() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rocks-\(UUID()).json")
        let store = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: UserDefaults(suiteName: "br-\(UUID())")!)
        let rock = try #require(store.add(text: "only"))
        #expect(!RockEditorViewModel(rockID: rock.id, store: store).isViewingOlderRevision)
    }
}

/// Revisions are chosen by when they were saved, newest first, and a rock
/// always opens on its newest.
@MainActor
struct RevisionChoiceTests {
    private func editor() throws -> (RockEditorViewModel, RockStore, Rock.ID) {
        let url = FileManager.default.temporaryDirectory.appending(path: "rocks-\(UUID()).json")
        let store = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: UserDefaults(suiteName: "rc-\(UUID())")!)
        let rock = try #require(store.add(text: "one"))
        store.revise(rock.id, to: "two", source: .edited)
        store.revise(rock.id, to: "three", source: .suggestion)
        return (RockEditorViewModel(rockID: rock.id, store: store), store, rock.id)
    }

    @Test func choicesRunOldestToNewestWithTheLatestMarked() throws {
        let (vm, _, _) = try editor()
        let choices = vm.revisionChoices
        #expect(choices.map(\.index) == [0, 1, 2])
        #expect(choices.map(\.isLatest) == [false, false, true])
        #expect(choices.last?.isShowing == true)
    }

    @Test func pickingADateShowsThatVersion() throws {
        let (vm, _, _) = try editor()
        vm.showRevision(0)
        #expect(vm.text == "one" && vm.isViewingOlderRevision)
        #expect(vm.revisionChoices.first?.isShowing == true)
    }

    @Test func aRockOpensOnItsNewestVersion() throws {
        let (vm, store, id) = try editor()
        vm.showRevision(0)
        let reopened = RockEditorViewModel(rockID: id, store: store)
        reopened.showLatest()
        #expect(reopened.text == "three" && !reopened.isViewingOlderRevision)
    }
}


/// Suggestions are cached (least recently used goes first), so swiping back
/// to a rock or version shows them instantly.
struct SuggestionCacheTests {
    @Test func keepsTheMostRecentlyUsed() {
        var cache = SuggestionCache<Int>(capacity: 2)
        cache["a"] = 1
        cache["b"] = 2
        _ = cache["a"]
        cache["c"] = 3
        #expect(cache["a"] == 1 && cache["c"] == 3)
        #expect(cache["b"] == nil, "least recently used was evicted")
    }

    @Test func overwritingKeepsOneEntry() {
        var cache = SuggestionCache<Int>(capacity: 2)
        cache["a"] = 1
        cache["a"] = 2
        cache["b"] = 3
        #expect(cache["a"] == 2 && cache.count == 2)
    }
}
