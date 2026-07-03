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

@MainActor
public struct ThemedGridView<Data, ID, Cell>: View
where Data: RandomAccessCollection, ID: Hashable, Cell: View {

    private let data: Data
    private let idKey: KeyPath<Data.Element, ID>
    private let layout: GridLayout
    private let axis: Axis
    private let aspectRatio: CGFloat?
    private let palette: ResolvedPalette
    private let onActivate: ((ID) -> Void)?
    private let cellBuilder: (Data.Element, GridCellState) -> Cell
    private let selectionBinding: Binding<Set<ID>>?
    private let allowsMultiSelect: Bool

    @State private var internalSelection: Set<ID> = []
    @State private var cursor: ID?
    @State private var hovered: ID?
    @State private var resolvedColumns: Int = 1
    @FocusState private var isFocused: Bool

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
                palette: ResolvedPalette,
                onActivate: ((ID) -> Void)? = nil,
                allowsMultiSelect: Bool = true,
                @ViewBuilder cell: @escaping (Data.Element, GridCellState) -> Cell) {
        self.data = data
        self.idKey = id
        self.selectionBinding = selection
        self.layout = layout
        self.axis = axis
        self.aspectRatio = aspectRatio
        self.palette = palette
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
                if selectionBinding == nil {
                    internalSelection = reconcileGridSelection(internalSelection, existing: present)
                }
                if let c = cursor, !present.contains(c) { cursor = nil }
                if let h = hovered, !present.contains(h) { hovered = nil }
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
        let isCur = isFocused && cursor == id
        let isHov = hovered == id
        let state = GridCellState(isSelected: isSel, isHovered: isHov, isFocused: isCur)

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
            .shadow(color: shadowColor(selected: isSel, hovered: isHov),
                    radius: (isSel || isHov) ? 4 : 0, x: 0, y: (isSel || isHov) ? 2 : 0)
            .contentShape(Rectangle())
            .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
            .gesture(TapGesture(count: 2).onEnded { onActivate?(id) })
            .gesture(selectionGesture(id))
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

    // MARK: selection
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

    // MARK: keyboard
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
