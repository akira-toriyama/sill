// ThemedScroller — a theme-painted `NSScroller`. macOS' stock overlay scroller
// draws a grey system knob that ignores the palette; on a dark/neon theme it
// reads as a foreign sliver of chrome. This subclass paints the knob (and an
// optional track) with a `ResolvedPalette` role instead, so EVERY scrollable
// surface in the family scrolls in-theme rather than in macOS grey.
//
// In-kit, `ThemedList` installs one for its vertical scroller. A host app gets
// the same treatment on its own scroll views:
//
//     scrollView.verticalScroller = ThemedScroller()          // keep .overlay
//     // on (re)theme:
//     (scrollView.verticalScroller as? ThemedScroller)?.knobColor = palette.muted
//
// The knob still fades in / out with the system's overlay animation — we only
// own the FILL, not the show/hide behaviour, so it stays a native-feeling
// auto-hiding scroller that simply happens to be the theme's colour.

import AppKit   // pure AppKit: the host hands in a resolved NSColor, so no PaletteKit dep

@MainActor
public final class ThemedScroller: NSScroller {

    /// The knob fill. Assign a theme role — `palette.muted` reads as subtle
    /// chrome on every theme (light and dark). Defaults to the system secondary
    /// label so an un-themed instance still draws a visible knob.
    public var knobColor: NSColor = .secondaryLabelColor {
        didSet { if knobColor != oldValue { needsDisplay = true } }
    }

    /// Optional fill for the track behind the knob. `nil` (default) keeps the
    /// overlay convention of a transparent track — no stock grey slot, just the
    /// knob floating over the content.
    public var trackColor: NSColor? {
        didSet { if trackColor != oldValue { needsDisplay = true } }
    }

    /// Required so AppKit keeps this subclass under `.overlay` style; without it
    /// the overlay path silently falls back to a stock system scroller.
    public override class var isCompatibleWithOverlayScrollers: Bool { true }

    public override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        guard let track = trackColor else { return }   // transparent — no native slot
        track.setFill()
        NSBezierPath(rect: slotRect).fill()
    }

    public override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.width > 0, knob.height > 0 else { return }
        // Slim the pill on its long axis (narrower than the gutter band) and pull
        // the ends in off the caps. Orientation is read from the knob's own shape
        // so this works for a vertical OR horizontal scroller.
        let vertical = knob.height >= knob.width
        let r = knob.insetBy(dx: vertical ? 2 : 3, dy: vertical ? 3 : 2)
        guard r.width > 0, r.height > 0 else { return }
        let radius = min(r.width, r.height) / 2
        knobColor.setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
    }
}
