import AppKit

/// `NSLayoutManager` subclass that paints `.backgroundColor`-attributed ranges
/// (= inline code) as a rounded "pill" instead of a square fill. Ported from
/// glance's `GlanceLayoutManager` — the AppKit floor-3 technique sill adopts so the
/// markdown stays natively selectable while inline code rounds (a SwiftUI
/// `textRenderer` pill cannot coexist with `.textSelection`; see the #17f spec).
///
/// `NSTextTable` cell backgrounds (code blocks / blockquotes / GFM tables) are drawn
/// via `paragraphStyle.textBlocks`, a separate path that does NOT route through here,
/// so those stay rectangular — only inline code rounds.
///
/// TextKit 1 only: the host builds the `NSTextStorage`/`NSTextContainer` stack
/// explicitly so this override is in effect (a plain `NSTextView(frame:)` would pick
/// TextKit 2 and bypass it).
final class InlineCodePillLayoutManager: NSLayoutManager {

    /// Pill corner radius — a shallow, one-character-ish rounding.
    var cornerRadius: CGFloat = 4
    /// Horizontal padding added on each side (negative inset = grow): the
    /// `.backgroundColor` attribute only spans the glyph advance, so widen it a touch
    /// to give the pill breathing room.
    var horizontalInset: CGFloat = -3
    /// Vertical inset (0 = line-height tight).
    var verticalInset: CGFloat = 0

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>,
                                          count rectCount: Int,
                                          forCharacterRange charRange: NSRange,
                                          color: NSColor) {
        color.set()
        for i in 0..<rectCount {
            let rect = rectArray[i].insetBy(dx: horizontalInset, dy: verticalInset)
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
    }
}
