import SwiftUI
import ScribeCore

struct RockEditorView: View {
    @StateObject private var viewModel: RockEditorViewModel
    @EnvironmentObject private var suggestions: SuggestionEngine
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditing: Bool
    @State private var confirmDelete = false

    init(rockID: Rock.ID, store: RockStore) {
        _viewModel = StateObject(wrappedValue: RockEditorViewModel(rockID: rockID, store: store))
    }

    var body: some View {
        Group {
            if viewModel.exists {
                VStack(spacing: 0) {
                    TextEditor(text: $viewModel.text)
                        .focused($isEditing)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal)
                    if !isEditing {
                        suggestionsBar
                    }
                }
            } else {
                ContentUnavailableView("Rock not found", systemImage: "fossil.shell")
            }
        }
        .navigationTitle(viewModel.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if viewModel.exists {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $viewModel.isDiamond) {
                        Label("Final draft", systemImage: viewModel.isDiamond ? "diamond.fill" : "diamond")
                    }
                    .toggleStyle(.button)
                    .accessibilityHint("Marks this rock as a diamond, your final draft")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Previous revision", systemImage: "chevron.left", action: viewModel.goBack)
                        .disabled(!viewModel.canGoBack)
                    if let label = viewModel.revisionLabel {
                        Text(label)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Revision \(label)")
                    }
                    Button("Next revision", systemImage: "chevron.right", action: viewModel.goForward)
                        .disabled(!viewModel.canGoForward)
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .confirmationDialog("Delete this rock?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                viewModel.delete()
                dismiss()
            }
        }
        .onDisappear(perform: viewModel.commit)
        .onChange(of: isEditing) { _, editing in
            if !editing { viewModel.commit() }
        }
    }

    @ViewBuilder
    private var suggestionsBar: some View {
        switch suggestions.state {
        case .ready:
            let variants = suggestions.variants(for: viewModel.rock?.text ?? viewModel.text)
            if !variants.isEmpty {
                VariantStrip(variants: variants) { viewModel.accept(suggestion: $0.text) }
                    .id(viewModel.rock?.text)
                    .padding(.bottom, 8)
            }
        case .loading:
            ProgressView().frame(height: 132)
        case .unavailable:
            EmptyView()
        }
    }
}
