// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedTextField`. Hosts the REAL
// shared AppKit text field inside SwiftUI (floating label, leading/trailing
// adornments, focus-accent transition, helper/error). Two modes:
//
//   * UNCONTROLLED (the original init, `text: String`): text is SEEDED ONCE —
//     `updateNSView` does NOT re-push it, so a theme re-render can't clobber
//     live typing.
//   * CONTROLLED (`text: Binding<String>`, T1): field edits land in the binding
//     (the AppKit `onChange` path — fires during IME composition too, so a
//     live-filter tracks marked text); model→field pushes are SILENT and happen
//     only while the field is NOT first responder — the same live-typing
//     protection, kept. Key seams (`onReturn`/`onEscape`/`onMoveUp`/`onMoveDown`,
//     handled-Bool contract, suppressed during IME composition by the AppKit
//     layer) and a `focused: Binding<Bool>` (programmatic grab/release +
//     truthful reflection of user-driven focus) ride along.
//
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
    /// For a controlled two-way binding use the `text: Binding<String>` init.
    var text: String
    var leading: String?
    var trailing: String?
    var helper: String?
    var error: String?
    var surface: NSColor?
    var previewFocused: Bool

    // Controlled surface (T1) — all nil in uncontrolled mode.
    var textBinding: Binding<String>?
    var focusBinding: Binding<Bool>?
    var onChange: ((String) -> Void)?
    var onReturn: (() -> Bool)?
    var onEscape: (() -> Bool)?
    var onMoveUp: (() -> Bool)?
    var onMoveDown: (() -> Bool)?

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

    /// CONTROLLED init (T1): two-way `text` binding + key callbacks + focus.
    /// The key callbacks return the handled-Bool of the AppKit seams: `true`
    /// consumes the key, `false` lets the field editor have it. All of them are
    /// suppressed during IME composition (marked text) by the AppKit layer, so
    /// Return/Esc/↑↓ confirm or cancel the conversion as Japanese input expects.
    public init(palette: ResolvedPalette, variant: ThemedTextField.Variant = .outlined,
                label: String? = nil, placeholder: String = "",
                text: Binding<String>, focused: Binding<Bool>? = nil,
                leading: String? = nil, trailing: String? = nil, helper: String? = nil,
                error: String? = nil, surface: NSColor? = nil,
                previewFocused: Bool = false,
                onChange: ((String) -> Void)? = nil,
                onReturn: (() -> Bool)? = nil,
                onEscape: (() -> Bool)? = nil,
                onMoveUp: (() -> Bool)? = nil,
                onMoveDown: (() -> Bool)? = nil) {
        self.init(palette: palette, variant: variant, label: label,
                  placeholder: placeholder, text: text.wrappedValue,
                  leading: leading, trailing: trailing, helper: helper,
                  error: error, surface: surface, previewFocused: previewFocused)
        self.textBinding = text
        self.focusBinding = focused
        self.onChange = onChange
        self.onReturn = onReturn
        self.onEscape = onEscape
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
    }

    public func makeNSView(context: Context) -> ThemedTextField { makeField() }

    public func updateNSView(_ f: ThemedTextField, context: Context) { apply(to: f) }

    /// Context-free creation seam (tests drive this directly).
    func makeField() -> ThemedTextField {
        let f = ThemedTextField(palette: palette)
        f.stringValue = textBinding?.wrappedValue ?? text
        f.onTrailingTap = { [weak f] in f?.clearText() }   // fire onChange("") on clear
        apply(to: f)
        return f
    }

    /// Context-free update seam. In controlled mode this (re)wires the callback
    /// seams — closures capture the CURRENT bindings/callbacks, so a re-render
    /// never leaves stale captures on the field — and reconciles model→field
    /// text (silently, only while not first responder) and programmatic focus.
    func apply(to f: ThemedTextField) {
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

        f.onReturn = onReturn
        f.onEscape = onEscape
        f.onMoveUp = onMoveUp
        f.onMoveDown = onMoveDown

        if textBinding != nil || onChange != nil {
            let binding = textBinding, observer = onChange
            f.onChange = { new in
                if let binding, binding.wrappedValue != new { binding.wrappedValue = new }
                observer?(new)
            }
        } else {
            f.onChange = nil
        }

        // Model → field: silent (no onChange echo), never over live typing.
        if let tb = textBinding, !f.isFirstResponderNow, f.stringValue != tb.wrappedValue {
            f.setText(tb.wrappedValue, notifying: false)
        }

        if let fb = focusBinding {
            f.onFocusChange = { focused in
                if fb.wrappedValue != focused { fb.wrappedValue = focused }
            }
            if fb.wrappedValue, !f.isFirstResponderNow {
                _ = f.focus()                       // needs a window; no-op before attach
            } else if !fb.wrappedValue, f.isFirstResponderNow {
                f.window?.makeFirstResponder(nil)
            }
        } else {
            f.onFocusChange = nil
        }
    }
}
