// ThemeKitUI — SwiftUI-native themed backdrop surface (#17c).
//
// A pure-SwiftUI backdrop: a `Shape` filled with the theme's surface colour
// (opaque, or a translucent scrim driven by the palette's `backgroundAlpha`),
// with an optional hairline border. NO blur.
//
// Why no blur: sill's AppKit policy keeps the widget layer SwiftUI-only (床3個).
// SwiftUI `Material` can't do behind-window blur, and a #17c investigation found
// every consumer's behind-window `NSVisualEffectView` blur (wand/perch/facet) was
// a toggleable cosmetic knob with an existing solid fallback — legibility never
// depended on it. So the backdrop is the shared, general surface those
// panels/pills/cards sit on: opaque fill, or an alpha SCRIM (the desktop/content
// behind shows through DIMMED but not blurred — pure `Color.opacity`), masked to
// any `Shape`. Design: docs/superpowers/specs/2026-06-28-17c-themed-backdrop-design.md
//
// GENERAL by design: the mask is any `Shape` (default a continuous rounded rect),
// the fill is `.auto` from the palette (or explicit), and the border is opt-in.
// Apps pass their corner radius / pill shape; prism shows the same pixels in
// every theme. Re-themes by reassigning `palette`.

import SwiftUI
import AppKit
import PaletteKit

/// How a ``ThemedBackdropView`` fills its shape.
public enum BackdropFill: Sendable, Equatable {
    /// Derive from the palette: a concrete `background` fills opaque (or at the
    /// palette's `backgroundAlpha`, the panel/pill knob, if set); a vibrancy
    /// theme (nil background) falls back to a translucent system surface.
    case auto
    /// Opaque themed fill.
    case solid
    /// Translucent tint at `opacity` (0…1) — content/desktop behind shows
    /// through DIMMED, not blurred (pure SwiftUI, no `NSVisualEffectView`).
    case scrim(opacity: Double)
    /// No fill — border-only (or a pure spacer).
    case clear
}

/// A themed backdrop surface: a `Shape` filled per ``BackdropFill`` with an
/// optional hairline. The general surface panels/pills/cards sit on.
public struct ThemedBackdropView<S: Shape>: View {
    public var palette: ResolvedPalette
    /// The mask. Default = a continuous rounded rect (r = 10).
    public var shape: S
    public var fill: BackdropFill
    /// Draw a 1pt hairline in `palette.border` around the shape.
    public var bordered: Bool

    public init(palette: ResolvedPalette,
                in shape: S = RoundedRectangle(cornerRadius: 10, style: .continuous),
                fill: BackdropFill = .auto,
                bordered: Bool = false) {
        self.palette = palette
        self.shape = shape
        self.fill = fill
        self.bordered = bordered
    }

    public var body: some View {
        let plan = ThemedBackdropView.plan(fill: fill,
                                           hasBackground: palette.background != nil,
                                           backgroundAlpha: palette.backgroundAlpha)
        shape
            .fill(fillColor.opacity(plan.draws ? plan.opacity : 0))
            .overlay { borderOverlay }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if bordered {
            shape.stroke(Color(nsColor: palette.border), lineWidth: 1)
        }
    }

    /// The surface colour: the theme's `background`, or the dynamic system
    /// surface for a vibrancy theme that left `background` nil.
    private var fillColor: Color {
        Color(nsColor: palette.background ?? .windowBackgroundColor)
    }

    // MARK: - Pure fill plan (no AppKit; reviewable in isolation)

    /// The decision ``body`` makes, as plain values — does it draw a fill, and at
    /// what opacity. Kept free of `NSColor`/SwiftUI so the policy reads clearly.
    struct FillPlan: Equatable { var draws: Bool; var opacity: Double }

    static func plan(fill: BackdropFill, hasBackground: Bool,
                     backgroundAlpha: CGFloat?) -> FillPlan {
        func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
        switch fill {
        case .clear:
            return FillPlan(draws: false, opacity: 0)
        case .solid:
            return FillPlan(draws: true, opacity: 1)
        case .scrim(let o):
            return FillPlan(draws: true, opacity: clamp(o))
        case .auto:
            // Concrete surface ⇒ opaque, or the panel/pill alpha knob if set.
            // Vibrancy theme (nil background) ⇒ translucent system scrim.
            let fallback: Double = hasBackground ? 1 : 0.85
            let a = backgroundAlpha.map { clamp(Double($0)) } ?? fallback
            return FillPlan(draws: true, opacity: a)
        }
    }
}

public extension View {
    /// Place a ``ThemedBackdropView`` behind this view (DRY ergonomic for
    /// `.background(ThemedBackdropView(...))`).
    func themedBackdrop<S: Shape>(
        _ palette: ResolvedPalette,
        in shape: S = RoundedRectangle(cornerRadius: 10, style: .continuous),
        fill: BackdropFill = .auto,
        bordered: Bool = false
    ) -> some View {
        background(ThemedBackdropView(palette: palette, in: shape, fill: fill, bordered: bordered))
    }
}
