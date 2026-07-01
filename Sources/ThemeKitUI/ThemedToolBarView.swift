// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedToolBar`. Hosts the REAL
// shared AppKit toolbar inside SwiftUI (surface / elevation / variant / flex
// sections + composed-button hover-press). `previewHoveredItem` forces the
// non-activating-panel hover path for deterministic capture.
//
// Items are passed as `ThemedToolBarView.Item` VALUE descriptors, not
// `ThemedToolBar.Item` directly: the latter has a `.custom(NSView)` case, so it
// is NSView-bearing and can't be safely carried across a SwiftUI update — the
// bridge rebuilds the live items from these descriptors each `updateNSView`.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedToolBarView: NSViewRepresentable {

    /// A SwiftUI-carryable value descriptor for a toolbar item (the subset that
    /// is not NSView-bearing). Mapped to the real `ThemedToolBar.Item` per update.
    public enum Item {
        case button(title: String?, symbol: String?, trailingSymbol: String? = nil,
                    role: ThemedButton.Role = .primary, variant: ThemedButton.Variant = .text,
                    enabled: Bool = true)
        case label(String)
        case flex
        case fixed(CGFloat)
        case divider

        func toItem() -> ThemedToolBar.Item {
            switch self {
            case let .button(t, s, trailing, role, variant, enabled):
                return .button(.init(title: t, symbol: s, trailingSymbol: trailing, role: role, variant: variant,
                                     isEnabled: enabled, tooltip: t ?? s))
            case .label(let s):     return .label(s)
            case .flex:             return .flexibleSpace
            case .fixed(let w):     return .fixedSpace(w)
            case .divider:          return .divider
            }
        }
    }

    let palette: ResolvedPalette
    var items: [Item]
    var surface: ThemedToolBar.Surface
    var variant: ThemedToolBar.Variant
    var corners: ThemedToolBar.Corners
    var elevation: Int
    var trackingMode: ThemedToolBar.TrackingMode
    var previewHoveredItem: Int?
    var onItemClick: ((Int) -> Void)?

    public init(palette: ResolvedPalette, items: [Item],
                surface: ThemedToolBar.Surface = .surface,
                variant: ThemedToolBar.Variant = .regular,
                corners: ThemedToolBar.Corners = .square, elevation: Int = 0,
                trackingMode: ThemedToolBar.TrackingMode = .standard,
                previewHoveredItem: Int? = nil, onItemClick: ((Int) -> Void)? = nil) {
        self.palette = palette
        self.items = items
        self.surface = surface
        self.variant = variant
        self.corners = corners
        self.elevation = elevation
        self.trackingMode = trackingMode
        self.previewHoveredItem = previewHoveredItem
        self.onItemClick = onItemClick
    }

    public func makeNSView(context: Context) -> ThemedToolBar {
        let bar = ThemedToolBar(palette: palette)
        apply(to: bar)
        return bar
    }

    public func updateNSView(_ bar: ThemedToolBar, context: Context) { apply(to: bar) }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedToolBar,
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
