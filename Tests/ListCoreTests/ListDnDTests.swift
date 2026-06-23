import XCTest
@testable import ListCore

final class ListDnDTests: XCTestCase {
    // 4 single rows a,b,c,d at 30pt each ⇒ yOffsets 0,30,60,90.
    let rows: [ListRow<String>] = ["a","b","c","d"].map { ListRow(id: $0) }
    let geom: [RowGeom] = (0..<4).map { RowGeom(yOffset: CGFloat($0)*30, height: 30) }
    let yes: (DragContext<String>, DropTarget<String>) -> Bool = { _,_ in true }

    func testBothZoneModel() {
        // source "a": top-quarter ⇒ between-before, middle ⇒ onto, bottom-quarter ⇒ between-after
        XCTAssertEqual(resolveDropTarget(atDocY: 62, source: "a", rows: rows, geom: geom,
                                         mode: .both, chunkIDs: [], validate: yes)?.placement,
                       .between(beforeID: "c"))
        XCTAssertEqual(resolveDropTarget(atDocY: 75, source: "a", rows: rows, geom: geom,
                                         mode: .both, chunkIDs: [], validate: yes)?.placement,
                       .onto(id: "c"))
        XCTAssertEqual(resolveDropTarget(atDocY: 88, source: "a", rows: rows, geom: geom,
                                         mode: .both, chunkIDs: [], validate: yes)?.placement,
                       .between(beforeID: "d"))
    }
    func testTrivialSelfDropRejected() {
        XCTAssertNil(resolveDropTarget(atDocY: 5, source: "a", rows: rows, geom: geom,
                                       mode: .both, chunkIDs: [], validate: yes), "onto self ⇒ nil")
    }
    func testOutOfBounds() {
        XCTAssertEqual(resolveDropTarget(atDocY: -5, source: "c", rows: rows, geom: geom,
                                         mode: .reorderBetween, chunkIDs: [], validate: yes)?.placement,
                       .between(beforeID: "a"))
        XCTAssertEqual(resolveDropTarget(atDocY: 999, source: "a", rows: rows, geom: geom,
                                         mode: .reorderBetween, chunkIDs: [], validate: yes)?.placement,
                       .between(beforeID: nil))
        XCTAssertNil(resolveDropTarget(atDocY: -5, source: "a", rows: rows, geom: geom,
                                       mode: .dropOnto, chunkIDs: [], validate: yes))
    }
    func testValidatorVeto() {
        let vetoB: (DragContext<String>, DropTarget<String>) -> Bool = { _, t in t.placement != .onto(id: "b") }
        XCTAssertNil(resolveDropTarget(atDocY: 45, source: "a", rows: rows, geom: geom,
                                       mode: .dropOnto, chunkIDs: [], validate: vetoB))
    }
    func testChunkGather() {
        let secRows: [ListRow<String>] = [
            ListRow(id: "A", kind: .sectionHeader()), ListRow(id: "a1"), ListRow(id: "a2"),
            ListRow(id: "B", kind: .sectionHeader()), ListRow(id: "b1"),
        ]
        XCTAssertEqual(chunkMemberIDs(forHeader: "A", rows: secRows), ["A", "a1", "a2"])
        XCTAssertEqual(chunkMemberIDs(forHeader: "a1", rows: secRows), [], "non-header ⇒ empty")
    }
    func testChunkAimsAtSectionGapsOnly() {
        let secRows: [ListRow<String>] = [
            ListRow(id: "A", kind: .sectionHeader()), ListRow(id: "a1"),
            ListRow(id: "B", kind: .sectionHeader()), ListRow(id: "b1"),
        ]
        let cands = dragCandidates(source: "A", rows: secRows, mode: .both,
                                   chunkIDs: ["A", "a1"], validate: yes).map(\.placement)
        XCTAssertEqual(cands, [.between(beforeID: "B"), .between(beforeID: nil)],
                       "a chunk lift aims at section gaps + the end gap only")
    }
}
