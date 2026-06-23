import XCTest
@testable import ListCore

private struct Opt { let id: String; let label: String }

final class ComboLogicTests: XCTestCase {
    let opts = [Opt(id: "1", label: "Apple"), Opt(id: "2", label: "Apricot"), Opt(id: "3", label: "Banana")]

    func testEmptyQueryKeepsAll() {
        XCTAssertEqual(comboFilter(opts, query: "", label: { $0.label }).count, 3)
    }
    func testContainsCaseInsensitive() {
        let r = comboFilter(opts, query: "ap", label: { $0.label })
        XCTAssertEqual(r.map { $0.id }, ["1", "2"])
    }
    func testReconcileKeepsIndexWhenInRange() {
        let r = reconcileSelection(selectedIndex: 2, committedValue: "Banana", labels: ["Apple", "Apricot", "Banana"])
        XCTAssertEqual(r.selectedIndex, 2); XCTAssertEqual(r.committedValue, "Banana")
    }
    func testReconcileRefindsByLabel() {
        let r = reconcileSelection(selectedIndex: nil, committedValue: "Banana", labels: ["Banana", "Apple"])
        XCTAssertEqual(r.selectedIndex, 0); XCTAssertEqual(r.committedValue, "Banana")
    }
    func testReconcileKeepsFreeSoloTarget() {
        let r = reconcileSelection(selectedIndex: nil, committedValue: "Cherry", labels: ["Apple"])
        XCTAssertNil(r.selectedIndex); XCTAssertEqual(r.committedValue, "Cherry")
    }
}
