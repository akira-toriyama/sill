// prism — ThemeKit toolbar bench. Hosts the REAL shared `ThemedToolBar` (ThemeKit)
// inside the SwiftUI gallery so the surface / elevation / variant / flex-section
// layout + the composed buttons' hover-press 演出 can be evaluated live in every
// theme. The top row is INTERACTIVE (hover an item, click to bump the counter);
// the rows below force each variant / surface / section / state — the icon-strip
// row uses `previewHoveredItem` (the non-activating-panel hover path) so it
// captures deterministically.
//
// The bridge (`ThemedToolBarView`) + its `Item` value descriptor now live in
// ThemeKitUI; this bench just feeds it `[ThemedToolBarView.Item]`.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - Showcase

struct MockToolBar: View, ShowcaseBench {
    var cellSpacing: CGFloat { 4 }
    var cellCaptionSize: CGFloat { 7.5 }
    let p: ResolvedPalette
    @State private var taps = 0

    private let liveItems: [ThemedToolBarView.Item] = [
        .button(title: nil, symbol: "list"),
        .label("Inbox"),
        .flex,
        .button(title: nil, symbol: "magnifying-glass"),
        .button(title: nil, symbol: "arrow-clockwise"),
        .divider,
        .button(title: "Compose", symbol: "note-pencil", variant: .contained),
    ]
    private let stripItems: [ThemedToolBarView.Item] = [
        .button(title: nil, symbol: "text-b"),
        .button(title: nil, symbol: "text-italic"),
        .button(title: nil, symbol: "text-underline"),
        .divider,
        .button(title: nil, symbol: "text-align-left"),
        .button(title: nil, symbol: "text-align-center"),
        .button(title: nil, symbol: "list-bullets", enabled: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ThemeKit · toolbar — the real shared app bar (top row LIVE: hover an item, click to bump)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // LIVE — touchable. Hover an item, click to feel the press; the
            // leading title + flex push the trailing actions to the right edge.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("regular · surface · live").font(sysFont(8, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                    Text("taps: \(taps)").font(sysFont(8, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                }
                ThemedToolBarView(palette: p, items: liveItems) { _ in taps += 1 }
                    .frame(height: 64)
            }

            // Density variants.
            row("variants") {
                cell("regular (64)")  { ThemedToolBarView(palette: p, items: liveItems, variant: .regular).frame(height: 64) }
                cell("dense (48)")    { ThemedToolBarView(palette: p, items: liveItems, variant: .dense).frame(height: 48) }
                cell("compact (40)")  { ThemedToolBarView(palette: p, items: liveItems, variant: .compact).frame(height: 40) }
            }

            // Surface (AppBar color) + elevation + corners.
            row("surface · elevation · corners") {
                cell("surface") { ThemedToolBarView(palette: p, items: liveItems, surface: .surface).frame(height: 56) }
                cell("primary") { ThemedToolBarView(palette: p, items: liveItems, surface: .primary).frame(height: 56) }
                cell("elevation 6") { ThemedToolBarView(palette: p, items: liveItems, surface: .surface, elevation: 6).frame(height: 56) }
                cell("transparent · rounded") {
                    ThemedToolBarView(palette: p, items: liveItems, surface: .transparent, corners: .rounded).frame(height: 56)
                }
            }

            // Sections (flexGrow spacers) — left-title vs centred title.
            row("sections (flex spacers)") {
                cell("left title · right actions (1 flex)") {
                    ThemedToolBarView(palette: p, items: [
                        .button(title: nil, symbol: "list"), .label("Files"), .flex,
                        .button(title: nil, symbol: "plus"), .button(title: nil, symbol: "dots-three"),
                    ]).frame(height: 56)
                }
                cell("centred title (2 flex)") {
                    ThemedToolBarView(palette: p, items: [
                        .button(title: nil, symbol: "caret-left"), .flex,
                        .label("Title"), .flex, .button(title: nil, symbol: "export"),
                    ]).frame(height: 56)
                }
            }

            // Compact icon strip — forced hover via the non-activating-panel path,
            // a disabled item, a vertical divider between clusters.
            row("compact strip · forced hover (item 1) · disabled (item 6) · divider") {
                cell("rest") {
                    ThemedToolBarView(palette: p, items: stripItems, surface: .transparent,
                                      variant: .compact, corners: .rounded).fixedSize()
                }
                cell("hover item 1 (panel mode)") {
                    ThemedToolBarView(palette: p, items: stripItems, surface: .transparent,
                                      variant: .compact, corners: .rounded,
                                      trackingMode: .nonActivatingPanel, previewHoveredItem: 1).fixedSize()
                }
            }
        }
        .showcasePanel(p)
    }

    @ViewBuilder
    private func row<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
            HStack(alignment: .top, spacing: 16) { content(); Spacer(minLength: 0) }
        }
    }
}
