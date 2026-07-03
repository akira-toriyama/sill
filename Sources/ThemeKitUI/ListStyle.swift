// ThemeKitUI — value-type configuration for the SwiftUI-native `ThemedListView`
// (#17b M2). `ThemedListStyle` is the assign-once config surface (density, selection mode,
// decorations, drag). `ListMetrics` is the pure, density-keyed constant table that
// reproduces the AppKit `ThemedList`'s fixed metrics 1:1 — the fidelity source of
// truth (see the plan's Metrics section; mirror of `ThemedList.swift:471-510`).
//
// The enums are FRESH ThemeKitUI module-level types (NOT the `ThemedList`-nested
// ThemeKit ones, which die at the M5 retire) so ThemeKitUI carries no coupling to
// the AppKit widget it replaces.

import AppKit
import ListCore

public enum Density: Equatable { case comfortable, compact }
public enum SelectionMode: Equatable { case none, single, multiple }   // .multiple is NEW (M2b)
public enum HoverStyle: Equatable { case wash, solidAccent }
public enum HighlightStyle: Equatable { case fill, outline }

public struct ThemedListStyle {
    public var density: Density = .comfortable
    public var selectionMode: SelectionMode = .single
    public var hoverStyle: HoverStyle = .wash
    public var highlightStyle: HighlightStyle = .fill
    public var roundedSelection: Bool = false
    public var showsDividers: Bool = false
    public var zebra: Bool = false                     // AppKit widget's `alternatingRowBackground`
    public var horizontalContentScroll: Bool = false
    public var reservesLeadingImageColumn: Bool = true
    public var wrapsHighlight: Bool = false
    public var highlightFollowsHover: Bool = false
    /// Hosted in a non-key AppKit popup (combo/menu): the SwiftUI rows do NOT own
    /// activation — the host's AppKit `mouseUp` fires the synchronous commit, and
    /// hover comes from an AppKit tracking area (a non-key panel's `.onHover`/tap
    /// can slip a tick or miss). `false` (default) = standalone (facet inline): rows
    /// own tap-select + `.onHover` as in M2. When true the view reports per-row
    /// viewport rects via `RowRectPreference` so the host can hit-test a click.
    public var hosted: Bool = false
    public var vendsRowAXElements: Bool = false
    public var surfaceColor: NSColor? = nil
    public var backgroundAlpha: CGFloat = 1            // parity-PLUS (design decision ⑤)
    // drag config (M2c)
    public var draggable: Bool = false
    public var dragMode: DragMode = .both
    public var showsReorderGrip: Bool = true

    public init() {}
}

public struct ListMetrics {
    public let singleRow, twoLineRow, header1, header2: CGFloat
    public let leadingInset, trailingInset, imageBox, iconGlyph, gapImageToText: CGFloat
    public let twoLineTop, lineGap, accentBar, roundedHInset: CGFloat
    public let badgeHeight, badgeHPad, badgeSymbolPt, badgeGap: CGFloat
    public let chevronPt, shortcutHeight, shortcutHPad, clusterGap, budgetMargin: CGFloat
    public let separatorBand, indentStep, disclosurePt, disclosureGap: CGFloat

    public var roundedRadius: CGFloat { 6 }            // Radius.md
    public var shortcutRadius: CGFloat { 4 }           // Radius.sm
    /// Text x when the leading image column is reserved (leadingInset + imageBox + gap).
    public var textXOrigin: CGFloat { leadingInset + imageBox + gapImageToText }
    /// Header title left-shift when the header is collapsible (disclosurePt + disclosureGap).
    public var disclosureGutter: CGFloat { disclosurePt + disclosureGap }

    public static func forDensity(_ d: Density) -> ListMetrics {
        switch d {
        case .comfortable:
            return ListMetrics(
                singleRow: 30, twoLineRow: 46, header1: 28, header2: 40,
                leadingInset: 12, trailingInset: 12, imageBox: 24, iconGlyph: 18, gapImageToText: 8,
                twoLineTop: 8, lineGap: 2, accentBar: 3, roundedHInset: 3,
                badgeHeight: 16, badgeHPad: 6, badgeSymbolPt: 11, badgeGap: 4,
                chevronPt: 11, shortcutHeight: 16, shortcutHPad: 5, clusterGap: 6, budgetMargin: 8,
                separatorBand: 9, indentStep: 16, disclosurePt: 11, disclosureGap: 5)
        case .compact:
            return ListMetrics(
                singleRow: 26, twoLineRow: 40, header1: 24, header2: 40,   // header2 NOT shrunk in compact
                leadingInset: 10, trailingInset: 10, imageBox: 20, iconGlyph: 16, gapImageToText: 6,
                twoLineTop: 6, lineGap: 2, accentBar: 3, roundedHInset: 3,
                badgeHeight: 14, badgeHPad: 6, badgeSymbolPt: 11, badgeGap: 4,
                chevronPt: 10, shortcutHeight: 14, shortcutHPad: 5, clusterGap: 6, budgetMargin: 8,
                separatorBand: 7, indentStep: 14, disclosurePt: 10, disclosureGap: 5)
        }
    }
}
