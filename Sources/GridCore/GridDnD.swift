import Foundation

// GridDnD — the grid twin of ListCore/ListDnD (#17e §3.2's "布石", unblocked by
// the macOS 26 floor). Same split: the pure mechanism (vocabulary + resolvers)
// lives here; the MEANING of a drop (swap / move / reorder) is the consumer's
// callback. Generic over ID like the rest of GridCore.

/// What kinds of drop a draggable grid resolves: `.dropOnto` (onto a cell —
/// swap/move semantics), `.reorderAt` (an insertion slot in row-major order),
/// `.both` (the kit picks onto vs slot by the pointer's in-cell fraction).
public enum GridDragMode: Equatable, Sendable { case dropOnto, reorderAt, both }

/// WHERE a drag would land. `.onto(id:)` ⇒ onto that cell; `.at(index:)` ⇒ the
/// insertion slot before the cell at `index` in row-major order (`ids.count` ⇒
/// the end slot).
public enum GridDropPlacement<ID: Hashable>: Equatable {
    case onto(id: ID)
    case at(index: Int)
}
extension GridDropPlacement: Sendable where ID: Sendable {}

/// The thing being dragged. Grid lifts are single-cell (no chunk analog —
/// a grid has no section structure to carry).
public struct GridDragContext<ID: Hashable>: Equatable {
    public let sourceID: ID
    public init(sourceID: ID) { self.sourceID = sourceID }
}
extension GridDragContext: Sendable where ID: Sendable {}

/// A resolved drop target handed to the validator / drop callback.
public struct GridDropTarget<ID: Hashable>: Equatable {
    public let placement: GridDropPlacement<ID>
    public init(placement: GridDropPlacement<ID>) { self.placement = placement }
}
extension GridDropTarget: Sendable where ID: Sendable {}

#if canImport(CoreGraphics)
import CoreGraphics

/// How far beyond the grid's cell extent a pointer may stray and still resolve
/// a target. BEYOND it the drag resolves to nil — releasing does nothing, the
/// flick-away escape hatch a mouse drag needs once lifted (the list's
/// `dropEscapeMargin` lesson from facet #448, applied here from day one).
public let gridDropEscapeMargin: CGFloat = 32

/// Squared distance from `p` to the nearest point of `r` (0 inside).
private func distSq(_ r: CGRect, _ p: CGPoint) -> CGFloat {
    let dx = Swift.max(r.minX - p.x, 0, p.x - r.maxX)
    let dy = Swift.max(r.minY - p.y, 0, p.y - r.maxY)
    return dx * dx + dy * dy
}

private func validatedGridTarget<ID: Hashable>(_ placement: GridDropPlacement<ID>,
                                               source: ID, ids: [ID],
                                               validate: (GridDragContext<ID>, GridDropTarget<ID>) -> Bool)
    -> GridDropTarget<ID>? {
    let si = ids.firstIndex(of: source)
    switch placement {
    case .onto(let id):
        guard id != source else { return nil }
    case .at(let index):
        guard index >= 0, index <= ids.count else { return nil }
        // The slot on either side of the source is the no-move gap.
        if let si, index == si || index == si + 1 { return nil }
    }
    let target = GridDropTarget(placement: placement)
    guard validate(GridDragContext(sourceID: source), target) else { return nil }
    return target
}

/// The validated drop target a pointer at `point` resolves to (pure). `frames`
/// are the cells' rects in the same coordinate space as `point`, index-aligned
/// with `ids`; zero-sized rects (unmeasured, culled cells) are ignored rather
/// than letting them shrink the abort boundary to the origin (the list's
/// culled-row lesson). A `point` more than `gridDropEscapeMargin` outside the
/// measured extent is nil — the abort zone. In-grid gaps resolve against the
/// NEAREST measured cell.
public func resolveGridDropTarget<ID: Hashable>(at point: CGPoint, source: ID,
                                                ids: [ID], frames: [CGRect],
                                                mode: GridDragMode,
                                                validate: (GridDragContext<ID>, GridDropTarget<ID>) -> Bool)
    -> GridDropTarget<ID>? {
    guard ids.count == frames.count else { return nil }
    let measured = frames.enumerated().filter { !$0.element.isEmpty }
    guard !measured.isEmpty else { return nil }
    var bounds = measured[0].element
    for (_, f) in measured.dropFirst() { bounds = bounds.union(f) }
    guard bounds.insetBy(dx: -gridDropEscapeMargin, dy: -gridDropEscapeMargin).contains(point) else {
        return nil
    }
    let i = measured.first { $0.element.contains(point) }?.offset
        ?? measured.min { distSq($0.element, point) < distSq($1.element, point) }!.offset
    let f = frames[i]
    let frac = f.width > 0 ? (point.x - f.minX) / f.width : 0.5
    switch mode {
    case .dropOnto:
        return validatedGridTarget(.onto(id: ids[i]), source: source, ids: ids, validate: validate)
    case .reorderAt:
        return validatedGridTarget(.at(index: frac < 0.5 ? i : i + 1), source: source, ids: ids, validate: validate)
    case .both:
        if frac < 0.25 { return validatedGridTarget(.at(index: i), source: source, ids: ids, validate: validate) }
        if frac > 0.75 { return validatedGridTarget(.at(index: i + 1), source: source, ids: ids, validate: validate) }
        return validatedGridTarget(.onto(id: ids[i]), source: source, ids: ids, validate: validate)
            ?? validatedGridTarget(.at(index: i), source: source, ids: ids, validate: validate)
    }
}

/// The ordered, validated keyboard/candidate targets for `source` + `mode`, in
/// row-major visual order (slots interleave before their cell; the end slot
/// closes a reorder list). The kit's SwiftUI grid does not yet bind a keyboard
/// lift itself — this is the pure aim list a host (or a future kit binding)
/// cycles through.
public func gridDragCandidates<ID: Hashable>(source: ID, ids: [ID], mode: GridDragMode,
                                             validate: (GridDragContext<ID>, GridDropTarget<ID>) -> Bool)
    -> [GridDropTarget<ID>] {
    var out: [GridDropTarget<ID>] = []
    for (i, id) in ids.enumerated() {
        switch mode {
        case .dropOnto:
            if let t = validatedGridTarget(.onto(id: id), source: source, ids: ids, validate: validate) { out.append(t) }
        case .reorderAt:
            if let t = validatedGridTarget(.at(index: i), source: source, ids: ids, validate: validate) { out.append(t) }
        case .both:
            if let t = validatedGridTarget(.at(index: i), source: source, ids: ids, validate: validate) { out.append(t) }
            if let t = validatedGridTarget(.onto(id: id), source: source, ids: ids, validate: validate) { out.append(t) }
        }
    }
    if mode != .dropOnto,
       let t = validatedGridTarget(.at(index: ids.count), source: source, ids: ids, validate: validate) {
        out.append(t)
    }
    return out
}
#endif
