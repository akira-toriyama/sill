// prism — ThemeKit text-field bench. Hosts the REAL shared `ThemedTextField`
// (ThemeKit) inside the SwiftUI gallery, both as the mock search fields
// (facet tree / wand tome) and a dedicated variant/state showcase, so the
// component can be evaluated live in every theme.

import SwiftUI
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - Showcase: every variant + state in the current theme

struct MockField: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ThemeKit · text field — the real shared component (live, editable)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            HStack(alignment: .top, spacing: 16) {
                ex("outlined · resting", h: 50) {
                    ThemedTextFieldView(palette: p, label: "Filter",
                                    placeholder: "type to filter…",
                                    leading: "magnifying-glass", surface: p.background)
                }
                ex("outlined · focused", h: 50) {
                    ThemedTextFieldView(palette: p, label: "Filter",
                                    placeholder: "type to filter…",
                                    leading: "magnifying-glass", surface: p.background,
                                    previewFocused: true)
                }
                ex("outlined · filled + clear", h: 50) {
                    ThemedTextFieldView(palette: p, label: "Filter", text: "kernel",
                                    leading: "magnifying-glass",
                                    trailing: "x-circle", surface: p.background)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ex("filled variant", h: 50) {
                    ThemedTextFieldView(palette: p, variant: .filled, label: "Name",
                                    text: "facet", surface: p.background)
                }
                ex("standard variant", h: 50) {
                    ThemedTextFieldView(palette: p, variant: .standard, label: "Tag",
                                    text: "web", surface: p.background)
                }
                ex("error + helper", h: 68) {
                    ThemedTextFieldView(palette: p, label: "Filter", text: "zzz",
                                    leading: "magnifying-glass",
                                    error: "no matches", surface: p.background)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                ex("controlled · binding + key seams (T1)", h: 72, w: 480) {
                    ControlledFieldDemo(p: p)
                }
            }
        }
        .showcasePanel(p)
    }

    @ViewBuilder
    private func ex<V: View>(_ caption: String, h: CGFloat, w: CGFloat = 230,
                             @ViewBuilder _ field: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption)
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            field().frame(width: w, height: h)
        }
    }
}

/// The T1 controlled surface, live: the bound model + last key seam are echoed
/// below the field, so typing / Return / Esc(clear) / ↑↓ visibly round-trip
/// through the `Binding<String>` (the facet-3 live-filter wiring).
private struct ControlledFieldDemo: View {
    let p: ResolvedPalette
    @State private var query = "ker"
    @State private var focused = false
    @State private var lastKey = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ThemedTextFieldView(palette: p, label: "Search",
                            placeholder: "live filter…",
                            text: $query, focused: $focused,
                            leading: "magnifying-glass", trailing: "x-circle",
                            surface: p.background,
                            onReturn: { lastKey = "⏎"; return true },
                            onEscape: { query = ""; lastKey = "esc·cleared"; return true },
                            onMoveUp: { lastKey = "↑"; return true },
                            onMoveDown: { lastKey = "↓"; return true })
                .frame(height: 46)
            Text("bound: \"\(query)\" · key: \(lastKey) · focus: \(focused ? "on" : "off")")
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
        }
    }
}
