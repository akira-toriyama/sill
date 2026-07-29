// ThemeKitUI — ThemedSkeletonView: the themed loading placeholder, SwiftUI-
// native (pulse / wave shimmer). Draws the SAME wash as ThemeKit's AppKit
// `ThemedSkeleton` (which stays for AppKit hosts): a low-alpha `muted` fill
// (the `.subtle` ink tier) in the variant's shape, breathing (`pulse`) or swept
// by a `foreground` highlight band (`wave`). The clock is a `TimelineView` —
// the house idiom for ambient motion — so the shimmer is a pure function of
// time: Reduce Motion / `previewFrozen` simply render one still frame (the same
// resting poses as the AppKit widget), and the display link stops by itself
// when the view is off screen (what ThemedSkeleton's window observers did by
// hand). `previewFrozen` holds the fixed mid-cycle phase for deterministic
// capture.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import Motion

public struct ThemedSkeletonView: View {
    @Environment(\.sillPalette) private var ambientPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var variant: ThemedSkeleton.Variant
    var animation: ThemedSkeleton.Animation
    var width: CGFloat?
    var height: CGFloat?
    var previewFrozen: Bool

    /// The one-time first-appearance moment — the MUI 0.5 s initial delay
    /// counts from here and never again (a later layout / theme pass must not
    /// re-introduce a dead pause).
    @State private var appeared: Date?

    public init(palette: ResolvedPalette? = nil, variant: ThemedSkeleton.Variant = .text,
                animation: ThemedSkeleton.Animation = .pulse, width: CGFloat? = nil,
                height: CGFloat? = nil, previewFrozen: Bool = false) {
        self.explicitPalette = palette
        self.variant = variant
        self.animation = animation
        self.width = width
        self.height = height
        self.previewFrozen = previewFrozen
    }

    // MARK: - Metrics (mirror ThemedSkeleton — a divergence here shows up as a
    // before/after diff in prism, so keep the two in lockstep)

    private let pulseRoundTrip: TimeInterval = 2.0   // MUI pulse: 2 s ease-in-out round trip
    private let waveSeconds: TimeInterval = 1.6      // MUI wave: 1.6 s linear sweep
    private let initialDelay: TimeInterval = 0.5     // MUI initial delay
    private let pulseMin: Double = 0.4               // MUI opacity floor
    private let frozenPhase: Double = 0.5            // mid-cycle hold for still capture
    /// The pulse opacity at the frozen phase — a recognizable mid-dim.
    private var frozenPulseOpacity: Double { 1 - (1 - pulseMin) * frozenPhase }
    /// CA's `.easeInEaseOut` — the curve the AppKit pulse runs on.
    private static let pulseEase = ThemedTransition.Easing.cubicBezier(0.42, 0, 0.58, 1)

    /// Text-row height from the themed font (MUI's `scale(1, 0.6)` squash).
    private var lineHeight: CGFloat { ceil(palette.uiFont(.body).boundingRectForFont.height * 0.6) }

    // MARK: - Theming (the same two roles as ThemedSkeleton)

    /// The wash — `muted` at the `.subtle` alpha tier. Translucent on purpose:
    /// it alpha-blends over the host backdrop.
    private var tint: NSColor { palette.ink(.subtle, of: .muted) }
    /// The wave's brighter band — `foreground` at the same tier.
    private var highlight: NSColor { palette.ink(.subtle, of: .foreground) }

    /// One drawable state: the fill opacity and the wave band's phase
    /// (`nil` = no band). Both stills and animated frames reduce to this.
    private struct Pose {
        var opacity: Double
        var wavePhase: Double?
    }

