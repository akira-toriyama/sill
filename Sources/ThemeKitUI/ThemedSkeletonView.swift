// ThemeKitUI — SwiftUI bridge for ThemeKit's `ThemedSkeleton`. Hosts the REAL
// shared AppKit loading placeholder inside SwiftUI (pulse / wave shimmer).
// `previewFrozen` freezes the shimmer at a fixed phase for deterministic capture.

import SwiftUI
import PaletteKit
import ThemeKit

public struct ThemedSkeletonView: NSViewRepresentable {
    let palette: ResolvedPalette
    var variant: ThemedSkeleton.Variant
    var animation: ThemedSkeleton.Animation
    var width: CGFloat?
    var height: CGFloat?
    var previewFrozen: Bool

    public init(palette: ResolvedPalette, variant: ThemedSkeleton.Variant = .text,
                animation: ThemedSkeleton.Animation = .pulse, width: CGFloat? = nil,
                height: CGFloat? = nil, previewFrozen: Bool = false) {
        self.palette = palette
        self.variant = variant
        self.animation = animation
        self.width = width
        self.height = height
        self.previewFrozen = previewFrozen
    }

    public func makeNSView(context: Context) -> ThemedSkeleton {
        let s = ThemedSkeleton(palette: palette)
        apply(to: s)
        return s
    }

    public func updateNSView(_ s: ThemedSkeleton, context: Context) { apply(to: s) }

    private func apply(to s: ThemedSkeleton) {
        s.palette = palette
        s.variant = variant
        s.animation = animation
        s.width = width
        s.height = height
        s.previewFrozen = previewFrozen
    }
}
