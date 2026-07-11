// ThemeKit — ThemedButtonGroup: a row/column of joined ThemedButtons (MUI
// <ButtonGroup>, basic). A faithful AppKit port: it forces a uniform
// variant/size/role onto its members and de-duplicates the shared edge so N
// buttons read as ONE control. Themed by assigning `palette`. AppKit / @MainActor.
//
// It COMPOSES the real `ThemedButton` (not a re-draw) — reusing its whole state
// machine (hover/press/focus/disabled, icons, key activation, contrast ink) —
// and only steers three additive ThemedButton knobs to make the seams read as
// one: `roundedCorners` (square the interior seam corners, round only the
// group's outer corners), `drawnBorderEdges` (an outlined member drops its
// shared edge so two 1pt strokes collapse to one), and `groupedShadow` (members
// forgo their own elevation so the group owns one continuous shadow).
//
// MUI <ButtonGroup> carries NO selection (that is the separate ToggleButtonGroup).
// So the default `.actions` mode is a faithful joined action group (`onTap(index)`,
// nothing ever active); an opt-in `.segmented` mode adds exclusive single-select
// (`selectedIndex` / `onSelect`), rendering the active segment by holding its
// member in the pressed tier (no new state on ThemedButton). Arrow keys rove
// focus between segments in `.segmented` mode.

import AppKit
import Palette
import PaletteKit
import Motion

@MainActor
public final class ThemedButtonGroup: NSView {

    /// One member of the group.
    public struct Segment {
        public var title: String
        public var leadingSymbol: String?   // a Phosphor slug
        public var trailingSymbol: String?  // a Phosphor slug
        public var isEnabled: Bool   // ANDs with the group's `isEnabled`
        public init(_ title: String, leading: String? = nil,
                    trailing: String? = nil, isEnabled: Bool = true) {
            self.title = title; self.leadingSymbol = leading
            self.trailingSymbol = trailing; self.isEnabled = isEnabled
        }
    }

    public enum Orientation { case horizontal, vertical }

    /// `actions` = a faithful joined action group (no segment ever active);
    /// `segmented` = exclusive single-select (the ToggleButtonGroup analogue).
    public enum Mode { case actions, segmented }

    // MARK: - Public configuration

    /// The theme. Assigning re-themes the group + every member.
    public var palette: ResolvedPalette { didSet { reconfigure() } }

    public var segments: [Segment] = [] { didSet { reconfigure(rebuild: true) } }

    public var orientation: Orientation = .horizontal { didSet { reconfigure() } }
    /// MUI's group default is `.outlined` (a bare button defaults to `.text`).
    public var variant: ThemedButton.Variant = .outlined { didSet { reconfigure() } }
    public var size:  ThemedButton.Size = .medium { didSet { reconfigure() } }
    public var role:  ThemedButton.Role = .primary { didSet { reconfigure() } }
    /// Stretch to the host's main-axis extent; members share it equally.
    public var fullWidth = false { didSet { reconfigure() } }
    /// MUI `disableElevation` — drop the contained group's shadow.
    public var disableElevation = false { didSet { reconfigure() } }
    /// Fans to every member (per-segment `isEnabled` ANDs with it).
    public var isEnabled = true { didSet { reconfigure() } }

    public var mode: Mode = .actions { didSet { reconfigure() } }

    /// `.actions`: fired per tap, no segment is ever active.
    public var onTap: ((Int) -> Void)?
    /// `.segmented`: the selected index (nil = none); exclusive single-select.
    public var selectedIndex: Int? { didSet { reconfigure() } }
    public var onSelect: ((Int) -> Void)?

    /// Force a state without events — deterministic still capture.
    public var previewSelectedIndex: Int? { didSet { reconfigure() } }
    public var previewHoveredIndex:  Int? { didSet { reconfigure() } }
    public var previewFocusedIndex:  Int? { didSet { reconfigure() } }

    // MARK: - Internals

