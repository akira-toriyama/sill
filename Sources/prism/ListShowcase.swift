// prism — ThemeKit List bench. Unlike the ComboBox / Tooltip popups (which live on
// their own child windows and CAN'T appear in a `screencapture` of prism's main
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
// prism never imports an app's View — these are mock data shapes drawn by the real
// kit, so the bench can't drift from facet / wand.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - Mock image helpers (pre-resolved NSImages — the kit parses no SF name)

/// A template Phosphor glyph (the kit tints it to a role at draw — facet app
/// icons, badge symbols, the disclosure caret).
@MainActor private func glyph(_ name: String, _ pt: CGFloat = 16) -> NSImage? {
    phosphorImage(name, pt: pt)   // a Phosphor slug → template NSImage
}

/// A SOLID-COLOUR glyph (non-template) — a stand-in favicon, so the `.solidAccent`
/// no-knockout path (a colour image draws as-is on the primary fill) is exercised.
@MainActor private func favicon(_ name: String, _ color: NSColor, _ pt: CGFloat = 16) -> NSImage? {
    guard let base = phosphorImage(name, pt: pt) else { return nil }
    let img = NSImage(size: base.size)
    img.lockFocus()
    color.set()
    base.draw(in: NSRect(origin: .zero, size: base.size))
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
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
        win("w1", "compass", "Safari", "GitHub — akira-toriyama/sill",
            [Badge("⌘3", role: .primary), Badge("Space 2")]),
        win("w2", "hammer", "Xcode", "ThemedList.swift — Edited",
            [Badge("⌘2", role: .primary), Badge("min", symbol: minGlyph, role: .secondary)]),
        win("w3", "terminal-window", "Terminal", "prism — swift build",
            [Badge("⌘1", role: .primary)]),
        ListItem(id: "wsB", primary: "Workspace B",
                 kind: .sectionHeader(subtitle: "2 windows")),
        win("w4", "note", "Notes", "memo.md", [Badge("hidden", role: .neutral)]),
        win("w5", "music-note", "Music", "Focus playlist", [Badge("⌘5", role: .primary)]),
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

// A plain reorder list (no headers) for the `.between` insertion-line affordance.
@MainActor private func reorderItems() -> [ListItem] {
    [
        ListItem(id: "r1", image: glyph("number-circle-one"),   primary: "First task"),
        ListItem(id: "r2", image: glyph("number-circle-two"),   primary: "Second task"),
        ListItem(id: "r3", image: glyph("number-circle-three"), primary: "Third task"),
        ListItem(id: "r4", image: glyph("number-circle-four"),  primary: "Fourth task"),
    ]
}

// A GENERIC sectioned list (no facet vocabulary) for the chunk-reorder demo: two
// short single-line sections so a lifted chunk AND the section insertion bar both
// frame in one static shot. Proves the chunk widget is app-agnostic, not facet-shaped.
@MainActor private func chunkItems() -> [ListItem] {
    func task(_ id: String, _ title: String) -> ListItem {
        ListItem(id: id, image: glyph("circle", 14), primary: title)
    }
    return [
        ListItem(id: "today", primary: "Today", kind: .sectionHeader()),
        task("t1", "Draft the proposal"),
        task("t2", "Review pull requests"),
        ListItem(id: "later", primary: "Later", kind: .sectionHeader()),
        task("l1", "Plan the release"),
        task("l2", "Write the changelog"),
    ]
}

// A nested tree: collapsible section headers at varying `indentLevel` + indented
// rows. Shows the indent steps (level 1 / 2), both disclosure states (▾ expanded /
// ▸ collapsed) on a 2-line AND a 1-line header, and a collapsed section whose child
// rows the HOST simply omits (the kit hides nothing itself — host owns the shape).
@MainActor private func treeItems() -> [ListItem] {
    [
        ListItem(id: "proj", primary: "Project",
                 kind: .sectionHeader(subtitle: "4 items", collapsed: false)),
        ListItem(id: "readme", image: glyph("file-text", 16), primary: "README.md", indentLevel: 1),
        ListItem(id: "src", primary: "src",
                 kind: .sectionHeader(collapsed: false), indentLevel: 1),
        ListItem(id: "f1", image: glyph("file-code", 16), primary: "ThemedList.swift", indentLevel: 2),
        ListItem(id: "f2", image: glyph("file-code", 16), primary: "ThemedMenu.swift", indentLevel: 2),
        ListItem(id: "build", primary: "build",
                 kind: .sectionHeader(collapsed: true), indentLevel: 1),    // collapsed — children omitted
        ListItem(id: "archive", primary: "Archive",
                 kind: .sectionHeader(collapsed: true)),                     // collapsed — children omitted
    ]
}

// Long titles that overflow a narrow pane — for the horizontalContentScroll demo
// (the row extends past the clip and scrolls sideways rather than truncating).
@MainActor private func longItems() -> [ListItem] {
    func r(_ id: String, _ icon: String, _ title: String, _ sub: String) -> ListItem {
        ListItem(id: id, image: glyph(icon, 16), primary: title, secondary: sub, secondaryMono: true,
                 badges: [Badge("⌘\(id.suffix(1))", role: .primary)])
    }
    return [
        r("1", "safari",   "akira-toriyama/sill — ThemedList.swift (Edited)", "github.com/akira-toriyama/sill/blob/main/Sources/ThemeKit/ThemedList.swift"),
        r("2", "hammer",   "prism — the visual bench for the whole widget kit",  "file:///Volumes/workspace/github.com/akira-toriyama/sill/Sources/prism"),
        r("3", "terminal", "swift build -c release && swift test --parallel",     "~/workspace/github.com/akira-toriyama/sill"),
    ]
}

// MARK: - Showcase

struct MockList: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · List — the REAL embeddable widget (hover a row, ↑↓/click in the dense list when focused). facet-tree shape (sticky 2-line headers · badges · single-select), wand-tome shape (solidAccent · rounded · mono url · shortcut/chevron), and a dense menu-style list. Middle row: the additive drag layer (default-off) — the lifted row dims under a drop-onto ring or a between insertion-line; a live drag's ghost is a child window (hand-checked, not captured). Chunk row: a section header + its rows drag as ONE unit — every member dims, a thick full-width section insertion bar marks the gap it lands in, a 2×3 grip marks each draggable header (facet shape + a generic sectioned list; a non-header row still lifts solo). 4th row: hierarchy — ListItem.indentLevel shifts content right (selection wash stays full-bleed) + collapsible section headers (▾ expanded / ▸ collapsed, click → onToggleSection; the host omits a collapsed section's rows). Bottom row: facet polish — highlightStyle .outline (a keyboard cursor ring distinct from the filled selection), alternatingRowBackground (zebra; parity resets per section), horizontalContentScroll (long titles draw in full and scroll sideways, never truncated).")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 20) {
                cell("facet tree · sticky headers · single-select") {
                    ThemedListView(palette: p) { list in
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
                    ThemedListView(palette: p) { list in
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
                    ThemedListView(palette: p) { list in
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

            HStack(alignment: .top, spacing: 20) {
                cell("drag · drop-onto (facet tree) · w3 → Workspace B") {
                    ThemedListView(palette: p) { list in
                        list.items = facetItems()
                        list.selectionMode = .single
                        list.showsDividers = true
                        list.draggable = true
                        list.dragMode = .dropOnto
                        // A window row lifted (dimmed) and aimed ONTO the Workspace B
                        // header — the ring + faint fill on the target, the static
                        // stand-in for the live ghost (a child window prism can't grab).
                        list.previewDragSource = "w3"
                        list.previewDropTarget = DropTarget(placement: .onto(id: "wsB"))
                        list.previewScrollY = 120         // bring the lifted w3 + the Workspace B target into view
                    }
                    .frame(width: 320, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("drag · reorder (insertion line) · before 'Third task'") {
                    ThemedListView(palette: p) { list in
                        list.items = reorderItems()
                        list.draggable = true
                        list.dragMode = .reorderBetween
                        // The first task lifted (dimmed); the insertion line + dot mark
                        // the gap it would land in (before the third row).
                        list.previewDragSource = "r1"
                        list.previewDropTarget = DropTarget(placement: .between(beforeID: "r3"))
                    }
                    .frame(width: 300, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            // Chunk reorder (v1.6.0): a section HEADER lifts with its child rows as ONE
            // unit — every member dims, a thick full-width section insertion bar marks the
            // section gap it lands in, and a 2×3 grip marks each draggable header. Shown in
            // the facet shape AND a generic sectioned list (no facet vocabulary). A
            // non-header row still lifts SOLO (the reorder cell above) — chunk is headers-only.
            HStack(alignment: .top, spacing: 20) {
                cell("drag · chunk reorder (facet) · header + its windows lift as one") {
                    ThemedListView(palette: p) { list in
                        list.items = facetItems()
                        list.selectionMode = .single
                        list.showsDividers = true
                        list.draggable = true
                        // Workspace A's header + its 3 window rows lifted as a chunk: all
                        // four dim together; the grips mark both headers as draggable.
                        list.previewDragChunk = ["wsA", "w1", "w2", "w3"]
                        list.previewScrollY = 0
                    }
                    .frame(width: 320, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("drag · chunk reorder (generic sections) · section insertion bar") {
                    ThemedListView(palette: p) { list in
                        list.items = chunkItems()
                        list.selectionMode = .single
                        list.showsDividers = true
                        list.draggable = true
                        // 'Later' (header + its 2 rows) lifted and aimed above 'Today': the
                        // members dim (bottom) while a thick full-width section bar marks the
                        // top gap it would land in — coarser than a single row's thin line.
                        list.previewDragChunk = ["later", "l1", "l2"]
                        list.previewDropTarget = DropTarget(placement: .between(beforeID: "today"))
                    }
                    .frame(width: 300, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 20) {
                cell("tree · indentLevel + collapsible sections (▾ / ▸)") {
                    ThemedListView(palette: p) { list in
                        list.items = treeItems()
                        list.selectionMode = .single
                        list.showsDividers = true
                        // An INDENTED row selected: the wash + 3pt bar stay full-bleed
                        // while the text sits at its depth (the MUI tree model).
                        list.previewSelection = "f1"
                    }
                    .frame(width: 320, height: 224)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            // Facet polish (all additive, default-off): outline keyboard cursor vs
            // filled selection · zebra rows · horizontal content scroll (no truncation).
            HStack(alignment: .top, spacing: 20) {
                cell("highlight .outline (cursor) ≠ selection (fill)") {
                    ThemedListView(palette: p) { list in
                        list.items = facetItems()
                        list.selectionMode = .single
                        list.highlightStyle = .outline
                        // w1 (Safari) committed (wash + bar); w2 (Xcode) is the keyboard
                        // cursor (a ring) — two distinct affordances at once (facet's tree).
                        list.previewSelection = "w1"
                        list.previewHighlight = "w2"
                    }
                    .frame(width: 320, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("zebra · alternatingRowBackground (resets per section)") {
                    ThemedListView(palette: p) { list in
                        list.items = facetItems()
                        list.alternatingRowBackground = true
                        list.selectionMode = .none
                    }
                    .frame(width: 300, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("horizontalContentScroll · long titles, no truncation") {
                    ThemedListView(palette: p) { list in
                        list.items = longItems()
                        list.selectionMode = .single
                        list.horizontalContentScroll = true
                        list.previewSelection = "1"
                        list.previewScrollX = 150          // scrolled sideways to reveal the title tail
                    }
                    .frame(width: 260, height: 150)
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
