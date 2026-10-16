//
//  ScriberocksApp.swift
//  Scriberocks
//
//  Created by Nicholas Carducci on 5/7/23.
//

import SwiftUI
import DeclaredAgeRange // Required at the app's entry point for requestAgeRange.
import FirebaseCore

@main
struct ScriberocksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var container: AppContainer
    @StateObject private var authState: UserAuthState
    @StateObject private var rockStore: RockStore
    @StateObject private var childSafetyManager = ChildSafetyManager()
    @StateObject private var suggestionEngine = SuggestionEngine()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The delegate isn't guaranteed to run before this init, and
        // UserAuthState touches Auth.auth() immediately.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        let container = AppContainer()
        _container = StateObject(wrappedValue: container)
        _authState = StateObject(wrappedValue: UserAuthState())
        _rockStore = StateObject(wrappedValue: RockStore(sync: container.rockSyncService))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .environmentObject(authState)
                .environmentObject(rockStore)
                .environmentObject(childSafetyManager)
                .environmentObject(suggestionEngine)
                .task(id: authState.userId) {
                    await rockStore.setUser(authState.userId)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up edits made on the web while the app was in the background.
            if phase == .active {
                Task { await rockStore.refresh() }
            }
        }
    }
}
