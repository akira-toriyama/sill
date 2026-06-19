// prism — ThemeKit toolbar bench. Hosts the REAL shared `ThemedToolBar` (ThemeKit)
// inside the SwiftUI gallery so the surface / elevation / variant / flex-section
// layout + the composed buttons' hover-press 演出 can be evaluated live in every
// theme. The top row is INTERACTIVE (hover an item, click to bump the counter);
// the rows below force each variant / surface / section / state — the icon-strip
// row uses `previewHoveredItem` (the non-activating-panel hover path) so it
// captures deterministically.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

// MARK: - A lightweight value descriptor (SwiftUI can't carry the NSView-bearing
//         ThemedToolBar.Item across an update, so the bridge rebuilds from these).

enum ToolBarDemoItem {
    case button(title: String?, symbol: String?,
                role: ThemedButton.Role = .primary, variant: ThemedButton.Variant = .text,
                enabled: Bool = true)
    case label(String)
    case flex
    case fixed(CGFloat)
    case divider

    func toItem() -> ThemedToolBar.Item {
        switch self {
        case let .button(t, s, role, variant, enabled):
            return .button(.init(title: t, symbol: s, role: role, variant: variant,
                                 isEnabled: enabled, tooltip: t ?? s))
        case .label(let s):     return .label(s)
        case .flex:             return .flexibleSpace
        case .fixed(let w):     return .fixedSpace(w)
        case .divider:          return .divider
        }
    }
}

// MARK: - SwiftUI bridge for ThemeKit's ThemedToolBar

struct ThemedToolBarView: NSViewRepresentable {
    let palette: ResolvedPalette
    var items: [ToolBarDemoItem]
    var surface: ThemedToolBar.Surface = .surface
    var variant: ThemedToolBar.Variant = .regular
    var corners: ThemedToolBar.Corners = .square
    var elevation: Int = 0
    var trackingMode: ThemedToolBar.TrackingMode = .standard
    var previewHoveredItem: Int? = nil
    var onItemClick: ((Int) -> Void)? = nil

    func makeNSView(context: Context) -> ThemedToolBar {
        let bar = ThemedToolBar(palette: palette)
        apply(to: bar)
        return bar
    }
    func updateNSView(_ bar: ThemedToolBar, context: Context) { apply(to: bar) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedToolBar,
                      context: Context) -> CGSize? {
        let s = nsView.intrinsicContentSize
        if s.width == NSView.noIntrinsicMetric {
            return CGSize(width: proposal.width ?? 360, height: s.height)
        }
        return s
    }

    private func apply(to bar: ThemedToolBar) {
        bar.palette = palette
        bar.surface = surface
        bar.variant = variant
        bar.corners = corners
        bar.elevation = elevation
        bar.trackingMode = trackingMode
        bar.onItemClick = onItemClick
        bar.previewHoveredItem = previewHoveredItem
        bar.items = items.map { $0.toItem() }   // set LAST (rebuilds from current props)
    }
}

// MARK: - Showcase

struct MockToolBar: View {
    let p: ResolvedPalette
    @State private var taps = 0

    private let liveItems: [ToolBarDemoItem] = [
        .button(title: nil, symbol: "list"),
        .label("Inbox"),
        .flex,
        .button(title: nil, symbol: "magnifying-glass"),
        .button(title: nil, symbol: "arrow-clockwise"),
        .divider,
        .button(title: "Compose", symbol: "note-pencil", variant: .contained),
    ]
    private let stripItems: [ToolBarDemoItem] = [
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
    }

    @ViewBuilder
    private func row<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
            HStack(alignment: .top, spacing: 16) { content(); Spacer(minLength: 0) }
        }
    }

    @ViewBuilder
    private func cell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }
}
