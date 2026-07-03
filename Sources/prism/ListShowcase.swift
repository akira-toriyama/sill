// prism — ThemeKitUI List bench. `ThemedListView` is now the SwiftUI-NATIVE themed
// list (#17b M2) — no longer an NSViewRepresentable over the AppKit widget. It draws
// straight into the per-theme grid and IS captured by prism's single-window
// screencapture. The specimens prove the coverage the kit was designed for, each in
// its own theme:
//   1. facet-tree shape  — 2-line sticky section headers, single-select (wash + bar),
//      role-typed badges, dividers.
//   2. wand-tome shape    — `.solidAccent` hover (opaque primary + onPrimary ink),
//      rounded selection, `.none` select, mono url secondary, shortcut / chevron trailing.
//   3. dense single-line  — `.compact` density, mixed trailing, a disabled row, an
//      `.error` tint row.
// The frozen `ListPreview` seam pins selection / highlight / scroll for a deterministic
// static shot. prism never imports an app's View — mock data shapes drawn by the real
// kit, so the bench can't drift from facet / wand.
//
// M2 staging note: rendering + single-select land in M2a; the drag affordances
// (cells 4-7) light up in M2c and animated collapse (cell 8 caret) in M2b — their
// captions flag what's still pending so the bench never overstates coverage.

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

/// Build a `ThemedListStyle` inline (the kit's config value type is assign-based).
private func makeStyle(_ configure: (inout ThemedListStyle) -> Void) -> ThemedListStyle {
    var s = ThemedListStyle(); configure(&s); return s
}

// MARK: - Specimen data builders

@MainActor private func facetItems() -> [ThemeKitUI.ListItem<String>] {
    func win(_ id: String, _ icon: String, _ app: String, _ title: String, _ badges: [Badge]) -> ThemeKitUI.ListItem<String> {
        ThemeKitUI.ListItem(id: id, image: glyph(icon, 18), primary: app, secondary: title, badges: badges)
    }
    let minGlyph = glyph("minus", 10)
    return [
        ThemeKitUI.ListItem(id: "wsA", primary: "Workspace A",
                 kind: .sectionHeader(subtitle: "3 windows")),
        win("w1", "compass", "Safari", "GitHub — akira-toriyama/sill",
            [Badge("⌘3", role: .primary), Badge("Space 2")]),
        win("w2", "hammer", "Xcode", "ThemedList.swift — Edited",
            [Badge("⌘2", role: .primary), Badge("min", symbol: minGlyph, role: .secondary)]),
        win("w3", "terminal-window", "Terminal", "prism — swift build",
            [Badge("⌘1", role: .primary)]),
        ThemeKitUI.ListItem(id: "wsB", primary: "Workspace B",
                 kind: .sectionHeader(subtitle: "2 windows")),
        win("w4", "note", "Notes", "memo.md", [Badge("hidden", role: .neutral)]),
        win("w5", "music-note", "Music", "Focus playlist", [Badge("⌘5", role: .primary)]),
    ]
}

@MainActor private func wandItems(_ p: ResolvedPalette) -> [ThemeKitUI.ListItem<String>] {
    func site(_ id: String, _ color: NSColor, _ title: String, _ url: String,
              _ trailing: TrailingAccessory) -> ThemeKitUI.ListItem<String> {
        ThemeKitUI.ListItem(id: id, image: favicon("globe", color, 16), primary: title,
                 secondary: url, secondaryMono: true, trailing: trailing)
    }
    return [
        site("s1", p.primary,   "GitHub",        "github.com/akira-toriyama",     .shortcut("⌘1")),
        site("s2", p.secondary, "Hacker News",   "news.ycombinator.com",          .shortcut("⌘2")),
        site("s3", p.error,     "MDN Web Docs",  "developer.mozilla.org/en-US",   .chevron),
        site("s4", p.muted,     "Swift Forums",  "forums.swift.org/c/evolution",  .chevron),
    ]
}

