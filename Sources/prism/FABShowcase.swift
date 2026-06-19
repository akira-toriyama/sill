// prism — ThemeKit FAB bench. Hosts the REAL shared `ThemedFAB` (ThemeKit)
// inside the SwiftUI gallery so the float / elevation / hover-press 演出 can be
// evaluated live in every theme. The top row is INTERACTIVE (hover for the
// state layer, click to bump the counter + feel the press deepen the shadow);
// the rows below force each state via the `preview…` overrides for deterministic
// capture. Shaped widget: an NSViewRepresentable fills its SwiftUI frame, so a
// circular FAB is given an explicit square frame (else it stretches to a pill).

import SwiftUI
import PaletteKit
import ThemeKit

// MARK: - SwiftUI bridge for ThemeKit's ThemedFAB

struct ThemedFABView: NSViewRepresentable {
    let palette: ResolvedPalette
    var variant: ThemedFAB.Variant = .circular
    var size: ThemedFAB.Size = .large
    var role: ThemedFAB.Role = .primary
    var symbol: String? = "plus"
    var image: NSImage? = nil          // pre-resolved icon (SVG / logo / …); wins over symbol
    var label: String = ""
    var enabled = true
    var previewHovered = false
    var previewPressed = false
    var previewFocused = false
    var onTap: (() -> Void)? = nil

    func makeNSView(context: Context) -> ThemedFAB {
        let f = ThemedFAB(palette: palette)
        apply(to: f)
        return f
    }
    func updateNSView(_ f: ThemedFAB, context: Context) { apply(to: f) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedFAB,
                      context: Context) -> CGSize? { nsView.intrinsicContentSize }

    private func apply(to f: ThemedFAB) {
        f.palette = palette
        f.variant = variant
        f.size = size
        f.role = role
        f.leadingSymbol = symbol
        f.leadingImage = image
        f.label = label
        f.isEnabled = enabled
        f.previewHovered = previewHovered
        f.previewPressed = previewPressed
        f.previewFocused = previewFocused
        f.onTap = onTap
    }
}

// MARK: - Showcase

struct MockFAB: View {
    let p: ResolvedPalette
    @State private var taps = 0

    /// Circular diameter per size — to pin an explicit square frame so the
    /// representable can't stretch the circle into a pill.
    private func dia(_ s: ThemedFAB.Size) -> CGFloat {
        s == .small ? 40 : s == .medium ? 48 : 56
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · FAB — the real shared control (top row LIVE: hover / click, watch it float)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // LIVE — touchable. Hover for the state layer, click to feel the
            // press deepen the elevation.
            HStack(spacing: 16) {
                circ(.large, role: .primary, symbol: "plus") { taps += 1 }
                ext(.large, role: .primary, symbol: "pencil", label: "Compose") { taps += 1 }
                Text("taps: \(taps)")
                    .font(sysFont(9, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.tertiary))
                Spacer(minLength: 0)
            }

            // Circular — sizes × roles.
            HStack(alignment: .bottom, spacing: 16) {
                tagged("small")     { circ(.small,  role: .primary,   symbol: "plus") }
                tagged("medium")    { circ(.medium, role: .primary,   symbol: "plus") }
                tagged("large")     { circ(.large,  role: .primary,   symbol: "plus") }
                tagged("secondary") { circ(.large,  role: .secondary, symbol: "heart") }
                Spacer(minLength: 0)
            }

            // Circular — forced interaction states.
            HStack(alignment: .bottom, spacing: 16) {
                tagged("rest")     { circ(.medium, role: .primary, symbol: "plus") }
                tagged("hover")    { circ(.medium, role: .primary, symbol: "plus", h: true) }
                tagged("pressed")  { circ(.medium, role: .primary, symbol: "plus", pr: true) }
                tagged("focus")    { circ(.medium, role: .primary, symbol: "plus", fo: true) }
                tagged("disabled") { circ(.medium, role: .primary, symbol: "plus", en: false) }
                Spacer(minLength: 0)
            }

            // Extended — roles + forced states (incl. the wide pill hover overlay
            // + focus ring, geometrically distinct from the circular ring).
            HStack(alignment: .center, spacing: 14) {
                cell("extended · primary")   { ext(.large, role: .primary,   symbol: "plus",       label: "Create") }
                cell("extended · secondary") { ext(.large, role: .secondary, symbol: "export", label: "Share") }
                cell("hover")                { ext(.large, role: .primary,   symbol: "plus",       label: "Create", h: true) }
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 14) {
                cell("focus")                { ext(.large, role: .primary,   symbol: "plus",       label: "Create", fo: true) }
                cell("pressed")              { ext(.large, role: .primary,   symbol: "plus",       label: "Create", pr: true) }
                cell("disabled")             { ext(.large, role: .primary,   symbol: "plus",       label: "Create", en: false) }
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

    /// A circular FAB pinned to an explicit square frame.
    @ViewBuilder
    private func circ(_ size: ThemedFAB.Size, role: ThemedFAB.Role, symbol: String,
                      h: Bool = false, pr: Bool = false, fo: Bool = false,
                      en: Bool = true, _ onTap: (() -> Void)? = nil) -> some View {
        ThemedFABView(palette: p, variant: .circular, size: size, role: role,
                      symbol: symbol, enabled: en,
                      previewHovered: h, previewPressed: pr, previewFocused: fo, onTap: onTap)
            .frame(width: dia(size), height: dia(size))
    }

    /// An extended FAB (sizes to its intrinsic content).
    @ViewBuilder
    private func ext(_ size: ThemedFAB.Size, role: ThemedFAB.Role, symbol: String,
                     label: String, h: Bool = false, pr: Bool = false,
                     fo: Bool = false, en: Bool = true,
                     _ onTap: (() -> Void)? = nil) -> some View {
        ThemedFABView(palette: p, variant: .extended, size: size, role: role,
                      symbol: symbol, label: label, enabled: en,
                      previewHovered: h, previewPressed: pr, previewFocused: fo, onTap: onTap)
            .fixedSize()
    }

    @ViewBuilder
    private func cell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            HStack(spacing: 0) { content(); Spacer(minLength: 0) }
        }
    }
    @ViewBuilder
    private func tagged<V: View>(_ tag: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 4) {
            content()
            Text(tag).font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
        }
    }
}
