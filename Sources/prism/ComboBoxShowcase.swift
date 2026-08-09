// prism — ThemeKit ComboBox bench. The dropdown lives on its OWN borderless
// child window, which `screencapture -l<winid>` of prism's main window can NEVER
// include — so (the Menu-bench pattern) the per-theme grid draws the OPEN
// dropdown IN-WINDOW with the REAL kit: a `ThemedListView` in the exact config
// `ThemedComboBox` hosts, mirroring its `syncList` row mapping (disabled rows,
// the inert "No options" row, the actionable "Create …" row), inside the
// container chrome the panel paints. A LIVE row hosts the REAL `ThemedComboBox`
// so the type-to-filter / arrow-nav / click-select 演出 can be felt by hand (its
// child window just won't appear in a static capture; `.previewOpen(_:)` /
// `.previewHighlight(_:)` freeze it live for interactive verification).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - The OPEN dropdown, drawn in-window by the REAL kit

/// Build a `ThemedListStyle` inline (the kit's config value type is assign-based).
private func makeStyle(_ configure: (inout ThemedListStyle) -> Void) -> ThemedListStyle {
    var s = ThemedListStyle(); configure(&s); return s
}

/// The open dropdown: the REAL `ThemedListView` in `ThemedComboBox`'s exact
/// hosting config (comfortable 30 pt rows · no selection · wash highlight +
/// accent bar · hover-follows-highlight · no dividers · image-less flush rows),
/// with `preview` freezing the highlight, inside the container chrome the panel
/// draws (surface + 1 pt `border` + `Radius.lg` corners). This cell is the
/// capture surface for the dropdown's THEMED DRAWING — placement / flip /
/// dismiss stay covered by the controller's probe tests.
private struct DropdownOpen: View {
    let p: ResolvedPalette
    let rows: [ThemeKitUI.ListItem<String>]
    let highlight: String?
    var width: CGFloat = 200

    private var surface: NSColor { p.background ?? .textBackgroundColor }

    var body: some View {
        ThemedListView(items: rows,
                       style: makeStyle {
                           $0.density = .comfortable
                           $0.selectionMode = .none
                           $0.selectionInk = .wash
                           $0.wrapsHighlight = true
                           $0.highlightFollowsHover = true
                           $0.showsDividers = false
                           $0.reservesLeadingImageColumn = false
                           $0.surfaceColor = surface
                       },
                       palette: p,
                       preview: ListPreview(highlight: highlight))
        .frame(width: width, height: CGFloat(rows.count) * 30)
        .background(Color(nsColor: surface))
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(Radius.lg)))
        .overlay(RoundedRectangle(cornerRadius: CGFloat(Radius.lg))
            .stroke(Color(nsColor: p.border), lineWidth: 1))
    }
}

struct MockComboBox: View {
    let p: ResolvedPalette

    private let fruits = ["Apple", "Apricot", "Banana", "Blueberry",
                          "Grape", "Mango", "Orange", "Peach"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · ComboBox / Autocomplete — the REAL control (top row, on its own window: type to filter, ↑↓ to navigate, ⏎ / click to select); the grid below is the open dropdown drawn in-window by the REAL kit (a ThemedListView in the combo's exact hosting config).")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            // LIVE — type into the real combo; its dropdown appears on a separate
            // child window (won't show in a prism screenshot, but proves the 演出).
            HStack(alignment: .top, spacing: 24) {
                liveCell("select-only") {
                    ThemedComboBoxView(palette: p, options: fruits,
                                       label: "Fruit", placeholder: "type to filter…")
                }
                liveCell("freeSolo") {
                    ThemedComboBoxView(palette: p, options: fruits,
                                       label: "Fruit (free)", placeholder: "type anything…",
                                       freeText: true)
                }
                liveCell("create on no-match") {
                    ThemedComboBoxView(palette: p, options: fruits,
                                       label: "Tag", placeholder: "type a new tag…",
                                       leading: "tag", createOnEmpty: true)
                }
                Spacer(minLength: 0)
            }

            // The dropdown rows mirror ThemedComboBox.syncList's mapping exactly:
            // options → (id · primary · isDisabled), empty → ONE inert disabled
            // "No options" row, actionable empty → ONE enabled "Create …" row.
            HStack(alignment: .top, spacing: 28) {
                mockCell("open · highlighted row 1") {
                    DropdownOpen(p: p, rows: [
                        ThemeKitUI.ListItem(id: "Apple",   primary: "Apple"),
                        ThemeKitUI.ListItem(id: "Apricot", primary: "Apricot"),
                        ThemeKitUI.ListItem(id: "Banana",  primary: "Banana"),
                        ThemeKitUI.ListItem(id: "Grape",   primary: "Grape", isDisabled: true),
                        ThemeKitUI.ListItem(id: "Mango",   primary: "Mango"),
                    ], highlight: "Apricot")
                }
                mockCell("no match · inert") {
                    DropdownOpen(p: p, rows: [
                        ThemeKitUI.ListItem(id: "no-options", primary: "No options", isDisabled: true),
                    ], highlight: nil)
                }
                mockCell("no match · actionable") {
                    DropdownOpen(p: p, rows: [
                        ThemeKitUI.ListItem(id: "create", primary: "Create “kiwi”"),
                    ], highlight: "create")
                }
                Spacer(minLength: 0)
            }
        }
        .showcasePanel(p)
    }

    @ViewBuilder
    private func liveCell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content().frame(width: 230, height: 50)
        }
    }

    @ViewBuilder
    private func mockCell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }
}
