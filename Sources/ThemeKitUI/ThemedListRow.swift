// ThemeKitUI — the per-row SwiftUI subview for `ThemedListView` (#17b M2). Task 3
// form is TEXT-ONLY (primary/secondary/header/separator); the themed decorations
// (zebra/tint/selection/hover/outline · leading image · trailing cluster · dividers ·
// section-header chrome · sticky) are layered on in Tasks 4-7, and interaction
// (tap/hover/collapse/drag) in Tasks 8-15. All metrics come from `ListMetrics`.

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

    /// x of the row's CONTENT (image/text). Decorations stay full-bleed (x=0) — added later.
    private var contentLeadingX: CGFloat {
        let base = style.reservesLeadingImageColumn ? metrics.textXOrigin : metrics.leadingInset
        return base + CGFloat(max(0, item.indentLevel)) * metrics.indentStep
    }

    private func secondaryFont() -> Font {
        item.secondaryMono
            ? .system(size: 11, weight: .medium, design: .monospaced)
            : Font(palette.uiFont(.secondaryBody) as CTFont)
    }

    var body: some View {
        content
            .padding(.leading, contentLeadingX)
            .padding(.trailing, metrics.trailingInset)
            .frame(height: rowHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

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
                    .foregroundColor(Color(nsColor: item.isDisabled ? palette.tertiary : palette.foreground))
                    .lineLimit(1)
                if let secondary = item.secondary {
                    Text(secondary)
                        .font(secondaryFont())
                        .foregroundColor(Color(nsColor: palette.muted))
                        .lineLimit(1)
                }
            }
        }
    }
}
