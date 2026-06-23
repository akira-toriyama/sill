import Foundation

/// Pure modifier flags for a multi-select click — NOT `NSEvent.ModifierFlags` (the host
/// maps the platform flags onto this). `.command` toggles one row; `.shift` selects the
/// anchor→clicked range.
public struct SelectMods: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = SelectMods(rawValue: 1 << 0)
    public static let shift   = SelectMods(rawValue: 1 << 1)
}

/// The inclusive id range between two endpoints in the ordered `selectable` list,
/// order-independent. Empty if either endpoint is absent.
public func rangeIDs<ID: Hashable>(from: ID, to: ID, in selectable: [ID]) -> [ID] {
    guard let a = selectable.firstIndex(of: from), let b = selectable.firstIndex(of: to) else { return [] }
    let lo = min(a, b), hi = max(a, b)
    return Array(selectable[lo...hi])
}

/// Resolve a row click into the new multi-selection + anchor, mirroring Finder/MUI:
///  * plain    — replace the selection with `{id}`, anchor = `id`.
///  * `.command` — toggle `id` in/out; anchor = `id`.
///  * `.shift`  — select the inclusive anchor→`id` range (anchor unchanged); with no
///                anchor it degrades to a plain click.
/// `selectable` is the ordered selectable-only id list (caller filters headers/separators/disabled).
public func resolveClick<ID: Hashable>(id: ID, current: Set<ID>, anchor: ID?,
                                       mods: SelectMods, selectable: [ID]) -> (selection: Set<ID>, anchor: ID?) {
    guard selectable.contains(id) else { return (current, anchor) }
    if mods.contains(.shift), let anchor, selectable.contains(anchor) {
        return (Set(rangeIDs(from: anchor, to: id, in: selectable)), anchor)
    }
    if mods.contains(.command) {
        var next = current
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return (next, id)
    }
    return ([id], id)
}

/// Keyboard move of the focus row by `delta` over `selectable` (reusing `nextHighlight`):
/// with `shiftHeld` the selection grows to the inclusive anchor→focus range; without it
/// the focus moves and the selection collapses to the new focus (anchor follows).
public func extendByKey<ID: Hashable>(current: Set<ID>, anchor: ID?, focus: ID?, delta: Int,
                                      selectable: [ID], shiftHeld: Bool, wraps: Bool)
    -> (selection: Set<ID>, anchor: ID?, focus: ID?) {
    let curIdx = focus.flatMap { selectable.firstIndex(of: $0) }
    guard let nextIdx = nextHighlight(current: curIdx, delta: delta,
                                      selectableIndices: Array(selectable.indices), wraps: wraps) else {
        return (current, anchor, focus)
    }
    let newFocus = selectable[nextIdx]
    if shiftHeld {
        let a = anchor ?? focus ?? newFocus
        return (Set(rangeIDs(from: a, to: newFocus, in: selectable)), a, newFocus)
    }
    return ([newFocus], newFocus, newFocus)
}

/// Select every selectable row (⌘A).
public func selectAll<ID: Hashable>(selectable: [ID]) -> Set<ID> { Set(selectable) }
