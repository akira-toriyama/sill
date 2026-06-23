import Foundation

// MARK: - DnD vocabulary (moved from ThemeKit.ThemedList; generic over ID)

/// What kinds of drop a draggable list resolves: `.dropOnto` (onto a row), `.reorderBetween`
/// (insertion line), `.both` (the kit picks onto vs between by the pointer's row fraction).
public enum DragMode: Equatable, Sendable { case dropOnto, reorderBetween, both }

/// WHERE a drag would land. `.onto(id:)` ⇒ onto that row; `.between(beforeID:)` ⇒ the gap
/// before `beforeID` (`nil` ⇒ after the last row, the end gap).
public enum DropPlacement<ID: Hashable & Sendable>: Equatable, Sendable {
    case onto(id: ID)
    case between(beforeID: ID?)
}

/// The thing being dragged: the lifted row + every id that moves with it (`[sourceID]`
/// for a single row, `[header, …children]` for a chunk; never empty).
public struct DragContext<ID: Hashable & Sendable>: Equatable, Sendable {
    public let sourceID: ID
    public let memberIDs: [ID]
    public init(sourceID: ID, memberIDs: [ID]) { self.sourceID = sourceID; self.memberIDs = memberIDs }
}

/// A resolved drop target handed to the validator / onDrop.
public struct DropTarget<ID: Hashable & Sendable>: Equatable, Sendable {
    public let placement: DropPlacement<ID>
    public init(placement: DropPlacement<ID>) { self.placement = placement }
}

#if canImport(CoreGraphics)
import CoreGraphics

/// One row's vertical layout in the flipped document space (the only geometry the
/// drop resolver reads). Built by the view from its row layout.
public struct RowGeom: Equatable, Sendable {
    public let yOffset: CGFloat
    public let height: CGFloat
    public init(yOffset: CGFloat, height: CGFloat) { self.yOffset = yOffset; self.height = height }
}

/// The row index containing `docY`, or nil if past the last row.
public func rowIndex(atDocY docY: CGFloat, geom: [RowGeom]) -> Int? {
    geom.firstIndex { docY >= $0.yOffset && docY < $0.yOffset + $0.height }
}

private func nextRowID<ID>(after i: Int, in rows: [ListRow<ID>]) -> ID? {
    let n = i + 1
    return rows.indices.contains(n) ? rows[n].id : nil
}

private func indexOf<ID: Hashable>(_ id: ID, in rows: [ListRow<ID>]) -> Int? {
    rows.firstIndex { $0.id == id }
}

private func isTrivialSelfDrop<ID: Hashable>(_ placement: DropPlacement<ID>, _ source: ID,
                                             rows: [ListRow<ID>]) -> Bool {
    switch placement {
    case .onto(let id): return id == source
    case .between(let beforeID):
        guard let si = indexOf(source, in: rows) else { return false }
        return beforeID == source || beforeID == nextRowID(after: si, in: rows)
    }
}

/// Returns true when `placement` lands inside (or in the no-move gap of) the lifted chunk.
/// Public so the AppKit test seam `_isInsideChunk` can forward here directly.
public func isInsideChunk<ID: Hashable>(_ placement: DropPlacement<ID>, source: ID,
                                        rows: [ListRow<ID>], chunkIDs: [ID]) -> Bool {
    guard !chunkIDs.isEmpty else { return false }
    let members = Set(chunkIDs)
    switch placement {
    case .onto(let id): return members.contains(id)
    case .between(let beforeID):
        if let beforeID, members.contains(beforeID) { return true }
        guard let lastID = chunkIDs.last, let li = indexOf(lastID, in: rows) else { return false }
        var j = li + 1
        while j < rows.count, rows[j].isSeparator { j += 1 }
        let boundaryID: ID? = j < rows.count ? rows[j].id : nil
        return beforeID == nextRowID(after: li, in: rows) || beforeID == boundaryID
    }
}

