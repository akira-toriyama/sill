// ThemeKitUI — ThemedButtonGroupView: a row/column of joined ThemedButtons
// (MUI <ButtonGroup>, basic), SwiftUI-native. Like ThemeKit's AppKit
// `ThemedButtonGroup` (which stays for AppKit hosts) it COMPOSES the real
// button rather than re-drawing it, and steers the same three knobs to make N
// buttons read as ONE control: round only the group's OUTER corners, drop each
// non-last outlined member's shared edge so two abutting 1 pt strokes collapse
// to one hairline, and forgo the members' own elevation so the group owns one
// continuous shadow. Here those knobs are `ThemedButtonView.Grouping`.
//
// `.actions` (the default) is a faithful joined action group — `onTap(index)`,
// nothing ever active. `.segmented` adds exclusive single-select, rendering the
// active segment by holding its member in the pressed tier (no new state on
// ThemedButtonView) and roving focus with the arrow keys.
//
// Placement is a custom `Layout` rather than an HStack because the geometry is
// not stack geometry: outlined members OVERLAP by 1 pt so their shared borders
// coincide, and the non-outlined seam hairline is placed at a snapped device
// pixel on the boundary. Subview ORDER carries the role — the first `count`
// subviews are members, the rest are the `count − 1` seam hairlines, which
// therefore also draw above the member fills (the AppKit `zPosition = 1`).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit

public struct ThemedButtonGroupView: View {
    @Environment(\.sillPalette) private var ambientPalette
    @Environment(\.displayScale) private var displayScale
    @Environment(\.isEnabled) private var ancestorEnabled
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var titles: [String]
    var orientation: ThemedButtonGroup.Orientation
    var variant: ThemedButton.Variant
    var size: ThemedButton.Size
    var role: ThemedButton.Role
    var mode: ThemedButtonGroup.Mode
    var fullWidth: Bool
    /// MUI `disableElevation` — drop the contained group's shadow.
    var disableElevation: Bool
    private let explicitEnabled: Bool
    /// The `enabled:` argument ∧ the ancestor `.disabled(_:)` environment — a
    /// disabled ancestor paints the disabled state (stock-control parity).
    var enabled: Bool { explicitEnabled && ancestorEnabled }
    var disabledMember: Int?
    var selectedIndex: Int?
    var previewSelectedIndex: Int?
    var previewHoveredIndex: Int?
    var previewFocusedIndex: Int?
    var onTap: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?

    /// The group owns its VISIBLE selection between host updates (the AppKit
    /// widget wrote its own `selectedIndex` the same way); a change to the
    /// `selectedIndex` argument re-drives it — the controlled-component idiom
    /// `ThemedCheckboxView` uses.
    @State private var selectedState: Int?
    @FocusState private var focusedMember: Int?

    public init(palette: ResolvedPalette? = nil, titles: [String],
                orientation: ThemedButtonGroup.Orientation = .horizontal,
                variant: ThemedButton.Variant = .outlined,
                size: ThemedButton.Size = .medium, role: ThemedButton.Role = .primary,
                mode: ThemedButtonGroup.Mode = .actions, fullWidth: Bool = false,
                disableElevation: Bool = false,
                enabled: Bool = true, disabledMember: Int? = nil, selectedIndex: Int? = nil,
                previewSelectedIndex: Int? = nil, previewHoveredIndex: Int? = nil,
                previewFocusedIndex: Int? = nil, onTap: ((Int) -> Void)? = nil,
                onSelect: ((Int) -> Void)? = nil) {
        self.explicitPalette = palette
        self.titles = titles
        self.orientation = orientation
        self.variant = variant
        self.size = size
        self.role = role
        self.mode = mode
        self.fullWidth = fullWidth
        self.disableElevation = disableElevation
        self.explicitEnabled = enabled
        self.disabledMember = disabledMember
        self.selectedIndex = selectedIndex
        self.previewSelectedIndex = previewSelectedIndex
        self.previewHoveredIndex = previewHoveredIndex
        self.previewFocusedIndex = previewFocusedIndex
        self.onTap = onTap
        self.onSelect = onSelect
        self._selectedState = State(initialValue: selectedIndex)
    }

    // MARK: - Derived state

    private var count: Int { titles.count }
    /// Outlined members overlap 1 pt so two abutting borders collapse to one.
    private var overlap: CGFloat { variant == .outlined ? 1 : 0 }
    /// The uniform per-member extent along the cross axis (the button height).
    /// The 30/36/42 ladder is ThemeKit's `controlHeight`, which is internal to
    /// that module — so it is mirrored here exactly as `ThemedButtonView` does.
    private var extent: CGFloat { size == .small ? 30 : size == .medium ? 36 : 42 }
    /// Which member is held in the active tier (`.actions` never has one).
    private var activeMember: Int? {
        mode == .segmented ? (previewSelectedIndex ?? selectedState) : nil
    }
    private func memberEnabled(_ i: Int) -> Bool { enabled && i != disabledMember }

