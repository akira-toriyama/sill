// t-1y9q regression: `RowPointer.body` must stay branch-free. The original
// `@ViewBuilder switch` over `kind` made each pointer shape a distinct
// `_ConditionalContent` branch, so the first drag tick (`dragState` set →
// the container call-site's kind flips nil → `.grab`) re-identified the whole
// wrapped subtree — destroying the row that owned the in-flight `DragGesture`,
// whose `.onEnded` (the only pointer-path `dragState = nil`) then never fired:
// the lift stayed grabbed forever, closed hand held, release a no-op.
//
// A live pointer can't be driven from XCTest, so these cases pin the fix at
// the mechanism level instead: descendant `@StateObject` state must survive
// every `kind` transition `RowPointer` can make mid-drag. The offscreen-window
// harness mirrors the probe that measured the failure (branch flip → child
// re-initialised; unconditional `pointerStyle` → preserved) on macOS 26 /
// Swift 6.3.3.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import ThemeKitUI

/// Counts descendant (re)creations — a `@StateObject` is re-initialised iff
/// SwiftUI tears the child down, i.e. iff structural identity changed.
private final class IdentityProbe: ObservableObject {
    nonisolated(unsafe) static var creations = 0
    init() { IdentityProbe.creations += 1 }
}

private struct ProbeChild: View {
    @StateObject private var probe = IdentityProbe()
    var body: some View { Text("child").frame(width: 100, height: 20) }
}

/// The container call-site's shape: `RowPointer` wrapping a ScrollView of
/// lazily-built rows (`ThemedListView.swift` applies it to exactly this).
private struct ProbeHost: View {
    let kind: ListPointerAffordance?
    var body: some View {
        ScrollView { LazyVStack { ProbeChild() } }
            .modifier(RowPointer(kind: kind))
            .frame(width: 200, height: 100)
    }
}

@MainActor
final class RowPointerIdentityTests: XCTestCase {

    /// Mount `from`, let it settle, then update the root to `to` (the same
    /// diffable position — how every `dragState` change reaches the modifier)
    /// and report how many times the descendant was created in total.
    private func creations(flipping from: ListPointerAffordance?,
                           to: ListPointerAffordance?) -> Int {
        IdentityProbe.creations = 0
        let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 200, height: 100),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        defer { win.orderOut(nil) }
        let host = NSHostingView(rootView: ProbeHost(kind: from))
        win.contentView = host
        win.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.rootView = ProbeHost(kind: to)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return IdentityProbe.creations
    }

    func testDragStartFlipPreservesDescendants() {
        // nil → .grab: the container twin's exact transition on the first
        // pointer-drag tick — the one that stranded the lift.
        XCTAssertEqual(creations(flipping: nil, to: .grab), 1,
                       "kind nil → .grab re-identified the subtree — the in-flight DragGesture dies (t-1y9q)")
    }

    func testHoverToDragFlipPreservesDescendants() {
        // .link → .grab: every row's per-row transition at drag start.
        XCTAssertEqual(creations(flipping: .link, to: .grab), 1,
                       "kind .link → .grab re-identified the subtree — all visible rows rebuilt on lift")
    }

    func testDropFlipPreservesDescendants() {
        // .grab → nil: the drop/release transition back to rest.
        XCTAssertEqual(creations(flipping: .grab, to: nil), 1,
                       "kind .grab → nil re-identified the subtree — all visible rows rebuilt on drop")
    }

    func testHarnessActuallyBuildsTheChild() {
        // Guard against a vacuous pass: an unmounted LazyVStack would report 0
        // creations and every equality above would "fail correctly" — but if
        // the harness ever stopped materialising children, assert it here with
        // a message that says so rather than three misleading identity fails.
        XCTAssertGreaterThanOrEqual(creations(flipping: nil, to: nil), 1,
                                    "offscreen harness no longer materialises the LazyVStack child")
    }
}
