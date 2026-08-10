// The dropTargetValidator seam (t-6r5m): a host's pre-validation must gate
// BOTH resolution paths — the pointer's per-move resolve and the keyboard
// lift's aim list. These cases call the package seams the production drag
// gesture / keyboard lift use verbatim, so the validator wired here is the
// validator the live paths consult. ListCore's own resolution semantics
// (self-drop, chunk interior, separators) are covered in ListDnDTests —
// here we prove the VIEW routes its stored closure into them.
import XCTest
import SwiftUI
import ListCore
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedListDropValidatorTests: XCTestCase {

    private func plainRows(_ n: Int) -> [ListItem<Int>] {
        (0..<n).map { ListItem<Int>(id: $0, primary: "row \($0)") }
    }

    /// Two sections: header 0 with rows 1–2, header 3 with rows 4–5.
    private func sectionedRows() -> [ListItem<Int>] {
        [ListItem<Int>(id: 0, primary: "A", kind: .sectionHeader()),
         ListItem<Int>(id: 1, primary: "a1"),
         ListItem<Int>(id: 2, primary: "a2"),
         ListItem<Int>(id: 3, primary: "B", kind: .sectionHeader()),
         ListItem<Int>(id: 4, primary: "b1"),
         ListItem<Int>(id: 5, primary: "b2")]
    }

    private func list(_ items: [ListItem<Int>],
                      validator: ((ListCore.DragContext<Int>, ListCore.DropTarget<Int>) -> Bool)? = nil)
        -> ThemedListView<Int> {
        var style = ThemedListStyle()
        style.draggable = true
        let v = ThemedListView<Int>(items: items, style: style, palette: pal)
        guard let validator else { return v }
        return v.dropTargetValidator(validator)
    }

    private func uniformGeom(_ n: Int, height: CGFloat = 24) -> [RowGeom] {
        (0..<n).map { RowGeom(yOffset: CGFloat($0) * height, height: height) }
    }

    // MARK: pointer path

    func testDefaultAcceptsPointerTarget() {
        let v = list(plainRows(8))
        let target = v.pointerDropTarget(atDocY: 12, source: 5, chunkIDs: [], geom: uniformGeom(8))
        XCTAssertEqual(target, DropTarget(placement: .onto(id: 0)),
                       "mid-row docY under .both must resolve onto row 0 when nothing rejects")
    }

    func testPointerFallsBackToBetweenWhenOntoRejected() {
        let v = list(plainRows(8)) { _, target in
            if case .onto = target.placement { return false }
            return true
        }
        let target = v.pointerDropTarget(atDocY: 12, source: 5, chunkIDs: [], geom: uniformGeom(8))
        XCTAssertEqual(target, DropTarget(placement: .between(beforeID: 0)),
                       "a rejected onto must fall through to ListCore's between fallback")
    }

    func testPointerResolvesNilWhenAllRejected() {
        let v = list(plainRows(8)) { _, _ in false }
        XCTAssertNil(v.pointerDropTarget(atDocY: 12, source: 5, chunkIDs: [], geom: uniformGeom(8)),
                     "a validator rejecting everything must leave the pointer with no target")
    }

    // MARK: keyboard path

    func testKeyboardAimEmptyWhenAllRejected() {
        let all = list(plainRows(8))
        XCTAssertFalse(all.kbDragAim(from: 5, chunkIDs: []).isEmpty)
        let none = list(plainRows(8)) { _, _ in false }
        XCTAssertTrue(none.kbDragAim(from: 5, chunkIDs: []).isEmpty,
                      "a validator rejecting everything must empty the keyboard aim")
    }

    func testValidatorSeesChunkMembersOnHeaderLift() {
        var seen: Set<[Int]> = []
        let v = list(sectionedRows()) { ctx, _ in
            seen.insert(ctx.memberIDs)
            return true
        }
        let chunk = v.kbChunk(for: 0)
        XCTAssertEqual(chunk, [0, 1, 2], "a header lift must carry the header + its rows")
        let aim = v.kbDragAim(from: 0, chunkIDs: chunk)
        XCTAssertFalse(aim.isEmpty)
        XCTAssertEqual(seen, [[0, 1, 2]],
                       "every consultation for a chunk lift must present the full member list")
    }

    // MARK: value semantics

    func testCopyMethodLeavesOriginalAccepting() {
        let original = list(plainRows(8))
        let rejecting = original.dropTargetValidator { _, _ in false }
        XCTAssertNil(rejecting.pointerDropTarget(atDocY: 12, source: 5, chunkIDs: [], geom: uniformGeom(8)))
        XCTAssertNotNil(original.pointerDropTarget(atDocY: 12, source: 5, chunkIDs: [], geom: uniformGeom(8)),
                        "dropTargetValidator(_:) must return a copy, not mutate the receiver")
    }
}