private func validatedTarget<ID: Hashable>(_ placement: DropPlacement<ID>, _ source: ID,
                                           rows: [ListRow<ID>], chunkIDs: [ID],
                                           validate: (DragContext<ID>, DropTarget<ID>) -> Bool) -> DropTarget<ID>? {
    guard !isTrivialSelfDrop(placement, source, rows: rows) else { return nil }
    guard !isInsideChunk(placement, source: source, rows: rows, chunkIDs: chunkIDs) else { return nil }
    if case let .onto(id) = placement, let i = indexOf(id, in: rows), rows[i].isSeparator { return nil }
    let target = DropTarget(placement: placement)
    let ctx = DragContext(sourceID: source, memberIDs: chunkIDs.isEmpty ? [source] : chunkIDs)
    guard validate(ctx, target) else { return nil }
    return target
}

/// The validated drop target a pointer at `docY` resolves to (pure). A non-empty `chunkIDs`
/// forces `.reorderBetween` (a chunk reorders to a gap, never onto a row).
public func resolveDropTarget<ID: Hashable>(atDocY docY: CGFloat, source: ID,
                                            rows: [ListRow<ID>], geom: [RowGeom],
                                            mode requestedMode: DragMode, chunkIDs: [ID],
                                            validate: (DragContext<ID>, DropTarget<ID>) -> Bool) -> DropTarget<ID>? {
    guard !rows.isEmpty else { return nil }
    let mode: DragMode = chunkIDs.isEmpty ? requestedMode : .reorderBetween
    if docY < 0 {
        return mode == .dropOnto ? nil : validatedTarget(.between(beforeID: rows[0].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    }
    guard let i = rowIndex(atDocY: docY, geom: geom) else {
        return mode == .dropOnto ? nil : validatedTarget(.between(beforeID: nil), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    }
    if rows[i].isSeparator { return nil }
    let minY = geom[i].yOffset, h = geom[i].height
    let frac = h > 0 ? (docY - minY) / h : 0.5
    switch mode {
    case .dropOnto:
        return validatedTarget(.onto(id: rows[i].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    case .reorderBetween:
        return validatedTarget(.between(beforeID: frac < 0.5 ? rows[i].id : nextRowID(after: i, in: rows)), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    case .both:
        if frac < 0.25 { return validatedTarget(.between(beforeID: rows[i].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) }
        if frac > 0.75 { return validatedTarget(.between(beforeID: nextRowID(after: i, in: rows)), source, rows: rows, chunkIDs: chunkIDs, validate: validate) }
        return validatedTarget(.onto(id: rows[i].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
            ?? validatedTarget(.between(beforeID: rows[i].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    }
}

/// The ordered, validated keyboard candidates for `source` + `mode`. A chunk lift aims at
/// section-header gaps + the end gap only (whole-section reorder); else onto/between per mode.
public func dragCandidates<ID: Hashable>(source: ID, rows: [ListRow<ID>], mode: DragMode,
                                         chunkIDs: [ID],
                                         validate: (DragContext<ID>, DropTarget<ID>) -> Bool) -> [DropTarget<ID>] {
    var out: [DropTarget<ID>] = []
    if !chunkIDs.isEmpty {
        for h in rows.indices where rows[h].isHeader {
            if let t = validatedTarget(.between(beforeID: rows[h].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        }
        if let t = validatedTarget(.between(beforeID: nil), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        return out
    }
    for row in rows where !row.isSeparator {
        switch mode {
        case .dropOnto:
            if let t = validatedTarget(.onto(id: row.id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        case .reorderBetween:
            if let t = validatedTarget(.between(beforeID: row.id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        case .both:
            if let t = validatedTarget(.between(beforeID: row.id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
            if let t = validatedTarget(.onto(id: row.id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        }
    }
    if mode != .dropOnto, let t = validatedTarget(.between(beforeID: nil), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
    return out
}

/// The ids that move as a unit when the section HEADER `id` is lifted: the header + every
/// row beneath up to (not including) the next header; separators skipped; non-header ⇒ [].
public func chunkMemberIDs<ID: Hashable>(forHeader id: ID, rows: [ListRow<ID>]) -> [ID] {
    guard let start = indexOf(id, in: rows), rows[start].isHeader else { return [] }
    var out = [rows[start].id]
    var i = start + 1
    while i < rows.count, !rows[i].isHeader {
        if !rows[i].isSeparator { out.append(rows[i].id) }
        i += 1
    }
    return out
}
#endif
