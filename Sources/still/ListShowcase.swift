// still — ThemeKit List bench. Unlike the ComboBox / Tooltip popups (which live on
// their own child windows and CAN'T appear in a `screencapture` of still's main
// window), `ThemedList` is a plain embeddable NSView — so the REAL widget bridges
// straight into the per-theme grid and IS captured. Three specimens prove the
// coverage the kit was designed for, each in its own theme:
//   1. facet-tree shape  — 2-line sticky section headers, single-select (wash + bar),
//      role-typed badges, dividers. `previewScrollY` pins / hands-off a header so a
//      static shot shows the sticky behaviour.
//   2. wand-tome shape    — `.solidAccent` hover (opaque primary + onPrimary ink),
//      rounded selection, `selectionMode = .none`, mono url secondary, shortcut /
//      chevron trailing. `previewHighlight` forces the accent row for capture.
//   3. dense single-line  — `.compact` density, mixed trailing, a disabled row, a
//      `.error` tint row.
// still never imports an app's View — these are mock data shapes drawn by the real
// kit, so the bench can't drift from facet / wand.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit

// MARK: - LIVE bridge: the REAL ThemedList

struct ListView: NSViewRepresentable {
    let palette: ResolvedPalette
    let configure: (ThemedList) -> Void

    func makeNSView(context: Context) -> ThemedList {
        let list = ThemedList(palette: palette)
        configure(list)
        return list
    }

    func updateNSView(_ list: ThemedList, context: Context) {
        list.palette = palette
        configure(list)            // re-applies items + preview seams after SwiftUI sizes the view
    }
}

// MARK: - Mock image helpers (pre-resolved NSImages — the kit parses no SF name)

/// A template SF glyph (the kit tints it to a role at draw — facet app icons,
/// badge symbols, the chevron).
@MainActor private func glyph(_ name: String, _ pt: CGFloat = 16) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let out = base.withSymbolConfiguration(.init(pointSize: pt, weight: .regular)) ?? base
    out.isTemplate = true
    return out
}

/// A SOLID-COLOUR glyph (non-template) — a stand-in favicon, so the `.solidAccent`
/// no-knockout path (a colour image draws as-is on the primary fill) is exercised.
@MainActor private func favicon(_ name: String, _ color: NSColor, _ pt: CGFloat = 16) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let sized = base.withSymbolConfiguration(.init(pointSize: pt, weight: .bold)) ?? base
    let img = NSImage(size: sized.size)
    img.lockFocus()
    color.set()
    sized.draw(in: NSRect(origin: .zero, size: sized.size))
    NSRect(origin: .zero, size: sized.size).fill(using: .sourceAtop)
    img.unlockFocus()
    img.isTemplate = false
    return img
}

// MARK: - Specimen data builders

@MainActor private func facetItems() -> [ListItem] {
    func win(_ id: String, _ icon: String, _ app: String, _ title: String, _ badges: [Badge]) -> ListItem {
        ListItem(id: id, image: glyph(icon, 18), primary: app, secondary: title, badges: badges)
    }
    let minGlyph = glyph("minus", 10)
    return [
        ListItem(id: "wsA", primary: "Workspace A",
                 kind: .sectionHeader(subtitle: "3 windows")),
        win("w1", "safari", "Safari", "GitHub — akira-toriyama/sill",
            [Badge("⌘3", role: .primary), Badge("Space 2")]),
        win("w2", "hammer", "Xcode", "ThemedList.swift — Edited",
            [Badge("⌘2", role: .primary), Badge("min", symbol: minGlyph, role: .secondary)]),
        win("w3", "terminal", "Terminal", "still — swift build",
            [Badge("⌘1", role: .primary)]),
        ListItem(id: "wsB", primary: "Workspace B",
                 kind: .sectionHeader(subtitle: "2 windows")),
        win("w4", "note.text", "Notes", "memo.md", [Badge("hidden", role: .neutral)]),
        win("w5", "music.note", "Music", "Focus playlist", [Badge("⌘5", role: .primary)]),
    ]
}

@MainActor private func wandItems(_ p: ResolvedPalette) -> [ListItem] {
    func site(_ id: String, _ color: NSColor, _ title: String, _ url: String,
              _ trailing: TrailingAccessory) -> ListItem {
        ListItem(id: id, image: favicon("globe", color, 16), primary: title,
                 secondary: url, secondaryMono: true, trailing: trailing)
    }
    return [
        site("s1", p.primary,   "GitHub",        "github.com/akira-toriyama",     .shortcut("⌘1")),
        site("s2", p.secondary, "Hacker News",   "news.ycombinator.com",          .shortcut("⌘2")),
        site("s3", p.error,     "MDN Web Docs",  "developer.mozilla.org/en-US",   .chevron),
        site("s4", p.muted,     "Swift Forums",  "forums.swift.org/c/evolution",  .chevron),
    ]
}

@MainActor private func denseItems() -> [ListItem] {
    [
        ListItem(id: "cut",   primary: "Cut",          trailing: .shortcut("⌘X")),
        ListItem(id: "copy",  primary: "Copy",         trailing: .shortcut("⌘C")),
        ListItem(id: "paste", primary: "Paste",        trailing: .shortcut("⌘V")),
        ListItem(id: "dup",   primary: "Duplicate",    trailing: .chevron),
        ListItem(id: "del",   primary: "Delete",       trailing: .shortcut("⌘⌫"), tint: .error),
        ListItem(id: "off",   primary: "Unavailable",  isDisabled: true),
    ]
}

// MARK: - Showcase

struct MockList: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · List — the REAL embeddable widget (hover a row, ↑↓/click in the dense list when focused). facet-tree shape (sticky 2-line headers · badges · single-select), wand-tome shape (solidAccent · rounded · mono url · shortcut/chevron), and a dense menu-style list.")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 20) {
                cell("facet tree · sticky headers · single-select") {
                    ListView(palette: p) { list in
                        list.items = facetItems()
                        list.selectionMode = .single
                        list.showsDividers = true
                        list.previewSelection = "w2"
                        list.previewScrollY = 30          // pin / hand-off the first header
                    }
                    .frame(width: 320, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("wand tome · solidAccent · no-select") {
                    ListView(palette: p) { list in
                        list.items = wandItems(p)
                        list.selectionMode = .none
                        list.hoverStyle = .solidAccent
                        list.roundedSelection = true
                        // Force a solidAccent row whose favicon ISN'T the primary
                        // colour, so the opaque-primary fill + onPrimary ink AND a
                        // visible colour favicon both read (a primary-tinted favicon
                        // would vanish into the fill — open-risk #1, by design: the
                        // kit never knocks out a colour image).
                        list.previewHighlight = "s2"
                    }
                    .frame(width: 300, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("dense · compact · menu-style") {
                    ListView(palette: p) { list in
                        list.items = denseItems()
                        list.density = .compact
                        list.managesFirstResponder = true
                        list.previewHighlight = "copy"
                    }
                    .frame(width: 220, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
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