@MainActor private func denseItems() -> [ThemeKitUI.ListItem<String>] {
    [
        ThemeKitUI.ListItem(id: "cut",   primary: "Cut",          trailing: .shortcut("⌘X")),
        ThemeKitUI.ListItem(id: "copy",  primary: "Copy",         trailing: .shortcut("⌘C")),
        ThemeKitUI.ListItem(id: "paste", primary: "Paste",        trailing: .shortcut("⌘V")),
        ThemeKitUI.ListItem(id: "dup",   primary: "Duplicate",    trailing: .chevron),
        ThemeKitUI.ListItem(id: "del",   primary: "Delete",       trailing: .shortcut("⌘⌫"), tint: .error),
        ThemeKitUI.ListItem(id: "off",   primary: "Unavailable",  isDisabled: true),
    ]
}

// A plain reorder list (no headers) for the `.between` insertion-line affordance.
@MainActor private func reorderItems() -> [ThemeKitUI.ListItem<String>] {
    [
        ThemeKitUI.ListItem(id: "r1", image: glyph("number-circle-one"),   primary: "First task"),
        ThemeKitUI.ListItem(id: "r2", image: glyph("number-circle-two"),   primary: "Second task"),
        ThemeKitUI.ListItem(id: "r3", image: glyph("number-circle-three"), primary: "Third task"),
        ThemeKitUI.ListItem(id: "r4", image: glyph("number-circle-four"),  primary: "Fourth task"),
    ]
}

// A GENERIC sectioned list (no facet vocabulary) for the chunk-reorder demo: two
// short single-line sections so a lifted chunk AND the section insertion bar both
// frame in one static shot. Proves the chunk widget is app-agnostic, not facet-shaped.
@MainActor private func chunkItems() -> [ThemeKitUI.ListItem<String>] {
    func task(_ id: String, _ title: String) -> ThemeKitUI.ListItem<String> {
        ThemeKitUI.ListItem(id: id, image: glyph("circle", 14), primary: title)
    }
    return [
        ThemeKitUI.ListItem(id: "today", primary: "Today", kind: .sectionHeader()),
        task("t1", "Draft the proposal"),
        task("t2", "Review pull requests"),
        ThemeKitUI.ListItem(id: "later", primary: "Later", kind: .sectionHeader()),
        task("l1", "Plan the release"),
        task("l2", "Write the changelog"),
    ]
}

// A nested tree: collapsible section headers at varying `indentLevel` + indented
// rows. Shows the indent steps (level 1 / 2), the disclosure caret (▾ / ▸), and — with
// a live `collapsed` binding — animated collapse: clicking a header rotates its caret
// and animates its child rows in/out (ListCore.toggleSection + flattenVisible). All
// child rows are PRESENT; the kit hides the collapsed ones via the binding.
@MainActor private func treeItems() -> [ThemeKitUI.ListItem<String>] {
    [
        ThemeKitUI.ListItem(id: "proj", primary: "Project",
                 kind: .sectionHeader(subtitle: "4 items", collapsed: false)),
        ThemeKitUI.ListItem(id: "readme", image: glyph("file-text", 16), primary: "README.md", indentLevel: 1),
        ThemeKitUI.ListItem(id: "src", primary: "src",
                 kind: .sectionHeader(collapsed: false), indentLevel: 1),
        ThemeKitUI.ListItem(id: "f1", image: glyph("file-code", 16), primary: "ThemedList.swift", indentLevel: 2),
        ThemeKitUI.ListItem(id: "f2", image: glyph("file-code", 16), primary: "ThemedMenu.swift", indentLevel: 2),
        ThemeKitUI.ListItem(id: "build", primary: "build",
                 kind: .sectionHeader(collapsed: false), indentLevel: 1),
        ThemeKitUI.ListItem(id: "b1", image: glyph("file-code", 16), primary: "Debug",   indentLevel: 2),
        ThemeKitUI.ListItem(id: "b2", image: glyph("file-code", 16), primary: "Release", indentLevel: 2),
        ThemeKitUI.ListItem(id: "archive", primary: "Archive", kind: .sectionHeader(collapsed: false)),
        ThemeKitUI.ListItem(id: "a1", image: glyph("file-text", 16), primary: "2024.zip", indentLevel: 1),
        ThemeKitUI.ListItem(id: "a2", image: glyph("file-text", 16), primary: "2023.zip", indentLevel: 1),
    ]
}

