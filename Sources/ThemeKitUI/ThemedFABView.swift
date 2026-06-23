// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedFAB`. Hosts the REAL shared
// AppKit floating action button inside SwiftUI (float / elevation / hover-press).
// `image` (pre-resolved icon) wins over `symbol`; the `preview…` overrides force
// each state for deterministic capture. Note: an NSViewRepresentable fills its
// SwiftUI frame, so give a circular FAB an explicit square frame at the call site
// (else it stretches to a pill).

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedFABView: NSViewRepresentable {
    let palette: ResolvedPalette
    var variant: ThemedFAB.Variant
    var size: ThemedFAB.Size
    var role: ThemedFAB.Role
    var symbol: String?
    var image: NSImage?          // pre-resolved icon (SVG / logo / …); wins over symbol
    var label: String
    var enabled: Bool
    var previewHovered: Bool
    var previewPressed: Bool
    var previewFocused: Bool
    var onTap: (() -> Void)?

    public init(palette: ResolvedPalette, variant: ThemedFAB.Variant = .circular,
                size: ThemedFAB.Size = .large, role: ThemedFAB.Role = .primary,
                symbol: String? = "plus", image: NSImage? = nil, label: String = "",
                enabled: Bool = true, previewHovered: Bool = false,
                previewPressed: Bool = false, previewFocused: Bool = false,
                onTap: (() -> Void)? = nil) {
        self.palette = palette
        self.variant = variant
        self.size = size
        self.role = role
        self.symbol = symbol
        self.image = image
        self.label = label
        self.enabled = enabled
        self.previewHovered = previewHovered
        self.previewPressed = previewPressed
        self.previewFocused = previewFocused
        self.onTap = onTap
    }

    public func makeNSView(context: Context) -> ThemedFAB {
        let f = ThemedFAB(palette: palette)
        apply(to: f)
        return f
    }

    public func updateNSView(_ f: ThemedFAB, context: Context) { apply(to: f) }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedFAB,
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
