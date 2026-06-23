// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedTextField`. Hosts the REAL
// shared AppKit text field inside SwiftUI (floating label, leading/trailing
// adornments, focus-accent transition, helper/error). `text` is SEEDED ONCE
// (uncontrolled on purpose): `updateNSView` does NOT re-push it, so a theme
// re-render can't clobber live typing — a host wanting two-way binding wires
// `onChange` to a model and pushes model→field only while not first responder.
// `previewFocused` forces the focused state for deterministic capture.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

public struct ThemedTextFieldView: NSViewRepresentable {
    let palette: ResolvedPalette
    var variant: ThemedTextField.Variant
    var label: String?
    var placeholder: String
    /// Seed-once / uncontrolled: set on the field at creation only — `updateNSView`
    /// deliberately does NOT re-push it (so a re-render can't clobber live typing).
    /// A controlled two-way binding (`onChange` + model push) is deferred to the
    /// native SwiftUI part (#17).
    var text: String
    var leading: String?
    var trailing: String?
    var helper: String?
    var error: String?
    var surface: NSColor?
    var previewFocused: Bool

    public init(palette: ResolvedPalette, variant: ThemedTextField.Variant = .outlined,
                label: String? = nil, placeholder: String = "", text: String = "",
                leading: String? = nil, trailing: String? = nil, helper: String? = nil,
                error: String? = nil, surface: NSColor? = nil,
                previewFocused: Bool = false) {
        self.palette = palette
        self.variant = variant
        self.label = label
        self.placeholder = placeholder
        self.text = text
        self.leading = leading
        self.trailing = trailing
        self.helper = helper
        self.error = error
        self.surface = surface
        self.previewFocused = previewFocused
    }

    public func makeNSView(context: Context) -> ThemedTextField {
        let f = ThemedTextField(palette: palette)
        f.stringValue = text
        f.onTrailingTap = { [weak f] in f?.clearText() }   // fire onChange("") on clear
        apply(to: f)
        return f
    }

    public func updateNSView(_ f: ThemedTextField, context: Context) { apply(to: f) }

    private func apply(to f: ThemedTextField) {
        f.palette = palette
        f.variant = variant
        f.label = label
        f.placeholder = placeholder
        f.leadingSymbol = leading
        f.trailingSymbol = trailing
        f.helperText = helper
        f.errorText = error
        f.surfaceColor = surface
        f.previewFocused = previewFocused
    }
}
