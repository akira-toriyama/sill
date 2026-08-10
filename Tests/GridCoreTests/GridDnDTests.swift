// GridDnD (t-n3be) — the pure resolution semantics behind ThemedGridView's
// pointer DnD, ListDnDTests' grid twin: containing-cell + nearest-cell-in-gap
// resolution, the in-cell fraction thresholds, the trivial self-drop / no-move
// gaps, the abort margin, culled (zero-rect) cell exclusion, and the validator
// gate on every path.
import XCTest
import CoreGraphics
@testable import GridCore

final class GridDnDTests: XCTestCase {

    // A 3×2 grid of 100pt cells with a 10pt gap:
    //   a(0,0)   b(110,0)   c(220,0)
    //   d(0,110) e(110,110) f(220,110)
    private let ids = ["a", "b", "c", "d", "e", "f"]
    private var frames: [CGRect] {
        (0..<6).map { CGRect(x: CGFloat($0 % 3) * 110, y: CGFloat($0 / 3) * 110,
                             width: 100, height: 100) }
    }
    private let accept: (GridDragContext<String>, GridDropTarget<String>) -> Bool = { _, _ in true }

    private func resolve(_ point: CGPoint, source: String, mode: GridDragMode,
                         validate: ((GridDragContext<String>, GridDropTarget<String>) -> Bool)? = nil)
        -> GridDropTarget<String>? {
        resolveGridDropTarget(at: point, source: source, ids: ids, frames: frames,
                              mode: mode, validate: validate ?? accept)
    }

    // MARK: onto

    func testPointInsideCellResolvesOnto() {
        XCTAssertEqual(resolve(CGPoint(x: 50, y: 50), source: "f", mode: .dropOnto),
                       GridDropTarget(placement: .onto(id: "a")))
    }

    func testSelfDropResolvesNil() {
        XCTAssertNil(resolve(CGPoint(x: 50, y: 50), source: "a", mode: .dropOnto))
    }

    func testGapResolvesNearestCell() {
        XCTAssertEqual(resolve(CGPoint(x: 104, y: 50), source: "f", mode: .dropOnto),
                       GridDropTarget(placement: .onto(id: "a")),
                       "a point in the 10pt gap must resolve against the nearest cell")
        XCTAssertEqual(resolve(CGPoint(x: 106, y: 50), source: "f", mode: .dropOnto),
                       GridDropTarget(placement: .onto(id: "b")))
    }

    // MARK: abort zone

    func testBeyondEscapeMarginResolvesNil() {
        XCTAssertNil(resolve(CGPoint(x: 320 + gridDropEscapeMargin + 1, y: 50),
                             source: "a", mode: .dropOnto),
                     "past the margin the release must do nothing — the flick-away abort")
        XCTAssertNil(resolve(CGPoint(x: 50, y: -gridDropEscapeMargin - 1),
                             source: "f", mode: .dropOnto))
    }

    func testWithinEscapeMarginStillResolves() {
        XCTAssertEqual(resolve(CGPoint(x: 320 + gridDropEscapeMargin - 1, y: 50),
                               source: "a", mode: .dropOnto),
                       GridDropTarget(placement: .onto(id: "c")))
    }

    // MARK: culled cells

    func testZeroRectCellsAreIgnored() {
        var partial = frames
        for i in 1..<6 { partial[i] = .zero }        // only "a" measured
        XCTAssertNil(resolveGridDropTarget(at: CGPoint(x: 400, y: 50), source: "f",
                                           ids: ids, frames: partial, mode: .dropOnto,
                                           validate: accept),
                     "zero rects must not stretch the abort boundary")
        XCTAssertEqual(resolveGridDropTarget(at: CGPoint(x: 120, y: 50), source: "f",
                                             ids: ids, frames: partial, mode: .dropOnto,
                                             validate: accept),
                       GridDropTarget(placement: .onto(id: "a")),
                       "an unmeasured neighbour must not steal a near-margin point")
    }

    func testAllZeroOrMismatchedFramesResolveNil() {
        XCTAssertNil(resolveGridDropTarget(at: CGPoint(x: 50, y: 50), source: "a", ids: ids,
                                           frames: Array(repeating: .zero, count: 6),
                                           mode: .dropOnto, validate: accept))
        XCTAssertNil(resolveGridDropTarget(at: CGPoint(x: 50, y: 50), source: "a", ids: ids,
                                           frames: [CGRect(x: 0, y: 0, width: 100, height: 100)],
                                           mode: .dropOnto, validate: accept))
    }

