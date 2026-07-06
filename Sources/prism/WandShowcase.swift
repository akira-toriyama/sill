// prism — wand launcher-tome bench. wand's launcher is a bespoke cascading panel
// tree (app-side); this mock rebuilds its DEFAULT `.list` tome from the REAL sill
// kit: a `ThemedTextFieldView` query field + inline `ThemedListView`s (mirroring
// `ThemedMenu`'s item→row mapping) for a static, deterministic 2-level cascade
// still, plus a `ThemedMenuTriggerView` live trigger that opens the REAL N-level
// `ThemedMenu` (the floating panels can't sit in a screenshot). prism never imports
// wand's View — these are mock shapes drawn by the real kit (zero drift).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import ThemeKitUI

@MainActor private func wandGlyph(_ name: String, _ pt: CGFloat = 15) -> NSImage? {
    phosphorImage(name, pt: pt)                    // a Phosphor slug → template NSImage
}

/// Build a `ThemedListStyle` inline (the kit's config value type is assign-based).
private func makeStyle(_ configure: (inout ThemedListStyle) -> Void) -> ThemedListStyle {
    var s = ThemedListStyle(); configure(&s); return s
}

// The tome's command rows (mirror ThemedMenu's MenuItem→ThemeKitUI.ListItem mapping). The
// "Switch Branch" folder row is pre-lit (previewHighlight) as if hovered; its
// children render in the offset child list to depict an OPEN cascade.
@MainActor private func tomeRows() -> [ThemeKitUI.ListItem<String>] {
    [
        ThemeKitUI.ListItem(id: "safari", image: appIcon(["com.apple.Safari"]) ?? wandGlyph("compass"),
                 primary: "Safari", secondary: "launch"),
        ThemeKitUI.ListItem(id: "settings", image: wandGlyph("gear"), primary: "System Settings",
                 trailing: .shortcut("⌘,")),
        ThemeKitUI.ListItem(id: "theme", image: wandGlyph("palette"), primary: "Switch theme"),
        ThemeKitUI.ListItem(id: "sep", primary: "", kind: .separator),
        ThemeKitUI.ListItem(id: "openin", image: wandGlyph("folder"), primary: "Open in…", trailing: .chevron),
        ThemeKitUI.ListItem(id: "branch", image: wandGlyph("git-branch"), primary: "Switch Branch", trailing: .chevron),
    ]
}

// The offset child list = the "Switch Branch" folder's async result (faux git
// branches, drawn statically — the still of wand's shell-fed submenu).
@MainActor private func branchRows() -> [ThemeKitUI.ListItem<String>] {
    [
        ThemeKitUI.ListItem(id: "main", image: wandGlyph("git-branch"), primary: "main"),
        ThemeKitUI.ListItem(id: "dev",  image: wandGlyph("git-branch"), primary: "develop"),
        ThemeKitUI.ListItem(id: "hot",  image: wandGlyph("git-branch"), primary: "hotfix"),
    ]
}

// The live trigger's items — a real ≥2-level cascade (Open in… → Editors → …) so
// clicking proves N-level LIVE (what the static shot can't hold).
@MainActor private func wandMenuItems() -> [ThemedMenu.MenuItem] {
    [
        ThemedMenu.MenuItem("Safari", icon: appIcon(["com.apple.Safari"])) {},
        ThemedMenu.MenuItem("System Settings", icon: wandGlyph("gear"), shortcut: "⌘,") {},
        .separator(),
        ThemedMenu.MenuItem(id: "openin", title: "Open in…", icon: wandGlyph("folder"), submenu: [
            ThemedMenu.MenuItem(id: "editors", title: "Editors", icon: wandGlyph("code"), submenu: [
                ThemedMenu.MenuItem("VS Code", icon: wandGlyph("code")) {},
                ThemedMenu.MenuItem("Xcode",   icon: wandGlyph("hammer")) {},
            ]),
            ThemedMenu.MenuItem("Finder", icon: wandGlyph("folder")) {},
        ]),
        ThemedMenu.MenuItem(id: "branch", title: "Switch Branch", icon: wandGlyph("git-branch"),
                            submenuProvider: {
            try? await Task.sleep(for: .milliseconds(400))     // faux `git branch` shell-out (deferred)
            return [
                ThemedMenu.MenuItem("main",    icon: wandGlyph("git-branch")) {},
                ThemedMenu.MenuItem("develop", icon: wandGlyph("git-branch")) {},
                ThemedMenu.MenuItem("hotfix",  icon: wandGlyph("git-branch")) {},
            ]
        }),
    ]
}

// Horizontal launcher bar items (the .toolbar / .labeledToolbar modes) — the SAME
// commands as a menu bar. `labeled` keeps the titles (icon+label) + a caret on a
// folder; icon-only drops them (tooltip carries the name). "Switch Branch" (index 5)
// is the pre-lit folder.
@MainActor private func wandBarItems(labeled: Bool) -> [ThemedToolBarView.Item] {
    func b(_ title: String, _ symbol: String, folder: Bool = false) -> ThemedToolBarView.Item {
        .button(title: labeled ? title : nil, symbol: symbol,
                trailingSymbol: (labeled && folder) ? "caret-down" : nil)
    }
    return [
        b("Safari", "compass"), b("Settings", "gear"), b("Theme", "palette"),
        .divider,
        b("Open in…", "folder", folder: true), b("Switch Branch", "git-branch", folder: true),
    ]
}

// A short labeled bar whose LEADING item is an open folder — so the depicted
// dropdown sits cleanly (gutter-aligned) beneath it: the still of an OPEN menu bar.
// Two items keep the bar within the specimen column (no clip).
@MainActor private func wandOpenBarItems() -> [ThemedToolBarView.Item] {
    [ .button(title: "Switch Branch", symbol: "git-branch", trailingSymbol: "caret-down"),
      .button(title: "Open in…", symbol: "folder", trailingSymbol: "caret-down") ]
}

