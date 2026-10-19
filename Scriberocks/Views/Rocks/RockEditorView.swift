import SwiftUI
import ScribeCore

struct RockEditorView: View {
    @StateObject private var viewModel: RockEditorViewModel
    @EnvironmentObject private var suggestions: SuggestionEngine
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditing: Bool
    @State private var confirmDelete = false
    /// Typing in the editor (tap the current text); otherwise the options pager.
    @State private var isTyping = false
    @State private var swipe = PageSwipe()
    @State private var dragOffset: CGFloat = 0

    init(rockID: Rock.ID, store: RockStore) {
        _viewModel = StateObject(wrappedValue: RockEditorViewModel(rockID: rockID, store: store))
    }

    var body: some View {
        Group {
            if viewModel.exists {
                let variants = variants
                VStack(spacing: 0) {
                    if isTyping || variants.isEmpty {
                        TextEditor(text: $viewModel.text)
                            .focused($isEditing)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal)
                            .onAppear { if isTyping { isEditing = true } }
                    } else {
                        pager(variants)
                    }
                    if !isEditing {
                        suggestionsBar(variants)
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
            // `-dragOffset X` freezes the pager mid-drag (screenshots of the transition).
            if let i = args.firstIndex(of: "-dragOffset"), i + 1 < args.count, let x = Double(args[i + 1]) {
                dragOffset = x
            }
        }
        #endif
        .onDisappear(perform: viewModel.commit)
        .onChange(of: isEditing) { _, editing in
            if !editing {
                viewModel.commit()
                isTyping = false
            }
        }
    }

    private var variants: [RockVariant] {
        guard case .ready = suggestions.state else { return [] }
        return suggestions.variants(for: viewModel.rock?.text ?? viewModel.text)
    }

    /// The writing area as pages: the current text, then each option (as a
    /// comparison with the current text). The finger drags the whole page and
    /// the neighbor slides in; a horizontal latch locks vertical scrolling for
    /// the rest of the drag (PageSwipe). Tap the current text to type.
    private func pager(_ variants: [RockVariant]) -> some View {
        let current = viewModel.rock?.text ?? viewModel.text
        let index = viewModel.optionIndex
        let count = variants.count
        return GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(max(0, index - 1)...min(count, index + 1), id: \.self) { k in
                    page(k == 0 ? AttributedString(current) : Self.inlineDiff(from: current, to: variants[k - 1].text))
                        .frame(width: width, height: geo.size.height)
                        .offset(x: CGFloat(k - index) * width + PageSwipe.offset(drag: dragOffset, index: index, count: count))
                        .onTapGesture {
                            if k == 0, swipe.axis == .undecided { isTyping = true }
                        }
                }
            }
            .clipped()
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: PageSwipe.latchDistance)
                    .onChanged { drag in
                        if let x = swipe.update(drag.translation) {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) { dragOffset = x }
                        }
                    }
                    .onEnded { drag in
                        let step = swipe.step(translation: drag.translation, predicted: drag.predictedEndTranslation, width: width)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            viewModel.stepOption(step, count: count)
                            dragOffset = 0
                        }
                        swipe.reset()
                    }
            )
        }
        .sensoryFeedback(.selection, trigger: index)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(index == 0 ? "Current text: \(current)" : "Option \(index) of \(count): \(variants[index - 1].text)")
        .accessibilityHint(index == 0 ? "Double-tap to type. Swipe up or down for options" : "Swipe up or down for other options; Save keeps this one")
        .accessibilityAction { if index == 0 { isTyping = true } }
        .accessibilityAdjustableAction { direction in
            withAnimation(.snappy) { viewModel.stepOption(direction == .increment ? 1 : -1, count: count) }
        }
    }

    private func page(_ text: AttributedString) -> some View {
        ScrollView {
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
        }
        .scrollDisabled(swipe.axis == .horizontal)
        .padding(.horizontal)
        .background(.background)
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
    private func suggestionsBar(_ variants: [RockVariant]) -> some View {
        switch suggestions.state {
        case .ready:
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
                        .disabled(!viewModel.canSaveOption || swipe.axis != .undecided)
                        .accessibilityHint("Keeps this option as a new revision")
                    }
                    .padding(.horizontal)
                    VariantStrip(
                        current: viewModel.rock?.text ?? viewModel.text,
                        variants: variants,
                        selection: Binding(get: { viewModel.optionIndex }, set: { i in withAnimation(.snappy) { viewModel.selectOption(i, count: variants.count) } })
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
