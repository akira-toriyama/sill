// prism — halo mock chrome. halo draws a thin, glowing, click-through ring
// around the FOCUSED macOS window (RingView, sampling Effects.resolveBorder at
// 30 Hz). This mock is a tiny fake "window" wrapped in the REAL shared
// ThemedBorderView, so the ring breathes / cycles live for an animatable theme
// exactly as halo ships — prism imports no app View (mirrors by eye only).

import SwiftUI
import AppKit
import PaletteKit   // ResolvedPalette
import Effects      // borderEffectFor, isAnimatableTheme
// NOTE: SpecimenBox, elevate, uiScale, sysFont, and ThemedBorderView are all
// prism-LOCAL (Specimens.swift / Gallery.swift / BorderShowcase.swift) — same
// target, no import needed. ThemedBorderView is prism's NSViewRepresentable
// bridge that wraps ThemeKit's ThemedBorder, so ThemeKit need not be imported here.

/// A miniature of halo's signature surface: a fake focused window (traffic-light
/// dots + a title + two content bars) hugged by the live effect ring. The ring
/// IS the shared `ThemedBorderView` (dogfood) — static `primary` stroke when the
/// theme has no effect / effects are off, the glowing breathing cycle otherwise.
struct MockHalo: View {
    let p: ResolvedPalette
    let themeName: String
    let showEffects: Bool

    var body: some View {
        SpecimenBox(title: "halo · ring", p: p) {
            ZStack {
                // The "focused window" the ring hugs — elevated off the panel so
                // the ring reads as surrounding a distinct surface.
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: elevate(p, by: 0.10)))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Color(nsColor: p.muted).opacity(0.6))
                                .frame(width: 6, height: 6)
                        }
                        Text("focused window")
                            .font(sysFont(9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(nsColor: p.muted))
                        Spacer(minLength: 0)
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: p.foreground).opacity(0.18))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: p.foreground).opacity(0.10))
                        .frame(width: 120 * uiScale, height: 8)
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .frame(height: 92 * uiScale)
            // The live ring — the REAL shared ThemedBorder widget.
            .overlay {
                ThemedBorderView(
                    palette: p,
                    effect: isAnimatableTheme(themeName) ? borderEffectFor(themeName) : nil,
                    effectsEnabled: showEffects,
                    cornerRadius: 10, lineWidth: 2)
            }
        }
    }
}
