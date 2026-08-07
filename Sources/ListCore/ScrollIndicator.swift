// ListCore — pure overlay scroll-indicator geometry (t-8649). The themed knob
// `ThemedListView` draws in SwiftUI needs one fact per axis: where the pill
// sits and how long it is, given the scroll geometry. That is arithmetic, so
// it lives here with the other pure decoration rules — the renderer passes the
// axis' content length, viewport length and offset, and paints whatever comes
// back. `nil` means "this axis does not overflow — draw nothing".

#if canImport(CoreGraphics)
import CoreGraphics

/// One axis' indicator pill, in viewport coordinates along that axis.
public struct ScrollKnob: Equatable, Sendable {
    /// Distance from the viewport's leading edge (top / left) to the pill's
    /// leading end. Already includes `endInset`.
    public let offset: CGFloat
    public let length: CGFloat
    public init(offset: CGFloat, length: CGFloat) {
        self.offset = offset; self.length = length
    }
}

/// The pill for one axis, or `nil` when the content fits the viewport.
///
/// The track spans the viewport minus `endInset` off each cap (the pill never
/// kisses a corner). Length is proportional to the visible fraction, floored
/// at `minLength` so a huge document still shows a grabbable pill, and capped
/// at the track. Offset maps the scroll progress linearly onto the track's
/// spare room, clamped — a rubber-band overscroll parks the pill at its end
/// rather than pushing it out of the viewport.
public func scrollKnob(content: CGFloat, viewport: CGFloat, offset: CGFloat,
                       minLength: CGFloat = 20, endInset: CGFloat = 3) -> ScrollKnob? {
    guard viewport > 0, content > viewport + 0.5 else { return nil }
    let track = viewport - endInset * 2
    guard track > 0 else { return nil }
    let length = min(track, max(minLength, track * viewport / content))
    let progress = min(1, max(0, offset / (content - viewport)))
    return ScrollKnob(offset: endInset + (track - length) * progress, length: length)
}
#endif
