import SwiftUI

/// A new rock, full screen. The draft is kept until saved.
struct ComposerView: View {
    @ObservedObject var viewModel: WriteViewModel
    let canCancel: Bool
    /// Called with the saved rock, or nil when cancelled.
    let finished: (Rock?) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $viewModel.draft)
                .focused($focused)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal)
                .overlay(alignment: .topLeading) {
                    if viewModel.draft.isEmpty {
                        Text("Drop a rock — a thought, a line, a first draft.")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 21)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                if canCancel {
                    ChromeButton(systemImage: "xmark", label: "Cancel") { finished(nil) }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer()
                PrimaryButton(systemImage: "checkmark", label: "Save rock", enabled: viewModel.canSave) {
                    if let rock = viewModel.save() {
                        focused = false
                        finished(rock)
                    }
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .onAppear { focused = true }
    }
}
