import SwiftUI

/// The app opens on its main feature: the latest rock, full screen, with its
/// suggestions a swipe away. One center button does what fits the moment
/// (new rock, save this suggestion, done). Groups and Profile are buttons at
/// the top; the date in the middle opens the rest of your rocks.
struct HomeView<Groups: View>: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var authState: UserAuthState
    @EnvironmentObject private var rockStore: RockStore
    @EnvironmentObject private var childSafety: ChildSafetyManager

    @StateObject private var composer: WriteViewModel
    /// The rock on screen; nil = the newest.
    @State private var rockID: Rock.ID?
    @State private var composing = false
    @State private var showGroups = false
    @State private var showProfile = false
    @State private var showLibrary = false
    private let groups: () -> Groups

    init(store: RockStore, @ViewBuilder groups: @escaping () -> Groups) {
        _composer = StateObject(wrappedValue: WriteViewModel(store: store))
        self.groups = groups
    }

    private var currentRock: Rock? {
        rockID.flatMap { id in rockStore.rocks.first { $0.id == id } } ?? rockStore.rocks.first
    }

    var body: some View {
        Group {
            if composing || currentRock == nil {
                ComposerView(viewModel: composer, canCancel: currentRock != nil) { saved in
                    if let saved { rockID = saved.id }
                    withAnimation(.snappy) { composing = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let rock = currentRock {
                RockCanvas(rockID: rock.id, store: rockStore) {
                    withAnimation(.snappy) { composing = true }
                } onDeleted: {
                    rockID = nil
                }
                .id(rock.id)
                .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showGroups) { groups().presentationDragIndicator(.visible) }
        .sheet(isPresented: $showProfile) {
            ProfileView(container: container, authState: authState, store: rockStore, childSafety: childSafety)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLibrary) {
            RockLibraryView(store: rockStore) { picked in
                rockID = picked
                composing = false
                showLibrary = false
            }
            .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .onAppear {
            // Screenshot/QA hooks.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-openGroups") { showGroups = true }
            if args.contains("-openProfile") { showProfile = true }
            if args.contains("-openLibrary") { showLibrary = true }
            if args.contains("-compose") { composing = true }
        }
        #endif
    }

    private var topBar: some View {
        HStack {
            ChromeButton(systemImage: "person.3.fill", label: "Groups") { showGroups = true }
            Spacer()
            Button { showLibrary = true } label: {
                HStack(spacing: 6) {
                    Image("rock").imageScale(.small)
                    Text(composing || currentRock == nil ? "New rock" : (currentRock?.createdAt.formatted(.dateTime.month(.abbreviated).day()) ?? ""))
                        .font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(.thinMaterial, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your rocks")
            .accessibilityHint("Opens all your rocks")
            Spacer()
            ChromeButton(systemImage: authState.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle", label: "Profile") { showProfile = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A round, material-backed control for the home chrome.
struct ChromeButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .background(.thinMaterial, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The big center button.
struct PrimaryButton: View {
    let systemImage: String
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Color.accentColor.opacity(enabled ? 1 : 0.35), in: .circle)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .sensoryFeedback(.impact(weight: .medium), trigger: systemImage)
    }
}
