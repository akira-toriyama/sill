// ThemeKitUI — ThemedMenuTriggerView: a themed trigger button that opens the
// REAL `ThemedMenu` built from the caller's `items`. SwiftUI-NATIVE: the
// trigger is `ThemedButtonView` and the CONTROLLER (which owns the floor-2
// `PopupPanel` child window — it can't be an embeddable NSView) anchors through
// the shared `PopupAnchorProxy` laid under the button, so the drop-down keeps
// its entire `present(from: NSView)` mechanism — placement below the trigger,
// the opening click's dismiss exemption, window-move/resize glue, scroll-out
// dismiss. (The open menu floats on its own window — it won't appear in a
// screenshot of the host window.)

import SwiftUI
import AppKit
import PaletteKit

public struct ThemedMenuTriggerView: View {
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var title: String
    var trailingSymbol: String?
    var items: [ThemedMenu.MenuItem]
    var presentation: ThemedMenu.Presentation

    /// The retained controller + its anchor, shared between the proxy (which
    /// creates both) and the button's tap (which presents). A class in `@State`
    /// so the SwiftUI value struct can be recreated freely while the menu — a
    /// stateful controller owning a panel + monitors — survives.
    @MainActor private final class MenuHolder {
        var menu: ThemedMenu?
        weak var anchor: NSView?
    }
    @State private var holder = MenuHolder()

    public init(palette: ResolvedPalette? = nil, title: String = "Actions",
                trailingSymbol: String? = "caret-down",
                presentation: ThemedMenu.Presentation = .vertical,
                items: [ThemedMenu.MenuItem]) {
        self.explicitPalette = palette
        self.title = title
        self.trailingSymbol = trailingSymbol
        self.presentation = presentation
        self.items = items
    }

    public var body: some View {
        ThemedButtonView(palette: palette, variant: .outlined, title: title,
                         trailing: trailingSymbol) { [holder] in
            guard let menu = holder.menu, let anchor = holder.anchor else { return }
            menu.present(from: anchor)
        }
        .background(PopupAnchorProxy<ThemedMenu>(
            attach: { [holder, palette, items, presentation] anchor in
                let menu = ThemedMenu.make(palette: palette, items: items)
                menu.presentation = presentation
                holder.menu = menu
                holder.anchor = anchor
                return menu
            },
            update: { [palette, items, presentation] menu in
                menu.palette = palette
                menu.presentation = presentation   // swap layout before items rebuild
                menu.items = items                 // caller-driven rebuild (ThemedMenu.items didSet)
            },
            detach: { $0.invalidate() }))
    }
}
