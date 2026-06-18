// prism — ThemeKit Menu bench. `ThemedMenu` is a CONTROLLER that owns a child
// window (like the combo / tooltip), so the open menu can't appear in a
// `screencapture` of prism's main window. The per-theme grid therefore renders an
// INLINE MOCK of the open menu — a REAL `ThemedList` configured exactly as
// `ThemedMenu` hosts it (selectionMode .none · solidAccent highlight ·
// highlightFollowsHover · compact · separators), with `previewHighlight` forcing a
// lit row — so the menu's look reads across all themes deterministically. Beside it
// a LIVE trigger opens the REAL `ThemedMenu` (touch it: hover, ↑↓, Enter, Esc), the
// 演出 to feel even though the floating panel won't sit in a static shot.
//
// prism never imports an app's View: these are mock data shapes drawn by the real
// kit, mirroring `ThemedMenu`'s own MenuItem → ListItem mapping, so the bench can't
// drift from facet / wand.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit

// MARK: - Mock images (pre-resolved template glyphs — the kit parses no SF name)

@MainActor private func menuGlyph(_ name: String, _ pt: CGFloat = 15) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let out = base.withSymbolConfiguration(.init(pointSize: pt, weight: .regular)) ?? base
    out.isTemplate = true
    return out
}

// MARK: - Inline-mock rows (mirror ThemedMenu's MenuItem → ListItem mapping)

@MainActor private func menuRows() -> [ListItem] {
    [
        ListItem(id: "new",    image: menuGlyph("doc.badge.plus"), primary: "New Window",  trailing: .shortcut("⌘N")),
        ListItem(id: "open",   image: menuGlyph("folder"),         primary: "Open…",        trailing: .shortcut("⌘O")),
        ListItem(id: "recent", image: menuGlyph("clock"),          primary: "Open Recent",  trailing: .chevron),
        ListItem(id: "sep1",   primary: "", kind: .separator),
        ListItem(id: "side",   image: menuGlyph("checkmark"),      primary: "Show Sidebar", trailing: .shortcut("⌘\\")),
        ListItem(id: "sep2",   primary: "", kind: .separator),
        ListItem(id: "rename", image: menuGlyph("pencil"),         primary: "Rename"),
        ListItem(id: "del",    image: menuGlyph("trash"),          primary: "Delete", trailing: .shortcut("⌘⌫"), tint: .error),
        ListItem(id: "off",    image: menuGlyph("nosign"),         primary: "Unavailable", isDisabled: true),
    ]
}
// 7 rows @ 26 (compact) + 2 separators @ 7 = 196pt of content.
private let mockMenuContentHeight: CGFloat = 196

// MARK: - Live trigger: a button that opens the REAL ThemedMenu

struct MenuTriggerView: NSViewRepresentable {
    let palette: ResolvedPalette

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 150, height: 34))
        let button = ThemedButton(palette: palette)
        button.variant = .outlined
        button.title = "Actions"
        button.trailingSymbol = "chevron.down"
        button.frame = NSRect(x: 0, y: 0, width: 130, height: 34)
        host.addSubview(button)

        let menu = ThemedMenu.make(palette: palette, items: liveItems(context.coordinator))
        context.coordinator.menu = menu
        context.coordinator.button = button
        button.onTap = { [weak menu, weak button] in
            guard let menu, let button else { return }
            menu.present(from: button)
        }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.button?.palette = palette
        context.coordinator.menu?.palette = palette
    }

    private func liveItems(_ coord: Coordinator) -> [ThemedMenu.MenuItem] {
        [
            ThemedMenu.MenuItem("New Window", icon: menuGlyph("doc.badge.plus"), shortcut: "⌘N") {},
            ThemedMenu.MenuItem("Open…",      icon: menuGlyph("folder"),         shortcut: "⌘O") {},
            ThemedMenu.MenuItem(id: "recent", title: "Open Recent", icon: menuGlyph("clock"), submenu: [
                ThemedMenu.MenuItem("Project Alpha", icon: menuGlyph("doc")) {},
                ThemedMenu.MenuItem("Project Beta",  icon: menuGlyph("doc")) {},
                .separator(),
                ThemedMenu.MenuItem("Clear Menu", icon: menuGlyph("xmark.bin"), isDestructive: true) {},
            ]),
            .separator(),
            ThemedMenu.MenuItem(id: "side", title: "Show Sidebar", icon: menuGlyph("checkmark"),
                                shortcut: "⌘\\", isChecked: true),
            .separator(),
            ThemedMenu.MenuItem("Rename", icon: menuGlyph("pencil")) {},
            ThemedMenu.MenuItem("Delete", icon: menuGlyph("trash"), isDestructive: true) {},
            ThemedMenu.MenuItem("Unavailable", icon: menuGlyph("nosign"), isEnabled: false),
        ]
    }

    @MainActor final class Coordinator {
        var menu: ThemedMenu?
        weak var button: ThemedButton?
    }
}

// MARK: - Showcase

struct MockMenu: View {
    let p: ResolvedPalette

    private var surface: Color { Color(nsColor: p.background ?? .windowBackgroundColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · Menu — a floating action menu (child window). The card shows an INLINE MOCK of the open menu (a real ThemedList in menu config); the live trigger opens the REAL ThemedMenu (hover / ↑↓ / Enter / Esc). solidAccent highlight, ⌘-shortcuts, a checkmark item, separators, a destructive (error) row, a disabled row — and a one-level SUBMENU CASCADE: hover or → on \"Open Recent\" opens a child menu beside it (← / Esc closes it).")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 24) {
                cell("inline mock · the open menu") {
                    ListView(palette: p) { list in
                        list.items = menuRows()
                        list.selectionMode = .none
                        list.hoverStyle = .solidAccent
                        list.highlightFollowsHover = true
                        list.density = .compact
                        list.previewHighlight = "open"          // a lit row for capture
                    }
                    .frame(width: 232, height: mockMenuContentHeight)
                    .padding(.vertical, 4)                       // the menu's vertical breathing room
                    .background(surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
                }

                cell("live trigger · opens the real menu") {
                    MenuTriggerView(palette: p)
                        .frame(width: 150, height: 38)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
    }

    @ViewBuilder
    private func cell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }
}
