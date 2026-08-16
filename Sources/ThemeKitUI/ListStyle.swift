// ThemeKitUI — value-type configuration for the SwiftUI-native `ThemedListView`
// (#17b M2). `ThemedListStyle` is the assign-once config surface (density, selection mode,
// decorations, drag). `ListMetrics` is the pure, density-keyed constant table carried
// over 1:1 from the retired AppKit `ThemedList`'s fixed metrics — the fidelity source
// of truth (see the M2 plan's Metrics section).
//
// The enums are ThemeKitUI module-level types; the `ThemedList`-nested ThemeKit
// originals died at the M5 retire, so ThemeKitUI carries no coupling to the AppKit
// widget it replaced.

import AppKit
import ListCore

public enum Density: Equatable { case comfortable, compact }
public enum SelectionMode: Equatable { case none, single, multiple }   // .multiple is NEW (M2b)
/// How a row that draws a fill (selected, or highlighted under `.fill`) is inked:
/// a translucent `selection` wash, or an opaque `primary` slab whose contents flip
/// to `onPrimary`. Named for what it governs — it was `hoverStyle`, whose only two
/// uses were both this decision, so the name sent consumers looking for a hover
/// knob and hid the one they were actually setting.
public enum SelectionInk: Equatable { case wash, solidAccent }
public enum HighlightStyle: Equatable { case fill, outline }

public struct ThemedListStyle {
    public var density: Density = .comfortable
    public var selectionMode: SelectionMode = .single
    public var selectionInk: SelectionInk = .wash
    public var highlightStyle: HighlightStyle = .fill
    public var roundedSelection: Bool = false
    /// Draw the 3pt `primary` bar down the leading edge of a wash-inked fill
    /// (the combo's affordance). Independent of `roundedSelection`, which picks
    /// the fill's SHAPE: choosing the pill used to delete the bar with no way to
    /// ask for both. Not consulted under `.solidAccent`, which has no wash to mark.
    public var showsSelectionAccentBar: Bool = true
    public var showsDividers: Bool = false
    /// Draw the theme-painted overlay scroll indicator(s) — a `muted` pill that
    /// appears while the viewport moves and fades out at rest, on each axis
    /// whose content overflows. Replaces the native `NSScroller`, which is
    /// suppressed unconditionally: the system knob ignores the palette, and
    /// `.scrollIndicators(.hidden)` proved to be a no-op on the AppKit-backed
    /// `ScrollView` (measured 2026-08-08, t-8649), so OFF here means "no
    /// indicator at all", not "the native one".
    public var showsScrollIndicators: Bool = true
    public var zebra: Bool = false                     // AppKit widget's `alternatingRowBackground`
    public var horizontalContentScroll: Bool = false
    public var reservesLeadingImageColumn: Bool = true
    public var wrapsHighlight: Bool = false
    public var highlightFollowsHover: Bool = false
    /// Hosted in a non-key AppKit popup (combo/menu): the SwiftUI rows do NOT own
    /// activation — the host's AppKit `mouseUp` fires the synchronous commit, and
    /// hover comes from an AppKit tracking area (a non-key panel's `.onHover`/tap
    /// can slip a tick or miss). `false` (default) = standalone (facet inline): rows
    /// own tap-select + `.onHover` as in M2.
    ///
    /// This flag governs THAT and nothing else. Per-row viewport rects
    /// (`RowRectPreference` → `onRowRects`) are published for every list, hosted or
    /// not: a hosted popup hit-tests a click with them, a standalone list anchors to
    /// them, and gating them here made choosing one capability silently forfeit the
    /// other.
    public var hosted: Bool = false
    /// Take keyboard focus (`.onKeyPress` nav, type-select, keyboard drag).
    /// Independent of `selectionMode`: a list that selects nothing still navigates
    /// and activates by keyboard, and gating focus on `.none` made picking the
    /// selection semantics silently forfeit every key. A list embedded in a
    /// non-key host (menu/combo, where AppKit owns the keys) sets this false.
    public var takesKeyboardFocus: Bool = true
    public var vendsRowAXElements: Bool = false
    /// Collapse a vended row to ONE AX element, hiding its inner labels/badges.
    /// Only consulted when `vendsRowAXElements` is on. Splitting it out is what
    /// lets a list vend rows for VoiceOver WITHOUT silently swallowing the row's
    /// contents — the two used to be the same switch.
    public var flattensRowAXChildren: Bool = true
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
    /// Cap on a badge's TEXT width; past it the label truncates (tail) instead
    /// of pushing the row's title out. The cluster is `.fixedSize()` — it never
    /// compresses, the text budget yields — so without a cap one long mark name
    /// eats the whole primary line, and a host that wants readable words is
    /// forced to drop the words. Measured by `ListController.badgeWidth` under
    /// the same cap, so layout and draw agree.
    public let badgeMaxText: CGFloat
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
                badgeHeight: 16, badgeHPad: 6, badgeSymbolPt: 11, badgeGap: 4, badgeMaxText: 96,
                chevronPt: 11, shortcutHeight: 16, shortcutHPad: 5, clusterGap: 6, budgetMargin: 8,
                separatorBand: 9, indentStep: 16, disclosurePt: 11, disclosureGap: 5)
        case .compact:
            return ListMetrics(
                singleRow: 26, twoLineRow: 40, header1: 24, header2: 40,   // header2 NOT shrunk in compact
                leadingInset: 10, trailingInset: 10, imageBox: 20, iconGlyph: 16, gapImageToText: 6,
                twoLineTop: 6, lineGap: 2, accentBar: 3, roundedHInset: 3,
                badgeHeight: 14, badgeHPad: 6, badgeSymbolPt: 11, badgeGap: 4, badgeMaxText: 88,
                chevronPt: 10, shortcutHeight: 14, shortcutHPad: 5, clusterGap: 6, budgetMargin: 8,
                separatorBand: 7, indentStep: 14, disclosurePt: 10, disclosureGap: 5)
        }
    }
}
