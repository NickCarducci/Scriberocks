import SwiftUI
import ScribeCore

/// A free-scrolling (no snapping) strip of suggestions. The card nearest the
/// center is emphasized and ticks as it changes; tap a card to accept it.
struct VariantStrip: View {
    let variants: [RockVariant]
    let onAccept: (RockVariant) -> Void

    @State private var centered: String?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(variants, id: \.text) { variant in
                    Button { onAccept(variant) } label: {
                        VariantCard(variant: variant, isCentered: centered == variant.text)
                    }
                    .buttonStyle(.plain)
                    .id(variant.text)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $centered, anchor: .center)
        .sensoryFeedback(.selection, trigger: centered)
        .frame(height: 132)
        .onAppear { centered = variants.first?.text }
        .accessibilityLabel("Suggestions")
    }
}

private struct VariantCard: View {
    let variant: RockVariant
    let isCentered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlighted)
                .font(.callout)
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(variant.ops.joined(separator: " · "))
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

    /// Changed words in the accent color.
    private var highlighted: AttributedString {
        var text = AttributedString(variant.text)
        for range in variant.changedRanges {
            guard let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text) else { continue }
            text[lower..<upper].foregroundColor = .accentColor
            text[lower..<upper].font = .callout.weight(.semibold)
        }
        return text
    }
}
