// ThemeKitUI — the per-row SwiftUI subview for `ThemedListView` (#17b M2). Reproduces
// the AppKit `ThemedList`'s per-row draw 1:1 from `ResolvedPalette` roles + `ListMetrics`
// (mirror of `ThemedList.swift` drawRow :1145-1300). Background decorations
// (zebra/tint/selection/hover/outline) + leading image column live here; the trailing
// cluster (badges/shortcut/chevron) lands in Task 6, section-header chrome in Task 7.
// All fills are FULL-BLEED (x=0) — only content indents (the MUI tree model).

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
    var dividerInset: CGFloat? = nil   // per-row divider leading x (nil = none; 0 = full-bleed above a header)
    var isCollapsed: Bool = false      // collapsible-header caret state (binding- or Kind-driven)
    var dimmed: Bool = false           // lifted drag source / chunk member (M2c)
    var drop: RowDrop? = nil           // drop affordance this row draws (M2c)

    private var rowSurface: NSColor? { style.surfaceColor ?? palette.background }
    /// This row's content text x (for a depth-aligned insertion line).
    private var contentTextX: CGFloat {
        (style.reservesLeadingImageColumn ? metrics.textXOrigin : metrics.leadingInset) + indentWidth
    }

    // MARK: draw decisions (mirror ThemedList.highlightFillAndAccent :1261)

    private var fillsHighlight: Bool { isHighlighted && style.highlightStyle == .fill }
    private var drawsFill: Bool { isSelected || fillsHighlight }
    private var onAccent: Bool { drawsFill && style.selectionInk == .solidAccent }
    private var paintsZebra: Bool {
        style.zebra && surfaceOpaque && !isSelected && !fillsHighlight && zebraOdd
    }
    private var showsTintBar: Bool {
        if case .none = item.tint { return false }
        return !onAccent
    }

    private var indentWidth: CGFloat { CGFloat(max(0, item.indentLevel)) * metrics.indentStep }

    private var rowHeight: CGFloat { item.laidOutHeight(metrics) }

    private var isCollapsibleHeader: Bool {
        if case let .sectionHeader(_, collapsed) = item.kind { return !item.isDisabled && collapsed != nil }
        return false
    }

    private func secondaryFont() -> Font {
        item.secondaryMono
            ? .system(size: 11, weight: .medium, design: .monospaced)
            : Font(palette.uiFont(.secondaryBody) as CTFont)
    }
    /// NB `disabledInk` (== `muted`), NOT `tertiary`. This row used to resolve
    /// disabled to `tertiary` while every themed CONTROL resolved it to
    /// `muted` — two greys for one state, visible the moment a disabled button
    /// and a disabled row shared a surface. `tertiary` means the third
    /// EMPHASIS tier, which is a different concept from unavailable.
    private var primaryColor: Color {
        onAccent ? Color(nsColor: palette.onPrimary(1))
                 : Color(nsColor: item.isDisabled ? palette.disabledInk : palette.foreground)
    }
    /// A row that draws a selection/highlight WASH has to re-check its
    /// secondary line against the wash, not against the background: `muted` on
    /// a flattened `selection` lands under the 3:1 supplementary-text floor on
    /// 16 of the 34 fixed presets (dracula worst, 2.18). `secondaryInk(on:)`
    /// returns `muted` unchanged wherever it is already legible, so themes that
    /// were fine are untouched.
    private var secondaryColor: Color {
        if onAccent { return Color(nsColor: palette.onPrimary(0.65)) }
        if item.isDisabled { return Color(nsColor: palette.disabledInk) }
        if drawsFill { return Color(nsColor: palette.secondaryInk(on: flattenedSelection)) }
        return Color(nsColor: palette.muted)
    }

    /// The opaque colour a selection/highlight wash actually resolves to on
    /// this row's surface — what the secondary line is really drawn on.
    private var flattenedSelection: NSColor {
        palette.flatten(palette.selection, over: rowSurface ?? .textBackgroundColor)
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
        rowContent
            .frame(height: rowHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(alignment: .bottom) { bottomRule }
            .overlay(outlineRing)
            .opacity(dimmed ? 0.4 : 1)     // lifted drag source / chunk member dims
            .overlay { dropOverlay }       // drop affordance at full opacity, above the dim
            .modifier(RowAX(vends: style.vendsRowAXElements && item.asRow.isSelectable,
                            flattens: style.flattensRowAXChildren,
                            label: axLabel))
    }

    /// The label VoiceOver reads for an actionable row (opt-in via `vendsRowAXElements`,
    /// the menu's per-row `.menuItem` parity) — the primary text, with a spoken
    /// "checked" marker folded in for a checked (toggle) row.
    private var axLabel: String { item.axChecked ? "\(item.primary), checked" : item.primary }

    // MARK: drop affordance (drawn relative to this row — ThemedList :1872-1911)

    @ViewBuilder private var dropOverlay: some View {
        switch drop {
        case .onto:
            RoundedRectangle(cornerRadius: metrics.roundedRadius).inset(by: 1.5)
                .fill(Color(nsColor: palette.primary).opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: metrics.roundedRadius).inset(by: 1.5)
                    .stroke(Color(nsColor: palette.primary), lineWidth: 2))
        case .betweenAbove:  insertionLine(.top)
        case .betweenBelow:  insertionLine(.bottom)
        case .sectionBarAbove: sectionBar(.top)
        case .sectionBarBelow: sectionBar(.bottom)
        case .none:          EmptyView()
        }
    }

    @ViewBuilder private func insertionLine(_ edge: Alignment) -> some View {
        Rectangle().fill(Color(nsColor: palette.primary)).frame(height: 2)
            .padding(.leading, contentTextX)
            .overlay(alignment: .leading) {
                Circle().fill(Color(nsColor: palette.primary)).frame(width: 6, height: 6)
                    .offset(x: contentTextX - 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge)
    }

    @ViewBuilder private func sectionBar(_ edge: Alignment) -> some View {
        Rectangle().fill(Color(nsColor: palette.primary)).frame(height: 3)   // coarse full-bleed chunk bar
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge)
    }

    @ViewBuilder private var rowContent: some View {
        switch item.kind {
        case .separator:
            Color.clear.overlay(Rectangle().fill(Color(nsColor: palette.border)).frame(height: 1))
        case let .sectionHeader(subtitle, _):
            HStack(spacing: 0) {
                if isCollapsibleHeader {
                    disclosureCaret
                    Color.clear.frame(width: metrics.disclosureGap)
                }
                headerContent(subtitle: subtitle)
                Spacer(minLength: 0)
                if showsGrip { reorderGrip }
            }
            .padding(.leading, metrics.leadingInset + indentWidth)
            .padding(.trailing, metrics.trailingInset)
        case .row:
            HStack(spacing: 0) {
                Color.clear.frame(width: metrics.leadingInset + indentWidth)
                if style.reservesLeadingImageColumn {
                    leadingImage
                    Color.clear.frame(width: metrics.gapImageToText)
                }
                textStack
                Spacer(minLength: metrics.budgetMargin)
                trailingCluster
            }
            .padding(.trailing, metrics.trailingInset)
        }
    }

    // MARK: trailing cluster (badges in order, then the accessory rightmost — ThemedList :1397-1439)

    @ViewBuilder private var trailingCluster: some View {
        HStack(spacing: 0) {
            ForEach(Array(item.badges.enumerated()), id: \.offset) { idx, badge in
                badgeView(badge).padding(.leading, idx == 0 ? 0 : metrics.badgeGap)
            }
            accessoryView
        }
        .fixedSize()          // never compress the cluster; the text budget yields instead
    }

    @ViewBuilder private var accessoryView: some View {
        let leadGap: CGFloat = item.badges.isEmpty ? 0 : metrics.clusterGap
        switch item.trailing {
        case .none:
            EmptyView()
        case .chevron:
            templateGlyph("caret-right", pt: metrics.chevronPt,
                          color: Color(nsColor: onAccent ? palette.onPrimary(0.55) : palette.tertiary))
                .padding(.leading, leadGap)
        case let .shortcut(text):
            shortcutLozenge(text).padding(.leading, leadGap)
        case let .custom(img):
            customAccessory(img).padding(.leading, leadGap)
        }
    }

    @ViewBuilder private func badgeView(_ badge: Badge) -> some View {
        let (fill, ink) = badgeColors(badge.role)
        HStack(spacing: 3) {
            if let sym = badge.symbol {
                Image(nsImage: sym).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: metrics.badgeSymbolPt, height: metrics.badgeSymbolPt)
                    .foregroundColor(ink)
            }
            Text(badge.text)
                .font(Font(palette.uiFont(.badge) as CTFont))
                .foregroundColor(ink)
        }
        .padding(.horizontal, metrics.badgeHPad)
        .frame(height: metrics.badgeHeight)
        .background(Capsule().fill(fill))
    }

    /// Badge fill (a @0.16 wash of the role) + ink (the full role color); onAccent flips
    /// to onPrimary (ThemedList :1508-1516).
    private func badgeColors(_ role: BadgeRole) -> (fill: Color, ink: Color) {
        if onAccent { return (Color(nsColor: palette.onPrimary(0.18)), Color(nsColor: palette.onPrimary(1))) }
        let base: NSColor
        switch role {
        case .neutral:   base = palette.muted
        case .primary:   base = palette.primary
        case .secondary: base = palette.secondary
        case .error:     base = palette.error
        }
        return (Color(nsColor: base).opacity(0.16), Color(nsColor: base))
    }

    private func shortcutLozenge(_ text: String) -> some View {
        Text(text)
            .font(Font(palette.uiFont(.shortcut) as CTFont))
            .foregroundColor(Color(nsColor: onAccent ? palette.onPrimary(1) : palette.muted))
            .padding(.horizontal, metrics.shortcutHPad)
            .frame(height: metrics.shortcutHeight)
            .overlay(RoundedRectangle(cornerRadius: metrics.shortcutRadius)
                .stroke(Color(nsColor: onAccent ? palette.onPrimary(0.4) : palette.border), lineWidth: 1))
    }

    @ViewBuilder private func customAccessory(_ img: NSImage) -> some View {
        let w = metrics.badgeHeight * (img.size.width / max(img.size.height, 1))
        if img.isTemplate {
            Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                .frame(width: w, height: metrics.badgeHeight)
                .foregroundColor(Color(nsColor: onAccent ? palette.onPrimary(1) : palette.foreground))
        } else {
            Image(nsImage: img).renderingMode(.original).resizable().scaledToFit()
                .frame(width: w, height: metrics.badgeHeight)
        }
    }

    @ViewBuilder private func templateGlyph(_ name: String, pt: CGFloat, color: Color) -> some View {
        if let img = phosphorImage(name, pt: pt) {
            Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                .frame(width: pt, height: pt)
                .foregroundColor(color)
        }
    }

    /// The 2×3 reorder grip on a draggable header — the KitCatalog has claimed
    /// this drawing since the drag layer shipped, but no draw code existed
    /// (t-avbj: a catalog asserting behaviour that isn't there is how a blind
    /// spot stays blind). Same liftability rule as `ThemedListView.isDragSource`:
    /// any non-disabled header, collapsible or not.
    private var showsGrip: Bool {
        style.draggable && style.showsReorderGrip && !item.isDisabled
    }

    private var reorderGrip: some View {
        let dot: CGFloat = 2, gap: CGFloat = 2.5
        return VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle().fill(Color(nsColor: palette.muted))
                            .frame(width: dot, height: dot)
                    }
                }
            }
        }
        .opacity(0.8)
        .accessibilityHidden(true)     // pure affordance; the header row itself carries AX
    }

    /// Reduce Motion snaps the caret rather than rotating it (see below).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A single caret-down glyph that ROTATES to ▸ when collapsed (the M2 improvement
    /// over the AppKit widget's static two-glyph swap).
    private var disclosureCaret: some View {
        templateGlyph("caret-down", pt: metrics.disclosurePt, color: Color(nsColor: palette.muted))
            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            // Reduce Motion snaps the caret instead of rotating it. The glyph
            // still ENDS in the right orientation — the state is conveyed, the
            // travel between the two states is not.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isCollapsed)
    }

    // MARK: leading image (template tint via .template render == AppKit .sourceAtop; colour favicon as-is)

    @ViewBuilder private var leadingImage: some View {
        Group {
            if let image = item.image {
                let side = image.isTemplate ? metrics.iconGlyph : metrics.imageBox
                if image.isTemplate {
                    Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: side, height: side)
                        .foregroundColor(Color(nsColor: onAccent ? palette.onPrimary(1) : palette.foreground))
                } else {
                    Image(nsImage: image).renderingMode(.original).interpolation(.high)
                        .resizable().scaledToFit()
                        .frame(width: side, height: side)
                }
            } else {
                Color.clear      // keep the column reserved even when this row has no image
            }
        }
        .frame(width: metrics.imageBox, height: metrics.imageBox)
    }

    @ViewBuilder private var textStack: some View {
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

    @ViewBuilder private func headerContent(subtitle: String?) -> some View {
        if let subtitle {
            VStack(alignment: .leading, spacing: metrics.lineGap) {
                Text(item.primary)
                    .font(Font(palette.uiFont(.sectionTitle) as CTFont))
                    .foregroundColor(Color(nsColor: palette.foreground))
                    .lineLimit(1)
                Text(subtitle)
                    .font(Font(palette.uiFont(.caption) as CTFont))
                    .foregroundColor(Color(nsColor: palette.muted))
                    .lineLimit(1)
            }
        } else {
            Text(item.primary.uppercased())
                .font(Font(palette.uiFont(.sectionHeader) as CTFont))
                .tracking(0.5)
                .foregroundColor(Color(nsColor: palette.muted))
                .lineLimit(1)
        }
    }

    // MARK: background decorations (full-bleed, .row only — headers/separators self-draw)

    @ViewBuilder private var rowBackground: some View {
        switch item.kind {
        case .row:
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
                if style.selectionInk == .wash, isSelected, isHovered {
                    selectionShape(Color(nsColor: palette.hover))
                }
            }
        case .sectionHeader:
            // Opaque "punch" so a PINNED header occludes the rows scrolling under it;
            // skipped on a nil/vibrancy surface (rows show through, by design).
            if surfaceOpaque, let surface = rowSurface {
                Color(nsColor: surface)
            }
        case .separator:
            EmptyView()
        }
    }

    /// Bottom rule: a full-bleed 1pt underline under a section header, or the per-row
    /// divider (leading-inset to the row's text, or full-bleed above a header).
    @ViewBuilder private var bottomRule: some View {
        switch item.kind {
        case .sectionHeader:
            Rectangle().fill(Color(nsColor: palette.border)).frame(height: 1)
        case .row:
            if let inset = dividerInset {
                Rectangle().fill(Color(nsColor: palette.border)).frame(height: 1)
                    .padding(.leading, inset)
                    .padding(.trailing, inset == 0 ? 0 : metrics.trailingInset)
            }
        case .separator:
            EmptyView()
        }
    }

    @ViewBuilder private var selectionFill: some View {
        if onAccent {
            selectionShape(Color(nsColor: palette.primary))       // opaque accent (wand's tome)
        } else {
            ZStack(alignment: .leading) {
                selectionShape(Color(nsColor: palette.selection))  // wash
                if style.showsSelectionAccentBar {                 // 3pt primary accent bar (combo's)
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
    /// TOP of any fill, inset so the stroke isn't clipped at the row edges. Drawn on
    /// rows AND section headers: the cursor WALKS headers (it seeds on the first row,
    /// which is a header whenever the list has sections; a section jump parks on an
    /// empty group's header), so a `.row`-only ring made the cursor vanish there while
    /// Enter still acted on the invisible row (facet #448). A separator is never a
    /// cursor stop, so it keeps no ring.
    @ViewBuilder private var outlineRing: some View {
        if isHighlighted, style.highlightStyle == .outline, !isSeparator {
            RoundedRectangle(cornerRadius: metrics.roundedRadius)
                .inset(by: 1.5)
                .stroke(Color(nsColor: palette.primary), lineWidth: 1.5)
        }
    }

    private var isSeparator: Bool {
        if case .separator = item.kind { return true }
        return false
    }
}

/// Opt-in per-row accessibility (the menu's `vendsRowAXElements`): expose an
/// actionable row as ONE button-trait element whose label is the menu-item text
/// (VoiceOver reads it as a menu row + activates on press). Default (off / a
/// non-actionable row) leaves SwiftUI's automatic per-view AX untouched.
///
/// `flattens` (`style.flattensRowAXChildren`) is a SEPARATE decision from vending:
/// `.ignore` discards the row's inner elements, which is right for a menu item
/// (one utterance) and wrong for a content row whose badges and secondary line
/// carry meaning. They were one switch, so asking for row AX silently deleted
/// the contents.
private struct RowAX: ViewModifier {
    let vends: Bool
    let flattens: Bool
    let label: String
    func body(content: Content) -> some View {
        if vends {
            content
                .accessibilityElement(children: flattens ? .ignore : .contain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}
