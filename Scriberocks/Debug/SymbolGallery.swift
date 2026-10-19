#if DEBUG
import SwiftUI

/// QA screen for the custom rock symbol: rendering modes and weights.
/// Launch with `-symbolGallery`.
struct SymbolGallery: View {
    @State private var bounce = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            row("Monochrome") { Image("rock").symbolRenderingMode(.monochrome).foregroundStyle(.primary) }
            row("Hierarchical") { Image("rock").symbolRenderingMode(.hierarchical).foregroundStyle(Color.accentColor) }
            row("Palette") { Image("rock").symbolRenderingMode(.palette).foregroundStyle(.orange, .indigo) }
            row("Multicolor") { Image("rock").symbolRenderingMode(.multicolor) }
            HStack(spacing: 24) {
                ForEach([Font.Weight.ultraLight, .regular, .black], id: \.self) { w in
                    Image("rock").font(.system(size: 44, weight: w)).symbolRenderingMode(.hierarchical)
                }
            }
            Image("rock")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce.byLayer, value: bounce)
                .onTapGesture { bounce += 1 }
        }
        .font(.system(size: 56))
        .padding(32)
    }

    private func row(_ title: String, @ViewBuilder _ image: () -> some View) -> some View {
        HStack(spacing: 20) {
            image()
            Text(title).font(.title3)
        }
    }
}
#endif
