import SwiftUI
import AppKit
import PaletteKit
import Palette
import GridCore

// ThemeKitUI — a general, content-agnostic, 100% SwiftUI-native themed grid (#17e).
// Owns: responsive layout (LazyVGrid/LazyHGrid in a ScrollView), themed chrome
// (rest/hover/selected/focused), controlled/uncontrolled selection seam, 2D
// keyboard navigation (onMoveCommand), and activation (double-click / Return on
// macOS 14+). The cell CONTENT is supplied by the consumer via @ViewBuilder.
// NO AppKit. DnD + carousel/hero are out of scope (see design spec §3.2/§11).

/// Frozen chrome state for a deterministic static screenshot (prism's per-cell
/// capture) — the grid twin of the list's `ListPreview` (t-avbj: the grid had
/// no seam at all, so hover / cursor / focus were bench-invisible). When
/// non-nil the grid renders THIS instead of its live `@State`/`@FocusState`.
public struct GridPreview<ID: Hashable> {
    public var hovered: ID?
    public var cursor: ID?
    /// Whether the grid renders as focused (the cursor ring only draws on a
    /// focused grid, mirroring the live `isFocused && cursor == id` rule).
    public var focused: Bool
    /// Frozen DnD pose (t-n3be): the lifted source cell (dims + parks the
    /// ghost) and the cell the drop would land ONTO (draws the target ring).
    /// `var`s with defaults rather than init labels — the API differ reads a
    /// changed init label set as a removal.
    public var dragSource: ID?
    public var dropTargetID: ID?
    /// Frozen reorder pose (t-mej6 G2): the insertion SLOT the drop would land
    /// at (draws the insertion line) — the `.at` twin of `dropTargetID`.
    public var dropSlot: Int?
    public init(hovered: ID? = nil, cursor: ID? = nil, focused: Bool = true) {
        self.hovered = hovered; self.cursor = cursor; self.focused = focused
    }

    /// A copy frozen mid-drag: `source` lifted, the drop landing on `over`.
    public func dragging(source: ID?, over: ID? = nil) -> Self {
        var c = self; c.dragSource = source; c.dropTargetID = over; return c
    }

    /// A copy frozen mid-reorder: `source` lifted, the drop landing at slot
    /// `slot` (the insertion line draws there).
    public func dragging(source: ID?, at slot: Int) -> Self {
        var c = self; c.dragSource = source; c.dropSlot = slot; return c
    }
}

