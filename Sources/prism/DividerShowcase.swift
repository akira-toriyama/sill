// prism — ThemeKit divider bench. Hosts the REAL shared `ThemedDivider`
// (ThemeKit) inside the SwiftUI gallery, one cell per orientation / variant,
// so the hairline can be evaluated live in every theme — crispness, the
// `border` tint, and the text-in-divider gap.

import SwiftUI
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - Showcase: every orientation + variant in the current theme

struct MockDivider: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ThemeKit · divider — the real shared hairline (live, device-pixel)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            HStack(alignment: .top, spacing: 16) {
                ex("horizontal · fullWidth", h: 14) {
                    ThemedDividerView(palette: p, surface: p.background)
                }
                ex("horizontal · inset 72", h: 14) {
                    ThemedDividerView(palette: p, variant: .inset, surface: p.background)
                }
                ex("horizontal · middle 16", h: 14) {
                    ThemedDividerView(palette: p, variant: .middle, surface: p.background)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ex("vertical · fullWidth", h: 44) {
                    ThemedDividerView(palette: p, orientation: .vertical,
                                      surface: p.background)
                }
                ex("text-in-divider · OR", h: 22) {
                    ThemedDividerView(palette: p, label: "OR", surface: p.background)
                }
                ex("heavier (2pt) rule", h: 14) {
                    // deviceHairline off + thickness>1 via a configured field below
                    HeavyRule(p: p)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
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
}

/// A 2 pt (non-device-hairline) rule, to show `deviceHairline = false` honoring
/// `thickness` literally — drawn through a tiny representable since the
/// `ThemedDividerView` knobs above don't expose thickness.
private struct HeavyRule: NSViewRepresentable {
    let p: ResolvedPalette
    func makeNSView(context: Context) -> ThemedDivider {
        let d = ThemedDivider(palette: p)
        d.deviceHairline = false
        d.thickness = 2
        d.surfaceColor = p.background
        return d
    }
    func updateNSView(_ d: ThemedDivider, context: Context) {
        d.palette = p
        d.surfaceColor = p.background
    }
}
