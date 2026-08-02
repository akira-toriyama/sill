// ThemeKitUI — ThemedTooltipAnchorView: a SwiftUI anchor with a live
// `ThemedTooltip` attached — hover it to see the inverted bubble fade in on its
// own child window. SwiftUI-NATIVE: the anchor is the real `ThemedButtonView`
// and the tooltip attaches through the `.themedTooltip(_:)` modifier (the
// shared `PopupAnchorProxy` supplies the popup controller its NSView anchor —
// floor-2 plumbing, ruled 2026-08-02). (A static tooltip bubble can't appear in
// a screenshot of the host window — it lives on a separate child window; the
// prism grid draws an inline mock instead.)

import SwiftUI
import PaletteKit

public struct ThemedTooltipAnchorView: View {
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    let text: String
    let placement: ThemedTooltip.Placement

    public init(palette: ResolvedPalette? = nil, text: String,
                placement: ThemedTooltip.Placement) {
        self.explicitPalette = palette
        self.text = text
        self.placement = placement
    }

    public var body: some View {
        ThemedButtonView(palette: palette, variant: .outlined, title: "Hover me")
            .themedTooltip(text, palette: palette, placement: placement)
    }
}
