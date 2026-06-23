// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedButtonGroup`. Hosts the REAL
// shared AppKit joined-button group inside SwiftUI (joined seams / corners /
// divider / elevation). `titles` builds the segments; `disabledMember` disables
// one; the `preview…` overrides force selection / hover / focus for capture.

import SwiftUI
import PaletteKit
import ThemeKit

public struct ThemedButtonGroupView: NSViewRepresentable {
    let palette: ResolvedPalette
    var titles: [String]
    var orientation: ThemedButtonGroup.Orientation
    var variant: ThemedButton.Variant
    var size: ThemedButton.Size
    var role: ThemedButton.Role
    var mode: ThemedButtonGroup.Mode
    var fullWidth: Bool
    var enabled: Bool
    var disabledMember: Int?
    var selectedIndex: Int?
    var previewSelectedIndex: Int?
    var previewHoveredIndex: Int?
    var previewFocusedIndex: Int?
    var onTap: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?

    public init(palette: ResolvedPalette, titles: [String],
                orientation: ThemedButtonGroup.Orientation = .horizontal,
                variant: ThemedButton.Variant = .outlined,
                size: ThemedButton.Size = .medium, role: ThemedButton.Role = .primary,
                mode: ThemedButtonGroup.Mode = .actions, fullWidth: Bool = false,
                enabled: Bool = true, disabledMember: Int? = nil, selectedIndex: Int? = nil,
                previewSelectedIndex: Int? = nil, previewHoveredIndex: Int? = nil,
                previewFocusedIndex: Int? = nil, onTap: ((Int) -> Void)? = nil,
                onSelect: ((Int) -> Void)? = nil) {
        self.palette = palette
        self.titles = titles
        self.orientation = orientation
        self.variant = variant
        self.size = size
        self.role = role
        self.mode = mode
        self.fullWidth = fullWidth
        self.enabled = enabled
        self.disabledMember = disabledMember
        self.selectedIndex = selectedIndex
        self.previewSelectedIndex = previewSelectedIndex
        self.previewHoveredIndex = previewHoveredIndex
        self.previewFocusedIndex = previewFocusedIndex
        self.onTap = onTap
        self.onSelect = onSelect
    }

    public func makeNSView(context: Context) -> ThemedButtonGroup {
        let g = ThemedButtonGroup(palette: palette)
        apply(to: g)
        return g
    }

    public func updateNSView(_ g: ThemedButtonGroup, context: Context) { apply(to: g) }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedButtonGroup,
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
