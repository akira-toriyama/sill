// prism — ThemeKit border bench. Hosts the REAL shared `ThemedBorder` (ThemeKit)
// — itself a plain embeddable NSView, so it bridges straight into the grid and IS
// captured. Three cells prove the universal contract in every theme: a static
// `primary` border, the SAME border lit by an effect (live bloom), and that effect
// border RESTING when the master `effectsEnabled` toggle is off (back to primary).
//
// The card's OWN rim (Gallery's overlay) is also a ThemedBorder now — this section
// just shows the three states side by side with the `copy ref` header.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects
import ThemeKit

// MARK: - SwiftUI bridge for ThemeKit's ThemedBorder

struct ThemedBorderView: NSViewRepresentable {
    let palette: ResolvedPalette
    var effect: EffectSpec? = nil
    var effectsEnabled: Bool = true
    var cornerRadius: CGFloat = 10
    var lineWidth: CGFloat = 1.5
    /// Freeze the live cycle at a fixed phase for deterministic capture (off in
    /// the bench — the rim animates live, like the Skeleton shimmer).
    var previewFrozen: Bool = false

    func makeNSView(context: Context) -> ThemedBorder {
        let b = ThemedBorder(palette: palette, effect: effect)
        apply(b)
        return b
    }

    func updateNSView(_ b: ThemedBorder, context: Context) { apply(b) }

    private func apply(_ b: ThemedBorder) {
        b.palette = palette
        b.effect = effect
        b.effectsEnabled = effectsEnabled
        b.cornerRadius = cornerRadius
        b.lineWidth = lineWidth
        b.previewFrozen = previewFrozen
    }
}

// MARK: - Showcase: static / live-effect / effect-off, in the current theme

struct MockBorder: View {
    let p: ResolvedPalette
    /// The card's theme — its own effect lights the live cell; a static theme
    /// borrows `rainbow` so every card still demonstrates an effect rim.
    let themeName: String

    private var demo: EffectSpec { borderEffectFor(themeName) ?? .rainbow }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ThemeKit · border — the real shared surface border (primary static ↔ live effect rim)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            HStack(spacing: 16) {
                cell("primary · static") {
                    ThemedBorderView(palette: p, effect: nil)
                }
                cell("effect · live") {
                    ThemedBorderView(palette: p, effect: demo, effectsEnabled: true)
                }
                cell("effect · off (master)") {
                    ThemedBorderView(palette: p, effect: demo, effectsEnabled: false)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
    }

    /// A captioned sample panel with the REAL ThemedBorder overlaid on it.
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
