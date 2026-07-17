// prism — shared showcase chrome. Every widget bench wraps itself in the
// same padded panel (theme background + hairline rim) and labels specimens
// with the same tertiary monospaced caption/tag, but each showcase carried
// its own verbatim copy (~39 across the target). This file is the single
// home for that chrome: `View.showcasePanel(_:stroke:)` is the panel,
// `ShowcaseBench` vends the captioned/tagged cells to any bench that
// exposes its palette as `p`. Values are the historical per-showcase ones —
// a bench overrides a knob (`cellSpacing`, `cellCaptionSize`) or keeps a
// private helper only where it always diverged.

import SwiftUI
import PaletteKit

extension View {
    /// The standard showcase panel: 12pt padding, full-width leading
    /// alignment, the theme background as a rounded card with a 1pt rim
    /// (`panelStroke` unless a showcase always used another stroke).
    @MainActor
    func showcasePanel(_ p: ResolvedPalette, stroke: NSColor? = nil) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: stroke ?? panelStroke(p)), lineWidth: 1))
    }
}

/// A showcase bench that labels its specimens with the shared caption/tag
/// typography. Conforming is one line for any view with a `p` palette;
/// a bench whose cell was never the shared shape keeps its private helper
/// (the concrete member wins over these defaults).
@MainActor
protocol ShowcaseBench {
    var p: ResolvedPalette { get }
    /// Caption-to-content gap of `cell` (historically 5, some benches 6/4).
    var cellSpacing: CGFloat { get }
    /// Caption point size of `cell` (historically 8, ToolBar 7.5).
    var cellCaptionSize: CGFloat { get }
}

extension ShowcaseBench {
    var cellSpacing: CGFloat { 5 }
    var cellCaptionSize: CGFloat { 8 }

    /// A captioned cell: small tertiary monospaced caption above the specimen.
    func cell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: cellSpacing) {
            Text(caption).font(sysFont(cellCaptionSize, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }

    /// A tagged specimen: the content above a tiny tertiary monospaced tag.
    func tagged<V: View>(_ tag: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 3) {
            content()
            Text(tag).font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
        }
    }
}
