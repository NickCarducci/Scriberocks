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
