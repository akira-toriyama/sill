// `ThemedListView` publishes per-row viewport rects for EVERY list — the guard
// on the regression that made facet's hover thumbnails impossible.
//
// `reportRowRect` used to be gated on `style.hosted`, so a standalone list got
// no rects at all. That looked like a hosted-popup implementation detail and was
// in fact load-bearing for anyone anchoring to a row: facet asks for rects to
// place its window previews, and could not turn the gate on without also losing
// its tap and hover gestures (`hosted` flips `StandaloneRowInteraction` off).
// The previews silently never appeared. Measured before the fix: hosted=false
// delivered 0 rects, hosted=true delivered 6.
//
// These cases host the real view and read what the preference actually carried,
// per CLAUDE.md's standing warning that XCTest proves logic and not SwiftUI
// render. `onPreferenceChange` turned out to fire inside a plain
// `layoutSubtreeIfNeeded`, so the PaletteEnvironmentTests hosting idiom is
// enough — no run loop needed (measured 2026-08-03).
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedListRowRectTests: XCTestCase {

    /// Collects what `onRowRects` delivered. A class so the escaping callback
    /// has somewhere to write that outlives the view value.
    private final class Sink {
        var calls = 0
        var last: [Int: CGRect] = [:]
    }

    private func rows(_ n: Int) -> [ListItem<Int>] {
        (0..<n).map { ListItem<Int>(id: $0, primary: "row \($0)") }
    }

    /// Host the list and return whatever the row-rect preference carried.
    /// Mirrors `PaletteEnvironmentTests.host` — layout, fitting size, layout.
    private func rects(hosted: Bool,
                       items: [ListItem<Int>],
                       collapsed: Set<Int> = []) -> Sink {
        let sink = Sink()
        var style = ThemedListStyle()
        style.hosted = hosted
        let view = ThemedListView<Int>(items: items,
                                       collapsed: .constant(collapsed),
                                       style: style,
                                       palette: pal,
                                       onRowRects: { r in sink.calls += 1; sink.last = r })
        let h = NSHostingView(rootView: view)
        h.frame = NSRect(x: 0, y: 0, width: 340, height: 420)
        h.layoutSubtreeIfNeeded()
        _ = h.fittingSize
        h.layoutSubtreeIfNeeded()
        return sink
    }

    // MARK: - the regression itself

    func testStandaloneListPublishesARectForEveryRow() {
        let sink = rects(hosted: false, items: rows(6))
        XCTAssertEqual(sink.last.count, 6,
                       "a standalone list must publish row rects — this is what facet's "
                       + "hover previews anchor to; 0 here is the shipped regression")
        XCTAssertEqual(Set(sink.last.keys), Set(0..<6), "…keyed by the caller's ids")
    }

    func testHostedAndStandaloneAgreeOnTheRects() {
        // `hosted` decides who drives click/hover. It must not decide whether
        // geometry exists — that coupling is exactly what broke.
        let standalone = rects(hosted: false, items: rows(6)).last
        let hosted = rects(hosted: true, items: rows(6)).last
        XCTAssertEqual(standalone.count, hosted.count, "same row count either way")
        for (id, r) in hosted {
            guard let s = standalone[id] else {
                return XCTFail("standalone dropped row \(id)")
            }
            XCTAssertEqual(s.origin.y, r.origin.y, accuracy: 0.5, "row \(id) origin")
            XCTAssertEqual(s.height, r.height, accuracy: 0.5, "row \(id) height")
        }
    }

    // MARK: - the rects are usable, not merely present

    func testRectsStackInRowOrderWithoutGaps() {
        // A caller anchors a popover to `rect.maxY`, so ordering and adjacency
        // are the properties that matter — present-but-garbage would pass a
        // bare count assertion.
        let sink = rects(hosted: false, items: rows(6))
        let ordered = sink.last.sorted { $0.key < $1.key }.map(\.value)
        let rowH = ListMetrics.forDensity(.comfortable).singleRow
        for (i, r) in ordered.enumerated() {
            XCTAssertEqual(r.height, rowH, accuracy: 0.5, "row \(i) is one metric row tall")
            XCTAssertEqual(r.origin.y, CGFloat(i) * rowH, accuracy: 0.5,
                           "row \(i) sits directly below row \(i - 1)")
        }
    }

    func testCollapsedSectionBodyIsNotReported() {
        // Scrolled-off / hidden rows must not appear, or a hit-test resolves a
        // point to a row the user cannot see.
        let items: [ListItem<Int>] = [
            ListItem(id: 0, primary: "section", kind: .sectionHeader(subtitle: nil, collapsed: true)),
            ListItem(id: 1, primary: "child a"),
            ListItem(id: 2, primary: "child b"),
        ]
        let sink = rects(hosted: false, items: items, collapsed: [0])
        XCTAssertNotNil(sink.last[0], "the header itself stays visible")
        XCTAssertNil(sink.last[1], "a collapsed section's body is not laid out")
        XCTAssertNil(sink.last[2], "…for any of its children")
    }
}
