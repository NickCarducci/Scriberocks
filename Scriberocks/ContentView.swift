//
//  ContentView.swift
//  Scriberocks
//

import SwiftUI
import DeclaredAgeRange


/// The app's root: the home screen (latest rock + suggestions), with Groups
/// and Profile a tap away at the top.
struct ContentView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var authState: UserAuthState
    @EnvironmentObject private var rockStore: RockStore
    @EnvironmentObject private var childSafetyManager: ChildSafetyManager
    @Environment(\.requestAgeRange) private var requestAgeRange

    var body: some View {
        HomeView(store: rockStore) { groups }
            .task(id: authState.userId) {
                // Keep the age range (and parental controls) current; see refreshAgeRange.
                if authState.userId != nil { await childSafetyManager.refreshAgeRange(using: requestAgeRange) }
            }
            #if DEBUG
            .overlay {
                if ProcessInfo.processInfo.arguments.contains("-symbolGallery") {
                    SymbolGallery().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.background)
                }
            }
            #endif
    }

    @ViewBuilder
    private var groups: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoGroups") {
            GroupsView(service: InMemoryGroupService.demo, userId: "demo", displayName: "You")
        } else {
            GroupsView(service: container.groupService, userId: authState.userId, displayName: authState.displayName)
                .id(authState.userId)
        }
        #else
        GroupsView(service: container.groupService, userId: authState.userId, displayName: authState.displayName)
            .id(authState.userId)
        #endif
    }
}

#Preview {
    let container = AppContainer(rockSyncService: LocalOnlyRockSyncService())
    ContentView()
        .environmentObject(container)
        .environmentObject(UserAuthState.preview())
        .environmentObject(RockStore.preview())
        .environmentObject(ChildSafetyManager())
        .environmentObject(SuggestionEngine(modelsURL: nil))
}

extension RockStore {
    #if DEBUG
    /// Sample rocks for screenshots/QA (`-demoRocks`): a throwaway local store,
    /// oldest first, one with a revision history. Never touches real rocks.
    static func demo() -> RockStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "demo-rocks-\(UUID()).json")
        let store = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: UserDefaults(suiteName: "demo-rocks")!)
        // `-demoLatest N` makes sample rock N (0-4, as below) the latest, so it opens first.
        let args = ProcessInfo.processInfo.arguments
        let latest = args.firstIndex(of: "-demoLatest").flatMap { i in i + 1 < args.count ? Int(args[i + 1]) : nil } ?? 3
        let samples: [() -> Void] = [
            {
                if let river = store.add(text: "the river bank was quiet this morning and the water looked cold") {
                    store.revise(river.id, to: "The river bank was quiet this morning. The water looked cold.", source: .suggestion)
                    store.revise(river.id, to: "The river bank was still this morning. The water looked cold.", source: .suggestion)
                }
            },
            { _ = store.add(text: "I want to finish the book but I keep getting distracted") },
            { _ = store.add(text: "She gave a brilliant speech about the future of small towns") },
            { _ = store.add(text: "i think the meeting was really kind of long and we didnt decide anything") },
            // A long rock (scrolls; only the strike box is scored).
            { _ = store.add(text: """
                We left before sunrise. The road was empty and the fields were grey. My brother wanted to stop for coffee but we kept going.

                By noon the hills had turned green. We ate lunch by a small lake. The water was very cold and nobody swam.

                In the afternoon it started to rain. We found a cheap motel near the highway. The room smelled of old carpet but the beds were soft.

                That night we talked about our father. He used to drive this same road every summer. I think he would have liked the trip.
                """) },
        ]
        for (i, add) in samples.enumerated() where i != latest { add() }
        if samples.indices.contains(latest) { samples[latest]() }
        return store
    }
    #endif

    static func preview() -> RockStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "preview-rocks-\(UUID()).json")
        let store = RockStore(sync: LocalOnlyRockSyncService(), fileURL: url, defaults: UserDefaults(suiteName: "preview")!)
        store.add(text: "Walked the long way home. The river was loud.")
        store.add(text: "A second rock for previews.")
        return store
    }
}

#if DEBUG
extension InMemoryGroupService {
    /// Screenshot/QA data for `-demoGroups`.
    static let demo: InMemoryGroupService = {
        let s = InMemoryGroupService()
        s.seedGroup(RockGroup(id: "commons", name: "Commons", about: "Share a rock with everyone.", reportsToHide: 2))
        s.seedGroup(RockGroup(id: "young", name: "Young Writers", about: "For writers under 18, with a guardian's OK.", reportsToHide: 1, minorsOnly: true))
        Task {
            try? await s.join(groupId: "commons", userId: "demo", displayName: "You", guardianApproved: false)
            try? await s.acceptTerms(version: CommunityTerms.version, userId: "demo")
        }
        s.seed(GroupPost(id: "1", groupId: "commons", authorId: "ana", authorName: "Ana", text: "The river was loud, so we walked the long way home.", createdAt: .now.addingTimeInterval(-3600), reportedBy: [], review: nil))
        s.seed(GroupPost(id: "2", groupId: "commons", authorId: "demo", authorName: "You", text: "First rock in the Commons.", createdAt: .now.addingTimeInterval(-600), reportedBy: ["x", "y"], review: nil))
        return s
    }()
}
#endif
