// prism — ThemeKit Tooltip bench. A tooltip lives on its OWN borderless child
// window, which `screencapture -l<winid>` of prism's main window can NEVER
// include — so the per-theme grid draws the rendered bubble IN-WINDOW with the
// REAL kit: `ThemedTooltip.previewBubble`, the controller's own measurement +
// model pipeline (fill `foreground@0.92`, best-contrast ink, the palette font,
// the edge arrow) across all four placements + a wrapped 300 px variant. A
// LIVE anchor row hosts the REAL `ThemedTooltip` attached to a real control so
// the hover-show / fade / placement-flip 演出 can be felt by hand (it just
// won't appear in a static capture; `.themedTooltip(_:previewVisible:)` can
// freeze it live for interactive verification).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import ThemeKitUI

struct MockTooltip: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · Tooltip — inverted bubble (foreground@0.92). Top row is the REAL control on its own window (hover live); grid below is the real bubble drawn in-window (ThemedTooltip.previewBubble — the controller's own measurement + model pipeline).")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            // LIVE — hover the real anchors; their tooltips appear on a separate
            // child window (won't show in a prism screenshot, but proves the 演出).
            HStack(spacing: 24) {
                liveCell("bottom (auto)", placement: .auto)
                liveCell("top",          placement: .top)
                liveCell("trailing",     placement: .trailing)
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 28) {
                mockCell("top")      { ThemedTooltip.previewBubble(text: "Add item", palette: p, placement: .top) }
                mockCell("bottom")   { ThemedTooltip.previewBubble(text: "Add item", palette: p, placement: .bottom) }
                mockCell("leading")  { ThemedTooltip.previewBubble(text: "Add item", palette: p, placement: .leading) }
                mockCell("trailing") { ThemedTooltip.previewBubble(text: "Add item", palette: p, placement: .trailing) }
                Spacer(minLength: 0)
            }

            mockCell("wrapped · 300px max") {
                ThemedTooltip.previewBubble(
                    text: "Tooltips wrap past 300 points so a longer hint stays readable.",
                    palette: p, placement: .bottom)
            }
        }
        .showcasePanel(p)
    }

    @ViewBuilder
    private func liveCell(_ caption: String, placement: ThemedTooltip.Placement) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            ThemedTooltipAnchorView(palette: p, text: "A live themed tooltip", placement: placement)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func mockCell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            HStack(spacing: 0) { content(); Spacer(minLength: 0) }
        }
    }
}
