// still — ThemeKit ComboBox bench. The dropdown lives on its OWN borderless
// child window, which `screencapture -l<winid>` of still's main window can NEVER
// include — so (like the Tooltip bench) the per-theme grid draws an INLINE MOCK
// of the OPEN dropdown (rounded `background` surface, 1 pt `border`, 30 pt rows,
// the highlighted row = `selection` wash + a `primary` accent bar, a disabled
// row in `tertiary`, and the "No options" empty row), plus a LIVE row hosting the
// REAL `ThemedComboBox` so the type-to-filter / arrow-nav / click-select 演出 can
// be felt by hand (it just won't appear in a static capture).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit

// MARK: - LIVE: a real ThemedComboBox (its field is the bridged NSView)

struct ThemedComboBoxView: NSViewRepresentable {
    let palette: ResolvedPalette
    var options: [String]
    var label: String? = nil
    var placeholder: String = ""
    var leading: String? = "magnifyingglass"
    var freeText: Bool = false

    final class Coordinator { var combo: ThemedComboBox? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ThemedTextField {
        let combo = ThemedComboBox(palette: palette)
        apply(combo)
        context.coordinator.combo = combo          // RETAIN the controller (owns the popup + monitor)
        return combo.field
    }

    func updateNSView(_ v: ThemedTextField, context: Context) {
        guard let combo = context.coordinator.combo else { return }
        apply(combo)
    }

    private func apply(_ combo: ThemedComboBox) {
        combo.palette = palette
        combo.options = options.map { ThemedComboBox.Item($0) }
        combo.label = label
        combo.placeholder = placeholder
        combo.allowsFreeText = freeText
        combo.field.leadingSymbol = leading
        combo.surfaceColor = palette.background
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedTextField,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 230, height: nsView.intrinsicContentSize.height)
    }
}

// MARK: - Inline mock of the OPEN dropdown (for the static grid)

private struct DropdownMock: View {
    let p: ResolvedPalette
    let rows: [String]
    let highlight: Int?
    var disabledIndex: Int? = nil
    var width: CGFloat = 200

    private var rowFont: Font {
        p.font == .mono ? sysFont(13, design: .monospaced) : sysFont(13)
    }

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                row("No options", color: p.muted, highlighted: false)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, label in
                    let disabled = (i == disabledIndex)
                    row(label,
                        color: disabled ? p.tertiary : p.foreground,
                        highlighted: i == highlight && !disabled)
                }
            }
        }
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: p.background ?? .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: p.border), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func row(_ label: String, color: NSColor, highlighted: Bool) -> some View {
        ZStack(alignment: .leading) {
            if highlighted {
                Color(nsColor: p.selection)
                Color(nsColor: p.primary).frame(width: 3)   // accent bar — reads on neon themes
            }
            Text(label)
                .font(rowFont)
                .foregroundColor(Color(nsColor: color))
                .padding(.leading, 12)
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Showcase

struct MockComboBox: View {
    let p: ResolvedPalette

    private let fruits = ["Apple", "Apricot", "Banana", "Blueberry",
                          "Grape", "Mango", "Orange", "Peach"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · ComboBox / Autocomplete — the REAL control (top row, on its own window: type to filter, ↑↓ to navigate, ⏎ / click to select); the grid below is a static mock of the open dropdown.")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            // LIVE — type into the real combo; its dropdown appears on a separate
            // child window (won't show in a still screenshot, but proves the 演出).
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
                Spacer(minLength: 0)
            }

            // Static mock grid — the rendered open dropdown.
            HStack(alignment: .top, spacing: 28) {
                mockCell("open · highlighted row 1") {
                    DropdownMock(p: p, rows: ["Apple", "Apricot", "Banana", "Grape", "Mango"],
                                 highlight: 1, disabledIndex: 3)
                }
                mockCell("no match") {
                    DropdownMock(p: p, rows: [], highlight: nil)
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
