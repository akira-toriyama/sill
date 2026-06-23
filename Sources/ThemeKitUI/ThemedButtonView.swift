// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedButton`. Hosts the REAL
// shared AppKit button inside SwiftUI so an app's View layer drives it from an
// `NSHostingView` shell. Sizes to the button's own intrinsic content (so it
// doesn't stretch to fill its frame) — except `fullWidth`, which takes the
// proposal. The `preview…` overrides force hover / pressed / focused for
// deterministic capture.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedButtonView: NSViewRepresentable {
    let palette: ResolvedPalette
    var variant: ThemedButton.Variant
    var size: ThemedButton.Size
    var role: ThemedButton.Role
    var title: String
    var leading: String?
    var trailing: String?
    var leadingImage: NSImage?      // pre-resolved icon (SVG / logo / …)
    var trailingImage: NSImage?
    var fullWidth: Bool
    var enabled: Bool
    var previewHovered: Bool
    var previewPressed: Bool
    var previewFocused: Bool
    var onTap: (() -> Void)?

    public init(palette: ResolvedPalette, variant: ThemedButton.Variant = .text,
                size: ThemedButton.Size = .medium, role: ThemedButton.Role = .primary,
                title: String = "Button", leading: String? = nil, trailing: String? = nil,
                leadingImage: NSImage? = nil, trailingImage: NSImage? = nil,
                fullWidth: Bool = false, enabled: Bool = true,
                previewHovered: Bool = false, previewPressed: Bool = false,
                previewFocused: Bool = false, onTap: (() -> Void)? = nil) {
        self.palette = palette
        self.variant = variant
        self.size = size
        self.role = role
        self.title = title
        self.leading = leading
        self.trailing = trailing
        self.leadingImage = leadingImage
        self.trailingImage = trailingImage
        self.fullWidth = fullWidth
        self.enabled = enabled
        self.previewHovered = previewHovered
        self.previewPressed = previewPressed
        self.previewFocused = previewFocused
        self.onTap = onTap
    }

    public func makeNSView(context: Context) -> ThemedButton {
        let b = ThemedButton(palette: palette)
        apply(to: b)
        return b
    }

    public func updateNSView(_ b: ThemedButton, context: Context) { apply(to: b) }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedButton,
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
        b.leadingImage = leadingImage
        b.trailingImage = trailingImage
        b.fullWidth = fullWidth
        b.isEnabled = enabled
        b.previewHovered = previewHovered
        b.previewPressed = previewPressed
        b.previewFocused = previewFocused
        b.onTap = onTap
    }
}
