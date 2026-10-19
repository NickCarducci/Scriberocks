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
                        .overlay { inlinePreview }
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
        #if DEBUG
        .task(id: variants.count) {
            // Screenshot/QA hook: `-previewOption N` previews option N inline.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-previewOption"), i + 1 < args.count, let n = Int(args[i + 1]), !variants.isEmpty {
                viewModel.selectOption(n, count: variants.count)
            }
        }
        #endif
        .onDisappear(perform: viewModel.commit)
        .onChange(of: isEditing) { _, editing in
            if !editing { viewModel.commit() }
        }
    }

    private var variants: [RockVariant] {
        guard case .ready = suggestions.state else { return [] }
        return suggestions.variants(for: viewModel.rock?.text ?? viewModel.text)
    }

    /// The selected option, drawn in place of the text (changed words
    /// highlighted). Swipe to move through options; nothing changes until Save.
    @ViewBuilder
    private var inlinePreview: some View {
        let options = isEditing ? [] : variants
        if viewModel.optionIndex > 0, options.indices.contains(viewModel.optionIndex - 1) {
            let variant = options[viewModel.optionIndex - 1]
            ScrollView {
                Text(Self.inlineDiff(from: viewModel.rock?.text ?? viewModel.text, to: variant.text))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal)
            .background(.background)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    withAnimation(.snappy) { viewModel.stepOption(drag.translation.width < 0 ? 1 : -1, count: options.count) }
                }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Option \(viewModel.optionIndex) of \(options.count): \(variant.text)")
            .accessibilityHint("Swipe up or down for other options; Save keeps this one")
            .accessibilityAdjustableAction { direction in
                viewModel.stepOption(direction == .increment ? 1 : -1, count: options.count)
            }
            .transition(.opacity)
        }
    }

    /// The option against the current text: removed words struck through and
    /// dimmed, added words in the accent color.
    static func inlineDiff(from current: String, to option: String) -> AttributedString {
        var out = AttributedString()
        var previous: String?
        for part in InlineDiff.parts(from: current, to: option) {
            if let previous, !InlineDiff.noSpaceBefore.contains(part.text), !InlineDiff.noSpaceAfter.contains(previous) {
                out += AttributedString(" ")
            }
            var piece = AttributedString(part.text)
            switch part.kind {
            case .kept: break
            case .removed:
                piece.strikethroughStyle = .single
                piece.foregroundColor = .secondary
            case .added:
                piece.foregroundColor = .accentColor
                piece.font = .body.weight(.semibold)
            }
            out += piece
            previous = part.text
        }
        return out
    }

    @ViewBuilder
    private var suggestionsBar: some View {
        switch suggestions.state {
        case .ready:
            let variants = variants
            if !variants.isEmpty {
                VStack(spacing: 4) {
                    HStack {
                        Text(viewModel.optionIndex == 0 ? "Current" : "Option \(viewModel.optionIndex) of \(variants.count)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save", systemImage: "checkmark") {
                            withAnimation(.snappy) { viewModel.saveOption(variants.map(\.text)) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canSaveOption)
                        .accessibilityHint("Keeps this option as a new revision")
                    }
                    .padding(.horizontal)
                    VariantStrip(
                        current: viewModel.rock?.text ?? viewModel.text,
                        variants: variants,
                        selection: Binding(get: { viewModel.optionIndex }, set: { viewModel.selectOption($0, count: variants.count) })
                    )
                    .id(viewModel.rock?.text)
                }
                .padding(.bottom, 8)
            }
        case .loading:
            ProgressView().frame(height: 132)
        case .unavailable:
            EmptyView()
        }
    }
}
