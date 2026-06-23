// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedCheckbox`. Hosts the REAL
// shared AppKit checkbox (box / check-draw-in / hover circle) inside SwiftUI.
// `onChange` fires on toggle; the `preview…` overrides force each state for
// deterministic capture.

import SwiftUI
import PaletteKit
import ThemeKit

public struct ThemedCheckboxView: NSViewRepresentable {
    let palette: ResolvedPalette
    var size: ThemedCheckbox.Size
    var label: String?
    var isChecked: Bool
    var isIndeterminate: Bool
    var enabled: Bool
    var previewHovered: Bool
    var previewPressed: Bool
    var previewFocused: Bool
    var previewChecked: Bool?
    var previewIndeterminate: Bool?
    var onChange: ((Bool) -> Void)?

    public init(palette: ResolvedPalette, size: ThemedCheckbox.Size = .medium,
                label: String? = nil, isChecked: Bool = false,
                isIndeterminate: Bool = false, enabled: Bool = true,
                previewHovered: Bool = false, previewPressed: Bool = false,
                previewFocused: Bool = false, previewChecked: Bool? = nil,
                previewIndeterminate: Bool? = nil, onChange: ((Bool) -> Void)? = nil) {
        self.palette = palette
        self.size = size
        self.label = label
        self.isChecked = isChecked
        self.isIndeterminate = isIndeterminate
        self.enabled = enabled
        self.previewHovered = previewHovered
        self.previewPressed = previewPressed
        self.previewFocused = previewFocused
        self.previewChecked = previewChecked
        self.previewIndeterminate = previewIndeterminate
        self.onChange = onChange
    }

    public func makeNSView(context: Context) -> ThemedCheckbox {
        let c = ThemedCheckbox(palette: palette)
        apply(to: c)
        return c
    }

    public func updateNSView(_ c: ThemedCheckbox, context: Context) { apply(to: c) }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedCheckbox,
                             context: Context) -> CGSize? { nsView.intrinsicContentSize }

    private func apply(to c: ThemedCheckbox) {
        c.palette = palette
        c.size = size
        c.label = label
        c.isChecked = isChecked
        c.isIndeterminate = isIndeterminate
        c.isEnabled = enabled
        c.previewHovered = previewHovered
        c.previewPressed = previewPressed
        c.previewFocused = previewFocused
        c.previewChecked = previewChecked
        c.previewIndeterminate = previewIndeterminate
        c.onChange = onChange
    }
}