    private var children: [ThemedButton] = []
    private let groupShadowLayer = CALayer()   // ONE elevation for the contained group (unclipped)
    private var dividerLayers: [CALayer] = []  // text/contained seam hairlines

    public override var isFlipped: Bool { false }

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false       // the group shadow lives outside bounds
        groupShadowLayer.zPosition = -1    // behind the member subviews
        groupShadowLayer.shadowColor = NSColor.black.cgColor
        groupShadowLayer.contentsScale = backingScale
        groupShadowLayer.isHidden = true
        layer?.addSublayer(groupShadowLayer)
        setAccessibilityRole(.group)
        reconfigure(rebuild: true)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    private var backingScale: CGFloat { themeBackingScale }

    /// The uniform per-member extent along the cross axis (the button height) —
    /// mirrors ThemedButton's per-size height.
    private var sizeExtent: CGFloat { size.controlHeight }
    /// Outlined members overlap 1pt so two abutting borders collapse to one.
    private var overlap: CGFloat { variant == .outlined ? 1 : 0 }
    private var effectiveSelected: Int? { previewSelectedIndex ?? selectedIndex }

    // MARK: - Position → corners / edges

    private enum Position { case lone, first, middle, last }
    private func position(_ i: Int, _ count: Int) -> Position {
        if count <= 1 { return .lone }
        if i == 0 { return .first }
        if i == count - 1 { return .last }
        return .middle
    }
    private static let allCorners: CACornerMask =
        [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]

