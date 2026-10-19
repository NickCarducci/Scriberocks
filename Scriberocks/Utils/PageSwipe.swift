import CoreGraphics

/// Swipe rules for the option pager (after Populist's pull navigation):
/// wait for a few points of movement, then latch the dominant axis for the
/// rest of the drag (the other axis is locked: a horizontal latch disables
/// vertical scrolling, a vertical latch ignores horizontal movement). A page
/// turns only on a clearly horizontal swipe (2:1) that travels, or would land,
/// far enough; otherwise the page springs back.
struct PageSwipe {
    enum Axis { case undecided, horizontal, vertical }

    private(set) var axis: Axis = .undecided

    static let latchDistance: CGFloat = 5
    static let turnDistance: CGFloat = 50
    /// Past the first or last page the page moves this fraction of the drag.
    static let resistance: CGFloat = 1.0 / 3.0

    /// The horizontal offset to show for this drag, or nil when the drag
    /// isn't (or isn't yet) a horizontal one.
    mutating func update(_ translation: CGSize) -> CGFloat? {
        if axis == .undecided {
            guard max(abs(translation.width), abs(translation.height)) > Self.latchDistance else { return nil }
            axis = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
        }
        return axis == .horizontal ? translation.width : nil
    }

    /// Pages to move when the drag ends: +1 (next, swipe left), -1, or 0.
    func step(translation: CGSize, predicted: CGSize, width: CGFloat) -> Int {
        guard axis == .horizontal, abs(translation.width) > abs(translation.height) * 2 else { return 0 }
        let far = max(Self.turnDistance, width / 3)
        if translation.width < -Self.turnDistance || predicted.width < -far { return 1 }
        if translation.width > Self.turnDistance || predicted.width > far { return -1 }
        return 0
    }

    mutating func reset() { axis = .undecided }

    /// The drag as shown on page `index` of 0...count: resisted past the ends.
    static func offset(drag: CGFloat, index: Int, count: Int) -> CGFloat {
        let pastEnd = (index <= 0 && drag > 0) || (index >= count && drag < 0)
        return pastEnd ? drag * resistance : drag
    }
}
