// ThemeKitUI — drag/reorder support for `ThemedGridView` (t-n3be, the grid twin
// of ThemedListDrag). The view PRODUCES per-cell frames that the pure GridCore
// resolvers consume (resolveGridDropTarget / gridDragCandidates) — all drop math
// stays pure. The affordances (target ring / source dim) + the drag ghost are
// SwiftUI overlays keyed off the drag state, in-bounds and screencaptureable.

import SwiftUI
import GridCore

/// Collects each cell's frame in the grid's content coordinate space, reduced
/// into the map the DnD resolver + the ghost read. Keyed by `AnyHashable`
/// because a `PreferenceKey` can't be generic over the grid's `ID`.
struct CellFramePreference: PreferenceKey {
    static var defaultValue: [AnyHashable: CGRect] { [:] }
    static func reduce(value: inout [AnyHashable: CGRect], nextValue: () -> [AnyHashable: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The named coordinate space the cell frames + the drag gesture both measure in.
let themedGridContentSpace = "themedGrid.content"

extension View {
    /// Report a cell's content-space frame into `CellFramePreference` under `id`.
    func reportCellFrame(_ id: AnyHashable) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: CellFramePreference.self,
                                       value: [id: geo.frame(in: .named(themedGridContentSpace))])
            }
        )
    }
}

/// Report a cell frame only when the grid is draggable — the frames are read
/// only by the drop resolver + the ghost, so a non-draggable grid skips the
/// per-cell `GeometryReader` cost (a single-purpose gate, unlike the dual-role
/// `hosted` flag t-fyvs removed).
struct OptionalCellFrameReport: ViewModifier {
    let active: Bool
    let id: AnyHashable
    @ViewBuilder func body(content: Content) -> some View {
        if active { content.reportCellFrame(id) } else { content }
    }
}
