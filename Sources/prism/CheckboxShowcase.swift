// prism — ThemeKit checkbox bench. Hosts the REAL shared `ThemedCheckbox`
// (ThemeKit) inside the SwiftUI gallery so the box / check-draw-in / hover circle
// can be evaluated live in every theme. The top row is INTERACTIVE (click to
// toggle, watch the checkmark draw in + the hover circle); the rows below force
// each state via the `preview…` overrides for deterministic capture.

import SwiftUI
import PaletteKit
import ThemeKit

// MARK: - SwiftUI bridge for ThemeKit's ThemedCheckbox

struct ThemedCheckboxView: NSViewRepresentable {
    let palette: ResolvedPalette
    var size: ThemedCheckbox.Size = .medium
    var label: String? = nil
    var isChecked = false
    var isIndeterminate = false
    var enabled = true
    var previewHovered = false
    var previewPressed = false
    var previewFocused = false
    var previewChecked: Bool? = nil
    var previewIndeterminate: Bool? = nil
    var onChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> ThemedCheckbox {
        let c = ThemedCheckbox(palette: palette)
        apply(to: c)
        return c
    }
    func updateNSView(_ c: ThemedCheckbox, context: Context) { apply(to: c) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedCheckbox,
                      context: Context) -> CGSize? { nsView.intrinsicContentSize }

    private func apply(to c: ThemedCheckbox) {
        c.palette = palette
        c.size = size
        c.label = label
        c.isChecked = isChecked
        c.isIndeterminate = isIndeterminate
        c.isEnabled = enabled
        c.previewHovered = previewHovered
        c.previewPressed = previewPressed
        c.previewFocused = previewFocused
        c.previewChecked = previewChecked
        c.previewIndeterminate = previewIndeterminate
        c.onChange = onChange
    }
}

// MARK: - Showcase

struct MockCheckbox: View {
    let p: ResolvedPalette
    @State private var on = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · checkbox — the real shared control (top row LIVE: click to toggle)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // LIVE — toggle it, watch the check draw in + the hover circle.
            HStack(spacing: 12) {
                cell("live + label") {
                    ThemedCheckboxView(palette: p, label: "Enable notifications",
                                       isChecked: on, onChange: { on = $0 })
                }
                Text("state: \(on ? "on" : "off")")
                    .font(sysFont(9, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.tertiary))
                Spacer(minLength: 0)
            }

            // Glyph states × sizes (forced).
            HStack(spacing: 18) {
                tagged("unchecked") { ThemedCheckboxView(palette: p, previewChecked: false) }
                tagged("checked")   { ThemedCheckboxView(palette: p, previewChecked: true) }
                tagged("indeterminate") { ThemedCheckboxView(palette: p, previewIndeterminate: true) }
                tagged("small ✓")  { ThemedCheckboxView(palette: p, size: .small, previewChecked: true) }
                tagged("small ☐")  { ThemedCheckboxView(palette: p, size: .small, previewChecked: false) }
                Spacer(minLength: 0)
            }

            // Interaction states (forced — preview flags in declaration order).
            HStack(spacing: 18) {
                tagged("hover ☐")  { ThemedCheckboxView(palette: p, previewHovered: true, previewChecked: false) }
                tagged("hover ✓")  { ThemedCheckboxView(palette: p, previewHovered: true, previewChecked: true) }
                tagged("pressed")  { ThemedCheckboxView(palette: p, previewPressed: true, previewChecked: true) }
                tagged("focus")    { ThemedCheckboxView(palette: p, previewFocused: true, previewChecked: true) }
                tagged("disabled ✓") { ThemedCheckboxView(palette: p, enabled: false, previewChecked: true) }
                tagged("disabled ☐") { ThemedCheckboxView(palette: p, enabled: false, previewChecked: false) }
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

    @ViewBuilder
    private func cell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }
    @ViewBuilder
    private func tagged<V: View>(_ tag: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) { content(); Spacer(minLength: 0) }.frame(width: 44)
            Text(tag).font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
        }
    }
}
