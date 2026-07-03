// ThemeKitUI — the per-row SwiftUI subview for `ThemedListView` (#17b M2). Reproduces
// the AppKit `ThemedList`'s per-row draw 1:1 from `ResolvedPalette` roles + `ListMetrics`
// (mirror of `ThemedList.swift` drawRow :1145-1300). Background decorations
// (zebra/tint/selection/hover/outline) land here in Task 4; leading image (Task 5) and
// trailing cluster (Task 6) follow. All fills are FULL-BLEED (x=0) — only content indents.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit
import ListCore

struct ThemedListRow<ID: Hashable & Sendable>: View {
    let item: ListItem<ID>
    let metrics: ListMetrics
    let style: ThemedListStyle
    let palette: ResolvedPalette
    let isSelected: Bool
    let isHighlighted: Bool
    var isHovered: Bool = false        // wired in Task 8; drives the wash-mode pointer veil
    var zebraOdd: Bool = false         // parity from ThemedListView (resets per section)
    var surfaceOpaque: Bool = true     // zebra only paints on an opaque surface

    // MARK: draw decisions (mirror ThemedList.highlightFillAndAccent :1261)

    private var fillsHighlight: Bool { isHighlighted && style.highlightStyle == .fill }
    private var drawsFill: Bool { isSelected || fillsHighlight }
    private var onAccent: Bool { drawsFill && style.hoverStyle == .solidAccent }
    private var paintsZebra: Bool {
        style.zebra && surfaceOpaque && !isSelected && !fillsHighlight && zebraOdd
    }
    private var showsTintBar: Bool {
        if case .none = item.tint { return false }
        return !onAccent
    }

    // MARK: geometry

    private var rowHeight: CGFloat {
        switch item.kind {
        case .separator:
            return metrics.separatorBand
        case let .sectionHeader(subtitle, _):
            return subtitle == nil ? metrics.header1 : metrics.header2
        case .row:
            return item.secondary == nil ? metrics.singleRow : metrics.twoLineRow
        }
    }

    /// x of the row's CONTENT (image/text). Decorations stay full-bleed (x=0).
    private var contentLeadingX: CGFloat {
        let base = style.reservesLeadingImageColumn ? metrics.textXOrigin : metrics.leadingInset
        return base + CGFloat(max(0, item.indentLevel)) * metrics.indentStep
    }

    // MARK: colors

    private func secondaryFont() -> Font {
        item.secondaryMono
            ? .system(size: 11, weight: .medium, design: .monospaced)
            : Font(palette.uiFont(.secondaryBody) as CTFont)
    }
    private var primaryColor: Color {
        onAccent ? Color(nsColor: palette.onPrimary(1))
                 : Color(nsColor: item.isDisabled ? palette.tertiary : palette.foreground)
    }
    private var secondaryColor: Color {
        onAccent ? Color(nsColor: palette.onPrimary(0.65))
                 : Color(nsColor: item.isDisabled ? palette.tertiary : palette.muted)
    }
    private var tintColor: Color {
        switch item.tint {
        case .none:            return .clear
        case .primary:         return Color(nsColor: palette.primary)
        case .secondary:       return Color(nsColor: palette.secondary)
        case .error:           return Color(nsColor: palette.error)
        case let .custom(hex): return Color(nsColor: NSColor(hex))
        }
    }

    var body: some View {
        content
            .padding(.leading, contentLeadingX)
            .padding(.trailing, metrics.trailingInset)
            .frame(height: rowHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(outlineRing)
    }

    // MARK: background decorations (full-bleed, .row only — headers/separators self-draw)

    @ViewBuilder private var rowBackground: some View {
        if case .row = item.kind {
            ZStack(alignment: .leading) {
                if paintsZebra {
                    Rectangle().fill(Color(nsColor: palette.hover).opacity(0.4))
                }
                if showsTintBar {
                    Rectangle().fill(tintColor)
                        .frame(width: metrics.accentBar)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if drawsFill {
                    selectionFill
                }
                if style.hoverStyle == .wash, isSelected, isHovered {
                    selectionShape(Color(nsColor: palette.hover))
                }
            }
        }
    }

    @ViewBuilder private var selectionFill: some View {
        if onAccent {
            selectionShape(Color(nsColor: palette.primary))       // opaque accent (wand's tome)
        } else {
            ZStack(alignment: .leading) {
                selectionShape(Color(nsColor: palette.selection))  // wash
                if !style.roundedSelection {                       // 3pt primary accent bar (combo's)
                    Rectangle().fill(Color(nsColor: palette.primary))
                        .frame(width: metrics.accentBar)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The selection/hover shape: a horizontally-inset rounded pill, or a full-bleed rect.
    @ViewBuilder private func selectionShape(_ color: Color) -> some View {
        if style.roundedSelection {
            RoundedRectangle(cornerRadius: metrics.roundedRadius).fill(color)
                .padding(.horizontal, metrics.roundedHInset)
        } else {
            Rectangle().fill(color)
        }
    }

    /// The keyboard cursor ring (highlightStyle == .outline): a 1.5pt primary stroke ON
    /// TOP of any fill, inset so the stroke isn't clipped at the row edges.
    @ViewBuilder private var outlineRing: some View {
        if case .row = item.kind, isHighlighted, style.highlightStyle == .outline {
            RoundedRectangle(cornerRadius: metrics.roundedRadius)
                .inset(by: 1.5)
                .stroke(Color(nsColor: palette.primary), lineWidth: 1.5)
        }
    }

    // MARK: content (text-only for now; image Task 5, trailing cluster Task 6)

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .separator:
            EmptyView()
        case let .sectionHeader(subtitle, _):
            if let subtitle {
                VStack(alignment: .leading, spacing: metrics.lineGap) {
                    Text(item.primary)
                        .font(Font(palette.uiFont(.sectionTitle) as CTFont))
                        .foregroundColor(Color(nsColor: palette.foreground))
                    Text(subtitle)
                        .font(Font(palette.uiFont(.caption) as CTFont))
                        .foregroundColor(Color(nsColor: palette.muted))
                }
            } else {
                Text(item.primary.uppercased())
                    .font(Font(palette.uiFont(.sectionHeader) as CTFont))
                    .tracking(0.5)
                    .foregroundColor(Color(nsColor: palette.muted))
            }
        case .row:
            VStack(alignment: .leading, spacing: metrics.lineGap) {
                Text(item.primary)
                    .font(Font(palette.uiFont(.body) as CTFont))
                    .foregroundColor(primaryColor)
                    .lineLimit(1)
                if let secondary = item.secondary {
                    Text(secondary)
                        .font(secondaryFont())
                        .foregroundColor(secondaryColor)
                        .lineLimit(1)
                }
            }
        }
    }
}
