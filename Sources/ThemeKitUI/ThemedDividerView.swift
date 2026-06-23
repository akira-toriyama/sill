// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedDivider`. Hosts the REAL
// shared AppKit hairline inside SwiftUI (orientation / variant / text-in-divider
// gap). `surface` is the backing colour the hairline sits on.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedDividerView: NSViewRepresentable {
    let palette: ResolvedPalette
    var orientation: ThemedDivider.Orientation
    var variant: ThemedDivider.Variant
    var label: String?
    var surface: NSColor?

    public init(palette: ResolvedPalette,
                orientation: ThemedDivider.Orientation = .horizontal,
                variant: ThemedDivider.Variant = .fullWidth,
                label: String? = nil, surface: NSColor? = nil) {
        self.palette = palette
        self.orientation = orientation
        self.variant = variant
        self.label = label
        self.surface = surface
    }

    public func makeNSView(context: Context) -> ThemedDivider {
        let d = ThemedDivider(palette: palette)
        apply(to: d)
        return d
    }

    public func updateNSView(_ d: ThemedDivider, context: Context) { apply(to: d) }

    private func apply(to d: ThemedDivider) {
        d.palette = palette
        d.orientation = orientation
        d.variant = variant
        d.label = label
        d.surfaceColor = surface
    }
}
