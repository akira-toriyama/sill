// prism — perch mock chrome. perch paints a universal "hint pill" overlay over
// arbitrary on-screen UI (HintPainter, 796 lines): a Vimium-style cluster of
// keyed pills at each actionable element, with a typed-prefix highlight, a
// matched glow, ghosting exits, and a miss flash. This mock rebuilds that scene
// out of the REAL ThemedPillView (#17g) over a faux desktop, so it re-themes
// across every catalog theme exactly as perch will — prism imports no app View
// (mirrors the layout by eye only). The neon/effect-border row (deferred from the
// t-yc68 mock) is now FILLED by #17k: the bottom row carries the animated effect
// border on every pill shape via ThemedPillView's `borderEffect` knob (built on
// #17d's AnimatedBorderView).

import SwiftUI
import AppKit
import PaletteKit   // ResolvedPalette
import ThemeKitUI   // ThemedPillView (the merged perch hint-pill widget)
import Effects       // borderEffectFor, EffectSpec — the #17k effect-border row
// NOTE: SpecimenBox, elevate, sysFont, uiScale are prism-LOCAL (Specimens.swift /
// Gallery.swift).

/// A miniature of perch's overlay: real `ThemedPillView` hints scattered at
/// element-anchor positions over a faux desktop. Stages the full range #17g
/// covers — idle + matched(glow) + ghosting + miss + corner badge + the
/// underline/tag/circle shapes + the two-color typed prefix — so the live card
/// proves perch's chrome rebuilds from sill parts on every theme. Pills are
/// frosted (`surfaceAlpha 0.3`) for perch's floating look; on an animatable theme
/// the card's 30 Hz `TimelineView` drives `p`, so the matched glow breathes live.
struct MockPerchOverlay: View {
    let p: ResolvedPalette
    let themeName: String
    let showEffects: Bool

    var body: some View {
        SpecimenBox(title: "perch · overlay", p: p) {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack(alignment: .topLeading) {
                        desktop
                        // idle hints — two-color typed prefix, frosted-floating
                        hint("FJ").position(x: w * 0.16, y: h * 0.20)
                        hint("DK").position(x: w * 0.80, y: h * 0.18)
                        hint("SL").position(x: w * 0.82, y: h * 0.52)
                        // the active candidate — matched glow
                        hint("FK", state: .matched).position(x: w * 0.42, y: h * 0.50)
                        // ghosting-out — idle look, faded + shrunk via the transform rail
                        hint("GH", opacity: 0.32, scale: 0.9).position(x: w * 0.20, y: h * 0.78)
                        hint("RU", opacity: 0.28, scale: 0.88).position(x: w * 0.56, y: h * 0.82)
                        // miss flash
                        hint("X", state: .miss).position(x: w * 0.50, y: h * 0.16)
                        // modifier badge
                        hint("EN", badge: "⌘").position(x: w * 0.82, y: h * 0.82)
                        // the other shapes — underline / tag / single-glyph circle
                        ThemedPillView(palette: p, label: "TY", shape: .underline,
                                       typedCount: 1)
                            .position(x: w * 0.34, y: h * 0.92)
                        ThemedPillView(palette: p, label: "OP", shape: .tag,
                                       typedCount: 1, surfaceAlpha: 0.3, frosted: true)
                            .position(x: w * 0.14, y: h * 0.48)
                        ThemedPillView(palette: p, label: "A", shape: .circle,
                                       surfaceAlpha: 0.3, frosted: true)
                            .position(x: w * 0.66, y: h * 0.36)
                    }
                }
                .frame(height: 150 * uiScale)
                effectBorderRow
            }
        }
    }

    /// The #17k payoff — the row deferred from the t-yc68 mock. Every pill shape
    /// (pill / square / circle / tag / neon-underline) carries the animated
    /// `borderEffect`, so the rim cycles + blooms live on an animatable theme and
    /// rests to the static border when the master effects toggle is off.
    private var effectBorderRow: some View {
        let fx = rowEffect
        return VStack(alignment: .leading, spacing: 6) {
            Text("neon border · all shapes")
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            HStack(spacing: 16) {
                ThemedPillView(palette: p, label: "FJ", shape: .pill, typedCount: 1,
                               surfaceAlpha: 0.3, frosted: true, borderEffect: fx)
                ThemedPillView(palette: p, label: "DK", shape: .square, typedCount: 1,
                               surfaceAlpha: 0.3, frosted: true, borderEffect: fx)
                ThemedPillView(palette: p, label: "A", shape: .circle,
                               surfaceAlpha: 0.3, frosted: true, borderEffect: fx)
                ThemedPillView(palette: p, label: "OP", shape: .tag, typedCount: 1,
                               surfaceAlpha: 0.3, frosted: true, borderEffect: fx)
                ThemedPillView(palette: p, label: "TY", shape: .underline,
                               typedCount: 1, borderEffect: fx)
            }
        }
    }

    /// The row's effect: the theme's catalog border-effect (`.neon` fallback so
    /// every theme lights up), rested to nil by the master effects toggle.
    private var rowEffect: EffectSpec? {
        showEffects ? (borderEffectFor(themeName) ?? .neon) : nil
    }

    /// A frosted idle/matched hint with a two-color typed prefix. `scale`/`opacity`
    /// feed `ThemedPillView`'s transform/opacity passthrough — the exact channel
    /// perch's ghost/appear/match drivers push, so the mock exercises the real rail.
    private func hint(_ label: String,
                      state: ThemedPillView.State = .idle,
                      badge: String? = nil,
                      opacity: Double = 1,
                      scale: CGFloat = 1) -> some View {
        ThemedPillView(palette: p, label: label, shape: .pill, state: state,
                       typedCount: 1, badge: badge,
                       surfaceAlpha: 0.3, frosted: true,
                       transform: CGAffineTransform(scaleX: scale, y: scale),
                       opacity: opacity)
    }

    /// The faux desktop the overlay floats over — an elevated surface with a few
    /// faint content bars, so the frosted pills read as floating over real UI.
    private var desktop: some View {
        let barWidths: [CGFloat] = [140, 90, 120]
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: elevate(p, by: 0.06)))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(barWidths.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: p.foreground).opacity(0.08))
                        .frame(width: barWidths[i] * uiScale, height: 8)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}
