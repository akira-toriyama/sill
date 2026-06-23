// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedComboBox`. `ThemedComboBox`
// is a CONTROLLER that owns a borderless popup window + a key monitor; the
// bridged NSView is its `field` (a `ThemedTextField`), and the Coordinator
// RETAINS the controller. Per-frame `updateNSView` re-themes ONLY — the static
// option data is set ONCE in `makeNSView`, so an animatable theme cycling at
// 30 Hz can't re-filter / reframe an open popup (which would reset the user's
// arrow-key highlight). `createOnEmpty` demos the opt-in actionable empty state.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedComboBoxView: NSViewRepresentable {
    let palette: ResolvedPalette
    var options: [String]
    var label: String?
    var placeholder: String
    var leading: String?
    var freeText: Bool
    /// Opt-in actionable empty state (e.g. facet's "Create a new tag"): on a
    /// no-match, offer a "Create …" row that, when committed, appends + selects it.
    var createOnEmpty: Bool

    public init(palette: ResolvedPalette, options: [String], label: String? = nil,
                placeholder: String = "", leading: String? = "magnifying-glass",
                freeText: Bool = false, createOnEmpty: Bool = false) {
        self.palette = palette
        self.options = options
        self.label = label
        self.placeholder = placeholder
        self.leading = leading
        self.freeText = freeText
        self.createOnEmpty = createOnEmpty
    }

    public final class Coordinator { var combo: ThemedComboBox? }
    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> ThemedTextField {
        let combo = ThemedComboBox(palette: palette)
        applyTheme(combo)
        configureStatic(combo)
        context.coordinator.combo = combo          // RETAIN the controller (owns the popup + monitor)
        return combo.field
    }

    public func updateNSView(_ v: ThemedTextField, context: Context) {
        guard let combo = context.coordinator.combo else { return }
        applyTheme(combo)          // ONLY the theming — see configureStatic
    }

    /// Per-frame: the theme. Under an animatable theme the host re-themes at
    /// 30 Hz, so this MUST stay cheap — and must NOT touch `options`, which would
    /// re-filter + reframe an open popup every tick (resetting the user's
    /// arrow-key highlight). The static data is set once in `configureStatic`.
    private func applyTheme(_ combo: ThemedComboBox) {
        combo.palette = palette
        combo.surfaceColor = palette.background
    }

    /// One-time: the static data + behaviour (the option list never changes
    /// after creation). Set in `makeNSView` so the live theme cycle doesn't churn
    /// the option list / popup geometry.
    private func configureStatic(_ combo: ThemedComboBox) {
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
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedTextField,
                             context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 230, height: nsView.intrinsicContentSize.height)
    }
}
