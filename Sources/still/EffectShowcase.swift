// still — the LIVE effect preview.
//
// still's old `EffectStrip` rendered an effect's flash palette STATICALLY —
// a row of fixed swatches. Nothing actually animated, so the dynamic-theming
// atom (Effects' `resolveBorder` / `blendThrough`) looked *disabled* in the
// gallery even though `show-effects = true`. This file drives a real clock
// (SwiftUI `TimelineView`) through the SAME shared animator the apps use
// (`resolveBorder`), so an animatable theme's card now GLOWS + cycles live —
// proving the effect works, not just listing its colours.
//
// Lives in its OWN file (not Gallery.swift) so the still preview's animation
// machinery is self-contained; Gallery.swift only swaps two call sites.

import SwiftUI
import Palette
import PaletteKit
import Effects

/// Seconds for one full effect cycle in the preview — slow enough to read
/// the colour blend, fast enough to feel alive.
let effectCycleSeconds: Double = 5

/// One live frame of a named effect, resolved through the shared
/// `resolveBorder` animator at wall-clock `now`. CONTINUOUS (no focus
/// flash): `cycleColors: true` makes a non-`cycles` effect blend smoothly
/// through its flash palette, while `rainbow` rotates the full spectrum —
/// exactly the two motions the apps ship. Returns the SwiftUI colour + the
/// breathing stroke width (which also drives the glow radius).
func liveEffectFrame(name: String, now: Double, fallback: NSColor)
    -> (color: Color, width: CGFloat) {
    let frame = resolveBorder(
        spec: borderEffectFor(name),
        baseWidth: 2, minWidth: 1.5, maxWidth: 4.5,
        cycleSeconds: effectCycleSeconds, cycleColors: true,
        now: now, flash: nil)
    let color: Color
    switch frame.color {
    case .off:
        color = Color(nsColor: fallback)
    case .rgb(let r, let g, let b):
        color = Color(.sRGB, red: r, green: g, blue: b)
    case .rainbowHue(let h):
        // Matches the apps' `NSColor(hue:saturation:0.9:brightness:1)`.
        color = Color(hue: h, saturation: 0.9, brightness: 1.0)
    }
    return (color, CGFloat(frame.width))
}

// MARK: - Live effect strip (the animated replacement for `EffectStrip`)

/// The animated successor to the old static `EffectStrip`: a LIVE cycling
/// chip (the actual animated colour, glowing) + the theme-tinted label,
/// then the full flash palette so every colour is still readable at a
/// glance, then a "● live" dot so it's unmistakable the gallery is moving
/// (a still screenshot catches one frame, but the lit dot reads as "on").
struct LiveEffectStrip: View {
    let fx: EffectSpec
    let name: String
    /// The `off` fallback — the card's own `primary` (Effects keeps the
    /// fallback palette-side, exactly as facet/halo do).
    let fallback: NSColor

    var body: some View {
        // 30 Hz cap mirrors the apps' redraw heartbeat — smooth without
        // pinning a core in a preview tool.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let live = liveEffectFrame(name: name, now: now, fallback: fallback)
            HStack(spacing: 7) {
                Text(fx.cycles ? "effect · spectrum" : "effect · flash")
                    .font(sysFont(9, weight: .semibold, design: .monospaced))
                    .foregroundColor(live.color)
                // The LIVE cycling chip — the real animated colour, glowing.
                RoundedRectangle(cornerRadius: 4)
                    .fill(live.color)
                    .frame(width: 30 * uiScale, height: 14 * uiScale)
                    .shadow(color: live.color.opacity(0.9), radius: live.width * 1.6)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(.white.opacity(0.25), lineWidth: 0.5))
                // The full flash palette, static, so every colour is visible.
                ForEach(Array(fx.flash.enumerated()), id: \.offset) { _, hex in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: NSColor(hex: hex)))
                        .frame(width: 18 * uiScale, height: 12 * uiScale)
                }
                liveDot(live.color)
            }
        }
    }

    /// A small glowing "● live" tag — proof the preview animates.
    private func liveDot(_ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color)
                .frame(width: 6 * uiScale, height: 6 * uiScale)
                .shadow(color: color, radius: 3)
            Text("live")
                .font(sysFont(8, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.9))
        }
    }
}

// MARK: - Animated card border (the showpiece)

/// A live, glowing, breathing border for an animatable theme's card —
/// the shared `resolveBorder` animator drawn as a stroked, double-bloomed
/// rounded rect. This is what makes "the effect" visible at gallery scale:
/// the whole card rim cycles its neon. Non-animatable themes keep the flat
/// 1 px `border` hairline (see Gallery's conditional overlay).
struct AnimatedCardBorder: View {
    let name: String
    let cornerRadius: CGFloat
    let fallback: NSColor

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let live = liveEffectFrame(name: name, now: now, fallback: fallback)
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(live.color, lineWidth: live.width)
                // Two-stop bloom: a tight bright halo + a soft wide wash,
                // scaled by the breathing width — a neon-tube glow.
                .shadow(color: live.color.opacity(0.85), radius: live.width * 2.2)
                .shadow(color: live.color.opacity(0.45), radius: live.width * 4.8)
        }
    }
}
