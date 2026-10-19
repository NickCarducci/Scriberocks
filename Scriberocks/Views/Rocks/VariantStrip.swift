import SwiftUI
import ScribeCore

/// A free-scrolling (no snapping) strip of options: the current text first,
/// then the suggestions. The card nearest the center is the selection (it
/// previews inline in the editor) and ticks as it changes; tap a card to
/// center it. Nothing is applied until Save.
struct VariantStrip: View {
    let current: String
    let variants: [RockVariant]
    /// 0 = the current text, 1...n = `variants[selection - 1]`.
    @Binding var selection: Int

    @State private var centered: Int?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                Button { select(0) } label: {
                    OptionCard(text: AttributedString(current), caption: "Current", isCentered: centered == 0)
                }
                .buttonStyle(.plain)
                .id(0)
                ForEach(Array(variants.enumerated()), id: \.element.text) { i, variant in
                    Button { select(i + 1) } label: {
                        OptionCard(text: variant.highlighted(font: .callout), caption: variant.ops.joined(separator: " · "), isCentered: centered == i + 1)
                    }
                    .buttonStyle(.plain)
                    .id(i + 1)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $centered, anchor: .center)
        .sensoryFeedback(.selection, trigger: centered)
        .frame(height: 132)
        .onAppear { centered = selection }
        .onChange(of: centered) { _, new in
            if let new, new != selection { selection = new }
        }
        .onChange(of: selection) { _, new in
            if new != centered { withAnimation(.snappy) { centered = new } }
        }
        .accessibilityLabel("Suggestions")
    }

    private func select(_ index: Int) {
        withAnimation(.snappy) { centered = index }
    }
}

private struct OptionCard: View {
    let text: AttributedString
    let caption: String
    let isCentered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.callout)
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 240, height: 120)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isCentered ? Color.accentColor : .clear, lineWidth: 2)
        }
        .scaleEffect(isCentered ? 1 : 0.96)
        .animation(.snappy(duration: 0.15), value: isCentered)
    }
}

extension RockVariant {
    /// The text with changed words in the accent color.
    func highlighted(font: Font) -> AttributedString {
        var out = AttributedString(text)
        for range in changedRanges {
            guard let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].foregroundColor = .accentColor
            out[lower..<upper].font = font.weight(.semibold)
        }
        return out
    }
}
