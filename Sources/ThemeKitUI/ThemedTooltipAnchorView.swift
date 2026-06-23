// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedTooltip`. A real anchor (a
// `ThemedButton`) with a live `ThemedTooltip` attached: hover it to see the
// inverted bubble fade in on its own child window. The tooltip is a CONTROLLER,
// so the Coordinator retains it. (A static tooltip bubble can't appear in a
// screenshot of the host window — it lives on a separate child window.)

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedTooltipAnchorView: NSViewRepresentable {
    let palette: ResolvedPalette
    let text: String
    let placement: ThemedTooltip.Placement

    public init(palette: ResolvedPalette, text: String,
                placement: ThemedTooltip.Placement) {
        self.palette = palette
        self.text = text
        self.placement = placement
    }

    public final class Coordinator { var tooltip: ThemedTooltip? }
    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> ThemedButton {
        let b = ThemedButton(palette: palette)
        b.variant = .outlined
        b.title = "Hover me"
        context.coordinator.tooltip =
            ThemedTooltip.attach(to: b, text: text, palette: palette, placement: placement)
        return b
    }

    public func updateNSView(_ b: ThemedButton, context: Context) {
        b.palette = palette
        b.title = "Hover me"
        if let t = context.coordinator.tooltip {
            t.palette = palette
            t.text = text
            t.placement = placement
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedButton,
                             context: Context) -> CGSize? { nsView.intrinsicContentSize }
}
