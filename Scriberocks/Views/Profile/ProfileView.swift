import SwiftUI
import AuthenticationServices
import DeclaredAgeRange

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.requestAgeRange) private var requestAgeRange
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var suggestions: SuggestionEngine
    @State private var confirmDelete = false
    /// The variety slider while dragging; saved (re-running suggestions) on release.
    @State private var variety: Double?

    init(container: AppContainer, authState: UserAuthState, store: RockStore, childSafety: ChildSafetyManager) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(
            container: container,
            authState: authState,
            store: store,
            childSafety: childSafety
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                if viewModel.isSignedIn {
                    ageSection
                }
                writingSection
                journalSection
                aboutSection
            }
            .navigationTitle("Profile")
            .disabled(viewModel.isWorking)
            .overlay {
                if viewModel.isWorking { ProgressView() }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                ),
                presenting: viewModel.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await viewModel.deleteAccount() }
                }
            } message: {
                Text("This permanently deletes your account and its cloud backup. Rocks saved on this device stay here.")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountSection: some View {
        if viewModel.isSignedIn {
            Section {
                LabeledContent {
                    if viewModel.isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: viewModel.syncError == nil ? "checkmark.icloud" : "exclamationmark.icloud")
                            .foregroundStyle(viewModel.syncError == nil ? Color.secondary : Color.orange)
                    }
                } label: {
                    Text(viewModel.accountTitle)
                    if let subtitle = viewModel.accountSubtitle {
                        Text(subtitle)
                    }
                }
                if let syncError = viewModel.syncError {
                    Text(syncError)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button("Sign Out") { viewModel.signOut() }
                Button("Delete Account", role: .destructive) { confirmDelete = true }
            } header: {
                Text("Account")
            } footer: {
                Text("Your rocks are backed up privately to your account.")
            }
        } else {
            Section {
                SignInWithAppleButton(.signIn) { request in
                    viewModel.prepareSignIn(request)
                } onCompletion: { result in
                    Task { await viewModel.completeSignIn(result, requestAgeRange: requestAgeRange) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Account")
            } footer: {
                Text("Optional. Signing in backs up your rocks privately so they follow you to a new phone. Everything works without an account.")
            }
        }
    }

    private var ageSection: some View {
        Section {
            LabeledContent("Age range", value: viewModel.ageBracketLabel)
            Button("Share Age Range…") {
                Task { await viewModel.shareAgeRange(requestAgeRange: requestAgeRange) }
            }
        } footer: {
            Text("Shared by your device through Apple, never your birthday. It stays on this phone and will only be used to involve a parent or guardian before anyone under 18 joins a group.")
        }
    }

    /// Suggestion options; each control shows only when its model is bundled.
    private var writingSection: some View {
        Section {
            if !suggestions.availableStyles.isEmpty {
                Picker("Prose style", selection: $suggestions.options.style) {
                    Text("Default").tag("")
                    ForEach(suggestions.availableStyles, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            VStack(alignment: .leading) {
                Text("Variety")
                Slider(value: Binding(get: { variety ?? suggestions.options.variety }, set: { variety = $0 }), in: 0...1) {
                    Text("Variety")
                } minimumValueLabel: {
                    Text("Safer").font(.caption)
                } maximumValueLabel: {
                    Text("Bolder").font(.caption)
                } onEditingChanged: { editing in
                    if !editing, let variety {
                        suggestions.options.variety = variety
                        self.variety = nil
                    }
                }
            }
            if suggestions.options.canGenerate(generateStyles: suggestions.generateStyles) {
                Toggle("Generate", isOn: $suggestions.options.generate)
            }
        } header: {
            Text("Writing")
        } footer: {
            Text(writingFooter)
        }
    }

    private var writingFooter: String {
        var parts: [String] = []
        if !suggestions.availableStyles.isEmpty { parts.append("Casual knows everyday writing; publishable knows published prose.") }
        parts.append("Variety trades safer word swaps for more of them.")
        if !suggestions.generateStyles.isEmpty {
            parts.append("Generate (\(suggestions.generateStyles.map(\.capitalized).joined(separator: ", "))): ScribeIE puts the suggestions editors would make first, and writes its own version of each, underlined in red.")
        }
        return parts.joined(separator: " ")
    }

    private var journalSection: some View {
        Section("Journal") {
            LabeledContent("Rocks", value: viewModel.rockCount, format: .number)
            ShareLink(
                item: viewModel.csvExport,
                preview: SharePreview("scriberocks.csv", image: Image(systemName: "tablecells"))
            ) {
                Label("Export as CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.rockCount == 0)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: viewModel.appVersion)
        }
    }
}

#Preview("Signed out") {
    ProfileView(
        container: AppContainer(rockSyncService: LocalOnlyRockSyncService()),
        authState: .preview(),
        store: .preview(),
        childSafety: ChildSafetyManager()
    )
    .environmentObject(SuggestionEngine(modelsURL: nil))
}