// Long titles that overflow a narrow pane — for the horizontalContentScroll demo
// (the row extends past the clip and scrolls sideways rather than truncating).
@MainActor private func longItems() -> [ThemeKitUI.ListItem<String>] {
    func r(_ id: String, _ icon: String, _ title: String, _ sub: String) -> ThemeKitUI.ListItem<String> {
        ThemeKitUI.ListItem(id: id, image: glyph(icon, 16), primary: title, secondary: sub, secondaryMono: true,
                 badges: [Badge("⌘\(id.suffix(1))", role: .primary)])
    }
    return [
        r("1", "safari",   "akira-toriyama/sill — ThemedList.swift (Edited)", "github.com/akira-toriyama/sill/blob/main/Sources/ThemeKit/ThemedList.swift"),
        r("2", "hammer",   "prism — the visual bench for the whole widget kit",  "file:///Volumes/workspace/github.com/akira-toriyama/sill/Sources/prism"),
        r("3", "terminal", "swift build -c release && swift test --parallel",     "~/workspace/github.com/akira-toriyama/sill"),
    ]
}

// A flat file list for the multi-select demo (⌘ toggle · ⇧ range · ⌘A all).
@MainActor private func multiItems() -> [ThemeKitUI.ListItem<String>] {
    func f(_ id: String, _ t: String) -> ThemeKitUI.ListItem<String> {
        ThemeKitUI.ListItem(id: id, image: glyph("file-text", 16), primary: t)
    }
    return [f("m1", "Introduction"), f("m2", "Getting Started"), f("m3", "Configuration"),
            f("m4", "Theming"), f("m5", "Widgets"), f("m6", "Migration")]
}

// MARK: - Showcase

