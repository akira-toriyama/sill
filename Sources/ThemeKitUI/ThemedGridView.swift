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
    public init(hovered: ID? = nil, cursor: ID? = nil, focused: Bool = true) {
        self.hovered = hovered; self.cursor = cursor; self.focused = focused
    }

    /// A copy frozen mid-drag: `source` lifted, the drop landing on `over`.
    public func dragging(source: ID?, over: ID? = nil) -> Self {
        var c = self; c.dragSource = source; c.dropTargetID = over; return c
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
    // resolver consumes (the list's DragInfo/geomMap twin).
    private struct DragInfo { var source: ID; var target: GridDropTarget<ID>?; var location: CGPoint; var tilt: CGFloat = 0 }
    @State private var dragState: DragInfo?
    @State private var cellFrames: [AnyHashable: CGRect] = [:]

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

    /// A copy whose cells can be pointer-dragged. Keyboard lift is not yet
    /// bound by the kit — `gridDragCandidates` is the pure aim list a host
    /// can cycle itself.
    public func draggable(_ mode: GridDragMode = .dropOnto) -> Self {
        var c = self; c.dragMode = mode; return c
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
            ScrollView(axis == .vertical ? .vertical : .horizontal) {
                gridBody
                    .padding(pad)
                    .coordinateSpace(.named(themedGridContentSpace))
                    .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
                    .overlay { dragGhostLayer }
            }
            .focusable()
            .focused($isFocused)
            .onKeyPress(.return) {
                if let c = cursor { onActivate?(c); return .handled }
                return .ignored
            }
            .onMoveCommand { move($0) }
            .onAppear { recomputeColumns(width: crossWidth(geo)) }
            .onChange(of: geo.size) { recomputeColumns(width: crossWidth(geo)) }
            .onChange(of: ids) { _, newIds in
                let present = Set(newIds)
                // Reap ids that no longer exist WHOEVER owns the storage. Handing
                // in a binding says "I want to observe the selection", not "I will
                // also garbage-collect it" — and gating the reap on `selectionBinding
                // == nil` meant a bound Set grew without bound across refreshes.
                selection.wrappedValue = reconcileGridSelection(selection.wrappedValue, existing: present)
                if let c = cursor, !present.contains(c) { cursor = nil }
                if let h = hovered, !present.contains(h) { hovered = nil }
                if let ds = dragState, !present.contains(ds.source) { dragState = nil }
            }
        }
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
            .modifier(AspectModifier(ratio: aspectRatio))
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
    /// held, so a plain and a Cmd click never both fire.
    private func selectionGesture(_ id: ID) -> some Gesture {
        let plain = TapGesture().onEnded { selectOnly(id); cursor = id; isFocused = true }
        let cmd = TapGesture().modifiers(.command).onEnded {
            if allowsMultiSelect { toggle(id) } else { selectOnly(id) }
            cursor = id; isFocused = true
        }
        return ExclusiveGesture(cmd, plain)
    }

    private func crossWidth(_ geo: GeometryProxy) -> CGFloat {
        (axis == .vertical ? geo.size.width : geo.size.height) - pad * 2
    }
    // resolvedColumns is a best-effort headless mirror of SwiftUI's own adaptive layout, used for nav only; it can differ by one at boundary widths — self-corrects on the next move.
    private func recomputeColumns(width: CGFloat) {
        switch layout {
        case .fixed(let n): resolvedColumns = Swift.max(n, 1)
        case .adaptive(let minW):
            resolvedColumns = gridColumns(availableWidth: width, minCellWidth: minW,
                                          gap: gap, max: Swift.max(ids.count, 1))
        }
    }
    // Arrow keys drive a single roving cursor that REPLACES the selection (macOS list/grid convention); shift-extend isn't expressible via onMoveCommand without AppKit.
    private func move(_ direction: MoveCommandDirection) {
        guard !ids.isEmpty else { return }
        let current = cursor.flatMap { ids.firstIndex(of: $0) } ?? 0
        let (dx, dy): (Int, Int)
        switch direction {
        case .left:  (dx, dy) = (-1, 0)
        case .right: (dx, dy) = (1, 0)
        case .up:    (dx, dy) = (0, -1)
        case .down:  (dx, dy) = (0, 1)
        @unknown default: (dx, dy) = (0, 0)
        }
        // GridCore handles the row-major↔column-major axis swap (a horizontal
        // LazyHGrid fills column-major); `resolvedColumns` is the cross-axis count.
        let next = nextGridIndex(from: current, dx: dx, dy: dy,
                                 count: ids.count, columns: resolvedColumns,
                                 horizontal: axis == .horizontal, wrap: false)
        cursor = ids[next]
        selectOnly(ids[next])
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