@MainActor
public struct ThemedGridView<Data, ID, Cell>: View
where Data: RandomAccessCollection, ID: Hashable, Cell: View {

    private let data: Data
    private let idKey: KeyPath<Data.Element, ID>
    private let layout: GridLayout
    private let axis: Axis
    private let aspectRatio: CGFloat?
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    private let onActivate: ((ID) -> Void)?
    private let cellBuilder: (Data.Element, GridCellState) -> Cell
    private let selectionBinding: Binding<Set<ID>>?
    private let allowsMultiSelect: Bool

    @State private var internalSelection: Set<ID> = []
    @State private var cursor: ID?
    @State private var hovered: ID?
    @State private var resolvedColumns: Int = 1
    @FocusState private var isFocused: Bool

    // Drag/reorder (t-n3be) — the live lift + the per-cell frames the pure
    // resolver consumes (the list's DragInfo/geomMap twin). `isKeyboard` marks
    // a Space-lifted drag (t-mej6 G3): its target comes from the aim list, not
    // the pointer.
    private struct DragInfo { var source: ID; var target: GridDropTarget<ID>?; var location: CGPoint; var tilt: CGFloat = 0; var isKeyboard: Bool = false }
    @State private var dragState: DragInfo?
    @State private var cellFrames: [AnyHashable: CGRect] = [:]
    // Keyboard-drag aim (t-mej6 G3): the validated candidate list a lift walks,
    // and the current aim (the list's dragAim/dragAimIndex twin — the grid
    // steps it geometrically, see `aimKeyboard`).
    @State private var dragAim: [GridDropTarget<ID>] = []
    @State private var dragAimIndex: Int = 0
    // Fit-to-viewport (t-mej6 G1): the pre-computed cell size when `fitsViewport`
    // is on (SwiftUI's grid only sizes off the cross axis, so fitting both axes
    // needs the explicit size).
    @State private var fittedSize: CGSize?

    /// Frozen chrome for a static capture. Set via `.preview(_:)`, NOT an init
    /// parameter — the API differ reads any init-label change as a removal
    /// (see `ListPreview.hovering`), so frozen state lands as a method here too.
    private var previewState: GridPreview<ID>?

    /// A copy that renders the frozen `preview` instead of live interaction
    /// state. Selection stays a binding — pass `.constant([...])` to freeze it.
    public func preview(_ p: GridPreview<ID>?) -> Self {
        var c = self; c.previewState = p; return c
    }

    // MARK: DnD opt-in (t-n3be — copy-methods, not init labels: the API differ
    // reads a changed init label set as a removal)

    /// Pointer DnD (nil = off). The grid resolves WHERE a drop lands (pure
    /// GridCore math gated by the validator); the consumer's `onGridDrop`
    /// decides WHAT it means (swap / move / reorder).
    private var dragMode: GridDragMode?
    private var dropValidate: (GridDragContext<ID>, GridDropTarget<ID>) -> Bool = { _, _ in true }
    private var onDropHandler: ((GridDragContext<ID>, GridDropTarget<ID>) -> Void)?

    /// A copy whose cells can be dragged — by pointer, and by keyboard
    /// (t-mej6 G3): Space lifts the cursor cell, arrows aim geometrically
    /// through the validated candidates, Return/Space commits, Esc cancels.
    public func draggable(_ mode: GridDragMode = .dropOnto) -> Self {
        var c = self; c.dragMode = mode; return c
    }

    // MARK: behaviour opt-ins (t-mej6 — each its own copy-method: a single-
    // purpose gate per t-fyvs, and the API differ reads init-label changes as
    // removals so none of these land as init parameters)

    private var wrapsCursorFlag = false
    private var clickActivates = false
    private var fitsViewportFlag = false
    private var keyboardFocusable = true

    /// A copy that does NOT take keyboard focus — the grid twin of
    /// `ThemedListStyle.takesKeyboardFocus`, for a HOST-DRIVEN keyboard
    /// (facet's overlay grid): no focus-on-click, no system focus ring, and
    /// the kit's own key bindings (`onKeyPress` / `onMoveCommand`) stay
    /// dormant because focus never lands on the grid. Pointer interaction
    /// (hover, taps, the cell drag) is unaffected.
    public func takesKeyboardFocus(_ on: Bool = true) -> Self {
        var c = self; c.keyboardFocusable = on; return c
    }

    /// A copy whose arrow-key cursor WRAPS at the grid's edges (t-mej6 G5) —
    /// last column → first, last row → first (the ragged last row snaps to the
    /// last real cell, `nextGridIndex`'s rule). Default: edges stop.
    public func wrapsCursor(_ wraps: Bool = true) -> Self {
        var c = self; c.wrapsCursorFlag = wraps; return c
    }

    /// A copy where a SINGLE click activates the cell (fires `onActivate`, on
    /// top of moving the cursor) — the overlay-picker idiom (t-mej6 G4), where
    /// a click means "choose this", not "select this". Double-click and Return
    /// keep working; Cmd-click still toggles selection.
    public func activatesOnClick(_ on: Bool = true) -> Self {
        var c = self; c.clickActivates = on; return c
    }

    /// A copy that fits EVERY cell inside its container — no scrolling: cells
    /// shrink (preserving `aspectRatio`) until all rows fit (t-mej6 G1, the
    /// full-screen overlay-grid sizing rule). The grid centres the cell block.
    public func fitsViewport(_ on: Bool = true) -> Self {
        var c = self; c.fitsViewportFlag = on; return c
    }

    /// A copy whose drag resolution consults `validate` before offering a
    /// placement (the list's `dropTargetValidator` twin). A rejected placement
    /// draws no affordance and never reaches `onGridDrop`.
    public func dropTargetValidator(_ validate: @escaping (GridDragContext<ID>, GridDropTarget<ID>) -> Bool) -> Self {
        var c = self; c.dropValidate = validate; return c
    }

    /// A copy that delivers a committed drop. (Named to stay clear of
    /// SwiftUI's own `onDrop`.)
    public func onGridDrop(_ handler: @escaping (GridDragContext<ID>, GridDropTarget<ID>) -> Void) -> Self {
        var c = self; c.onDropHandler = handler; return c
    }

    /// A frozen preview OWNS each interactive facet (the `ListPreview` rule):
    /// falling through to live state would let a stray pointer or focus change
    /// contaminate a deterministic capture.
    private var effHovered: ID? { previewState != nil ? previewState?.hovered : hovered }
    private var effCursor: ID? { previewState != nil ? previewState?.cursor : cursor }
    private var effFocused: Bool { previewState?.focused ?? isFocused }
    private var effDragSource: ID? { previewState != nil ? previewState?.dragSource : dragState?.source }
    private var effDropTargetID: ID? {
        if let p = previewState { return p.dropTargetID }
        if case .onto(let id) = dragState?.target?.placement { return id }
        return nil
    }
    /// The insertion SLOT a reorder drop would land at (`.at` twin of
    /// `effDropTargetID`) — drives the insertion line (t-mej6 G2).
    private var effDropSlot: Int? {
        if let p = previewState { return p.dropSlot }
        if case .at(let i) = dragState?.target?.placement { return i }
        return nil
    }

    // Tokens (tuned later in prism).
    private let gap = CGFloat(Space.md)        // 8
    private let pad = CGFloat(Space.md)        // 8
    private let corner = CGFloat(Radius.lg)    // 8
    private let focusOutset = CGFloat(Space.xxs)  // 2

    public init(_ data: Data,
                id: KeyPath<Data.Element, ID>,
                selection: Binding<Set<ID>>? = nil,
                layout: GridLayout = .adaptive(minCellWidth: 160),
                axis: Axis = .vertical,
                aspectRatio: CGFloat? = nil,
                palette: ResolvedPalette? = nil,
                onActivate: ((ID) -> Void)? = nil,
                allowsMultiSelect: Bool = true,
                @ViewBuilder cell: @escaping (Data.Element, GridCellState) -> Cell) {
        self.data = data
        self.idKey = id
        self.selectionBinding = selection
        self.layout = layout
        self.axis = axis
        self.aspectRatio = aspectRatio
        self.explicitPalette = palette
        self.onActivate = onActivate
        self.allowsMultiSelect = allowsMultiSelect
        self.cellBuilder = cell
    }

    private var selection: Binding<Set<ID>> { selectionBinding ?? $internalSelection }
    private var elements: [Data.Element] { Array(data) }
    private var ids: [ID] { elements.map { $0[keyPath: idKey] } }

    private var gridItems: [GridItem] {
        // Fit mode pre-sizes the cell (both axes), so tracks are FIXED at that
        // size — flexible/adaptive tracks would re-stretch the width the fit
        // just computed.
        if let fs = fittedSize {
            let track = axis == .vertical ? fs.width : fs.height
            return Array(repeating: GridItem(.fixed(track), spacing: gap),
                         count: resolvedColumns)
        }
        switch layout {
        case .fixed(let n):
            return Array(repeating: GridItem(.flexible(), spacing: gap),
                         count: Swift.max(n, 1))
        case .adaptive(let minW):
            return [GridItem(.adaptive(minimum: minW), spacing: gap)]
        }
    }

    public var body: some View {
        GeometryReader { geo in
            gridContainer(geo)
            .focusable(keyboardFocusable)
            .focused($isFocused)
            .onKeyPress(.return) {
                if keyboardDragging { commitKeyboardDrag(); return .handled }
                if let c = cursor { onActivate?(c); return .handled }
                return .ignored
            }
            .onKeyPress(.space) {
                if keyboardDragging { commitKeyboardDrag(); return .handled }
                if dragMode != nil, cursor != nil { liftKeyboard(); return .handled }
                return .ignored
            }
            .onKeyPress(.escape) {
                // Only a live keyboard lift owns Esc — otherwise it stays the
                // host's (an overlay grid dismisses on it).
                guard keyboardDragging else { return .ignored }
                cancelKeyboardDrag(); return .handled
            }
            .onMoveCommand { move($0) }
            .onAppear { recomputeLayout(geo.size) }
            .onChange(of: geo.size) { recomputeLayout(geo.size) }
            .onChange(of: ids) { _, newIds in
                let present = Set(newIds)
                // Reap ids that no longer exist WHOEVER owns the storage. Handing
                // in a binding says "I want to observe the selection", not "I will
                // also garbage-collect it" — and gating the reap on `selectionBinding
                // == nil` meant a bound Set grew without bound across refreshes.
                selection.wrappedValue = reconcileGridSelection(selection.wrappedValue, existing: present)
                if let c = cursor, !present.contains(c) { cursor = nil }
                if let h = hovered, !present.contains(h) { hovered = nil }
                if let ds = dragState, !present.contains(ds.source) {
                    dragState = nil; dragAim = []; dragAimIndex = 0
                }
                recomputeLayout(geo.size)      // fit sizing tracks the count
            }
        }
    }

    /// The scroll container (the default), or the fit-to-viewport block
    /// (t-mej6 G1) — a non-scrolling, centred cell block whose cells were
    /// pre-sized by `recomputeLayout`.
    @ViewBuilder private func gridContainer(_ geo: GeometryProxy) -> some View {
        let content = gridBody
            .padding(pad)
            .coordinateSpace(.named(themedGridContentSpace))
            .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
            .overlay { dragGhostLayer }
            .overlay { slotLineLayer }
        if fitsViewportFlag {
            // EXPLICIT block size, never `.fixedSize()` (t-1cbr): under
            // fixedSize + centred max-frame, the content's ideal-size change
            // when the fit lands (and any structural cell re-identify, e.g.
            // `.onHover`'s hover region) strands descendants'
            // `GeometryReader.frame(in:)` at the PRE-fit placement — pixels
            // re-centre, geometry doesn't, and a host resolving drops against
            // frames its cells report in an OUTER space aims one row off
            // (multi-row grids only; a one-row fit block self-cancels). The
            // kit's own inner-space `cellFrames` are relative and stay
            // consistent either way.
            content
                .frame(width: fittedBlockSize?.width, height: fittedBlockSize?.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView(axis == .vertical ? .vertical : .horizontal) { content }
        }
    }

    /// The fit block's TOTAL size (tracks + gaps + padding), nil before the
    /// first `recomputeLayout`. Sizing the block EXPLICITLY (instead of
    /// `.fixedSize()`) keeps the placement pass deterministic.
    private var fittedBlockSize: CGSize? {
        guard let fs = fittedSize else { return nil }
        let tracks = CGFloat(resolvedColumns)
        let count = ids.count
        let lanes = CGFloat(Swift.max((Swift.max(count, 1) + resolvedColumns - 1) / resolvedColumns, 1))
        let trackSpan = axis == .vertical ? fs.width : fs.height
        let laneSpan = axis == .vertical ? fs.height : fs.width
        let cross = tracks * trackSpan + (tracks - 1) * gap + pad * 2
        let main = lanes * laneSpan + (lanes - 1) * gap + pad * 2
        return axis == .vertical ? CGSize(width: cross, height: main)
                                 : CGSize(width: main, height: cross)
    }

    @ViewBuilder
    private var gridBody: some View {
        if axis == .vertical {
            LazyVGrid(columns: gridItems, spacing: gap) { cells }
        } else {
            LazyHGrid(rows: gridItems, spacing: gap) { cells }
        }
    }

    @ViewBuilder
    private var cells: some View {
        ForEach(elements, id: idKey) { element in
            chrome(for: element)
        }
    }

    @ViewBuilder
    private func chrome(for element: Data.Element) -> some View {
        let id = element[keyPath: idKey]
        let isSel = selection.wrappedValue.contains(id)
        let isCur = effFocused && effCursor == id
        let isHov = effHovered == id
        let isSrc = effDragSource == id
        let isTgt = effDropTargetID == id
        let state: GridCellState = {
            var s = GridCellState(isSelected: isSel, isHovered: isHov, isFocused: isCur)
            s.isDropTarget = isTgt
            s.isSwapSource = isSrc
            return s
        }()

        cellBuilder(element, state)
            .modifier(AspectModifier(ratio: fittedSize == nil ? aspectRatio : nil))
            .frame(width: fittedSize?.width, height: fittedSize?.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fillColor(selected: isSel, hovered: isHov))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(strokeColor(selected: isSel, hovered: isHov),
                                  lineWidth: isSel ? 2 : 1)
            )
            .overlay(focusRing(isCur))
            .opacity(isSrc ? 0.4 : 1)          // lifted source dims (the list's rule)
            .overlay(dropRing(isTgt))          // target ring at full opacity, above the dim
            .shadow(color: shadowColor(selected: isSel, hovered: isHov),
                    radius: (isSel || isHov) ? 4 : 0, x: 0, y: (isSel || isHov) ? 2 : 0)
            .contentShape(Rectangle())
            .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
            .gesture(TapGesture(count: 2).onEnded { onActivate?(id) })
            .gesture(selectionGesture(id))
            .modifier(OptionalDrag(active: dragMode != nil, gesture: cellDragGesture(id)))
            .modifier(OptionalCellFrameReport(active: dragMode != nil, id: AnyHashable(id)))
    }

    /// The drop-target affordance — the grid twin of the list's `.onto` ring
    /// (same inset / fill / stroke so the two widgets read as one family).
    @ViewBuilder private func dropRing(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: corner, style: .continuous).inset(by: 1.5)
                .fill(Color(nsColor: palette.primary).opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).inset(by: 1.5)
                    .stroke(Color(nsColor: palette.primary), lineWidth: 2))
        }
    }

    // MARK: pointer drag (t-n3be — resolution stays pure in GridCore)

    /// Cell frames in `ids` order, `.zero` for unmeasured (culled) cells — the
    /// resolver ignores those rather than letting them shrink the abort zone.
    private var orderedFrames: [CGRect] { ids.map { cellFrames[AnyHashable($0)] ?? .zero } }

    /// The validated target a pointer at `point` resolves to — the one
    /// resolution path the drag gesture uses (package: the validator-plumbing
    /// test seam, mirroring `ThemedListView.pointerDropTarget`).
    package func pointerDropTarget(at point: CGPoint, source: ID, frames: [CGRect]) -> GridDropTarget<ID>? {
        guard let mode = dragMode else { return nil }
        return resolveGridDropTarget(at: point, source: source, ids: ids, frames: frames,
                                     mode: mode, validate: dropValidate)
    }

    private func cellDragGesture(_ id: ID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(themedGridContentSpace))
            .onChanged { value in
                if dragState == nil {
                    dragState = DragInfo(source: id, target: nil, location: value.location)
                }
                var ds = dragState!
                // Lean into the sideways motion (the list ghost's card tilt),
                // smoothed against the previous frame.
                let dx = value.location.x - ds.location.x
                ds.tilt = max(-7, min(7, ds.tilt * 0.6 + dx * 0.8))
                ds.location = value.location
                ds.target = pointerDropTarget(at: value.location, source: ds.source, frames: orderedFrames)
                dragState = ds
            }
            .onEnded { _ in
                if let ds = dragState, let target = ds.target {
                    onDropHandler?(GridDragContext(sourceID: ds.source), target)
                }
                dragState = nil
            }
    }

    // MARK: drag ghost — the lifted cell itself follows the pointer (in-bounds
    // overlay, screencaptureable; the list-ghost rule: re-rendering the real
    // cell is truer than a stand-in chip). A frozen `preview` has no pointer,
    // so the card parks low-right of the cell it lifted.

    @ViewBuilder private var dragGhostLayer: some View {
        if let src = effDragSource,
           let element = elements.first(where: { $0[keyPath: idKey] == src }) {
            GeometryReader { proxy in
                if let centre = ghostCentre(for: src, in: proxy.size) {
                    ghostCard(element)
                        .rotationEffect(.degrees(Double(dragState?.tilt ?? 0)))
                        .position(centre)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    private func ghostCentre(for src: ID, in size: CGSize) -> CGPoint? {
        if let ds = dragState { return ds.location }
        guard previewState != nil else { return nil }
        let f = cellFrames[AnyHashable(src)] ?? .zero
        guard !f.isEmpty else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        return CGPoint(x: f.midX + f.width * 0.25, y: f.midY + f.height * 0.35)
    }

    private func ghostCard(_ element: Data.Element) -> some View {
        let f = cellFrames[AnyHashable(element[keyPath: idKey])]
        let size = (f?.isEmpty == false) ? f!.size : CGSize(width: 96, height: 96)
        return cellBuilder(element, GridCellState(isSelected: false, isHovered: false, isFocused: false))
            .modifier(AspectModifier(ratio: aspectRatio))
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color(nsColor: palette.primary), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .opacity(0.85)
    }

    @ViewBuilder
    private func focusRing(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: corner + focusOutset, style: .continuous)
                .strokeBorder(Color(nsColor: palette.primary), lineWidth: 2)
                .padding(-focusOutset)
        }
    }

    // MARK: colours (canonical roles)
    private func fillColor(selected: Bool, hovered: Bool) -> Color {
        if selected { return Color(nsColor: palette.selection).opacity(0.30) }
        if hovered  { return Color(nsColor: palette.hover).opacity(0.22) }
        return Color(nsColor: palette.muted).opacity(0.08)
    }
    private func strokeColor(selected: Bool, hovered: Bool) -> Color {
        if selected { return Color(nsColor: palette.primary).opacity(0.70) }
        if hovered  { return Color(nsColor: palette.foreground).opacity(0.45) }
        return Color(nsColor: palette.border).opacity(0.50)
    }
    private func shadowColor(selected: Bool, hovered: Bool) -> Color {
        guard selected || hovered else { return .clear }
        let sh = palette.shadow(.dp2)
        return Color(nsColor: palette.foreground).opacity(Double(sh.opacity))
    }

    private func selectOnly(_ id: ID) { selection.wrappedValue = [id] }
    private func toggle(_ id: ID) {
        if selection.wrappedValue.contains(id) { selection.wrappedValue.remove(id) }
        else { selection.wrappedValue.insert(id) }
    }

    /// Single tap replaces the selection; Cmd-tap toggles (multi-select only).
    /// ExclusiveGesture gives the Cmd variant precedence when the modifier is
    /// held, so a plain and a Cmd click never both fire. Under
    /// `activatesOnClick` (t-mej6 G4) the plain tap ALSO fires `onActivate` —
    /// the overlay-picker idiom where one click means "choose this".
    private func selectionGesture(_ id: ID) -> some Gesture {
        let plain = TapGesture().onEnded {
            selectOnly(id); cursor = id; isFocused = true
            if clickActivates { onActivate?(id) }
        }
        let cmd = TapGesture().modifiers(.command).onEnded {
            if allowsMultiSelect { toggle(id) } else { selectOnly(id) }
            cursor = id; isFocused = true
        }
        return ExclusiveGesture(cmd, plain)
    }

    private func crossWidth(_ geo: GeometryProxy) -> CGFloat {
        (axis == .vertical ? geo.size.width : geo.size.height) - pad * 2
    }
    // resolvedColumns is a best-effort headless mirror of SwiftUI's own adaptive layout, used for nav only (and for fit sizing, where the FIXED tracks make it exact); it can differ by one at boundary widths — self-corrects on the next move.
    private func recomputeLayout(_ size: CGSize) {
        let width = (axis == .vertical ? size.width : size.height) - pad * 2
        switch layout {
        case .fixed(let n): resolvedColumns = Swift.max(n, 1)
        case .adaptive(let minW):
            resolvedColumns = gridColumns(availableWidth: width, minCellWidth: minW,
                                          gap: gap, max: Swift.max(ids.count, 1))
        }
        guard fitsViewportFlag else { fittedSize = nil; return }
        let avail = CGSize(width: size.width - pad * 2, height: size.height - pad * 2)
        if axis == .vertical {
            fittedSize = gridFittedCellSize(available: avail, count: ids.count,
                                            columns: resolvedColumns, gap: gap,
                                            aspectRatio: aspectRatio)
        } else {
            // Column-major: fit in TRANSPOSED space (tracks are rows), then
            // swap the result back.
            let t = gridFittedCellSize(available: CGSize(width: avail.height, height: avail.width),
                                       count: ids.count, columns: resolvedColumns, gap: gap,
                                       aspectRatio: aspectRatio.map { $0 > 0 ? 1 / $0 : 1 })
            fittedSize = CGSize(width: t.height, height: t.width)
        }
    }
    // Arrow keys drive a single roving cursor that REPLACES the selection (macOS list/grid convention); shift-extend isn't expressible via onMoveCommand without AppKit.
    private func move(_ direction: MoveCommandDirection) {
        guard !ids.isEmpty else { return }
        let (dx, dy): (Int, Int)
        switch direction {
        case .left:  (dx, dy) = (-1, 0)
        case .right: (dx, dy) = (1, 0)
        case .up:    (dx, dy) = (0, -1)
        case .down:  (dx, dy) = (0, 1)
        @unknown default: (dx, dy) = (0, 0)
        }
        // A live keyboard lift owns the arrows: they AIM the drop, not the
        // cursor (t-mej6 G3).
        if keyboardDragging { aimKeyboard(dx: dx, dy: dy); return }
        let current = cursor.flatMap { ids.firstIndex(of: $0) } ?? 0
        // GridCore handles the row-major↔column-major axis swap (a horizontal
        // LazyHGrid fills column-major); `resolvedColumns` is the cross-axis count.
        let next = nextGridIndex(from: current, dx: dx, dy: dy,
                                 count: ids.count, columns: resolvedColumns,
                                 horizontal: axis == .horizontal, wrap: wrapsCursorFlag)
        cursor = ids[next]
        selectOnly(ids[next])
    }

    // MARK: keyboard drag (t-mej6 G3 — lift / aim / commit / cancel, the
    // ThemedListView handleDragKey family shape; the aim STEP is geometric,
    // because a 2-D grid's candidate list isn't linear)

    private var keyboardDragging: Bool { dragState?.isKeyboard == true }

    private func liftKeyboard() {
        guard let mode = dragMode, let h = cursor else { return }
        let aim = gridDragCandidates(source: h, ids: ids, mode: mode,
                                     validate: dropValidate)
        dragAim = aim
        dragAimIndex = 0
        var info = DragInfo(source: h, target: aim.first, location: .zero, isKeyboard: true)
        info.location = aim.first.flatMap(targetAnchor)
            ?? (cellFrames[AnyHashable(h)].map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero)
        dragState = info
    }

    private func aimKeyboard(dx: Int, dy: Int) {
        guard keyboardDragging, !dragAim.isEmpty else { return }
        let points = dragAim.map { targetAnchor($0) ?? .zero }
        dragAimIndex = gridAimIndex(from: Swift.min(dragAimIndex, dragAim.count - 1),
                                    dx: dx, dy: dy, points: points)
        dragState?.target = dragAim[dragAimIndex]
        dragState?.location = points[dragAimIndex]
    }

    private func commitKeyboardDrag() {
        if let ds = dragState, let target = ds.target {
            onDropHandler?(GridDragContext(sourceID: ds.source), target)
        }
        cancelKeyboardDrag()
    }

    private func cancelKeyboardDrag() {
        dragState = nil; dragAim = []; dragAimIndex = 0
    }

    /// Where a candidate target sits in content space (ghost park + aim
    /// geometry) — the pure `gridTargetAnchor` over the measured frames.
    private func targetAnchor(_ target: GridDropTarget<ID>) -> CGPoint? {
        gridTargetAnchor(target, ids: ids, frames: orderedFrames,
                         horizontal: axis == .horizontal, gap: gap)
    }

    // MARK: reorder insertion line (t-mej6 G2 — the grid twin of the list row's
    // `insertionLine`: a 2pt primary line with 6pt end caps at the slot edge)

    @ViewBuilder private var slotLineLayer: some View {
        if let slot = effDropSlot,
           let seg = gridSlotSegment(index: slot, frames: orderedFrames,
                                     horizontal: axis == .horizontal, gap: gap) {
            let accent = Color(nsColor: palette.primary)
            ZStack {
                Path { p in p.move(to: seg.a); p.addLine(to: seg.b) }
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(accent).frame(width: 6, height: 6).position(seg.a)
                Circle().fill(accent).frame(width: 6, height: 6).position(seg.b)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Applies a fixed width/height ratio to a cell when requested; a no-op otherwise.
private struct AspectModifier: ViewModifier {
    let ratio: CGFloat?
    func body(content: Content) -> some View {
        if let ratio { content.aspectRatio(ratio, contentMode: .fit) }
        else { content }
    }
}
