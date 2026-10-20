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
    @State private var pullOffset: CGFloat = 0
    @State private var pullArmed = false
    @State private var edges = Edges()
    /// Text that would branch into a new rock, awaiting confirmation.
    @State private var pendingBranch: String?
    let previousRockText: String?
    let nextRockText: String?
    let onNewRock: () -> Void
    let onDeleted: () -> Void
    /// -1: the newer rock; +1: the older rock.
    let onMove: (Int) -> Void
    let onOpenRock: (Rock.ID) -> Void

    init(rockID: Rock.ID, store: RockStore, previousRockText: String?, nextRockText: String?,
         onNewRock: @escaping () -> Void, onDeleted: @escaping () -> Void,
         onMove: @escaping (Int) -> Void, onOpenRock: @escaping (Rock.ID) -> Void) {
        _viewModel = StateObject(wrappedValue: RockEditorViewModel(rockID: rockID, store: store))
        self.previousRockText = previousRockText
        self.nextRockText = nextRockText
        self.onNewRock = onNewRock
        self.onDeleted = onDeleted
        self.onMove = onMove
        self.onOpenRock = onOpenRock
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
        .confirmationDialog("Branch into a new rock?", isPresented: Binding(get: { pendingBranch != nil }, set: { if !$0 { pendingBranch = nil } }),
                            titleVisibility: .visible) {
            Button("Branch into a new rock") {
                if let text = pendingBranch, let id = viewModel.branch(to: text) { onOpenRock(id) }
                pendingBranch = nil
            }
            Button("Cancel", role: .cancel) { pendingBranch = nil }
        } message: {
            Text("This is an older version. Branching starts a new rock from it and leaves this rock as it is.")
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
            // `-pullOffset Y` freezes a revision pull (screenshots).
            if let i = args.firstIndex(of: "-pullOffset"), i + 1 < args.count, let y = Double(args[i + 1]) {
                pullArmed = true
                pullOffset = y
            }
        }
        #endif
        .onDisappear(perform: viewModel.commit)
        .onChange(of: isEditing) { _, editing in
            if !editing {
                if viewModel.isViewingOlderRevision, let rock = viewModel.rock, viewModel.text != rock.text {
                    // Edited an older version: offer a branch instead of rewriting history.
                    pendingBranch = viewModel.text
                    viewModel.text = rock.text
                } else {
                    viewModel.commit()
                }
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
                Text(viewModel.isViewingOlderRevision ? "Editing an older version · saving branches a new rock" : "Editing")
            } else if viewModel.isViewingOlderRevision, viewModel.optionIndex == 0, let label = viewModel.revisionLabel {
                // Before "no suggestions": this warning matters more.
                Label("Revision \(label) · changes branch a new rock", systemImage: "arrow.triangle.branch")
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
                PrimaryButton(systemImage: viewModel.isViewingOlderRevision ? "arrow.triangle.branch" : "checkmark",
                              label: viewModel.isViewingOlderRevision ? "Branch into a new rock" : "Save this suggestion",
                              enabled: swipe.axis == .undecided) {
                    if viewModel.isViewingOlderRevision {
                        pendingBranch = variants[viewModel.optionIndex - 1].text
                    } else {
                        withAnimation(.snappy) { viewModel.saveOption(variants.map(\.text)) }
                    }
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

    /// One row of pages, stories-style: the newer rock's text | this rock's
    /// text, then its suggestions (each against the text) | the older rock's
    /// text. The finger drags the whole page; a horizontal latch locks scrolling
    /// (PageSwipe). Vertical pulls from the scroll edge move through revision
    /// history (Populist's pull rules); tap the text to type.
    private func pager(_ variants: [RockVariant]) -> some View {
        let current = viewModel.rock?.text ?? viewModel.text
        let index = viewModel.optionIndex
        let count = variants.count
        let first = previousRockText == nil ? 0 : -1
        let last = nextRockText == nil ? count : count + 1
        return GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(max(first, index - 1)...min(last, index + 1), id: \.self) { k in
                    page(pageText(k, current: current, variants: variants), isCurrent: k == index, dimmed: k < 0 || k > count)
                        .frame(width: width, height: geo.size.height)
                        .offset(x: CGFloat(k - index) * width
                                + PageSwipe.offset(drag: dragOffset, atStart: index == 0 && previousRockText == nil,
                                                   atEnd: index == count && nextRockText == nil),
                                y: k == index ? pullOffset * 0.45 : 0)
                        .onTapGesture {
                            if k == 0, swipe.axis == .undecided { isTyping = true }
                        }
                }
            }
            .overlay(alignment: pullOffset > 0 ? .top : .bottom) { pullHint }
            .clipped()
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: PageSwipe.latchDistance)
                    .onChanged { drag in
                        var t = Transaction()
                        t.disablesAnimations = true
                        if let x = swipe.update(drag.translation) {
                            withTransaction(t) { dragOffset = x }
                        } else if let y = swipe.pull(drag.translation) {
                            // A pull only from the scroll edge (down at the top, up at the bottom).
                            pullArmed = (y > 0 && edges.top) || (y < 0 && edges.bottom)
                            withTransaction(t) { pullOffset = pullArmed ? y : 0 }
                        }
                    }
                    .onEnded { drag in
                        if swipe.axis == .vertical {
                            let step = swipe.pullStep(translation: drag.translation, atTop: edges.top, atBottom: edges.bottom)
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                if step < 0, viewModel.canGoBack { viewModel.goBack() }
                                if step > 0, viewModel.canGoForward { viewModel.goForward() }
                                pullOffset = 0
                            }
                        } else {
                            let step = swipe.step(translation: drag.translation, predicted: drag.predictedEndTranslation, width: width)
                            switch RockEditorViewModel.rowMove(index: index, step: step, count: count) {
                            case .option(let n):
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    viewModel.selectOption(n, count: count)
                                    dragOffset = 0
                                }
                            case .previousRock where previousRockText != nil:
                                slide(to: width, then: { onMove(-1) })
                            case .nextRock where nextRockText != nil:
                                slide(to: -width, then: { onMove(1) })
                            default:
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { dragOffset = 0 }
                            }
                        }
                        pullArmed = false
                        swipe.reset()
                    }
            )
        }
        .sensoryFeedback(.selection, trigger: index)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.rock?.revisionIndex)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(index == 0 ? "Current text: \(current)" : "Option \(index) of \(count): \(variants[index - 1].text)")
        .accessibilityHint(index == 0 ? "Double-tap to type. Swipe up or down for options" : "Swipe up or down for other options; the center button keeps this one")
        .accessibilityAction { if index == 0 { isTyping = true } }
        .accessibilityAction(named: "Previous revision") { viewModel.goBack() }
        .accessibilityAction(named: "Next revision") { viewModel.goForward() }
        .accessibilityAdjustableAction { direction in
            withAnimation(.snappy) { viewModel.stepOption(direction == .increment ? 1 : -1, count: count) }
        }
    }

    private func pageText(_ k: Int, current: String, variants: [RockVariant]) -> AttributedString {
        if k < 0 { return AttributedString(previousRockText ?? "") }
        if k > variants.count { return AttributedString(nextRockText ?? "") }
        return k == 0 ? AttributedString(current) : Self.inlineDiff(from: current, to: variants[k - 1].text)
    }

    /// Finishes a swipe past this rock's row by sliding the neighbor fully in,
    /// then hands over to it.
    private func slide(to x: CGFloat, then done: @escaping () -> Void) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            dragOffset = x
        } completion: {
            done()
        }
    }

    /// Shown while pulling: which revision a release lands on.
    @ViewBuilder
    private var pullHint: some View {
        if pullArmed, pullOffset != 0, let rock = viewModel.rock {
            let older = pullOffset > 0
            let target = rock.revisionIndex + (older ? -1 : 1)
            let ready = abs(pullOffset) > PageSwipe.pullDistance
            Label(rock.revisions.indices.contains(target)
                  ? "\(ready ? "Release for" : "Pull for") revision \(target + 1) of \(rock.revisions.count)"
                  : (older ? "This is the first version" : "This is the latest version"),
                  systemImage: older ? "arrow.down" : "arrow.up")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: .capsule)
                .padding(.vertical, 8)
                .transition(.opacity)
        }
    }

    private struct Edges: Equatable { var top = true; var bottom = true }

    private func page(_ text: AttributedString, isCurrent: Bool, dimmed: Bool) -> some View {
        ScrollView {
            Text(text)
                .font(.title3)
                .foregroundStyle(dimmed ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
        }
        .onScrollGeometryChange(for: Edges.self) { geo in
            Edges(top: geo.contentOffset.y <= -geo.contentInsets.top + 1,
                  bottom: geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 1)
        } action: { _, new in
            if isCurrent { edges = new }
        }
        .scrollDisabled(swipe.axis == .horizontal || pullArmed)
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
