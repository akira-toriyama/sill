// prism — ThemeKitUI thumbnail-grid bench (#17e). Shows the native `ThemedGridView`
// across states in every theme using DETERMINISTIC dummy thumbnails (solid colour
// swatches drawn into NSImage — ScreenCaptureKit is backstage, never used here).

import SwiftUI
import AppKit
import PaletteKit
import ThemeKitUI
import GridCore

struct MockThumbnailGrid: View {
    let p: ResolvedPalette

    // Live interaction state so the maintainer can verify the #17e interaction fixes
    // right here in prism: ⌘-click multi-select (the set grows) and double-click /
    // Return activation (the status line below updates).
    @State private var selection: Set<String> = ["c0"]
    @State private var lastActivated: String = "—"

    // Live DnD state (t-n3be): drag a cell onto another and the two swap — the
    // real pointer path (resolve → ring → ghost → commit), not a mock.
    @State private var dndOrder: [Int] = Array(0..<6)
    @State private var lastDrop: String = "—"

    private func swatch(_ nsColor: NSColor, _ size: CGFloat = 120) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        nsColor.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        img.unlockFocus()
        return img
    }

    private var loadedItems: [ThumbnailItem] {
        let roles: [(NSColor, String)] = [
            (p.primary, "primary"), (p.secondary, "secondary"), (p.muted, "muted"),
            (p.tertiary, "tertiary"), (p.border, "border"), (p.foreground, "fg"),
        ]
        return roles.enumerated().map { i, r in
            ThumbnailItem(id: "c\(i)", image: swatch(r.0), label: r.1)
        }
    }

    // A few cells with nil image to show the SwiftUI shimmer.
    private var loadingItems: [ThumbnailItem] {
        (0..<3).map { ThumbnailItem(id: "l\($0)", image: nil, label: "loading") }
    }

    // Opt-in interaction trace (off by default; run `PRISM_LOG=1 prism`), matching
    // prism's other PRISM_* env seams. Now that prism has a genuinely interactive
    // widget, this surfaces selection/activation to stdout for debugging.
    private func prismLog(_ msg: String) {
        if ProcessInfo.processInfo.environment["PRISM_LOG"] != nil {
            print("[ThemedGrid] \(msg)")
            fflush(stdout)   // stdout is block-buffered when redirected to a file
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ThemeKitUI · ThemedGridView — native themed thumbnail grid (#17e)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Interaction hint + live state — exercises the gesture/activation fixes.
            Text("click=replace · ⌘click=multi-select · double-click/Return=activate · arrows=move")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            Text("selected: \(selection.sorted().joined(separator: ", "))   ·   activated: \(lastActivated)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Color(nsColor: p.primary))

            // Vertical adaptive grid (default) — CONTROLLED selection + activation wired
            // live so ⌘-click multi-select and Return/double-click activation are visible.
            ThemedThumbnailGridView(loadedItems + loadingItems,
                                    selection: $selection,
                                    layout: .adaptive(minCellWidth: 96),
                                    aspectRatio: 1, palette: p,
                                    onActivate: { lastActivated = $0; prismLog("activated \($0)") })
                .frame(height: 240)
                .onChange(of: selection) { _, sel in prismLog("selected [\(sel.sorted().joined(separator: ", "))]") }

            Text("horizontal rail strip · fixed 1-row").font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Horizontal rail strip — uncontrolled; click a cell then arrow Left/Right
            // to drive the roving cursor (verifies the horizontal-axis nav fix).
            ThemedThumbnailGridView(loadedItems,
                                    layout: .fixed(columns: 1),
                                    axis: .horizontal, aspectRatio: 1, palette: p)
                .frame(height: 110)

            Text("frozen · hover c1 · cursor ring c2 · selected c0 · shimmer phase 0.5")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // The t-avbj freeze seam: every interactive chrome layer pinned, so a
            // static capture shows hover veil + cursor ring + a mid-cell shimmer
            // band deterministically (the grid had NO preview seam before, so
            // none of these states could appear in a bench shot).
            ThemedThumbnailGridView(loadedItems + loadingItems,
                                    selection: .constant(["c0"]),
                                    layout: .adaptive(minCellWidth: 96),
                                    aspectRatio: 1, palette: p)
                .preview(GridPreview(hovered: "c1", cursor: "c2"))
                .previewShimmerPhase(0.5)
                .frame(height: 240)

            Text("draggable · drag a cell onto another to SWAP · last drop: \(lastDrop)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Live pointer DnD (t-n3be) — the REAL path (resolve → target ring →
            // ghost → commit), not a hand-drawn mock (the t-avbj bench rule).
            ThemedThumbnailGridView(dndItems,
                                    layout: .fixed(columns: 3),
                                    aspectRatio: 1, palette: p)
                .draggable(.dropOnto)
                .onGridDrop { ctx, target in
                    guard case .onto(let over) = target.placement,
                          let si = dndItems.firstIndex(where: { $0.id == ctx.sourceID }),
                          let ti = dndItems.firstIndex(where: { $0.id == over }) else { return }
                    dndOrder.swapAt(si, ti)
                    lastDrop = "\(ctx.sourceID) ⇄ \(over)"
                    prismLog("drop \(ctx.sourceID) onto \(over)")
                }
                .frame(height: 240)

            Text("frozen · mid-drag pose — c0 lifted (dim + ghost) over c4 (target ring)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // The DnD freeze seam: source dim + parked ghost + target ring in one
            // deterministic static pose.
            ThemedThumbnailGridView(loadedItems,
                                    selection: .constant([]),
                                    layout: .fixed(columns: 3),
                                    aspectRatio: 1, palette: p)
                .draggable(.dropOnto)
                .preview(GridPreview(focused: false).dragging(source: "c0", over: "c4"))
                .frame(height: 160)

            Text("frozen · reorder pose — c1 lifted, insertion line at slot 3 (t-mej6 G2)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // The reorder freeze seam (t-mej6): the `.at` insertion line (2pt
            // primary + end caps — the list insertionLine's grid twin) in a
            // deterministic static pose. Also the live keyboard path: click a
            // cell, Space lifts, arrows aim, Return commits.
            ThemedThumbnailGridView(loadedItems,
                                    selection: .constant([]),
                                    layout: .fixed(columns: 3),
                                    aspectRatio: 1, palette: p)
                .draggable(.reorderAt)
                .preview(GridPreview(focused: false).dragging(source: "c1", at: 3))
                .frame(height: 160)

            Text("fitsViewport · 6 cells · 3 cols · 16:10 in a 150pt box — no scroll, rows shrink to fit (G1)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Fit-to-viewport (t-mej6 G1): the overlay-grid sizing rule — every
            // cell visible, height binds, aspect preserved, block centred.
            // Also exercises G4/G5 live: single click activates, arrows wrap.
            ThemedThumbnailGridView(loadedItems,
                                    selection: .constant([]),
                                    layout: .fixed(columns: 3),
                                    aspectRatio: 1.6, palette: p,
                                    onActivate: { lastActivated = $0; prismLog("fit activated \($0)") })
                .fitsViewport()
                .activatesOnClick()
                .wrapsCursor()
                .frame(height: 150)
        }
    }

    /// The live-DnD grid's items in their current (swap-mutated) order.
    private var dndItems: [ThumbnailItem] {
        let base = loadedItems
        return dndOrder.compactMap { base.indices.contains($0) ? base[$0] : nil }
    }
}
