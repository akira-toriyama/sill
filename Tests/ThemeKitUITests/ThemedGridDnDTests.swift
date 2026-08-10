// ThemedGridView DnD (t-n3be) — two claims, each tested the way it can fail:
//
// 1. PLUMBING: the view's one resolution path (`pointerDropTarget`, the same
//    package seam the drag gesture calls) gates on `draggable(_:)` and routes
//    the stored `dropTargetValidator` into GridCore — the t-6r5m pattern.
// 2. RENDER: the frozen DnD pose actually DRAWS (t-avbj's rule — a state a
//    bench can't freeze regresses invisibly): `dragging(source:)` dims the
//    lifted cell + parks the ghost, `over:` strokes the target ring in the
//    primary role, and captures are deterministic.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
import GridCore
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedGridDnDTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)
    private let width: CGFloat = 320
    private let height: CGFloat = 240

    private let items = (0..<6).map { ThumbnailItem(id: "c\($0)", image: nil, label: "cell \($0)") }

    // Same 3×2 synthetic geometry as GridDnDTests, in ids order c0…c5.
    private var frames: [CGRect] {
        (0..<6).map { CGRect(x: CGFloat($0 % 3) * 110, y: CGFloat($0 / 3) * 110,
                             width: 100, height: 100) }
    }

    private func grid(validator: ((GridDragContext<String>, GridDropTarget<String>) -> Bool)? = nil,
                      draggable: Bool = true) -> ThemedGridView<[ThumbnailItem], String, Color> {
        var g = ThemedGridView(items, id: \.id, layout: .fixed(columns: 3),
                               palette: theme) { _, _ in Color.clear }
        if draggable { g = g.draggable(.dropOnto) }
        if let validator { g = g.dropTargetValidator(validator) }
        return g
    }

    // MARK: plumbing (the gesture's resolution path, minus the gesture)

    func testResolutionGatesOnDraggable() {
        XCTAssertNil(grid(draggable: false)
                        .pointerDropTarget(at: CGPoint(x: 50, y: 50), source: "c5", frames: frames),
                     "without draggable(_:) the grid must resolve nothing")
        XCTAssertEqual(grid()
                        .pointerDropTarget(at: CGPoint(x: 50, y: 50), source: "c5", frames: frames),
                       GridDropTarget(placement: .onto(id: "c0")))
    }

    func testValidatorGatesResolution() {
        XCTAssertNil(grid(validator: { _, _ in false })
                        .pointerDropTarget(at: CGPoint(x: 50, y: 50), source: "c5", frames: frames),
                     "a rejecting validator must leave the pointer with no target")
    }

    func testCopyMethodLeavesOriginalAccepting() {
        let original = grid()
        let rejecting = original.dropTargetValidator { _, _ in false }
        XCTAssertNil(rejecting.pointerDropTarget(at: CGPoint(x: 50, y: 50), source: "c5", frames: frames))
        XCTAssertNotNil(original.pointerDropTarget(at: CGPoint(x: 50, y: 50), source: "c5", frames: frames),
                        "dropTargetValidator(_:) must return a copy, not mutate the receiver")
    }

    // MARK: render (freeze seams — raster harness shared with FreezeSeamRenderTests)

    private func raster<V: View>(_ view: V) -> (px: [UInt8], w: Int, h: Int) {
        let host = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap rep"); return ([], 0, 0)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let img = rep.cgImage else { XCTFail("no image"); return ([], 0, 0) }
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: img.width, height: img.height,
                                bitsPerComponent: 8, bytesPerRow: img.width * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
        return (buf, img.width, img.height)
    }

    private func diff(_ a: (px: [UInt8], w: Int, h: Int), _ b: (px: [UInt8], w: Int, h: Int),
                      matches color: NSColor? = nil, tol: Int = 40) -> (count: Int, hitsColor: Bool) {
        var cr = 0, cg = 0, cb = 0
        if let c = color?.usingColorSpace(.sRGB) {
            cr = Int(c.redComponent * 255); cg = Int(c.greenComponent * 255); cb = Int(c.blueComponent * 255)
        }
        var n = 0, hit = false
        for i in stride(from: 0, to: min(a.px.count, b.px.count), by: 4) {
            guard a.px[i] != b.px[i] || a.px[i+1] != b.px[i+1]
                || a.px[i+2] != b.px[i+2] || a.px[i+3] != b.px[i+3] else { continue }
            n += 1
            if color != nil, abs(Int(a.px[i]) - cr) <= tol && abs(Int(a.px[i+1]) - cg) <= tol
                && abs(Int(a.px[i+2]) - cb) <= tol { hit = true }
        }
        return (n, hit)
    }

    private func frozen(_ preview: GridPreview<String>) -> some View {
        ThemedThumbnailGridView(items, selection: .constant([]),
                                layout: .fixed(columns: 3), aspectRatio: 1, palette: theme)
            .previewShimmerPhase(0.5)
            .draggable(.dropOnto)
            .preview(preview)
    }

    func testFrozenLiftDrawsDimAndGhost() {
        let d = diff(raster(frozen(GridPreview(focused: false).dragging(source: "c0"))),
                     raster(frozen(GridPreview(focused: false))))
        XCTAssertGreaterThan(d.count, 0,
                             "dragging(source:) must dim the lifted cell and park the ghost — "
                             + "the drag pose a live-only @State kept out of every bench shot")
    }

    func testFrozenDropTargetStrokesPrimaryRing() {
        let d = diff(raster(frozen(GridPreview(focused: false).dragging(source: "c0", over: "c4"))),
                     raster(frozen(GridPreview(focused: false).dragging(source: "c0"))),
                     matches: theme.primary)
        XCTAssertGreaterThan(d.count, 0, "dragging(over:) must draw the target ring")
        XCTAssertTrue(d.hitsColor, "the target ring strokes in the primary role")
    }

    func testFrozenDragPoseIsDeterministic() {
        let pose = GridPreview<String>(focused: false).dragging(source: "c0", over: "c4")
        XCTAssertEqual(raster(frozen(pose)).px, raster(frozen(pose)).px,
                       "two captures of the same frozen drag pose must be byte-identical")
    }
}
