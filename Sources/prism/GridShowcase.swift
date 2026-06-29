// prism — ThemeKitUI thumbnail-grid bench (#17e). Shows the native `ThemedGridView`
// across states in every theme using DETERMINISTIC dummy thumbnails (solid colour
// swatches drawn into NSImage — ScreenCaptureKit is backstage, never used here).

import SwiftUI
import AppKit
import PaletteKit
import ThemeKitUI

struct MockThumbnailGrid: View {
    let p: ResolvedPalette

    // Live interaction state so the maintainer can verify the #17e interaction fixes
    // right here in prism: ⌘-click multi-select (the set grows) and double-click /
    // Return activation (the status line below updates).
    @State private var selection: Set<String> = ["c0"]
    @State private var lastActivated: String = "—"

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
                .onChange(of: selection) { prismLog("selected [\($0.sorted().joined(separator: ", "))]") }

            Text("horizontal rail strip · fixed 1-row").font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Horizontal rail strip — uncontrolled; click a cell then arrow Left/Right
            // to drive the roving cursor (verifies the horizontal-axis nav fix).
            ThemedThumbnailGridView(loadedItems,
                                    layout: .fixed(columns: 1),
                                    axis: .horizontal, aspectRatio: 1, palette: p)
                .frame(height: 110)
        }
    }
}