    /// A member must ACCEPT the width the Layout proposes rather than hug its
    /// own label whenever the group hands out a uniform extent: under
    /// `fullWidth`, and always vertically, where every member shares the widest
    /// member's width. AppKit gets this by setting frames absolutely; in
    /// SwiftUI the member has to opt into `maxWidth: .infinity`, which is
    /// exactly what its `fullWidth` flag does.
    private var memberFillsProposal: Bool { fullWidth || orientation == .vertical }

    // MARK: - Position → corners / edges (the AppKit tables, verbatim)

    private enum Position { case lone, first, middle, last }
    private func position(_ i: Int) -> Position {
        if count <= 1 { return .lone }
        if i == 0 { return .first }
        if i == count - 1 { return .last }
        return .middle
    }

    /// Round only the group's OUTER corners; square the interior seam corners.
    /// The mask is PHYSICAL (minX/maxX), matching AppKit — deliberately not
    /// leading/trailing, which would flip under an RTL layout and desync from
    /// the Layout, which places by physical x.
    private func corners(_ i: Int) -> CACornerMask {
        switch (orientation, position(i)) {
        case (_, .lone):            return .themedAllCorners
        case (.horizontal, .first): return [.layerMinXMinYCorner, .layerMinXMaxYCorner]  // left
        case (.horizontal, .last):  return [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]  // right
        case (.vertical, .first):   return [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]  // top
        case (.vertical, .last):    return [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // bottom
        case (_, .middle):          return []
        }
    }

    /// A non-last outlined member drops its shared (trailing) edge.
    private func edges(_ i: Int) -> ThemedButton.BorderEdges {
        switch position(i) {
        case .last, .lone:    return .all
        case .first, .middle: return ThemedButton.BorderEdges.all
                                  .subtracting(orientation == .horizontal ? .right : .bottom)
        }
    }

    // MARK: - Colours

    private var roleColor: NSColor {
        switch role {
        case .primary:   return palette.primary
        case .secondary: return palette.secondary
        case .error:     return palette.error
        }
    }

    /// The seam hairline for the variants whose members have no border of their
    /// own. An outlined group has none — the overlapped border IS the seam.
    private var dividerColor: NSColor {
        guard enabled else { return palette.disabledInk }
        switch variant {
        case .text:      return palette.restingStroke(of: roleColor)
        case .contained: return palette.bestContrast(on: roleColor).withAlphaComponent(0.25)
        case .outlined:  return .clear
        }
    }
    private var showsDivider: Bool { variant != .outlined && count > 1 }

    /// One static dp2 for the whole contained group (MUI). Note this ignores
    /// `enabled`, exactly as the AppKit group does: a disabled contained group
    /// still casts its shadow while every member goes flat.
    private var groupShadowVisible: Bool {
        variant == .contained && !disableElevation && count > 0
    }

    // MARK: - Body

    public var body: some View {
        JoinedGroupLayout(orientation: orientation, overlap: overlap, extent: extent,
                          fullWidth: fullWidth, memberCount: count, scale: displayScale) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, title in
                ThemedButtonView(palette: palette, variant: variant, size: size, role: role,
                                 title: title, fullWidth: memberFillsProposal,
                                 enabled: memberEnabled(i),
                                 previewHovered: i == previewHoveredIndex,
                                 previewPressed: activeMember == i,
                                 previewFocused: i == previewFocusedIndex,
                                 grouping: .init(roundedCorners: corners(i),
                                                 drawnBorderEdges: edges(i),
                                                 groupedShadow: variant == .contained),
                                 onTap: { handleTap(i) })
                    .focused($focusedMember, equals: i)
            }
            if showsDivider {
                ForEach(0 ..< (count - 1), id: \.self) { _ in
                    Rectangle().fill(Color(nsColor: dividerColor))
                }
            }
        }
        .frame(maxWidth: fullWidth && orientation == .horizontal ? .infinity : nil)
        .modifier(GroupElevation(token: groupShadowVisible ? Elevation.dp2.token : nil))
        .onKeyPress(phases: .down) { roveFocus($0) }
        .onChange(of: selectedIndex) { _, new in selectedState = new }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Dispatch

    private func handleTap(_ i: Int) {
        if mode == .segmented {
            selectedState = i
            onSelect?(i)
        } else {
            onTap?(i)
        }
    }

    /// Arrow keys rove FOCUS between segments — they never change the selection
    /// and never fire `onSelect` (keyboard selection is arrow-then-Space, the
    /// AppKit behaviour). No wrap: running off the end is `.ignored`, which is
    /// AppKit falling through to `super.keyDown`.
    private func roveFocus(_ press: KeyPress) -> KeyPress.Result {
        guard mode == .segmented, count > 0, let cur = focusedMember else { return .ignored }
        let forwardKey: KeyEquivalent = orientation == .horizontal ? .rightArrow : .downArrow
        let backKey: KeyEquivalent = orientation == .horizontal ? .leftArrow : .upArrow
        let forward: Bool
        if press.key.character == forwardKey.character { forward = true }
        else if press.key.character == backKey.character { forward = false }
        else { return .ignored }
        guard let next = nextEnabledIndex(from: cur, forward: forward) else { return .ignored }
        focusedMember = next
        return .handled
    }

