//
//  ContentView.swift
//  Scriberocks
//

import SwiftUI

enum AppTab: Hashable {
    case write, rocks, groups, profile
}

struct ContentView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var authState: UserAuthState
    @EnvironmentObject private var rockStore: RockStore
    @EnvironmentObject private var childSafetyManager: ChildSafetyManager

    @State private var selection: AppTab = .write
    /// Open rock in the Rocks tab; saving a new rock opens it here.
    @State private var rocksPath: [Rock.ID] = []

    var body: some View {
        TabView(selection: $selection) {
            Tab("Write", systemImage: "pencil.and.outline", value: .write) {
                WriteView(store: rockStore) { rock in
                    rocksPath = [rock.id]
                    selection = .rocks
                }
            }
            Tab("Rocks", image: "rock", value: .rocks) {
                RocksListView(store: rockStore, path: $rocksPath)
            }
            Tab("Groups", systemImage: "person.3", value: .groups) {
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
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                ProfileView(
                    container: container,
                    authState: authState,
                    store: rockStore,
                    childSafety: childSafetyManager
                )
            }
        }
        #if DEBUG
        .overlay {
            if ProcessInfo.processInfo.arguments.contains("-symbolGallery") {
                SymbolGallery().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.background)
            }
        }
        .onAppear {
            // Screenshot/QA hook: `-openNewestRock` opens the newest rock in the editor.
            if ProcessInfo.processInfo.arguments.contains("-openGroups") { selection = .groups }
            if ProcessInfo.processInfo.arguments.contains("-openNewestRock"), let rock = rockStore.rocks.first {
                selection = .rocks
                rocksPath = [rock.id]
            }
        }
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
        if let diamond = store.add(text: "A diamond is the final draft.") {
            store.toggleDiamond(diamond)
        }
        return store
    }
}

#if DEBUG
extension InMemoryGroupService {
    /// Screenshot/QA data for `-demoGroups`.
    static let demo: InMemoryGroupService = {
        let s = InMemoryGroupService()
        s.seedGroup(RockGroup(id: "commons", name: "Commons", about: "Share a rock with everyone.", reportsToHide: 2))
        s.seedGroup(RockGroup(id: "young", name: "Young Writers", about: "For writers under 18, with a guardian's OK.", reportsToHide: 1))
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
