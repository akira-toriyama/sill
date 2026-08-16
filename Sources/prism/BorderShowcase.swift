// prism — animated-border bench. Hosts the REAL shared `AnimatedBorderView`
// (ThemeKitUI, SwiftUI-native #17d) so it's captured live in every theme. Three
// cells prove the universal contract: a static `primary` border, the SAME border
// lit by an effect (live two-stop bloom), and that effect border RESTING when the
// master `effectsEnabled` toggle is off (back to primary).
//
// The card's OWN rim (Gallery's overlay) is also an AnimatedBorderView — this
// section just shows the three states side by side with the `copy ref` header.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects
import ThemeKitUI

// MARK: - Showcase: static / live-effect / effect-off, in the current theme

struct MockBorder: View {
    let p: ResolvedPalette
    /// The card's theme — its own effect lights the live cell; a static theme
    /// borrows `rainbow` so every card still demonstrates an effect rim.
    let themeName: String

    private var demo: EffectSpec { borderEffectFor(themeName) ?? .rainbow }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ThemeKitUI · AnimatedBorderView — the shared surface border (primary static ↔ live effect rim)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            HStack(spacing: 16) {
                cell("primary · static") {
                    AnimatedBorderView(palette: p, effect: nil)
                }
                cell("effect · live") {
                    AnimatedBorderView(palette: p, effect: demo, effectsEnabled: true)
                }
                cell("effect · off (master)") {
                    AnimatedBorderView(palette: p, effect: demo, effectsEnabled: false)
                }
                cell("effect · steady colour") {
                    steadyColorBorder
                }
                Spacer(minLength: 0)
            }
        }
        .showcasePanel(p)
    }

    /// `cyclesColors = false` — the rim holds the effect's steady hue instead of
    /// looping its flash palette (facet's bare-`[border] effect` contract).
    private var steadyColorBorder: AnimatedBorderView<RoundedRectangle> {
        var v = AnimatedBorderView(palette: p, effect: demo, effectsEnabled: true)
        v.cyclesColors = false
        return v
    }

    /// A captioned sample panel with the REAL AnimatedBorderView overlaid on it.
    @ViewBuilder
    private func cell<V: View>(_ caption: String, @ViewBuilder _ border: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption)
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: p.background ?? .windowBackgroundColor))
                .frame(width: 150, height: 56)
                .overlay(border())
        }
    }
}