    // MARK: reorder slots

    func testReorderResolvesSlotByHalf() {
        XCTAssertEqual(resolve(CGPoint(x: 30, y: 50), source: "f", mode: .reorderAt),
                       GridDropTarget(placement: .at(index: 0)))
        XCTAssertEqual(resolve(CGPoint(x: 80, y: 50), source: "f", mode: .reorderAt),
                       GridDropTarget(placement: .at(index: 1)))
    }

    func testReorderNoMoveGapsResolveNil() {
        XCTAssertNil(resolve(CGPoint(x: 30, y: 50), source: "a", mode: .reorderAt),
                     "the slot before the source is the no-move gap")
        XCTAssertNil(resolve(CGPoint(x: 80, y: 50), source: "a", mode: .reorderAt),
                     "…and so is the slot after it")
    }

    func testReorderEndSlot() {
        XCTAssertEqual(resolve(CGPoint(x: 300, y: 150), source: "a", mode: .reorderAt),
                       GridDropTarget(placement: .at(index: 6)),
                       "the trailing half of the last cell aims at the end slot")
    }

    // MARK: .both fractions + fallback

    func testBothPicksByFraction() {
        XCTAssertEqual(resolve(CGPoint(x: 10, y: 50), source: "f", mode: .both),
                       GridDropTarget(placement: .at(index: 0)))
        XCTAssertEqual(resolve(CGPoint(x: 50, y: 50), source: "f", mode: .both),
                       GridDropTarget(placement: .onto(id: "a")))
        XCTAssertEqual(resolve(CGPoint(x: 90, y: 50), source: "f", mode: .both),
                       GridDropTarget(placement: .at(index: 1)))
    }

    func testBothFallsBackToSlotWhenOntoRejected() {
        let rejectOnto: (GridDragContext<String>, GridDropTarget<String>) -> Bool = { _, t in
            if case .onto = t.placement { return false }
            return true
        }
        XCTAssertEqual(resolve(CGPoint(x: 50, y: 50), source: "f", mode: .both, validate: rejectOnto),
                       GridDropTarget(placement: .at(index: 0)))
    }

    func testValidatorRejectingAllResolvesNil() {
        XCTAssertNil(resolve(CGPoint(x: 50, y: 50), source: "f", mode: .both,
                             validate: { _, _ in false }))
    }

    // MARK: candidates

    func testCandidatesOntoSkipSource() {
        let out = gridDragCandidates(source: "a", ids: ids, mode: .dropOnto, validate: accept)
        XCTAssertEqual(out.map(\.placement),
                       ["b", "c", "d", "e", "f"].map { GridDropPlacement.onto(id: $0) })
    }

    func testCandidatesReorderSkipNoMoveGapsAndCloseWithEndSlot() {
        let out = gridDragCandidates(source: "a", ids: ids, mode: .reorderAt, validate: accept)
        XCTAssertEqual(out.map(\.placement),
                       [2, 3, 4, 5, 6].map { GridDropPlacement<String>.at(index: $0) })
    }

    func testCandidatesConsultValidator() {
        var seen: [GridDropTarget<String>] = []
        let out = gridDragCandidates(source: "a", ids: ids, mode: .dropOnto) { ctx, t in
            XCTAssertEqual(ctx.sourceID, "a")
            seen.append(t)
            return t.placement != .onto(id: "c")
        }
        XCTAssertEqual(out.count, 4)
        XCTAssertFalse(out.contains { $0.placement == .onto(id: "c") })
        XCTAssertEqual(seen.count, 5, "every non-trivial candidate consults the validator")
    }

    func testCandidatesBothInterleaveSlotBeforeCell() {
        let out = gridDragCandidates(source: "f", ids: ids, mode: .both, validate: accept)
        XCTAssertEqual(Array(out.map(\.placement).prefix(4)),
                       [GridDropPlacement.at(index: 0), .onto(id: "a"),
                        .at(index: 1), .onto(id: "b")])
    }
}
