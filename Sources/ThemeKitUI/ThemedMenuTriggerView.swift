// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedMenu`. `ThemedMenu` is a
// CONTROLLER that owns a child window (like the combo / tooltip), so it can't be
// an embeddable NSView. This bridge IS the real `ThemedButton` trigger that opens
// the REAL `ThemedMenu` built from the caller's `items`; the Coordinator retains
// the controller. (The open menu floats on its own window — it won't appear in a
// screenshot of the host window.)

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedMenuTriggerView: NSViewRepresentable {
    let palette: ResolvedPalette
    var title: String
    var trailingSymbol: String?
    var items: [ThemedMenu.MenuItem]
    var presentation: ThemedMenu.Presentation

    public init(palette: ResolvedPalette, title: String = "Actions",
                trailingSymbol: String? = "caret-down",
                presentation: ThemedMenu.Presentation = .vertical,
                items: [ThemedMenu.MenuItem]) {
        self.palette = palette
        self.title = title
        self.trailingSymbol = trailingSymbol
        self.presentation = presentation
        self.items = items
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    // The trigger IS the button — no fixed-size host wrapper. SwiftUI sizes us via
    // `sizeThatFits` off the button's intrinsic content size (mirrors ThemedButtonView).
    public func makeNSView(context: Context) -> ThemedButton {
        let button = ThemedButton(palette: palette)
        button.variant = .outlined
        button.title = title
        button.trailingSymbol = trailingSymbol

        let menu = ThemedMenu.make(palette: palette, items: items)
        menu.presentation = presentation
        context.coordinator.menu = menu
        button.onTap = { [weak menu, weak button] in
            guard let menu, let button else { return }
            menu.present(from: button)
        }
        return button
    }

    public func updateNSView(_ button: ThemedButton, context: Context) {
        button.palette = palette
        button.title = title
        button.trailingSymbol = trailingSymbol
        context.coordinator.menu?.palette = palette
        context.coordinator.menu?.presentation = presentation   // swap layout before items rebuild
        context.coordinator.menu?.items = items   // caller-driven items rebuild (ThemedMenu.items didSet)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedButton,
                             context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    @MainActor public final class Coordinator {
        var menu: ThemedMenu?
    }
}
