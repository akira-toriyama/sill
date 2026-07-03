// ThemeKitUI — drag/reorder support for `ThemedListView` (#17b M2c). The view PRODUCES
// per-row geometry (`RowGeom`) that the pure `ListCore` DnD resolvers consume
// (resolveDropTarget / dragCandidates / chunkMemberIDs) — all drop math stays pure. The
// affordances (onto ring / between line / section bar / source dim) + the drag ghost are
// SwiftUI overlays keyed off the drag state; the ghost REPLACES the AppKit DragGhost child
// window (policy-safe AppKit reduction — a standalone list's ghost stays in-bounds).

import SwiftUI
import ListCore

/// Collects each row's (yOffset, height) in the list's content coordinate space, reduced
/// into a map the DnD resolvers + affordance overlays read. Keyed by `AnyHashable` because
/// a `PreferenceKey` can't be generic over the list's `ID`.
struct RowGeomPreference: PreferenceKey {
    static var defaultValue: [AnyHashable: RowGeom] { [:] }
    static func reduce(value: inout [AnyHashable: RowGeom], nextValue: () -> [AnyHashable: RowGeom]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The named coordinate space the geometry + the drag gesture both measure in.
let themedListContentSpace = "themedList.content"

/// Collects each row's frame in the list's VIEWPORT space (fixed to the ScrollView,
/// NOT the scrolling content) so a non-key AppKit popup host can hit-test a `mouseUp`
/// / `mouseMoved` point back to a row id (#17b M3 `hosted` mode). Scrolled-off rows
/// land outside the viewport bounds, so a point-in-rect test naturally excludes them.
/// `AnyHashable`-keyed (a `PreferenceKey` can't be generic over `ID`), remapped to
/// `ID` at the collection site.
struct RowRectPreference: PreferenceKey {
    static var defaultValue: [AnyHashable: CGRect] { [:] }
    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The named coordinate space anchored to the ScrollView viewport (M3 hit-testing).
let themedListViewportSpace = "themedList.viewport"

/// The drop affordance a single row draws (relative to ITSELF — no cross-row geometry).
/// `between*Above` sits at the row's top edge (the gap before it); `*Below` at its bottom
/// (the end gap after the last row).
enum RowDrop: Equatable {
    case onto                       // rounded ring + faint fill on the target row
    case betweenAbove               // thin insertion line + dot at this row's top
    case betweenBelow               // …at the bottom (end gap)
    case sectionBarAbove            // coarse full-bleed chunk bar at the top
    case sectionBarBelow            // …at the bottom
}

extension View {
    /// Report a row's geometry into `RowGeomPreference` under `id`.
    func reportRowGeom<ID: Hashable>(_ id: ID) -> some View {
        background(
            GeometryReader { geo in
                let f = geo.frame(in: .named(themedListContentSpace))
                Color.clear.preference(key: RowGeomPreference.self,
                                       value: [AnyHashable(id): RowGeom(yOffset: f.minY, height: f.height)])
            }
        )
    }

    /// Report a row's VIEWPORT-space frame into `RowRectPreference` under `id`, but
    /// only when `active` (the `hosted` popup path — a standalone list skips it).
    @ViewBuilder func reportRowRect<ID: Hashable>(_ id: ID, when active: Bool) -> some View {
        if active {
            background(
                GeometryReader { geo in
                    Color.clear.preference(key: RowRectPreference.self,
                                           value: [AnyHashable(id): geo.frame(in: .named(themedListViewportSpace))])
                }
            )
        } else {
            self
        }
    }
}

/// The row's SwiftUI tap + hover — installed only for a STANDALONE list. A `hosted`
/// popup (combo/menu) drives activation + hover from the host's AppKit `mouseUp` /
/// tracking area instead, so the SwiftUI gestures are omitted to avoid double-firing
/// and the non-key-panel tick slip (#17b M3).
struct StandaloneRowInteraction: ViewModifier {
    let active: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    func body(content: Content) -> some View {
        if active {
            content.onTapGesture(perform: onTap).onHover(perform: onHover)
        } else {
            content
        }
    }
}

/// Attach a drag gesture only when the row is a live drag source (so non-draggable rows
/// keep their plain tap/hover handling untouched).
struct OptionalDrag<G: Gesture>: ViewModifier {
    let active: Bool
    let gesture: G
    @ViewBuilder func body(content: Content) -> some View {
        if active { content.gesture(gesture) } else { content }
    }
}