    /// The still to rest on when no clock should run — `previewFrozen` holds
    /// the recognizable mid-cycle shimmer; Reduce Motion rests on the calm end
    /// state (a mid-dim breath / a uniform wash with the band parked off the
    /// left edge, the AppKit widget's exact resting poses). `nil` ⇒ animate.
    private var stillPose: Pose? {
        switch animation {
        case .none:
            return Pose(opacity: 1, wavePhase: nil)
        case .pulse:
            return (previewFrozen || reduceMotion)
                ? Pose(opacity: frozenPulseOpacity, wavePhase: nil) : nil
        case .wave:
            if previewFrozen { return Pose(opacity: 1, wavePhase: frozenPhase) }
            if reduceMotion { return Pose(opacity: 1, wavePhase: 0) }
            return nil
        }
    }

    /// The animated pose — a pure function of elapsed time, so a frame is
    /// deterministic given a clock value (and the first 0.5 s is the rest pose,
    /// the MUI initial delay).
    private func pose(at now: Date) -> Pose {
        let t = (appeared.map(now.timeIntervalSince) ?? 0) - initialDelay
        switch animation {
        case .none:
            return Pose(opacity: 1, wavePhase: nil)
        case .pulse:
            guard t > 0 else { return Pose(opacity: 1, wavePhase: nil) }
            let leg = t.truncatingRemainder(dividingBy: pulseRoundTrip) / (pulseRoundTrip / 2)
            let toFloor = leg < 1 ? leg : 2 - leg          // autoreverse
            return Pose(opacity: 1 - (1 - pulseMin) * Self.pulseEase(toFloor), wavePhase: nil)
        case .wave:
            guard t > 0 else { return Pose(opacity: 1, wavePhase: 0) }
            return Pose(opacity: 1,
                        wavePhase: t.truncatingRemainder(dividingBy: waveSeconds) / waveSeconds)
        }
    }

    public var body: some View {
        Group {
            if let still = stillPose {
                wash(still)
            } else {
                TimelineView(.animation) { tl in
                    wash(pose(at: tl.date))
                }
            }
        }
        // Explicit width/height fix their axis (as they did via
        // intrinsicContentSize); the ideal frame answers a nil proposal with
        // the variant's intrinsic default. Hosts size cells with `.frame`
        // exactly as they did against the bridged widget.
        .frame(width: width, height: height)
        .frame(idealWidth: idealSize.width, idealHeight: idealSize.height)
        .onAppear { if appeared == nil { appeared = Date() } }
        .accessibilityHidden(true)   // a placeholder — AX-ignored
    }

    /// `intrinsicContentSize`, translated: `text` derives its height from the
    /// themed font line; `circular` a diameter from height-or-width; blocks
    /// default to a block height. A `nil` width stays host-decided.
    private var idealSize: (width: CGFloat?, height: CGFloat) {
        switch variant {
        case .text:
            return (width, height ?? lineHeight)
        case .circular:
            let d = height ?? width ?? 40
            return (d, d)
        case .rectangular, .rounded:
            return (width, height ?? 16)
        }
    }

    /// The variant's shape. `circular` is a capsule — the AppKit widget's
    /// `min(w, h) / 2` corner — so a square frame reads as a circle.
    private var washShape: AnyShape {
        switch variant {
        case .rectangular: return AnyShape(Rectangle())
        case .circular:    return AnyShape(Capsule())
        case .text, .rounded:
            return AnyShape(RoundedRectangle(cornerRadius: CGFloat(Radius.sm)))
        }
    }

    private func wash(_ pose: Pose) -> some View {
        Rectangle()
            .fill(Color(nsColor: tint))
            .overlay { band(pose.wavePhase) }
            .clipShape(washShape)      // clip the band to the rounded shape
            .opacity(pose.opacity)     // the pulse breath dims wash + band together
    }

    /// The wave highlight — a band one bounds-width wide whose leading edge
    /// travels from fully off the left (phase 0) to fully off the right
    /// (phase 1), the AppKit `waveX` math.
    @ViewBuilder private func band(_ phase: Double?) -> some View {
        if let phase {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, Color(nsColor: highlight), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width)
                    .offset(x: (2 * phase - 1) * geo.size.width)
            }
        }
    }
}