    /// The next enabled member in `forward`/backward order (nil = ran off the
    /// end; no wrap).
    private func nextEnabledIndex(from i: Int, forward: Bool) -> Int? {
        let step = forward ? 1 : -1
        var j = i + step
        while j >= 0 && j < count {
            if memberEnabled(j) { return j }
            j += step
        }
        return nil
    }
}

/// One dp2 for the whole joined silhouette (MUI's contained group), or none.
///
/// The shadow is cast by the MEMBERS — flattened first, so the group sheds one
/// continuous shadow instead of one per member (which would show at every
/// seam). The AppKit group instead owns a contentless shadow layer; casting
/// from real content is the only thing SwiftUI offers, and it is also honest:
/// a disabled contained group, whose member fill is translucent, casts a
/// proportionally lighter shadow rather than AppKit's full-strength one.
struct GroupElevation: ViewModifier {
    var token: ElevationToken?

    func body(content: Content) -> some View {
        if let e = token {
            content
                .compositingGroup()
                .shadow(color: .black.opacity(e.opacity), radius: CGFloat(e.blur),
                        x: 0, y: CGFloat(e.dy))
        } else {
            content
        }
    }
}

// MARK: - Layout

/// The joined placement: `ThemedButtonGroup.intrinsicContentSize` + `layout()`,
/// ported. Members are `subviews[0 ..< memberCount]`; anything after them is a
/// seam hairline, one per interior boundary.
struct JoinedGroupLayout: Layout {
    var orientation: ThemedButtonGroup.Orientation
    var overlap: CGFloat
    var extent: CGFloat
    var fullWidth: Bool
    var memberCount: Int
    /// Backing scale for the hairline snap (the AppKit `snap()`).
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard memberCount > 0 else { return .zero }
        let widths = memberWidths(subviews)
        let collapsed = widths.reduce(0, +) - CGFloat(memberCount - 1) * overlap
        switch orientation {
        case .horizontal:
            // AppKit answers `noIntrinsicMetric` under fullWidth and lets
            // AutoLayout decide; a Layout must return a number, so an
            // unspecified proposal falls back to the collapsed intrinsic.
            return CGSize(width: fullWidth ? (proposal.width ?? collapsed) : collapsed,
                          height: extent)
        case .vertical:
            let w = widths.max() ?? 0
            return CGSize(width: fullWidth ? (proposal.width ?? w) : w,
                          height: CGFloat(memberCount) * extent - CGFloat(memberCount - 1) * overlap)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard memberCount > 0 else { return }
        let h = extent, ov = overlap
        var frames: [CGRect] = []
        switch orientation {
        case .horizontal:
            let y = bounds.minY + (bounds.height - h) / 2
            if fullWidth {
                let cw = (bounds.width + CGFloat(memberCount - 1) * ov) / CGFloat(memberCount)
                for i in 0 ..< memberCount {
                    frames.append(CGRect(x: bounds.minX + CGFloat(i) * (cw - ov),
                                         y: y, width: cw, height: h))
                }
            } else {
                var x = bounds.minX
                for w in memberWidths(subviews) {
                    frames.append(CGRect(x: x, y: y, width: w, height: h))
                    x += w - ov
                }
            }
        case .vertical:
            let w = fullWidth ? bounds.width : (memberWidths(subviews).max() ?? 0)
            for i in 0 ..< memberCount {
                frames.append(CGRect(x: bounds.minX, y: bounds.minY + CGFloat(i) * (h - ov),
                                     width: w, height: h))
            }
        }
        for (i, f) in frames.enumerated() { place(subviews[i], in: f) }

        // The seam hairlines sit ON the boundary (non-outlined ⇒ overlap 0), a
        // device pixel wide and snapped to the pixel grid.
        let first = memberCount
        guard subviews.count > first else { return }
        for i in 0 ..< (memberCount - 1) where first + i < subviews.count {
            let a = frames[i]
            let seam: CGRect
            switch orientation {
            case .horizontal: seam = CGRect(x: snap(a.maxX) - 0.5, y: a.minY, width: 1, height: h)
            case .vertical:   seam = CGRect(x: a.minX, y: snap(a.maxY) - 0.5, width: a.width, height: 1)
            }
            place(subviews[first + i], in: seam)
        }
    }

    private func memberWidths(_ subviews: Subviews) -> [CGFloat] {
        (0 ..< memberCount).map { subviews[$0].sizeThatFits(.unspecified).width }
    }

    private func place(_ subview: LayoutSubview, in frame: CGRect) {
        subview.place(at: CGPoint(x: frame.minX, y: frame.minY), anchor: .topLeading,
                      proposal: ProposedViewSize(width: frame.width, height: frame.height))
    }

    private func snap(_ v: CGFloat) -> CGFloat {
        guard scale > 0 else { return v }
        return (v * scale).rounded() / scale
    }
}
