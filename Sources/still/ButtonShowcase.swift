// still — ThemeKit button bench. Hosts the REAL shared `ThemedButton`
// (ThemeKit) inside the SwiftUI gallery so it can be evaluated live in every
// theme: the top row is fully INTERACTIVE (hover with the pointer, click to
// bump the tap counter — the 演出 to feel), and the rows below force each
// state via the `preview…` overrides so hover / pressed / focus / disabled
// capture deterministically in a screenshot.

import SwiftUI
import PaletteKit
import ThemeKit

// MARK: - SwiftUI bridge for ThemeKit's ThemedButton

struct ThemedButtonView: NSViewRepresentable {
    let palette: ResolvedPalette
    var variant: ThemedButton.Variant = .text
    var size: ThemedButton.Size = .medium
    var role: ThemedButton.Role = .primary
    var title: String = "Button"
    var leading: String? = nil
    var trailing: String? = nil
    var fullWidth = false
    var enabled = true
    var previewHovered = false
    var previewPressed = false
    var previewFocused = false
    var onTap: (() -> Void)? = nil

    func makeNSView(context: Context) -> ThemedButton {
        let b = ThemedButton(palette: palette)
        apply(to: b)
        return b
    }

    func updateNSView(_ b: ThemedButton, context: Context) { apply(to: b) }

    /// Size to the button's own intrinsic content (so it doesn't stretch to fill
    /// the cell) — except `fullWidth`, which intentionally takes the proposal.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedButton,
                      context: Context) -> CGSize? {
        if fullWidth { return nil }
        return nsView.intrinsicContentSize
    }

    private func apply(to b: ThemedButton) {
        b.palette = palette
        b.variant = variant
        b.size = size
        b.role = role
        b.title = title
        b.leadingSymbol = leading
        b.trailingSymbol = trailing
        b.fullWidth = fullWidth
        b.isEnabled = enabled
        b.previewHovered = previewHovered
        b.previewPressed = previewPressed
        b.previewFocused = previewFocused
        b.onTap = onTap
    }
}

// MARK: - Showcase: variants (live) + every state / role / size in the theme

struct MockButton: View {
    let p: ResolvedPalette
    @State private var taps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · button — the real shared control (top row LIVE: hover / click)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // LIVE — touchable. Hover for the state layer, click to bump taps.
            HStack(spacing: 12) {
                ThemedButtonView(palette: p, variant: .text, title: "Text") { taps += 1 }
                ThemedButtonView(palette: p, variant: .contained, title: "Contained") { taps += 1 }
                ThemedButtonView(palette: p, variant: .outlined, title: "Outlined") { taps += 1 }
                Text("taps: \(taps)")
                    .font(sysFont(9, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.tertiary))
                Spacer(minLength: 0)
            }

            // Forced states (preview overrides) — deterministic for capture.
            stateRow("contained · states", variant: .contained)
            stateRow("outlined · states", variant: .outlined)

            // Roles (contained) + sizes + icons + fullWidth.
            HStack(spacing: 12) {
                cell("primary")   { ThemedButtonView(palette: p, variant: .contained, role: .primary,   title: "Primary") }
                cell("secondary") { ThemedButtonView(palette: p, variant: .contained, role: .secondary, title: "Secondary") }
                cell("error")     { ThemedButtonView(palette: p, variant: .contained, role: .error,     title: "Delete") }
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 12) {
                cell("small")    { ThemedButtonView(palette: p, variant: .contained, size: .small,  title: "Small") }
                cell("medium")   { ThemedButtonView(palette: p, variant: .contained, size: .medium, title: "Medium") }
                cell("large")    { ThemedButtonView(palette: p, variant: .contained, size: .large,  title: "Large") }
                cell("+ icons")  { ThemedButtonView(palette: p, variant: .outlined, title: "Save",
                                                    leading: "tray.and.arrow.down", trailing: "chevron.right") }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("fullWidth").font(sysFont(8, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.tertiary))
                ThemedButtonView(palette: p, variant: .contained, title: "Full width", fullWidth: true)
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

    /// One row of the same variant in each forced state.
    @ViewBuilder
    private func stateRow(_ caption: String, variant: ThemedButton.Variant) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            HStack(spacing: 10) {
                tagged("rest")     { ThemedButtonView(palette: p, variant: variant, title: "Button") }
                tagged("hover")    { ThemedButtonView(palette: p, variant: variant, title: "Button", previewHovered: true) }
                tagged("pressed")  { ThemedButtonView(palette: p, variant: variant, title: "Button", previewPressed: true) }
                tagged("focus")    { ThemedButtonView(palette: p, variant: variant, title: "Button", previewFocused: true) }
                tagged("disabled") { ThemedButtonView(palette: p, variant: variant, title: "Button", enabled: false) }
                Spacer(minLength: 0)
            }
        }
    }

    /// A small sub-caption above a forced-state specimen.
    @ViewBuilder
    private func tagged<V: View>(_ tag: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 3) {
            content()
            Text(tag).font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
        }
    }

    /// A captioned cell holding an intrinsically-sized button, left-aligned.
    @ViewBuilder
    private func cell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }
}
