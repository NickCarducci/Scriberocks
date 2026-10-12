import SwiftUI

struct RockEditorView: View {
    @StateObject private var viewModel: RockEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(rockID: Rock.ID, store: RockStore) {
        _viewModel = StateObject(wrappedValue: RockEditorViewModel(rockID: rockID, store: store))
    }

    var body: some View {
        Group {
            if viewModel.exists {
                TextEditor(text: $viewModel.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal)
            } else {
                ContentUnavailableView("Rock not found", systemImage: "fossil.shell")
            }
        }
        .navigationTitle(viewModel.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.exists {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $viewModel.isDiamond) {
                        Label("Final draft", systemImage: viewModel.isDiamond ? "diamond.fill" : "diamond")
                    }
                    .toggleStyle(.button)
                    .accessibilityHint("Marks this rock as a diamond, your final draft")
                }
                ToolbarItem(placement: .bottomBar) {
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
    }
}