struct MockWandLauncher: View {
    let p: ResolvedPalette

    private var surface: Color { Color(nsColor: p.background ?? .windowBackgroundColor) }

    // Compact rows are 26pt; separators ~7pt. Sized so the tome list shows all rows
    // WITHOUT a scrollbar (5 rows + 1 sep + vpad), and the child holds 3 rows.
    private let tomeListHeight: CGFloat = 162
    private let childListHeight: CGFloat = 86
    private let childListWidth: CGFloat = 160      // snug for the short branch names (main / develop / hotfix)
    // Push the child list down so its first row tops-aligns with the lit "Switch
    // Branch" row (the tome's last row). Eyeball-tuned against prism live (Task 3).
    private let childTopOffset: CGFloat = 176

    var body: some View {
        SpecimenBox(title: "wand · launcher", p: p) {
            VStack(alignment: .leading, spacing: 12) {
                Text("wand's launcher, rebuilt from the real kit. VERTICAL tome (.list): the query field + inline ThemedLists mirror ThemedMenu's row mapping; the offset child depicts an OPEN cascade (Switch Branch → faux branches). HORIZONTAL bar (.toolbar / .labeledToolbar): ThemedMenu composes the real ThemedToolBar; a folder bar-item (▾) opens its vertical submenu BELOW it. The live triggers open the REAL N-level ThemedMenu. wand's shell-fed submenus + motion stay app-side.")
                    .font(sysFont(9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
                    .fixedSize(horizontal: false, vertical: true)

                // Tier 1 — the static tome + its open cascade (deterministic still).
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        ThemedTextFieldView(palette: p, placeholder: "open…",
                                            leading: "magnifying-glass", surface: p.background)
                            .frame(width: 232, height: 40)
                        menuCard(rows: tomeRows(), lit: "branch", height: tomeListHeight, width: 232)
                    }
                    menuCard(rows: branchRows(), lit: "main", height: childListHeight, width: childListWidth)
                        .padding(.top, childTopOffset)
                }

                // Tier 2 — the live trigger opens the REAL extended ThemedMenu.
                VStack(alignment: .leading, spacing: 6) {
                    Text("live · opens the real N-level menu")
                        .font(sysFont(8, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                    ThemedMenuTriggerView(palette: p, title: "Actions", items: wandMenuItems())
                        .frame(width: 150, height: 38)
                }

                Divider().overlay(Color(nsColor: p.border))

                // Tier 3 — the HORIZONTAL launcher modes (menu bar).
                horizontalTier
            }
        }
    }

    // The .toolbar (icon-only) + .labeledToolbar (icon+label, with an open folder
    // dropdown) menu-bar modes, + live triggers that open the REAL horizontal menu.
    @ViewBuilder private var horizontalTier: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("horizontal launcher — menu-bar modes (composes the real ThemedToolBar)")
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))

            // .toolbar — icon-only strip (Switch Branch pre-lit).
            barCard {
                ThemedToolBarView(palette: p, items: wandBarItems(labeled: false), surface: .transparent,
                                  variant: .compact, corners: .rounded,
                                  trackingMode: .nonActivatingPanel, previewHoveredItem: 5)
                    .fixedSize()
            }

            // .labeledToolbar — icon+label bar with the leading folder OPEN (a vertical
            // dropdown beneath it, depicting the cascade a horizontal parent opens BELOW).
            VStack(alignment: .leading, spacing: 2) {
                barCard {
                    ThemedToolBarView(palette: p, items: wandOpenBarItems(), surface: .transparent,
                                      variant: .dense, corners: .rounded,
                                      trackingMode: .nonActivatingPanel, previewHoveredItem: 0)
                        .fixedSize()
                }
                HStack(spacing: 0) {
                    Spacer().frame(width: 14)                 // ≈ the dense bar's leading gutter
                    menuCard(rows: branchRows(), lit: "main", height: childListHeight, width: childListWidth)
                }
            }

            // Live — triggers that open the REAL horizontal ThemedMenu (hover an item,
            // ↓ opens its dropdown below, ←→ moves along the bar, Esc closes).
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("live · .toolbar").font(sysFont(8, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                    ThemedMenuTriggerView(palette: p, title: "Bar", presentation: .toolbar, items: wandMenuItems())
                        .frame(width: 110, height: 34)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("live · .labeledToolbar").font(sysFont(8, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                    ThemedMenuTriggerView(palette: p, title: "Labeled", presentation: .labeledToolbar, items: wandMenuItems())
                        .frame(width: 140, height: 34)
                }
            }
        }
    }

    // A rounded, bordered, shadowed launcher-bar surface hosting a transparent
    // ThemedToolBar (the bar's own chrome is off; this card is the menu surface).
    @ViewBuilder private func barCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(2)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: p.border), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
    }

    // A rounded, bordered, shadowed menu surface hosting a real ThemedListView in menu
    // config with a lit row — the MockMenu inline-mock recipe.
    @ViewBuilder private func menuCard(rows: [ThemeKitUI.ListItem<String>], lit: String,
                                       height: CGFloat, width: CGFloat) -> some View {
        ThemedListView(items: rows,
                       style: makeStyle { $0.selectionMode = .none; $0.hoverStyle = .solidAccent; $0.highlightFollowsHover = true; $0.density = .compact },
                       palette: p,
                       preview: ListPreview(highlight: lit))
        .frame(width: width, height: height)
        .padding(.vertical, 4)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: p.border), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
    }
}
