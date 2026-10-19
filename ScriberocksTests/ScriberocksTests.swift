import Foundation
import Testing
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
        store.toggleDiamond(rock)
        let updated = try #require(store.rocks.first)
        #expect(updated.isDiamond)
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

    @Test func includesHeaderAndStatus() {
        let csv = RocksCSV(rocks: [Rock(text: "x", isDiamond: true)]).csv
        let lines = csv.split(separator: "\n")
        #expect(lines.first == "created_at,updated_at,status,text")
        #expect(lines.last?.hasSuffix(",diamond,x") == true)
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
