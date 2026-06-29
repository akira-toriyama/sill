// prism — ThemeKitUI thumbnail-grid bench (#17e). Shows the native `ThemedGridView`
// across states in every theme using DETERMINISTIC dummy thumbnails (solid colour
// swatches drawn into NSImage — ScreenCaptureKit is backstage, never used here).

import SwiftUI
import AppKit
import PaletteKit
import ThemeKitUI

struct MockThumbnailGrid: View {
    let p: ResolvedPalette

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ThemeKitUI · ThemedGridView — native themed thumbnail grid (#17e)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Vertical adaptive grid (default).
            ThemedThumbnailGridView(loadedItems + loadingItems,
                                    selection: .constant(["c0"]),   // show a selected cell
                                    layout: .adaptive(minCellWidth: 96),
                                    aspectRatio: 1, palette: p)
                .frame(height: 240)

            Text("horizontal rail strip · fixed-3 grid").font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Horizontal rail strip.
            ThemedThumbnailGridView(loadedItems,
                                    layout: .fixed(columns: 1),
                                    axis: .horizontal, aspectRatio: 1, palette: p)
                .frame(height: 110)
        }
    }
}
