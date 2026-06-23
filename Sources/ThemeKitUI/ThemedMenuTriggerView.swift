// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedMenu`. `ThemedMenu` is a
// CONTROLLER that owns a child window (like the combo / tooltip), so it can't be
// an embeddable NSView. This bridge hosts a real `ThemedButton` trigger that
// opens the REAL `ThemedMenu` built from the caller's `items`; the Coordinator
// retains the controller. (The open menu floats on its own window — it won't
// appear in a screenshot of the host window.)

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedMenuTriggerView: NSViewRepresentable {
    let palette: ResolvedPalette
    var title: String
    var trailingSymbol: String?
    var items: [ThemedMenu.MenuItem]

    public init(palette: ResolvedPalette, title: String = "Actions",
                trailingSymbol: String? = "caret-down",
                items: [ThemedMenu.MenuItem]) {
        self.palette = palette
        self.title = title
        self.trailingSymbol = trailingSymbol
        self.items = items
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 34))
        let button = ThemedButton(palette: palette)
        button.variant = .outlined
        button.title = title
        button.trailingSymbol = trailingSymbol
        button.frame = NSRect(x: 0, y: 0, width: 130, height: 34)
        host.addSubview(button)

        let menu = ThemedMenu.make(palette: palette, items: items)
        context.coordinator.menu = menu
        context.coordinator.button = button
        button.onTap = { [weak menu, weak button] in
            guard let menu, let button else { return }
            menu.present(from: button)
        }
        return host
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.button?.palette = palette
        context.coordinator.button?.title = title
        context.coordinator.button?.trailingSymbol = trailingSymbol
        context.coordinator.menu?.palette = palette
        context.coordinator.menu?.items = items   // caller-driven items rebuild (ThemedMenu.items didSet)
    }

    @MainActor public final class Coordinator {
        var menu: ThemedMenu?
        weak var button: ThemedButton?
    }
}
