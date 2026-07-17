// prism — ThemeKit skeleton bench. Hosts the REAL shared `ThemedSkeleton`
// (ThemeKit) inside the SwiftUI gallery, one cell per variant / animation, so
// the loading placeholder can be evaluated live in every theme. The shimmer
// runs LIVE here (the bench is where the pulse / wave 演出 is demonstrated and
// felt — `previewFrozen` is the screenshot-only override, exercised by the
// tests, not wired on in the bench).

import SwiftUI
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - Showcase: every variant + animation in the current theme

struct MockSkeleton: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ThemeKit · skeleton — the real shared placeholder (live pulse / wave)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // A SwiftUI `.frame` governs an NSViewRepresentable's size (it
            // overrides the widget's intrinsicContentSize), so each cell sizes
            // its skeleton explicitly + left-aligns it — a circle stays square.
            HStack(alignment: .top, spacing: 16) {
                ex("text · pulse", h: 14) {
                    lead { ThemedSkeletonView(palette: p, variant: .text)
                        .frame(width: 180, height: 12) }
                }
                ex("rounded · wave", h: 18) {
                    lead { ThemedSkeletonView(palette: p, variant: .rounded, animation: .wave)
                        .frame(width: 180, height: 16) }
                }
                ex("text · none", h: 14) {
                    lead { ThemedSkeletonView(palette: p, variant: .text, animation: .none)
                        .frame(width: 120, height: 12) }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ex("circular", h: 44) {
                    lead { ThemedSkeletonView(palette: p, variant: .circular)
                        .frame(width: 40, height: 40) }
                }
                ex("rectangular", h: 44) {
                    lead { ThemedSkeletonView(palette: p, variant: .rectangular)
                        .frame(width: 120, height: 40) }
                }
                ex("card row", h: 44) {
                    // a realistic compose: avatar + two text lines
                    lead {
                        HStack(spacing: 8) {
                            ThemedSkeletonView(palette: p, variant: .circular)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                ThemedSkeletonView(palette: p, variant: .text)
                                    .frame(width: 120, height: 11)
                                ThemedSkeletonView(palette: p, variant: .text)
                                    .frame(width: 80, height: 11)
                            }
                        }
                    }
                }
            }
        }
        .showcasePanel(p)
    }

    @ViewBuilder
    private func ex<V: View>(_ caption: String, h: CGFloat,
                             @ViewBuilder _ field: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption)
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            field().frame(width: 230, height: h)
        }
    }

    /// Left-align an explicitly-sized skeleton within its 230-wide cell (so a
    /// circular / fixed-width specimen keeps its true shape instead of stretching).
    @ViewBuilder
    private func lead<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 0) { content(); Spacer(minLength: 0) }
    }
}
