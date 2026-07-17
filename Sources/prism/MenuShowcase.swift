// prism — ThemeKitUI Menu bench. `ThemedMenu` is a CONTROLLER that owns a child
// window (like the combo / tooltip), so the open menu can't appear in a
// `screencapture` of prism's main window. The per-theme grid therefore renders an
// INLINE MOCK of the open menu — a REAL `ThemedListView` configured exactly as
// `ThemedMenu` hosts it (selectionMode .none · solidAccent highlight ·
// highlightFollowsHover · compact · separators), with `preview` forcing a
// lit row — so the menu's look reads across all themes deterministically. Beside it
// a LIVE trigger opens the REAL `ThemedMenu` (touch it: hover, ↑↓, Enter, Esc), the
// 演出 to feel even though the floating panel won't sit in a static shot.
//
// prism never imports an app's View: these are mock data shapes drawn by the real
// kit, mirroring `ThemedMenu`'s own MenuItem → ThemeKitUI.ListItem mapping, so the bench can't
// drift from facet / wand.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - Mock images (pre-resolved template glyphs — the kit parses no SF name)

@MainActor private func menuGlyph(_ name: String, _ pt: CGFloat = 15) -> NSImage? {
    phosphorImage(name, pt: pt)   // a Phosphor slug → template NSImage
}

/// Build a `ThemedListStyle` inline (the kit's config value type is assign-based).
private func makeStyle(_ configure: (inout ThemedListStyle) -> Void) -> ThemedListStyle {
    var s = ThemedListStyle(); configure(&s); return s
}

// MARK: - Inline-mock rows (mirror ThemedMenu's MenuItem → ThemeKitUI.ListItem mapping)

@MainActor private func menuRows() -> [ThemeKitUI.ListItem<String>] {
    [
        ThemeKitUI.ListItem(id: "new",    image: menuGlyph("file-plus"), primary: "New Window",  trailing: .shortcut("⌘N")),
        ThemeKitUI.ListItem(id: "open",   image: menuGlyph("folder"),         primary: "Open…",        trailing: .shortcut("⌘O")),
        ThemeKitUI.ListItem(id: "recent", image: menuGlyph("clock"),          primary: "Open Recent",  trailing: .chevron),
        ThemeKitUI.ListItem(id: "sep1",   primary: "", kind: .separator),
        ThemeKitUI.ListItem(id: "side",   image: menuGlyph("check"),      primary: "Show Sidebar", trailing: .shortcut("⌘\\")),
        ThemeKitUI.ListItem(id: "sep2",   primary: "", kind: .separator),
        ThemeKitUI.ListItem(id: "rename", image: menuGlyph("pencil"),         primary: "Rename"),
        ThemeKitUI.ListItem(id: "del",    image: menuGlyph("trash"),          primary: "Delete", trailing: .shortcut("⌘⌫"), tint: .error),
        ThemeKitUI.ListItem(id: "off",    image: menuGlyph("prohibit"),         primary: "Unavailable", isDisabled: true),
    ]
}
// 7 rows @ 26 (compact) + 2 separators @ 7 = 196pt of content.
private let mockMenuContentHeight: CGFloat = 196

// MARK: - Live-trigger menu items (the demo action menu the live trigger opens)

/// The `ThemedMenu.MenuItem` tree the live `ThemedMenuTriggerView` (ThemeKitUI)
/// opens. Now that the trigger bridge is a GENERAL sill component (it takes its
/// items from the caller), prism owns the demo content here.
@MainActor private func menuTriggerItems() -> [ThemedMenu.MenuItem] {
    [
        ThemedMenu.MenuItem("New Window", icon: menuGlyph("file-plus"), shortcut: "⌘N") {},
        ThemedMenu.MenuItem("Open…",      icon: menuGlyph("folder"),         shortcut: "⌘O") {},
        ThemedMenu.MenuItem(id: "recent", title: "Open Recent", icon: menuGlyph("clock"), submenu: [
            ThemedMenu.MenuItem("Project Alpha", icon: menuGlyph("file")) {},
            ThemedMenu.MenuItem("Project Beta",  icon: menuGlyph("file")) {},
            .separator(),
            ThemedMenu.MenuItem("Clear Menu", icon: menuGlyph("trash"), isDestructive: true) {},
        ]),
        // A DEFERRED folder — children supplied async on open (Loading… → filled),
        // showcasing MenuItem.submenuProvider independent of wand.
        ThemedMenu.MenuItem(id: "insert", title: "Insert Snippet", icon: menuGlyph("code"),
                            submenuProvider: {
            try? await Task.sleep(for: .milliseconds(300))
            return [
                ThemedMenu.MenuItem("Header", icon: menuGlyph("file")) {},
                ThemedMenu.MenuItem("Footer", icon: menuGlyph("file")) {},
            ]
        }),
        .separator(),
        ThemedMenu.MenuItem(id: "side", title: "Show Sidebar", icon: menuGlyph("check"),
                            shortcut: "⌘\\", isChecked: true),
        .separator(),
        ThemedMenu.MenuItem("Rename", icon: menuGlyph("pencil")) {},
        ThemedMenu.MenuItem("Delete", icon: menuGlyph("trash"), isDestructive: true) {},
        ThemedMenu.MenuItem("Unavailable", icon: menuGlyph("prohibit"), isEnabled: false),
    ]
}

// MARK: - Showcase

struct MockMenu: View, ShowcaseBench {
    var cellSpacing: CGFloat { 6 }
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
                    ThemedListView(items: menuRows(),
                                   style: makeStyle { $0.selectionMode = .none; $0.hoverStyle = .solidAccent; $0.highlightFollowsHover = true; $0.density = .compact },
                                   palette: p,
                                   preview: ListPreview(highlight: "open"))
                    .frame(width: 232, height: mockMenuContentHeight)
                    .padding(.vertical, 4)                       // the menu's vertical breathing room
                    .background(surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
                }

                cell("live trigger · opens the real menu") {
                    ThemedMenuTriggerView(palette: p, items: menuTriggerItems())
                        .fixedSize()   // intrinsic-content sized — no fixed frame
                }
                Spacer(minLength: 0)
            }
        }
        .showcasePanel(p)
    }
}
