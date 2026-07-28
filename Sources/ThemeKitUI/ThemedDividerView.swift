// ThemeKitUI — ThemedDividerView: the themed hairline separator, SwiftUI-native
// (orientation / variant / text-in-divider gap). Draws the SAME geometry as
// ThemeKit's AppKit `ThemedDivider` (which stays for AppKit hosts): a rule in
// the palette's `border` role, one DEVICE pixel thick (1/scale pt),
// pixel-phase-aligned so it stays crisp on Retina instead of blurring across
// two rows. `surface` is the backing colour the hairline sits on — it fills the
// gap a label cuts in the rule (so the rule reads as cut, not struck through).
// Decorative + non-hit-testable; no animation.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit

public struct ThemedDividerView: View {
    @Environment(\.sillPalette) private var ambientPalette
    @Environment(\.displayScale) private var displayScale
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var orientation: ThemedDivider.Orientation
    var variant: ThemedDivider.Variant
    var label: String?
    var surface: NSColor?

    public init(palette: ResolvedPalette? = nil,
                orientation: ThemedDivider.Orientation = .horizontal,
                variant: ThemedDivider.Variant = .fullWidth,
                label: String? = nil, surface: NSColor? = nil) {
        self.explicitPalette = palette
        self.orientation = orientation
        self.variant = variant
        self.label = label
        self.surface = surface
    }

    // MARK: - Metrics (mirror ThemedDivider — a divergence here shows up as a
    // before/after diff in prism, so keep the two in lockstep)

    private let inset: CGFloat = 72                              // MUI list-content gutter
    private let labelPadX: CGFloat = 10                          // breathing room each side of the label
    private let middleInset: CGFloat = CGFloat(Space.xl)         // MUI spacing(2) — horizontal `.middle`
    private let middleVerticalInset: CGFloat = CGFloat(Space.md) // MUI spacing(1) — vertical `.middle`
    private var labelSize: CGFloat { 11 }                        // small caption tier

    private var hasLabel: Bool { label != nil && orientation == .horizontal }

    /// One device pixel (1/scale pt). A degenerate scale still draws a hairline
    /// instead of silently vanishing.
    private var ruleThickness: CGFloat { 1 / max(displayScale, 1) }

    private var surfaceFill: NSColor { surface ?? palette.background ?? .textBackgroundColor }

    public var body: some View {
        let t = ruleThickness
        return Canvas { context, size in
            draw(&context, size: size)
        }
        // The thin axis is fixed (with a label the view must be tall enough for
        // the text); the long axis takes whatever the host proposes.
        .frame(width: orientation == .vertical ? t : nil,
               height: orientation == .horizontal
                   ? (hasLabel ? max(t, ceil(labelSize) + 6) : t) : nil)
        .allowsHitTesting(false)     // decorative: clicks pass through
        .accessibilityHidden(true)   // decorative — AX-ignored
    }

    // MARK: - Device-pixel geometry (same math as ThemedDivider)

    /// Snap a coordinate so the rule's leading edge lands ON a device-pixel
    /// boundary (no straddle → no blur). Phase-align the EDGE in backing space —
    /// snapping the whole rect would round the sub-point thickness to 0.
    private func pixelSnap(_ coord: CGFloat) -> CGFloat {
        let s = max(displayScale, 1)
        return (coord * s).rounded(.down) / s
    }

    /// (leading, trailing) insets along the rule's long axis for the variant.
    /// `inset` is a horizontal-list affordance — a vertical rule treats `.inset`
    /// as `.fullWidth`. `.middle` is a symmetric long-axis margin in BOTH
    /// orientations: 16 pt horizontal, 8 pt vertical (MUI spacing(2) / spacing(1)).
    private func longAxisInsets() -> (CGFloat, CGFloat) {
        switch (orientation, variant) {
        case (_, .fullWidth):            return (0, 0)
        case (.horizontal, .inset):      return (inset, 0)
        case (.vertical, .inset):        return (0, 0)   // inset is horizontal-only → fullWidth
        case (.horizontal, .middle):     return (middleInset, middleInset)
        case (.vertical, .middle):       return (middleVerticalInset, middleVerticalInset)
        }
    }

    // MARK: - Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let t = ruleThickness
        let (lead, trail) = longAxisInsets()
        let rule: CGRect
        switch orientation {
        case .horizontal:
            rule = CGRect(x: lead, y: pixelSnap(size.height / 2 - t / 2),
                          width: max(size.width - lead - trail, 0), height: t)
        case .vertical:
            rule = CGRect(x: pixelSnap(size.width / 2 - t / 2), y: lead,
                          width: t, height: max(size.height - lead - trail, 0))
        }
        context.fill(Path(rule), with: .color(Color(nsColor: palette.border)))

        // Centre the label + cut a surface-coloured gap in the rule beneath it
        // (horizontal-only, like the AppKit widget).
        guard hasLabel, let label else { return }
        let text = context.resolve(
            Text(label)
                .font(Font(palette.uiFont(.caption) as CTFont))
                .foregroundColor(Color(nsColor: palette.muted)))
        let measured = text.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                               height: CGFloat.greatestFiniteMagnitude))
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let gapW = ceil(measured.width) + 2 + 2 * labelPadX
        let gapH = max(t, ceil(labelSize))
        context.fill(
            Path(CGRect(x: centre.x - gapW / 2, y: centre.y - gapH / 2,
                        width: gapW, height: gapH)),
            with: .color(Color(nsColor: surfaceFill)))
        context.draw(text, at: centre)
    }
}
