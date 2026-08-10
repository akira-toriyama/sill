// The viewport FOLLOWS the keyboard — the guard on the regression where the
// cursor and the keyboard-drag aim walked off the visible list and every later
// keypress acted on a row the user could not see.
//
// sill's own scroll lived inside `moveHighlight`, reachable only from the
// list's `.onKeyPress`. A host that drives the cursor from its own key monitor
// (facet swallows the arrows before `.onKeyPress` can run) moved `highlight`
// through the binding and nothing ever scrolled. Same for the keyboard lift:
// the aim renders through `preview.dropTarget`, and no aim change scrolled.
// The follow now hangs off `effectiveHighlight` / the drop-target anchor, so
// BOTH movers — internal keypress and host-driven state — take the same path.
//
// These cases host the real view and read which rows the viewport actually
// laid out (the row-rect preference — LazyVStack culls off-screen rows, so
// presence in the rect map IS visibility; measured in #175). Render facts,
// not logic: per CLAUDE.md, XCTest proves logic and not SwiftUI render, so
// asserting on the published rects is what makes these render tests.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
import ListCore
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedListScrollFollowTests: XCTestCase {

    /// Collects what `onRowRects` delivered — the laid-out (= visible) rows.
    private final class Sink {
        var last: [Int: CGRect] = [:]
    }

    private func rows(_ n: Int) -> [ListItem<Int>] {
        (0..<n).map { ListItem<Int>(id: $0, primary: "row \($0)") }
    }

    /// One list value with the given cursor / preview, wired to `sink`.
    private func list(highlight: Int? = nil,
                      preview: ListPreview<Int>? = nil,
                      sink: Sink) -> ThemedListView<Int> {
        ThemedListView<Int>(items: rows(60),
                            collapsed: .constant([]),
                            highlight: .constant(highlight),
                            style: ThemedListStyle(),
                            palette: pal,
                            onRowRects: { sink.last = $0 },
                            preview: preview)
    }

    /// Host `first`, then swap in `second` (how a host-driven state change
    /// arrives: a new view value through the binding), and return the laid-out
    /// row ids after each pass.
    private func visibleRows(first: ThemedListView<Int>,
                             second: ThemedListView<Int>,
                             sink: Sink) -> (before: Set<Int>, after: Set<Int>) {
        let h = NSHostingView(rootView: first)
        h.frame = NSRect(x: 0, y: 0, width: 340, height: 200)
        // Unlike the sibling render suites, this one hosts inside a real
        // (never-shown) window: a windowless `NSHostingView` applies a
        // `scrollTo` only during its INITIAL layout — post-appear scrolls are
        // silently dropped, which would pass-by-vacuity the pinned-preview
        // case and fail the two follow cases (measured via the CLT probe,
        // 2026-08-04).
        let win = NSWindow(contentRect: h.frame, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        win.contentView = h
        h.layoutSubtreeIfNeeded()
        _ = h.fittingSize
        h.layoutSubtreeIfNeeded()
        let before = Set(sink.last.keys)
        h.rootView = second
        // The follow lands on a scroll-geometry pass, not inside
        // `layoutSubtreeIfNeeded` like the preference did — pump briefly.
        for _ in 0..<10 {
            h.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let after = Set(sink.last.keys)
        return (before, after)
    }

    // MARK: - the regression itself

    func testHighlightChangeScrollsTheCursorIntoView() {
        let sink = Sink()
        let r = visibleRows(first: list(highlight: nil, sink: sink),
                            second: list(highlight: 40, sink: sink),
                            sink: sink)
        XCTAssertTrue(r.before.contains(0), "a 200pt viewport starts at the top")
        XCTAssertFalse(r.before.contains(40), "row 40 starts far below the fold")
        XCTAssertTrue(r.after.contains(40),
                      "moving the cursor to row 40 must scroll it into view — a "
                      + "host-driven highlight that never scrolls is the shipped regression")
    }

    func testDropTargetAimScrollsIntoView() {
        // The keyboard lift renders through the preview seam (facet's does), so
        // the aim's anchor row must pull the viewport the same way the cursor does.
        let sink = Sink()
        var aimed = ListPreview<Int>(dragSource: 1, dragChunk: [1])
        aimed.dropTarget = ListCore.DropTarget(placement: .between(beforeID: 40))
        let r = visibleRows(first: list(preview: ListPreview<Int>(dragSource: 1, dragChunk: [1]), sink: sink),
                            second: list(preview: aimed, sink: sink),
                            sink: sink)
        XCTAssertFalse(r.before.contains(40), "the aim's row starts below the fold")
        XCTAssertTrue(r.after.contains(40),
                      "aiming the drop at row 40 must scroll the aim into view — "
                      + "committing a keyboard drop blind is the shipped regression")
    }

    // MARK: - section headers are scroll targets too

    func testHeaderHighlightScrollsIntoView() {
        // facet's tree is ALL section headers (a workspace list with no
        // windows yet). A Section header is not a ForEach child — it renders
        // as the Section's pinned header content — so it is only resolvable
        // by `scrollTo(id:)` through its explicit `.id`. Losing that `.id`
        // is invisible to the Int-keyed cases above: an Int id collides with
        // the outer section ForEach's `\.offset` identity and follows BY
        // ACCIDENT (measured 2026-08-10 — the live facet tree, String-like
        // enum ids, never scrolled while every Int probe passed). Hence
        // String ids here.
        final class StrSink { var last: [String: CGRect] = [:] }
        let sink = StrSink()
        let headers: [ListItem<String>] = (0..<30).map {
            ListItem<String>(id: "h\($0)", primary: "workspace \($0)",
                             kind: .sectionHeader(subtitle: "bsp", collapsed: nil))
        }
        func list(highlight: String?) -> ThemedListView<String> {
            ThemedListView<String>(items: headers,
                                   collapsed: .constant([]),
                                   highlight: .constant(highlight),
                                   style: ThemedListStyle(),
                                   palette: pal,
                                   onRowRects: { sink.last = $0 })
        }
        let h = NSHostingView(rootView: list(highlight: nil))
        h.frame = NSRect(x: 0, y: 0, width: 340, height: 200)
        let win = NSWindow(contentRect: h.frame, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        win.contentView = h
        h.layoutSubtreeIfNeeded()
        _ = h.fittingSize
        h.layoutSubtreeIfNeeded()
        let before = Set(sink.last.keys)
        h.rootView = list(highlight: "h25")
        for _ in 0..<10 {
            h.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let after = Set(sink.last.keys)
        XCTAssertTrue(before.contains("h0"), "a 200pt viewport starts at the top")
        XCTAssertFalse(before.contains("h25"), "header 25 starts below the fold")
        XCTAssertTrue(after.contains("h25"),
                      "moving the cursor to a section header must scroll it into "
                      + "view — headers without scroll-target identity are the "
                      + "hole the live facet tree shipped into")
    }

    // MARK: - a pinned capture stays put

    func testPinnedPreviewOffsetBeatsTheFollow() {
        // prism freezes a scroll offset for deterministic captures; a cursor
        // change must not move a viewport the preview explicitly pinned.
        let sink = Sink()
        var pinned = ListPreview<Int>()
        pinned.scrollY = 0
        var moved = pinned
        moved.highlight = 40
        let r = visibleRows(first: list(preview: pinned, sink: sink),
                            second: list(preview: moved, sink: sink),
                            sink: sink)
        XCTAssertTrue(r.after.contains(0), "the pinned top-of-list offset holds")
        XCTAssertFalse(r.after.contains(40),
                       "a preview that pins scrollY owns the viewport — the "
                       + "follow must not reframe a deterministic capture")
    }
}
