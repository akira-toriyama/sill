// prism — ThemeKitUI backdrop bench. Renders the SwiftUI-native
// `ThemedBackdropView` (#17c) live in every theme: fill modes (auto / scrim /
// solid / clear), an arbitrary `Shape` (Capsule pill), the `.themedBackdrop`
// modifier, and a scrim over a vivid pattern so the "dimmed but NOT blurred"
// translucency reads. No blur — the AppKit floors stay at 2.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKitUI

struct MockBackdrop: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ThemeKitUI · backdrop — themed surface for panels/pills/cards (solid or alpha scrim, any Shape; no blur)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            HStack(alignment: .top, spacing: 16) {
                cell("auto · theme surface") {
                    ThemedBackdropView(palette: p, bordered: true)
                        .overlay { label("Aa surface") }
                }
                cell("scrim 0.6 · over pattern") {
                    ZStack {
                        pattern
                        ThemedBackdropView(palette: p, fill: .scrim(opacity: 0.6), bordered: true)
                        label("dimmed, not blurred")
                    }
                }
                cell("solid · opaque") {
                    ZStack {
                        pattern
                        ThemedBackdropView(palette: p, fill: .solid, bordered: true)
                        label("opaque")
                    }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                cell("pill · Capsule + border") {
                    ThemedBackdropView(palette: p, in: Capsule(), bordered: true)
                        .overlay { label("⌘K  pill") }
                }
                cell(".themedBackdrop modifier") {
                    label("content")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .themedBackdrop(p, in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                        bordered: true)
                }
                cell("clear · border only") {
                    ThemedBackdropView(palette: p, fill: .clear, bordered: true)
                        .overlay { label("border only") }
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

    /// A vivid gradient so a scrim's translucency is visible in a static card.
    private var pattern: some View {
        LinearGradient(colors: [Color(nsColor: p.primary),
                                Color(nsColor: p.secondary),
                                Color(nsColor: p.error)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func label(_ s: String) -> some View {
        Text(s)
            .font(sysFont(9, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(nsColor: p.foreground))
    }

    @ViewBuilder
    private func cell<V: View>(_ caption: String, @ViewBuilder _ field: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption)
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            field().frame(width: 150, height: 64)
        }
    }
}
