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
package enum RowDrop: Equatable {
    case onto                       // rounded ring + faint fill on the target row
    case betweenAbove               // thin insertion line + dot at this row's top
    case betweenBelow               // …at the bottom (end gap)
    case sectionBarAbove            // coarse full-bleed chunk bar at the top
    case sectionBarBelow            // …at the bottom
    // The BAND (host-declared via `dropBand(_:)`): the rows a coarse-granularity
    // drop actually affects, painted as one filled + outlined area. Split by
    // position so the outline closes at the ends and the middle stays open —
    // one row's overlay can't know its neighbours.
    case bandTop                    // fill + top/leading/trailing edge
    case bandBody                   // fill + leading/trailing edge
    case bandBottom                 // fill + bottom/leading/trailing edge
    case bandSolo                   // fill + the whole outline (a one-row band)
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

    /// Report a row's VIEWPORT-space frame into `RowRectPreference` under `id`.
    ///
    /// Unconditional. This used to be gated on `style.hosted`, which quietly made
    /// one flag decide two unrelated things: whether the host drives click/hover
    /// AND whether row rects exist at all. A standalone list that wants to anchor
    /// something to a row — facet's hover thumbnails — then had no way to ask for
    /// rects without also surrendering its tap and hover gestures (`hosted` turns
    /// `StandaloneRowInteraction` off), so the previews silently never appeared.
    /// Publishing always costs one more `GeometryReader` per VISIBLE row on top of
    /// `reportRowGeom`, which is already unconditional — the gate saved a second
    /// copy of a cost the list was paying regardless.
    func reportRowRect<ID: Hashable>(_ id: ID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: RowRectPreference.self,
                                       value: [AnyHashable(id): geo.frame(in: .named(themedListViewportSpace))])
            }
        )
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

/// Vend the pointer shape a row's affordance calls for (`ListPointerAffordance`,
/// decided by `ThemedListView.pointerAffordance(for:)`); `nil` leaves the system
/// arrow. `grab` (`.grabActive`, the closed hand) rides BOTH the rows and
/// the list container during a live lift — the container catches the gaps
/// between rows, the rows out-specify the container (innermost pointer style
/// wins), and together the hand never flickers mid-drag. macOS honours a
/// pointer style only while the app is ACTIVE — over a non-activating panel at
/// rest this is a no-op, the OS limit the AppKit predecessor accepted (its
/// `NSCursor.set()` was the same silent no-op there).
///
/// INVARIANT — `body` must stay BRANCH-FREE (`pointerStyle(_:)` takes an
/// Optional; map `kind` into it). A `@ViewBuilder` branch over `kind` puts the
/// wrapped subtree inside `_ConditionalContent`, so the very first drag tick
/// (`dragState` set → the container call-site's kind flips nil → `.grab`)
/// re-identifies everything under it — including the row holding the live
/// `DragGesture`, whose `.onEnded` (the only pointer-path `dragState = nil`)
/// then never fires: the lift stays grabbed forever (t-1y9q regression).
/// `RowPointerIdentityTests` pins this at the mechanism level.
struct RowPointer: ViewModifier {
    let kind: ListPointerAffordance?
    func body(content: Content) -> some View {
        content.pointerStyle(kind.map { $0 == .link ? .link : .grabActive })
    }
}

/// Attach a hover tooltip only when the row vends one (`ThemedListRow.helpText`)
/// — `.help("")` still registers an empty tip, so absence must be structural.
struct OptionalHelp: ViewModifier {
    let text: String?
    @ViewBuilder func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
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