struct MockList: View {
    let p: ResolvedPalette
    // Live collapse state for the tree cell — clicking a header animates via this binding.
    @State private var treeCollapsed: Set<String> = ["build", "archive"]
    // Live multi-selection (⌘/⇧-click to change) — starts with a 3-row range selected.
    @State private var multiSelection: Set<String> = ["m2", "m3", "m4"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKitUI · List — the SwiftUI-NATIVE themed list (#17b M2). facet-tree shape (sticky 2-line headers · badges · single-select), wand-tome shape (solidAccent · rounded · mono url · shortcut/chevron), and a dense menu-style list. Middle rows: the additive drag layer (default-off) — lifted row dims under a drop-onto ring or a between insertion-line; chunk drag lifts a header + its rows as one unit with a full-width section insertion bar and a 2×3 grip on draggable headers (drag affordances render in M2c). 4th row: hierarchy — indentLevel shifts content right (selection wash stays full-bleed) + collapsible section headers (▾/▸; animated caret in M2b). Bottom row: highlightStyle .outline (keyboard cursor ring ≠ filled selection), zebra (parity resets per section), horizontalContentScroll (long titles scroll sideways, never truncated).")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 20) {
                cell("facet tree · sticky headers · single-select") {
                    ThemedListView(items: facetItems(),
                                   style: makeStyle { $0.selectionMode = .single; $0.showsDividers = true },
                                   palette: p,
                                   preview: ListPreview(selection: ["w2"], scrollY: 30))
                    .frame(width: 320, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("wand tome · solidAccent · no-select") {
                    ThemedListView(items: wandItems(p),
                                   style: makeStyle { $0.selectionMode = .none; $0.hoverStyle = .solidAccent; $0.roundedSelection = true },
                                   palette: p,
                                   preview: ListPreview(highlight: "s2"))
                    .frame(width: 300, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("dense · compact · menu-style") {
                    ThemedListView(items: denseItems(),
                                   style: makeStyle { $0.density = .compact },
                                   palette: p,
                                   preview: ListPreview(highlight: "copy"))
                    .frame(width: 220, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 20) {
                cell("drag · drop-onto (facet tree) · w3 → Workspace B  (affordance: M2c)") {
                    ThemedListView(items: facetItems(),
                                   style: makeStyle { $0.selectionMode = .single; $0.showsDividers = true; $0.draggable = true; $0.dragMode = .dropOnto },
                                   palette: p,
                                   preview: ListPreview(scrollY: 120, dragSource: "w3",
                                                        dropTarget: DropTarget(placement: .onto(id: "wsB"))))
                    .frame(width: 320, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("drag · reorder (insertion line) · before 'Third task'  (affordance: M2c)") {
                    ThemedListView(items: reorderItems(),
                                   style: makeStyle { $0.draggable = true; $0.dragMode = .reorderBetween },
                                   palette: p,
                                   preview: ListPreview(dragSource: "r1",
                                                        dropTarget: DropTarget(placement: .between(beforeID: "r3"))))
                    .frame(width: 300, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 20) {
                cell("drag · chunk reorder (facet) · header + its windows lift as one  (affordance: M2c)") {
                    ThemedListView(items: facetItems(),
                                   style: makeStyle { $0.selectionMode = .single; $0.showsDividers = true; $0.draggable = true },
                                   palette: p,
                                   preview: ListPreview(scrollY: 0, dragChunk: ["wsA", "w1", "w2", "w3"]))
                    .frame(width: 320, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("drag · chunk reorder (generic sections) · section insertion bar  (affordance: M2c)") {
                    ThemedListView(items: chunkItems(),
                                   style: makeStyle { $0.selectionMode = .single; $0.showsDividers = true; $0.draggable = true },
                                   palette: p,
                                   preview: ListPreview(dropTarget: DropTarget(placement: .between(beforeID: "today")),
                                                        dragChunk: ["later", "l1", "l2"]))
                    .frame(width: 300, height: 188)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 20) {
                cell("tree · indent + collapsible sections (click a header → animates ▾ / ▸)") {
                    ThemedListView(items: treeItems(),
                                   collapsed: $treeCollapsed,
                                   style: makeStyle { $0.selectionMode = .single; $0.showsDividers = true },
                                   palette: p,
                                   preview: ListPreview(selection: ["f1"]))
                    .frame(width: 320, height: 224)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 20) {
                cell("highlight .outline (cursor) ≠ selection (fill)") {
                    ThemedListView(items: facetItems(),
                                   style: makeStyle { $0.selectionMode = .single; $0.highlightStyle = .outline },
                                   palette: p,
                                   preview: ListPreview(selection: ["w1"], highlight: "w2"))
                    .frame(width: 320, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("zebra · alternating rows (resets per section)") {
                    ThemedListView(items: facetItems(),
                                   style: makeStyle { $0.zebra = true; $0.selectionMode = .none },
                                   palette: p)
                    .frame(width: 300, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }

                cell("horizontalContentScroll · long titles, no truncation") {
                    ThemedListView(items: longItems(),
                                   style: makeStyle { $0.selectionMode = .single; $0.horizontalContentScroll = true },
                                   palette: p,
                                   preview: ListPreview(selection: ["1"], scrollX: 150))
                    .frame(width: 260, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 20) {
                cell("multi-select · ⌘ toggle · ⇧ range · ⌘A all (click to try)") {
                    ThemedListView(items: multiItems(),
                                   selection: $multiSelection,
                                   style: makeStyle { $0.selectionMode = .multiple; $0.showsDividers = true },
                                   palette: p)
                    .frame(width: 300, height: 180)
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
