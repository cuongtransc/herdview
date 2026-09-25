import Foundation

/// Which size of a row of segments to show in the width there is, chosen from
/// measured needs rather than by laying every size out and seeing what fits.
///
/// `ViewThatFits` over three segmented controls crashed the app on 2026-09-25:
/// the larger size, being taller, brought up the list's scroller; the scroller
/// took the width the larger size needed; the smaller size sent the scroller
/// away — and AppKit's constraint passes traded the two until it threw.
/// Deciding here, with slack wider than a scroller before growing back, gives
/// one answer for one width.
public enum SegmentFit {
    /// Room to spare, in points, before a smaller size gives way to a larger.
    /// More than a legacy scroller's 15–17 pt, so the scroller coming and
    /// going can never flip the choice by itself.
    public static let slack: Double = 20

    /// `needs` is each size's width, widest first. Returns its index: the
    /// widest that fits, except that a size already shown stays until it stops
    /// fitting or a wider one fits with `slack` to spare. When none fits, the
    /// narrowest.
    public static func choose(available: Double, needs: [Double], current: Int?) -> Int {
        guard !needs.isEmpty else { return 0 }
        let fitting = needs.firstIndex { $0 <= available } ?? needs.count - 1
        guard let current, needs.indices.contains(current), needs[current] <= available else { return fitting }
        return needs[..<current].firstIndex { $0 + slack <= available } ?? current
    }
}
