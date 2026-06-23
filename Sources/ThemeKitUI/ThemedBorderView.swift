// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedBorder`. Hosts the REAL
// shared AppKit border (a plain embeddable NSView) inside SwiftUI, so an app's
// View layer can drop a themed surface rim — static `primary`, or lit by a live
// `EffectSpec` — into an `NSHostingView` shell. `previewFrozen` freezes the live
// cycle at a fixed phase for deterministic capture.

import SwiftUI
import AppKit
import PaletteKit
import Effects
import ThemeKit

public struct ThemedBorderView: NSViewRepresentable {
    let palette: ResolvedPalette
    var effect: EffectSpec?
    var effectsEnabled: Bool
    var cornerRadius: CGFloat
    var lineWidth: CGFloat
    var previewFrozen: Bool

    public init(palette: ResolvedPalette, effect: EffectSpec? = nil,
                effectsEnabled: Bool = true, cornerRadius: CGFloat = 10,
                lineWidth: CGFloat = 1.5, previewFrozen: Bool = false) {
        self.palette = palette
        self.effect = effect
        self.effectsEnabled = effectsEnabled
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.previewFrozen = previewFrozen
    }

    public func makeNSView(context: Context) -> ThemedBorder {
        let b = ThemedBorder(palette: palette, effect: effect)
        apply(b)
        return b
    }

    public func updateNSView(_ b: ThemedBorder, context: Context) { apply(b) }

    private func apply(_ b: ThemedBorder) {
        b.palette = palette
        b.effect = effect
        b.effectsEnabled = effectsEnabled
        b.cornerRadius = cornerRadius
        b.lineWidth = lineWidth
        b.previewFrozen = previewFrozen
    }
}
