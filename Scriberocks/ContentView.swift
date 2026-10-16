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
            Tab("Rocks", systemImage: "fossil.shell", value: .rocks) {
                RocksListView(store: rockStore, path: $rocksPath)
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
        .onAppear {
            // Screenshot/QA hook: `-openNewestRock` opens the newest rock in the editor.
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
