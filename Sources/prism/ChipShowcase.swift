// prism — ThemeKit chip bench. Hosts the REAL shared `ThemedChip` (ThemeKit)
// inside the SwiftUI gallery so it can be evaluated live in every theme: the top
// rows are INTERACTIVE (hover a clickable filter chip, click to toggle, click the
// × to remove a tag); the rows below force each state via the `preview…`
// overrides so hover / pressed / focus / disabled capture deterministically. The
// keycap variant shows the real `⌘ ⇧ ⌘N ⇧⌘N` glyphs.

import SwiftUI
import PaletteKit
import ThemeKit

// MARK: - SwiftUI bridge for ThemeKit's ThemedChip

struct ThemedChipView: NSViewRepresentable {
    let palette: ResolvedPalette
    var variant: ThemedChip.Variant = .filled
    var size: ThemedChip.Size = .medium
    var role: ThemedChip.Role = .neutral
    var title: String = "Tag"
    var leading: String? = nil
    var selected = false
    var enabled = true
    var previewHovered = false
    var previewPressed = false
    var previewFocused = false
    var clickable = false
    var deletable = false
    var onTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    func makeNSView(context: Context) -> ThemedChip {
        let c = ThemedChip(palette: palette)
        apply(to: c)
        return c
    }

    func updateNSView(_ c: ThemedChip, context: Context) { apply(to: c) }

    /// Size to the chip's own intrinsic content (so it hugs its label, not the cell).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedChip,
                      context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    private func apply(to c: ThemedChip) {
        c.palette = palette
        c.variant = variant
        c.size = size
        c.role = role
        c.title = title
        c.leadingSymbol = leading
        c.isSelected = selected
        c.isEnabled = enabled
        c.previewHovered = previewHovered
        c.previewPressed = previewPressed
        c.previewFocused = previewFocused
        c.onTap = clickable ? (onTap ?? {}) : nil
        c.onDelete = deletable ? (onDelete ?? {}) : nil
    }
}

// MARK: - Showcase: variants (live) + every state / role / size in the theme

struct MockChip: View {
    let p: ResolvedPalette
    @State private var toggled = true
    @State private var taps = 0
    @State private var tags = ["design", "swift", "appkit", "mui"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · chip — the real shared token (top rows LIVE: toggle / hover / × to remove)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // LIVE — a clickable filter chip that toggles, and removable tags.
            HStack(spacing: 8) {
                ThemedChipView(palette: p, variant: .outlined, role: .primary,
                               title: "Filter", selected: toggled, clickable: true) { toggled.toggle() }
                Text("on: \(toggled ? "yes" : "no")  ·  taps: \(taps)")
                    .font(sysFont(9, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.tertiary))
                ThemedChipView(palette: p, title: "Tap me", clickable: true) { taps += 1 }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    ThemedChipView(palette: p, title: tag, deletable: true) {
                        tags.removeAll { $0 == tag }
                    }
                }
                if tags.isEmpty {
                    Text("(all removed — re-run to reset)")
                        .font(sysFont(9, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                }
                Spacer(minLength: 0)
            }

            // Forced states (preview overrides) — deterministic for capture.
            stateRow("filled · clickable states", variant: .filled)
            stateRow("outlined · clickable states", variant: .outlined)

            // Roles (filled).
            HStack(spacing: 10) {
                cell("neutral")   { ThemedChipView(palette: p, role: .neutral,   title: "Neutral") }
                cell("primary")   { ThemedChipView(palette: p, role: .primary,   title: "Primary") }
                cell("secondary") { ThemedChipView(palette: p, role: .secondary, title: "Secondary") }
                cell("error")     { ThemedChipView(palette: p, role: .error,     title: "Error") }
                Spacer(minLength: 0)
            }

            // Sizes + leading icon + outlined + selected.
            HStack(alignment: .bottom, spacing: 10) {
                cell("small")     { ThemedChipView(palette: p, size: .small, title: "Small") }
                cell("medium")    { ThemedChipView(palette: p, size: .medium, title: "Medium") }
                cell("+ icon")    { ThemedChipView(palette: p, variant: .outlined, title: "Tag", leading: "tag") }
                cell("selected")  { ThemedChipView(palette: p, variant: .outlined, role: .primary,
                                                   title: "On", selected: true, clickable: true) }
                cell("delete")    { ThemedChipView(palette: p, title: "Remove", deletable: true) }
                Spacer(minLength: 0)
            }

            // Keycap variant — the real shortcut glyphs (<kbd>).
            VStack(alignment: .leading, spacing: 5) {
                Text("keycap (<kbd>) — mono, key-shaped, static")
                    .font(sysFont(8, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.tertiary))
                HStack(spacing: 6) {
                    ThemedChipView(palette: p, variant: .keycap, size: .small, title: "⌘")
                    ThemedChipView(palette: p, variant: .keycap, size: .small, title: "⇧")
                    ThemedChipView(palette: p, variant: .keycap, size: .small, title: "⌥")
                    ThemedChipView(palette: p, variant: .keycap, size: .small, title: "⌘N")
                    ThemedChipView(palette: p, variant: .keycap, size: .medium, title: "⇧⌘N")
                    ThemedChipView(palette: p, variant: .keycap, size: .medium, title: "Esc")
                    Spacer(minLength: 0)
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

    /// One row of the same variant in each forced state (clickable so the state
    /// layer is meaningful).
    @ViewBuilder
    private func stateRow(_ caption: String, variant: ThemedChip.Variant) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            HStack(spacing: 10) {
                tagged("rest")     { ThemedChipView(palette: p, variant: variant, title: "Chip", clickable: true) }
                tagged("hover")    { ThemedChipView(palette: p, variant: variant, title: "Chip", previewHovered: true, clickable: true) }
                tagged("pressed")  { ThemedChipView(palette: p, variant: variant, title: "Chip", previewPressed: true, clickable: true) }
                tagged("focus")    { ThemedChipView(palette: p, variant: variant, title: "Chip", previewFocused: true, clickable: true) }
                tagged("disabled") { ThemedChipView(palette: p, variant: variant, title: "Chip", enabled: false, clickable: true) }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func tagged<V: View>(_ tag: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 3) {
            content()
            Text(tag).font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
        }
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
