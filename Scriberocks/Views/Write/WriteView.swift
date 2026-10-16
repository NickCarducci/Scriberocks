import SwiftUI

struct WriteView: View {
    @StateObject private var viewModel: WriteViewModel
    @FocusState private var isEditorFocused: Bool
    private let onSaved: (Rock) -> Void

    init(store: RockStore, onSaved: @escaping (Rock) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: WriteViewModel(store: store))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $viewModel.draft)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal)
                .overlay(alignment: .topLeading) {
                    if viewModel.draft.isEmpty {
                        Text("Drop a rock — a thought, a line, a first draft.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 21)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle(Date.now.formatted(date: .abbreviated, time: .omitted))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") {
                            if let rock = viewModel.save() {
                                isEditorFocused = false
                                onSaved(rock)
                            }
                        }
                        .disabled(!viewModel.canSave)
                    }
                    ToolbarItem(placement: .keyboard) {
                        Button("Done") { isEditorFocused = false }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
        }
    }
}

#Preview {
    WriteView(store: .preview())
}
