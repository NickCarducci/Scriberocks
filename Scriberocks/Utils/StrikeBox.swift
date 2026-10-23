import UIKit
import ScribeCore

/// Long rocks scroll; only the sentences in the strike box are scored. The box
/// is a band at the top of the text, four lines of 16-point type tall. Every
/// sentence with any part inside it is struck, however many that is; the
/// rest of the rock is left exactly as written (suggestions are spliced in).
enum StrikeBox {
    static let height: CGFloat = 4 * UIFont.systemFont(ofSize: 16).lineHeight

    /// The sentences of `text` as the engine splits them (core `text::sentences`:
    /// a line break, or . ! ? followed by whitespace or the end), trimmed.
    static func sentences(in text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start = text.startIndex
        func close(_ end: String.Index) {
            let piece = text[start..<end]
            if let first = piece.firstIndex(where: { !$0.isWhitespace }),
               let last = piece.lastIndex(where: { !$0.isWhitespace }) {
                out.append(first..<text.index(after: last))
            }
        }
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            let next = text.index(after: i)
            if c == "\n" {
                close(i)
                start = next
            } else if ".!?".contains(c), next == text.endIndex || text[next].isWhitespace {
                close(next)
                start = next
            }
            i = next
        }
        close(text.endIndex)
        return out
    }

    /// The struck stretch of `text` (first struck sentence through the last)
    /// with the box `top` points down the laid-out text, or nil when every
    /// sentence is struck (score the whole rock).
    @MainActor
    static func range(in text: String, top: CGFloat, width: CGFloat, font: UIFont) -> Range<String.Index>? {
        let sentences = sentences(in: text)
        guard sentences.count > 1, width > 0 else { return nil }
        let key = "\(width)|\(text)"
        let extents = cache[key] ?? extents(of: sentences, in: text, width: width, font: font)
        if cache.count > 32 { cache.removeAll() }
        cache[key] = extents
        let box = top...(top + height)
        // A box in a gap (between paragraphs) strikes the nearest sentence.
        let hit = struck(extents, box: box) ?? {
            let i = extents.indices.min { distance(extents[$0], box) < distance(extents[$1], box) }!
            return i...i
        }()
        if hit == 0...(sentences.count - 1) { return nil }
        return sentences[hit.lowerBound].lowerBound..<sentences[hit.upperBound].upperBound
    }

    @MainActor private static var cache: [String: [ClosedRange<CGFloat>]] = [:]

    private static func distance(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> CGFloat {
        max(0, max(a.lowerBound, b.lowerBound) - min(a.upperBound, b.upperBound))
    }

    /// Each sentence's vertical extent (top of its first line to the bottom of
    /// its last) when `text` is laid out `width` points wide in `font`.
    static func extents(of sentences: [Range<String.Index>], in text: String, width: CGFloat, font: UIFont) -> [ClosedRange<CGFloat>] {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        return sentences.map { range in
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(range, in: text), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            return rect.minY...max(rect.minY, rect.maxY)
        }
    }

    /// Indices of the sentences with any part inside `box`, or nil if none.
    static func struck(_ extents: [ClosedRange<CGFloat>], box: ClosedRange<CGFloat>) -> ClosedRange<Int>? {
        let hits = extents.indices.filter { extents[$0].overlaps(box) }
        guard let first = hits.first, let last = hits.last else { return nil }
        return first...last
    }

    /// `variant` (of the struck text `text[range]`) put back into the whole
    /// rock, its byte ranges moved to match.
    static func splice(_ variant: RockVariant, into text: String, at range: Range<String.Index>) -> RockVariant {
        let before = String(text[..<range.lowerBound]), after = String(text[range.upperBound...])
        let shift = UInt32(before.utf8.count)
        let moved = { (ranges: [ByteRange]) in ranges.map { ByteRange(start: $0.start + shift, end: $0.end + shift) } }
        return RockVariant(text: before + variant.text + after, ops: variant.ops, fluencyDelta: variant.fluencyDelta,
                           changed: moved(variant.changed), enhanced: variant.enhanced.map { before + $0 + after },
                           enhancedChanged: moved(variant.enhancedChanged))
    }
}
