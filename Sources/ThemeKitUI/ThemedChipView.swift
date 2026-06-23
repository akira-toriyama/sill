// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedChip`. Hosts the REAL shared
// AppKit chip inside SwiftUI (filled / outlined / keycap). `clickable` gates
// `onTap`, `deletable` gates the trailing × (`onDelete`); the `preview…`
// overrides force hover / pressed / focused for deterministic capture. Sizes to
// the chip's own intrinsic content (so it hugs its label).

import SwiftUI
import PaletteKit
import ThemeKit

public struct ThemedChipView: NSViewRepresentable {
    let palette: ResolvedPalette
    var variant: ThemedChip.Variant
    var size: ThemedChip.Size
    var role: ThemedChip.Role
    var title: String
    var leading: String?
    var selected: Bool
    var enabled: Bool
    var previewHovered: Bool
    var previewPressed: Bool
    var previewFocused: Bool
    var clickable: Bool
    var deletable: Bool
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    public init(palette: ResolvedPalette, variant: ThemedChip.Variant = .filled,
                size: ThemedChip.Size = .medium, role: ThemedChip.Role = .neutral,
                title: String = "Tag", leading: String? = nil, selected: Bool = false,
                enabled: Bool = true, previewHovered: Bool = false,
                previewPressed: Bool = false, previewFocused: Bool = false,
                clickable: Bool = false, deletable: Bool = false,
                onTap: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.palette = palette
        self.variant = variant
        self.size = size
        self.role = role
        self.title = title
        self.leading = leading
        self.selected = selected
        self.enabled = enabled
        self.previewHovered = previewHovered
        self.previewPressed = previewPressed
        self.previewFocused = previewFocused
        self.clickable = clickable
        self.deletable = deletable
        self.onTap = onTap
        self.onDelete = onDelete
    }

    public func makeNSView(context: Context) -> ThemedChip {
        let c = ThemedChip(palette: palette)
        apply(to: c)
        return c
    }

    public func updateNSView(_ c: ThemedChip, context: Context) { apply(to: c) }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedChip,
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
