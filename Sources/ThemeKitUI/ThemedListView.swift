// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedList`. Unlike the
// ComboBox / Tooltip popups (own child windows), `ThemedList` is a plain
// embeddable NSView, so the REAL widget bridges straight into SwiftUI. The host
// supplies a `configure` closure (items + preview seams), applied ONCE on the
// first update after SwiftUI has sized the view (the previewScrollY/Highlight
// seams need bounds); subsequent frames only re-theme, so an animatable theme
// cycling at 30 Hz doesn't trigger a full item reload + NSImage re-raster.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedListView: NSViewRepresentable {
    let palette: ResolvedPalette
    let configure: (ThemedList) -> Void

    public init(palette: ResolvedPalette, configure: @escaping (ThemedList) -> Void) {
        self.palette = palette
        self.configure = configure
    }

    public final class Coordinator { var configured = false }
    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> ThemedList {
        ThemedList(palette: palette)
    }

    public func updateNSView(_ list: ThemedList, context: Context) {
        list.palette = palette                  // re-tint every frame (cheap snap-recolour)
        if !context.coordinator.configured {
            configure(list)                     // items + preview seams: once, post-sizing
            context.coordinator.configured = true
        }
    }
}
