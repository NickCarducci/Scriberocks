import SwiftUI
import UIKit
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
    /// Edges where the finger was last lifted (Populist's pull locking).
    @State private var lock = PullLock()
    /// The edges when the current vertical drag latched.
    @State private var pullStart: Edges?
    /// Long rocks: the strike box's top, in points down the text (set when
    /// scrolling the current text settles); its width; its height.
    @State private var strikeTop: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var textHeight: CGFloat = 0
    /// The current page's scroll position; neighbors show the strike box's place.
    @State private var pagePosition = ScrollPosition(y: 0)
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
            revisionMenu
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
        .onAppear { viewModel.showLatest() }
        .task(id: prefetchKey) {
            // Prepare what's likely next: this rock's other versions, the neighboring rocks.
            guard case .ready = suggestions.state, let rock = viewModel.rock else { return }
            let versions = rock.revisions.map(\.text).filter { $0 != rock.text }
            // What each would strike when it opens (scrolled to the top).
            suggestions.prefetch(([previousRockText, nextRockText].compactMap { $0 } + versions.reversed()).map { text in
                strikeRange(text, top: 0).map { String(text[$0]) } ?? text
            })
        }
        .onDisappear(perform: viewModel.commit)
        .onChange(of: edges) { _, new in lock.moved(atTop: new.top, atBottom: new.bottom) }
        .onChange(of: viewModel.optionIndex) {
            // The page turned to keeps the strike box's place in view.
            pagePosition = ScrollPosition(y: strikeTop)
        }
        .onChange(of: viewModel.rock?.revisionIndex) {
            strikeTop = 0
            pagePosition = ScrollPosition(y: 0)
        }
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

    private var prefetchKey: String {
        "\(viewModel.rock?.text.hashValue ?? 0)-\(suggestions.state.isReady)"
    }

    private var variants: [RockVariant] {
        guard case .ready = suggestions.state else { return [] }
        let text = viewModel.rock?.text ?? viewModel.text
        return suggestions.variants(for: text, struck: strikeRange(text, top: strikeTop))
    }

    static let pageFont = UIFont.preferredFont(forTextStyle: .title3)

    /// The struck sentences of `text` with the strike box at `top`; nil = all.
    private func strikeRange(_ text: String, top: CGFloat) -> Range<String.Index>? {
        StrikeBox.range(in: text, top: top, width: textWidth, font: Self.pageFont)
    }

    /// Taller than the strike box: the box shows and only what it strikes is scored.
    private var isLong: Bool { textHeight > StrikeBox.height + 1 }

    /// "Current" or "Option 2 of 14 · cut", or the engine's state.
    @ViewBuilder
    private func indicator(_ variants: [RockVariant]) -> some View {
        Group {
            if isTyping {
                Text(viewModel.isViewingOlderRevision ? "Editing an older version · saving branches a new rock" : "Editing")
            } else if viewModel.isViewingOlderRevision, viewModel.optionIndex == 0 {
                // Before "no suggestions": this warning matters more.
                Label("Older version · changes branch a new rock", systemImage: "arrow.triangle.branch")
            } else if case .loading = suggestions.state {
                CrabLoader()
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
        .padding(.top, viewModel.revisionChoices.count > 1 && !isTyping ? 4 : 8)
        .padding(.bottom, 8)
        .animation(.snappy, value: viewModel.optionIndex)
    }

    /// Saved versions by date and time, newest first; the one showing is checked.
    @ViewBuilder
    private var revisionMenu: some View {
        let choices = viewModel.revisionChoices
        if choices.count > 1, !isTyping, let showing = choices.first(where: \.isShowing) {
            Menu {
                Picker("Version", selection: Binding(get: { showing.index }, set: { i in withAnimation(.snappy) { viewModel.showRevision(i) } })) {
                    ForEach(choices) { choice in
                        Text(choice.isLatest ? "Latest · \(Self.when(choice.date))" : Self.when(choice.date)).tag(choice.index)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(showing.isLatest ? "Latest · \(Self.when(showing.date))" : Self.when(showing.date))
                    if !showing.isLatest {
                        Text("branches").foregroundStyle(.tint)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.footnote.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: .capsule)
            }
            .buttonStyle(.plain)
            // Most recent at the top wherever the menu opens (iOS otherwise puts
            // the first item nearest the button, flipping it when opening upward).
            .menuOrder(.fixed)
            .padding(.top, 8)
            .accessibilityLabel("Version: \(showing.isLatest ? "latest, " : "")\(Self.when(showing.date))")
            .accessibilityHint("Choose a saved version. Changes to an older version branch into a new rock.")
        }
    }

    /// "Today, 5:19 PM" or "Oct 12, 3:04 PM".
    static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? "Today, " + date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func bottomBar(_ variants: [RockVariant]) -> some View {
        let action = viewModel.primaryAction(isTyping: isTyping)
        return HStack {
            Color.clear.frame(width: 44, height: 44)
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
                    page(pageText(k, current: current, variants: variants), isCurrent: k == index, dimmed: k < 0 || k > count,
                         isText: k == 0, viewport: geo.size.height)
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
                            // A pull only from the scroll edge it started at (down at the top,
                            // up at the bottom), and only once a finger was lifted there.
                            if pullStart == nil { pullStart = edges }
                            let from = lock.edges(startedAtTop: pullStart!.top, startedAtBottom: pullStart!.bottom)
                            pullArmed = (y > 0 && from.top) || (y < 0 && from.bottom)
                            withTransaction(t) { pullOffset = pullArmed ? y : 0 }
                        }
                    }
                    .onEnded { drag in
                        if swipe.axis == .vertical {
                            let start = pullStart ?? edges
                            let from = lock.edges(startedAtTop: start.top, startedAtBottom: start.bottom)
                            let step = swipe.pullStep(translation: drag.translation, atTop: from.top, atBottom: from.bottom)
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
                        pullStart = nil
                        lock.released(atTop: edges.top, atBottom: edges.bottom)
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
        if k == 0 { return AttributedString(current) }
        let v = variants[k - 1]
        if let enhanced = v.enhanced { return Self.generatePage(current: current, proposal: v.text, enhanced: enhanced) }
        return Self.inlineDiff(from: current, to: v.text)
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
        if pullArmed, pullOffset != 0 {
            // Thumb up (pushing from the bottom) = older; thumb down (from the top) = newer.
            let older = pullOffset < 0
            let ready = abs(pullOffset) > PageSwipe.pullDistance
            let date = viewModel.revisionDate(offset: older ? -1 : 1)
            Label(date.map { "\(ready ? "Release for" : "Pull for") the \(older ? "earlier" : "newer") version · \(Self.when($0))" }
                  ?? (older ? "This is the first version" : "This is the latest version"),
                  systemImage: older ? "arrow.up" : "arrow.down") // the way the thumb moves
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: .capsule)
                .padding(.vertical, 8)
                .transition(.opacity)
        }
    }

    private struct Edges: Equatable { var top = true; var bottom = true }

    /// `isText`: this rock's own text, whose scrolling moves the strike box.
    private func page(_ text: AttributedString, isCurrent: Bool, dimmed: Bool, isText: Bool, viewport: CGFloat) -> some View {
        ScrollView {
            Text(text)
                .font(.title3)
                .foregroundStyle(dimmed ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    if isText { textWidth = size.width; textHeight = size.height }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
        }
        // Long rocks scroll far enough for the last sentence to reach the box.
        .contentMargins(.bottom, isLong ? max(0, viewport - StrikeBox.height - 16) : 0, for: .scrollContent)
        .scrollPosition(isCurrent ? $pagePosition : .constant(ScrollPosition(y: strikeTop)))
        .onScrollPhaseChange { _, phase, context in
            if isText, isCurrent, phase == .idle {
                strikeTop = max(0, context.geometry.contentOffset.y + context.geometry.contentInsets.top)
            }
        }
        .overlay(alignment: .top) {
            if isText, isLong {
                // The strike box: the sentences it touches are the ones scored.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(height: StrikeBox.height)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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

    /// A Generate page: the enhanced proposal against the current text, as
    /// `inlineDiff`, except that words ScribeIE (Intent-conditioned Editing)
    /// added beyond ScribeSLM's proposal get ScribeIE's marks — red underline
    /// over a semi-transparent highlight (`ScribeIEStyle`) — instead of the
    /// accent color, so writers see which words came from generation.
    static func generatePage(current: String, proposal: String, enhanced: String) -> AttributedString {
        var fromProposal: [String: Int] = [:]
        for w in InlineDiff.parts(from: current, to: proposal).map(\.text) { fromProposal[w.lowercased(), default: 0] += 1 }
        var out = AttributedString()
        var previous: String?
        for part in InlineDiff.parts(from: current, to: enhanced) {
            if let previous, InlineDiff.spaced(previous, part.text) {
                out += AttributedString(" ")
            }
            var piece = AttributedString(part.text)
            let key = part.text.lowercased()
            let ours = (fromProposal[key] ?? 0) > 0
            if ours { fromProposal[key]! -= 1 }
            switch part.kind {
            case .kept: break
            case .removed:
                piece.strikethroughStyle = .single
                piece.foregroundColor = .secondary
            case .added where !ours && part.text.contains(where: \.isLetter):
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: ScribeIEStyle.underline)
                piece.backgroundColor = ScribeIEStyle.highlight
                piece.font = .title3.weight(.semibold)
            case .added:
                piece.foregroundColor = .accentColor
                piece.font = .title3.weight(.semibold)
            }
            out += piece
            previous = part.text
        }
        return out
    }

    /// The option against the current text: removed words struck through and
    /// dimmed, added words in the accent color.
    static func inlineDiff(from current: String, to option: String) -> AttributedString {
        var out = AttributedString()
        var previous: String?
        for part in InlineDiff.parts(from: current, to: option) {
            if let previous, InlineDiff.spaced(previous, part.text) {
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

/// Tiny Rust crabs scuttle while the language engine (written in Rust) loads.
struct CrabLoader: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Text("🦀")
                        .font(.footnote)
                        .offset(x: CGFloat(sin(t * 6 + Double(i) * 1.3)) * 4,
                                y: CGFloat(abs(sin(t * 9 + Double(i)))) * -2)
                        .scaleEffect(x: cos(t * 3 + Double(i)) > 0 ? 1 : -1, y: 1)
                }
                Text("Warming up the crabs…")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading suggestions")
    }
}

extension SuggestionEngine.State {
    var isReady: Bool { if case .ready = self { return true } else { return false } }
}

/// ScribeIE's marks: a red underline over a semi-transparent highlight —
/// white in light mode, dark in dark mode. One place to retune.
enum ScribeIEStyle {
    static let underline = Color.red
    static let highlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.45) : UIColor.white.withAlphaComponent(0.45)
    })
}
