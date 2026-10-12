//
//  ContentView.swift
//  Scriberocks
//

import SwiftUI

enum AppTab: Hashable {
    case write, rocks, profile
}

struct ContentView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var authState: UserAuthState
    @EnvironmentObject private var rockStore: RockStore
    @EnvironmentObject private var childSafetyManager: ChildSafetyManager

    @State private var selection: AppTab = .write

    var body: some View {
        TabView(selection: $selection) {
            Tab("Write", systemImage: "pencil.and.outline", value: .write) {
                WriteView(store: rockStore) { selection = .rocks }
            }
            Tab("Rocks", systemImage: "fossil.shell", value: .rocks) {
                RocksListView(store: rockStore)
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
    }
}

#Preview {
    let container = AppContainer(rockSyncService: LocalOnlyRockSyncService())
    ContentView()
        .environmentObject(container)
        .environmentObject(UserAuthState.preview())
        .environmentObject(RockStore.preview())
        .environmentObject(ChildSafetyManager())
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
