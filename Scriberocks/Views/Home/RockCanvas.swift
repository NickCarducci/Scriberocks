import SwiftUI
import ScribeCore

/// One rock, full screen: tap to type; swipe through its suggestions page by
/// page (each shown against the current text). Bottom: final-draft toggle,
/// the center button (new rock / save this suggestion / done), and a menu for
/// revision history and delete.
struct RockCanvas: View {
    @StateObject private var viewModel: RockEditorViewModel
    @EnvironmentObject private var suggestions: SuggestionEngine
    @FocusState private var isEditing: Bool
    @State private var confirmDelete = false
    /// Typing in the editor (tap the current text); otherwise the options pager.
    @State private var isTyping = false
    @State private var swipe = PageSwipe()
    @State private var dragOffset: CGFloat = 0
    let onNewRock: () -> Void
    let onDeleted: () -> Void

    init(rockID: Rock.ID, store: RockStore, onNewRock: @escaping () -> Void, onDeleted: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: RockEditorViewModel(rockID: rockID, store: store))
        self.onNewRock = onNewRock
        self.onDeleted = onDeleted
    }

    var body: some View {
        let variants = variants
        VStack(spacing: 0) {
            if isTyping || variants.isEmpty {
                TextEditor(text: $viewModel.text)
                    .focused($isEditing)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal)
                    .onAppear { if isTyping { isEditing = true } }
            } else {
                pager(variants)
            }
            indicator(variants)
            bottomBar(variants)
        }
        .confirmationDialog("Delete this rock?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                viewModel.delete()
                onDeleted()
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

    /// "Current" or "Option 2 of 14 · cut", or the engine's state.
    @ViewBuilder
    private func indicator(_ variants: [RockVariant]) -> some View {
        Group {
            if isTyping {
                Text("Editing")
            } else if case .loading = suggestions.state {
                Label("Finding suggestions…", systemImage: "sparkles")
            } else if variants.isEmpty {
                Text("No suggestions for this one yet")
            } else if viewModel.optionIndex == 0 {
                Label("Swipe for \(variants.count) suggestions", systemImage: "hand.draw")
            } else {
                Text("Option \(viewModel.optionIndex) of \(variants.count) · \(variants[viewModel.optionIndex - 1].ops.joined(separator: " · "))")
            }
        }
        .font(.footnote.weight(.medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: .capsule)
        .padding(.vertical, 8)
        .animation(.snappy, value: viewModel.optionIndex)
    }

    private func bottomBar(_ variants: [RockVariant]) -> some View {
        let action = viewModel.primaryAction(isTyping: isTyping)
        return HStack {
            ChromeButton(systemImage: viewModel.isDiamond ? "diamond.fill" : "diamond",
                         label: viewModel.isDiamond ? "Final draft" : "Mark as final draft") {
                viewModel.isDiamond.toggle()
            }
            .accessibilityHint("A diamond is your final draft")
            Spacer()
            switch action {
            case .newRock:
                PrimaryButton(systemImage: "plus", label: "New rock", action: onNewRock)
            case .saveOption:
                PrimaryButton(systemImage: "checkmark", label: "Save this suggestion", enabled: swipe.axis == .undecided) {
                    withAnimation(.snappy) { viewModel.saveOption(variants.map(\.text)) }
                }
            case .done:
                PrimaryButton(systemImage: "checkmark", label: "Done") { isEditing = false }
            }
            Spacer()
            Menu {
                if let label = viewModel.revisionLabel {
                    Section("Revision \(label)") {
                        Button("Previous revision", systemImage: "chevron.left", action: viewModel.goBack).disabled(!viewModel.canGoBack)
                        Button("Next revision", systemImage: "chevron.right", action: viewModel.goForward).disabled(!viewModel.canGoForward)
                    }
                }
                Button("Edit text", systemImage: "pencil") { isTyping = true }
                Button("Delete rock", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
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
                .font(.title3)
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
                piece.font = .title3.weight(.semibold)
            }
            out += piece
            previous = part.text
        }
        return out
    }

}
