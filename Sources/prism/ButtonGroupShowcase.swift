// prism — ThemeKit button-group bench. Hosts the REAL shared `ThemedButtonGroup`
// (ThemeKit) inside the SwiftUI gallery so the joined seams / corners / divider /
// elevation can be evaluated live in every theme. The top rows are INTERACTIVE
// (hover a member, click to bump the tap counter, click the segmented group to
// move selection); the rows below force each variant / orientation / state via
// the `preview…` overrides so they capture deterministically.

import SwiftUI
import PaletteKit
import ThemeKit

// MARK: - SwiftUI bridge for ThemeKit's ThemedButtonGroup

struct ThemedButtonGroupView: NSViewRepresentable {
    let palette: ResolvedPalette
    var titles: [String]
    var orientation: ThemedButtonGroup.Orientation = .horizontal
    var variant: ThemedButton.Variant = .outlined
    var size: ThemedButton.Size = .medium
    var role: ThemedButton.Role = .primary
    var mode: ThemedButtonGroup.Mode = .actions
    var fullWidth = false
    var enabled = true
    var disabledMember: Int? = nil
    var selectedIndex: Int? = nil
    var previewSelectedIndex: Int? = nil
    var previewHoveredIndex: Int? = nil
    var previewFocusedIndex: Int? = nil
    var onTap: ((Int) -> Void)? = nil
    var onSelect: ((Int) -> Void)? = nil

    func makeNSView(context: Context) -> ThemedButtonGroup {
        let g = ThemedButtonGroup(palette: palette)
        apply(to: g)
        return g
    }

    func updateNSView(_ g: ThemedButtonGroup, context: Context) { apply(to: g) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedButtonGroup,
                      context: Context) -> CGSize? {
        if fullWidth { return nil }
        return nsView.intrinsicContentSize
    }

    private func apply(to g: ThemedButtonGroup) {
        g.palette = palette
        g.orientation = orientation
        g.variant = variant
        g.size = size
        g.role = role
        g.mode = mode
        g.fullWidth = fullWidth
        g.isEnabled = enabled
        g.segments = titles.enumerated().map { i, t in
            ThemedButtonGroup.Segment(t, isEnabled: i != disabledMember)
        }
        g.selectedIndex = selectedIndex
        g.previewSelectedIndex = previewSelectedIndex
        g.previewHoveredIndex = previewHoveredIndex
        g.previewFocusedIndex = previewFocusedIndex
        g.onTap = onTap
        g.onSelect = onSelect
    }
}

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
