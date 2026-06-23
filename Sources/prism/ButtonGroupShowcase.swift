// prism — ThemeKit button-group bench. Hosts the REAL shared `ThemedButtonGroup`
// (ThemeKit) inside the SwiftUI gallery so the joined seams / corners / divider /
// elevation can be evaluated live in every theme. The top rows are INTERACTIVE
// (hover a member, click to bump the tap counter, click the segmented group to
// move selection); the rows below force each variant / orientation / state via
// the `preview…` overrides so they capture deterministically.

import SwiftUI
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - Showcase

struct MockButtonGroup: View {
    let p: ResolvedPalette
    @State private var taps = 0
    @State private var selected: Int? = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · button group — the real shared joined control (top rows LIVE)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // LIVE — actions group (hover a member, click to bump) + segmented group.
            HStack(spacing: 16) {
                cell("actions · live") {
                    ThemedButtonGroupView(palette: p, titles: ["Cut", "Copy", "Paste"]) { _ in taps += 1 }
                }
                Text("taps: \(taps)")
                    .font(sysFont(9, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.tertiary))
                cell("segmented · live") {
                    ThemedButtonGroupView(palette: p, titles: ["Day", "Week", "Month"],
                                          variant: .contained, mode: .segmented,
                                          selectedIndex: selected, onSelect: { selected = $0 })
                }
                Spacer(minLength: 0)
            }

            // Variants (forced) — horizontal.
            HStack(spacing: 16) {
                cell("text") { ThemedButtonGroupView(palette: p, titles: ["One", "Two", "Three"], variant: .text) }
                cell("outlined") { ThemedButtonGroupView(palette: p, titles: ["One", "Two", "Three"], variant: .outlined) }
                cell("contained") { ThemedButtonGroupView(palette: p, titles: ["One", "Two", "Three"], variant: .contained) }
                Spacer(minLength: 0)
            }

            // Orientation + states.
            HStack(alignment: .top, spacing: 16) {
                cell("vertical · outlined") {
                    ThemedButtonGroupView(palette: p, titles: ["Top", "Mid", "End"],
                                          orientation: .vertical, variant: .outlined)
                }
                cell("segmented · sel 1") {
                    ThemedButtonGroupView(palette: p, titles: ["A", "B", "C"], variant: .outlined,
                                          mode: .segmented, previewSelectedIndex: 1)
                }
                cell("hover member 1") {
                    ThemedButtonGroupView(palette: p, titles: ["A", "B", "C"], variant: .contained,
                                          previewHoveredIndex: 1)
                }
                cell("focus member 1") {
                    ThemedButtonGroupView(palette: p, titles: ["A", "B", "C"], variant: .outlined,
                                          mode: .segmented, previewFocusedIndex: 1)
                }
                cell("disabled member 1") {
                    ThemedButtonGroupView(palette: p, titles: ["A", "B", "C"], variant: .outlined,
                                          disabledMember: 1)
                }
                Spacer(minLength: 0)
            }

            // fullWidth.
            VStack(alignment: .leading, spacing: 5) {
                Text("fullWidth · segmented").font(sysFont(8, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.tertiary))
                ThemedButtonGroupView(palette: p, titles: ["Left", "Center", "Right"],
                                      variant: .outlined, mode: .segmented, fullWidth: true,
                                      previewSelectedIndex: 0)
                    .frame(height: 36)
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
    private func cell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }
}