    /// Round only the group's OUTER corners; square the interior seam corners.
    private func corners(_ pos: Position) -> CACornerMask {
        switch (orientation, pos) {
        case (_, .lone):            return Self.allCorners
        case (.horizontal, .first): return [.layerMinXMinYCorner, .layerMinXMaxYCorner]  // left
        case (.horizontal, .last):  return [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]  // right
        case (.vertical, .first):   return [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]  // top
        case (.vertical, .last):    return [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // bottom
        case (_, .middle):          return []
        }
    }
    /// A non-last outlined member drops its shared (trailing) edge.
    private func edges(_ pos: Position) -> ThemedButton.BorderEdges {
        switch pos {
        case .last, .lone:      return .all
        case .first, .middle:   return ThemedButton.BorderEdges.all
                                    .subtracting(orientation == .horizontal ? .right : .bottom)
        }
    }

    // MARK: - Reconfigure (re-fan group config onto every member)

    private func reconfigure(rebuild: Bool = false) {
        if rebuild || children.count != segments.count { rebuildChildViews() }
        let count = children.count
        let sel = (mode == .segmented) ? effectiveSelected : nil
        for (i, c) in children.enumerated() {
            let seg = segments[i]
            let pos = position(i, count)
            c.palette = palette
            c.variant = variant
            c.size = size
            c.role = role
            c.fullWidth = fullWidth
            c.title = seg.title
            c.leadingSymbol = seg.leadingSymbol
            c.trailingSymbol = seg.trailingSymbol
            c.isEnabled = isEnabled && seg.isEnabled
            c.roundedCorners = corners(pos)
            c.drawnBorderEdges = edges(pos)
            c.groupedShadow = (variant == .contained)
            c.previewHovered = (i == previewHoveredIndex)
            c.previewFocused = (i == previewFocusedIndex)
            c.previewPressed = (sel == i)             // the active-segment treatment
            c.onTap = { [weak self] in self?.handleTap(i) }
        }
        updateGroupLayers()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func rebuildChildViews() {
        for c in children { c.removeFromSuperview() }
        children = segments.map { _ in ThemedButton(palette: palette) }
        for c in children { addSubview(c) }
        for d in dividerLayers { d.removeFromSuperlayer() }
        dividerLayers = (0 ..< max(0, segments.count - 1)).map { _ in
            let d = CALayer()
            d.zPosition = 1                  // above the member fills (the seam line)
            d.contentsScale = backingScale
            layer?.addSublayer(d)
            return d
        }
    }

    private func handleTap(_ i: Int) {
        if mode == .segmented {
            selectedIndex = i        // didSet → reconfigure() paints the sticky active treatment
            setAccessibilityValue(selectedIndex)
            onSelect?(i)
            postAXValueChanged()
        } else {
            onTap?(i)
        }
    }

    // MARK: - Group-owned layer colours

    private var roleColor: NSColor { palette.color(for: role.control) }
    private var dividerColor: NSColor {
        guard isEnabled else { return palette.muted }
        switch variant {
        case .text:      return roleColor.withAlphaComponent(0.5)
        case .contained: return palette.bestContrast(on: roleColor).withAlphaComponent(0.25)
        case .outlined:  return .clear   // the overlapped border IS the seam
        }
    }
    private var groupShadowVisible: Bool {
        variant == .contained && !disableElevation && !children.isEmpty
    }

    private func updateGroupLayers() {
        layerTxn(animated: false) {
            let showDivider = (self.variant != .outlined) && self.children.count > 1
            for d in self.dividerLayers {
                d.isHidden = !showDivider
                d.backgroundColor = self.dividerColor.cgColor
            }
            self.groupShadowLayer.isHidden = !self.groupShadowVisible
            if self.groupShadowVisible {
                let e = self.palette.shadow(.dp2)   // MUI contained group = static dp2
                self.groupShadowLayer.applyShadowSpec(e)
            }
        }
    }

    // MARK: - Layout

    private var maxChildWidth: CGFloat {
        children.map { $0.intrinsicContentSize.width }.max() ?? 0
    }

    public override var intrinsicContentSize: NSSize {
        let count = children.count
        guard count > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        let h = sizeExtent, ov = overlap
        switch orientation {
        case .horizontal:
            if fullWidth { return NSSize(width: NSView.noIntrinsicMetric, height: h) }
            let sum = children.reduce(0) { $0 + $1.intrinsicContentSize.width }
            return NSSize(width: sum - CGFloat(count - 1) * ov, height: h)
        case .vertical:
            let w = fullWidth ? NSView.noIntrinsicMetric : maxChildWidth
            return NSSize(width: w, height: CGFloat(count) * h - CGFloat(count - 1) * ov)
        }
    }

    public override func layout() {
        super.layout()
        let count = children.count
        guard count > 0 else { return }
        let h = sizeExtent, ov = overlap
        layerTxn(animated: false) {
            switch self.orientation {
            case .horizontal:
                let y = (self.bounds.height - h) / 2
                if self.fullWidth {
                    let cw = (self.bounds.width + CGFloat(count - 1) * ov) / CGFloat(count)
                    for (i, c) in self.children.enumerated() {
                        c.frame = NSRect(x: CGFloat(i) * (cw - ov), y: y, width: cw, height: h)
                    }
                } else {
                    var x: CGFloat = 0
                    for c in self.children {
                        let w = c.intrinsicContentSize.width
                        c.frame = NSRect(x: x, y: y, width: w, height: h)
                        x += w - ov
                    }
                }
            case .vertical:
                let w = self.fullWidth ? self.bounds.width : self.maxChildWidth
                for (i, c) in self.children.enumerated() {
                    let top = self.bounds.height - CGFloat(i) * (h - ov)
                    c.frame = NSRect(x: 0, y: top - h, width: w, height: h)
                }
            }
            self.layoutGroupLayers(h: h)
        }
    }

    private func layoutGroupLayers(h: CGFloat) {
        if groupShadowVisible, let first = children.first, let last = children.last {
            let union = first.frame.union(last.frame)
            groupShadowLayer.frame = union
            groupShadowLayer.shadowPath = CGPath(
                roundedRect: CGRect(origin: .zero, size: union.size),
                cornerWidth: CGFloat(Radius.sm), cornerHeight: CGFloat(Radius.sm), transform: nil)
        }
        guard variant != .outlined, children.count > 1 else { return }
        let scale = backingScale
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        for i in 0 ..< (children.count - 1) {
            let a = children[i].frame   // seam sits on this member's trailing edge (no overlap)
            let d = dividerLayers[i]
            switch orientation {
            case .horizontal:
                d.frame = NSRect(x: snap(a.maxX) - 0.5, y: a.minY, width: 1, height: h)
            case .vertical:
                // first is above last (y-up); the seam is the lower edge of `a`.
                d.frame = NSRect(x: a.minX, y: snap(a.minY) - 0.5, width: a.width, height: 1)
            }
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = backingScale
        groupShadowLayer.contentsScale = s
        dividerLayers.forEach { $0.contentsScale = s }
        needsLayout = true
    }

    // MARK: - Keyboard: arrow-key roving focus (segmented mode)

    public override func keyDown(with event: NSEvent) {
        if mode == .segmented, !children.isEmpty {
            let kc = event.keyCode
            let forward  = orientation == .horizontal ? kc == 124 : kc == 125   // → / ↓
            let backward = orientation == .horizontal ? kc == 123 : kc == 126   // ← / ↑
            if forward || backward, moveFocus(forward: forward) { return }
        }
        super.keyDown(with: event)
    }

    @discardableResult
    private func moveFocus(forward: Bool) -> Bool {
        guard let fr = window?.firstResponder as? ThemedButton,
              let cur = children.firstIndex(where: { $0 === fr }),
              let next = nextEnabledIndex(from: cur, forward: forward) else { return false }
        window?.makeFirstResponder(children[next])
        return true
    }

    /// The next enabled member in `forward`/backward order (nil = ran off the
    /// end; no wrap). Pure index math, split out so it's deterministically
    /// testable without a window / first responder.
    private func nextEnabledIndex(from i: Int, forward: Bool) -> Int? {
        let step = forward ? 1 : -1
        var j = i + step
        while j >= 0 && j < children.count {
            if children[j].isEnabled { return j }
            j += step
        }
        return nil
    }
}

#if DEBUG
// Test-only window into the joined geometry + selection, so a deterministic test
// can assert per-member position / corners / edges / divider colour WITHOUT
// synthetic events. Same-file extension so it can read the private members.
extension ThemedButtonGroup {
    struct GroupProbe {
        public let count: Int
        public let perMemberCorners: [CACornerMask]
        public let perMemberEdges: [ThemedButton.BorderEdges]
        public let perMemberGroupedShadow: [Bool]
        public let perMemberEnabled: [Bool]
        public let perMemberHeight: [CGFloat]      // the fanned size (button height)
        public let perMemberOverlay: [CGColor?]    // each member's RENDERED state-layer
        public let selectedMember: Int?            // which member is held active
        public let dividerColor: CGColor?
        public let dividerCount: Int
        public let dividerVisible: Bool
        public let groupShadowVisible: Bool
    }
    var groupProbe: GroupProbe {
        return GroupProbe(
            count: children.count,
            perMemberCorners: children.map { $0.buttonProbe.maskedCorners },
            perMemberEdges: children.map { $0.buttonProbe.drawnBorderEdges },
            perMemberGroupedShadow: children.map { $0.buttonProbe.groupedShadow },
            perMemberEnabled: children.map { $0.isEnabled },
            perMemberHeight: children.map { $0.buttonProbe.height },
            perMemberOverlay: children.map { $0.buttonProbe.overlayColor },
            selectedMember: (mode == .segmented) ? effectiveSelected : nil,
            dividerColor: dividerLayers.first?.backgroundColor,
            dividerCount: dividerLayers.count,
            dividerVisible: !(dividerLayers.first?.isHidden ?? true),
            groupShadowVisible: !groupShadowLayer.isHidden)
    }

    /// Drive the member-tap dispatch without synthetic events — the same path a
    /// real member click takes.
    func simulateTapForTesting(_ i: Int) { handleTap(i) }
    /// The window-free roving-focus index math.
    func nextEnabledIndexForTesting(from i: Int, forward: Bool) -> Int? {
        nextEnabledIndex(from: i, forward: forward)
    }
}
#endif
