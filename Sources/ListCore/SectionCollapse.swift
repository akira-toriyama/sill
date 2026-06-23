import Foundation

/// Toggle a section header's collapsed state in the host-owned `collapsed` set.
public func toggleSection<ID: Hashable>(_ id: ID, in collapsed: Set<ID>) -> Set<ID> {
    var next = collapsed
    if next.contains(id) { next.remove(id) } else { next.insert(id) }
    return next
}

/// The visible rows given a host-owned `collapsed` set: a collapsed header keeps the
/// header itself but drops every row after it up to (not including) the next header.
/// The single source of "visible" for the renderer AND the DnD/chunk/sticky cores, so
/// they never disagree about which rows exist.
public func flattenVisible<ID: Hashable>(rows: [ListRow<ID>], collapsed: Set<ID>) -> [ListRow<ID>] {
    var out: [ListRow<ID>] = []
    var skipping = false
    for row in rows {
        if row.isHeader {
            out.append(row)
            skipping = collapsed.contains(row.id)
        } else if !skipping {
            out.append(row)
        }
    }
    return out
}
