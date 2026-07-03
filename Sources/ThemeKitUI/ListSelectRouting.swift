// ThemeKitUI — the thin selection-routing seam for `ThemedListView` (#17b M2). Forwards
// to the pure, already-tested `ListCore.MultiSelection` resolvers so the SwiftUI list
// inherits the M1 green net instead of re-implementing selection math. Single-select is
// just a click with no modifiers; multi-select (.command / .shift) lands in M2b.

import ListCore

enum ThemedListSelect {
    /// A row click → new (selection, anchor). Non-selectable ids (headers / separators /
    /// disabled) are a no-op. Delegates to `ListCore.resolveClick`.
    static func click<ID: Hashable>(id: ID, current: Set<ID>, anchor: ID?,
                                    mods: SelectMods, selectable: [ID]) -> (selection: Set<ID>, anchor: ID?) {
        guard selectable.contains(id) else { return (current, anchor) }
        return resolveClick(id: id, current: current, anchor: anchor, mods: mods, selectable: selectable)
    }

    /// Select every selectable row (⌘A) — delegates to `ListCore.selectAll`.
    static func all<ID: Hashable>(selectable: [ID]) -> Set<ID> {
        selectAll(selectable: selectable)
    }
}
