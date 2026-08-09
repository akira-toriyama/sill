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
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
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

    public init(palette: ResolvedPalette? = nil, variant: ThemedTextField.Variant = .outlined,
                label: String? = nil, placeholder: String = "", text: String = "",
                leading: String? = nil, trailing: String? = nil, helper: String? = nil,
                error: String? = nil, surface: NSColor? = nil,
                previewFocused: Bool = false) {
        self.explicitPalette = palette
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

// MARK: - FieldHostProxy (floor-1 plumbing — the adoption seam)

/// Hosts a CONTROLLER-OWNED `ThemedTextField` in SwiftUI — the floor-1 adoption
/// seam, the `PopupAnchorProxy` of the edit core (glossary §6, *IME-adjacent
/// composition*). A composite widget whose visible control IS the floor-1 field
/// (today only `ThemedComboBoxView`) routes through THIS representable instead
/// of declaring its own: floor 1 covers the edit core, not view-layer bridging,
/// so this file — the one booked floor-1 line in `scripts/appkit-floor.sh` —
/// is the only place a `ThemedTextField` crosses into SwiftUI.
///
/// `attach` runs once (from `makeNSView`) and returns the field to host plus
/// the controller that owns + wires it; the coordinator RETAINS the controller
/// (the ThemedTooltip/ThemedMenu "caller MUST retain" contract). `update`
/// re-drives the controller's value inputs on every SwiftUI update — theming
/// only, by the same static-once discipline the combo documents. `detach` runs
/// at dismantle for deterministic teardown (`invalidate()`).
///
/// Sizing is the composite-field contract the combo has always had: width = the
/// proposal (230 pt when unspecified), height = the field's intrinsic height.
struct FieldHostProxy<Controller: AnyObject>: NSViewRepresentable {
    let attach: @MainActor () -> (field: ThemedTextField, controller: Controller)
    let update: @MainActor (Controller) -> Void
    let detach: @MainActor (Controller) -> Void

    /// `dismantleNSView` is static, so the coordinator carries BOTH the retained
    /// controller and the `detach` closure that tears it down. `update` is the
    /// LATEST SwiftUI values — the window-attach re-run below must not replay
    /// stale ones from `makeNSView` time.
    final class Coordinator {
        var controller: Controller?
        var update: (@MainActor (Controller) -> Void)?
        var detach: (@MainActor (Controller) -> Void)?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ThemedTextField {
        let (field, controller) = attach()
        context.coordinator.controller = controller
        context.coordinator.update = update
        context.coordinator.detach = detach
        // Re-drive on window attach/detach: the field arrives windowless, and a
        // window-dependent controller seam (`previewOpen`) set at first update
        // must be re-assertable once presenting becomes possible.
        field.onDidMoveToWindow = { [weak coordinator = context.coordinator] in
            guard let coordinator, let c = coordinator.controller else { return }
            coordinator.update?(c)
        }
        return field
    }

    func updateNSView(_ v: ThemedTextField, context: Context) {
        context.coordinator.update = update
        if let c = context.coordinator.controller { update(c) }
    }

    static func dismantleNSView(_ v: ThemedTextField, coordinator: Coordinator) {
        v.onDidMoveToWindow = nil
        if let c = coordinator.controller { coordinator.detach?(c) }
        coordinator.controller = nil
        coordinator.update = nil
        coordinator.detach = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedTextField,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 230, height: nsView.intrinsicContentSize.height)
    }
}
