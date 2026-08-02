// ThemeKitUI — ThemedComboBoxView, the SwiftUI front for `ThemedComboBox`.
// SwiftUI-NATIVE by the demarcation settled 2026-08-02 (glossary §6,
// *IME-adjacent composition*): the combo owns no floor of its own, so this view
// is a plain `View` composing the three layers that do — the visible control is
// the controller-owned floor-1 `ThemedTextField`, hosted through the floor-1
// file's `FieldHostProxy` (never a representable of the combo's own); the popup
// shell is floor 2 inside the controller; the dropdown rows are the hosted
// SwiftUI list. The proxy's coordinator RETAINS the controller (which owns the
// popup + key monitor) and `invalidate()`s it on dismantle.
//
// Per-frame `update` re-themes ONLY — the static option data is set ONCE in
// `attach`, so an animatable theme cycling at 30 Hz can't re-filter / reframe an
// open popup (which would reset the user's arrow-key highlight). `createOnEmpty`
// demos the opt-in actionable empty state.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedComboBoxView: View {
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var options: [String]
    var label: String?
    var placeholder: String
    var leading: String?
    var freeText: Bool
    /// Opt-in actionable empty state (e.g. facet's "Create a new tag"): on a
    /// no-match, offer a "Create …" row that, when committed, appends + selects it.
    var createOnEmpty: Bool

    public init(palette: ResolvedPalette? = nil, options: [String], label: String? = nil,
                placeholder: String = "", leading: String? = "magnifying-glass",
                freeText: Bool = false, createOnEmpty: Bool = false) {
        self.explicitPalette = palette
        self.options = options
        self.label = label
        self.placeholder = placeholder
        self.leading = leading
        self.freeText = freeText
        self.createOnEmpty = createOnEmpty
    }

    public var body: some View {
        FieldHostProxy<ThemedComboBox>(
            // One-time: the controller + the static data / behaviour (the option
            // list never changes after creation — set here so the live theme
            // cycle in `update` doesn't churn the option list / popup geometry).
            attach: { [palette, options, label, placeholder, leading, freeText, createOnEmpty] in
                let combo = ThemedComboBox(palette: palette)
                combo.options = options.map { ThemedComboBox.Item($0) }
                combo.label = label
                combo.placeholder = placeholder
                combo.allowsFreeText = freeText
                combo.field.leadingSymbol = leading
                if createOnEmpty {
                    combo.emptyActionRow = { q in q.isEmpty ? nil : "Create “\(q)”" }
                    combo.onEmptyAction = { [weak combo] q in
                        guard let combo, !q.isEmpty else { return }
                        combo.options.append(ThemedComboBox.Item(q))     // the consumer owns the create
                        combo.selectedIndex = combo.options.count - 1
                    }
                }
                return (combo.field, combo)
            },
            // Per-frame: the theme. Under an animatable theme the host re-themes
            // at 30 Hz, so this MUST stay cheap — and must NOT touch `options`.
            update: { [palette] combo in
                combo.palette = palette
                combo.surfaceColor = palette.background
            },
            detach: { $0.invalidate() })
    }
}
