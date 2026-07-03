import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects   // EffectSpec — the animated border-effect knob (#17k)

// MARK: - Pure logic (deterministic XCTest surface; no SwiftUI/AppKit)

/// Palette-free, SwiftUI-free helpers for ThemedPill. The whole point is that
/// these are unit-testable in CI without a window or a resolved palette.
enum PillLogic {
    /// Split `label` into a typed prefix (first `typedCount` chars, clamped to
    /// `0...count`) and the remaining suffix.
    static func splitLabel(_ label: String, typedCount: Int) -> (prefix: String, suffix: String) {
        let n = max(0, min(typedCount, label.count))
        let cut = label.index(label.startIndex, offsetBy: n)
        return (String(label[label.startIndex..<cut]), String(label[cut...]))
    }

    /// A `.circle` pill is only drawn as a circle for a single glyph (perch parity).
    static func isCircleEligible(_ label: String) -> Bool { label.count <= 1 }

    /// `.circle` degrades to `.pill` for multi-glyph labels; every other shape is
    /// returned unchanged.
    static func resolvedShape(_ requested: ThemedPillView.Shape,
                              label: String) -> ThemedPillView.Shape {
        (requested == .circle && !isCircleEligible(label)) ? .pill : requested
    }

    /// The typed prefix is drawn in the error colour on a miss, else the accent.
    static func prefixUsesError(_ state: ThemedPillView.State) -> Bool { state == .miss }

    /// The animated effect rim shows on idle/matched but NEVER on a miss — the red
    /// error stroke is a semantic signal the rim must not eat. No effect ⇒ no rim
    /// (the pill keeps its static tri-state border). Applies to every shape,
    /// including the underline bar.
    static func showsEffectRim(hasEffect: Bool, state: ThemedPillView.State) -> Bool {
        hasEffect && state != .miss
    }
}

// MARK: - ThemedPillView (display / indicator pill; pure SwiftUI)

/// A non-interactive themed pill — the display/indicator counterpart to the
/// interactive `ThemedChip`. Absorbs perch's universal hint pill: 5 shape
/// presets, a two-color typed-prefix label, idle/matched/miss result states,
/// frost, a drop shadow, and an optional corner badge. Clickable tokens stay
/// `ThemedChip`'s job — this widget renders, it does not interact.
public struct ThemedPillView: View {
    public enum Shape: Equatable, Sendable { case pill, square, circle, underline, tag }
    public enum State: Equatable, Sendable { case idle, matched, miss }

    public var palette: ResolvedPalette
    public var label: String
    public var shape: Shape
    public var state: State
    public var typedCount: Int
    public var badge: String?
    public var accent: Color?
    public var surfaceAlpha: Double?
    public var frosted: Bool
    public var elevated: Bool
    public var transform: CGAffineTransform
    public var opacity: Double
    /// Non-nil ⇒ the pill carries an animated neon/effect rim (stroked along its
    /// own shape via `AnimatedBorderView`), replacing the static idle/matched
    /// border; nil ⇒ the current tri-state border, byte-identical. A miss always
    /// keeps the error stroke. 派手/静か is the app's call (pass nil to rest).
    public var borderEffect: EffectSpec?
    /// Glow style for the effect rim (`.none` flat / `.bloom` neon-tube halo).
    public var borderGlow: AnimatedBorderGlow
    /// Seconds for one full colour cycle of the effect rim.
    public var borderCycleSeconds: Double
    /// Bump to roll a focus/match blink burst on the effect rim (perch drives it
    /// on a state change). No-op when `borderEffect == nil`.
    public var flashToken: Int
    /// Hold the rim's live cycle at a fixed phase (prism deterministic capture).
    public var previewFrozen: Bool
    /// The phase held when `previewFrozen`.
    public var previewPhase: CGFloat

    public init(palette: ResolvedPalette,
                label: String,
                shape: Shape = .pill,
                state: State = .idle,
                typedCount: Int = 0,
                badge: String? = nil,
                accent: Color? = nil,
                surfaceAlpha: Double? = nil,
                frosted: Bool = false,
                elevated: Bool = true,
                transform: CGAffineTransform = .identity,
                opacity: Double = 1,
                borderEffect: EffectSpec? = nil,
                borderGlow: AnimatedBorderGlow = .bloom,
                borderCycleSeconds: Double = 5,
                flashToken: Int = 0,
                previewFrozen: Bool = false,
                previewPhase: CGFloat = 0.35) {
        self.palette = palette
        self.label = label
        self.shape = shape
        self.state = state
        self.typedCount = typedCount
        self.badge = badge
        self.accent = accent
        self.surfaceAlpha = surfaceAlpha
        self.frosted = frosted
        self.elevated = elevated
        self.transform = transform
        self.opacity = opacity
        self.borderEffect = borderEffect
        self.borderGlow = borderGlow
        self.borderCycleSeconds = borderCycleSeconds
        self.flashToken = flashToken
        self.previewFrozen = previewFrozen
        self.previewPhase = previewPhase
    }

    // Colours (canonical roles only — never invent role names).
    private var accentColor: Color { accent ?? Color(nsColor: palette.primary) }
    private var foreground: Color { Color(nsColor: palette.foreground) }
    private var errorColor: Color { Color(nsColor: palette.error) }
    private var prefixColor: Color { PillLogic.prefixUsesError(state) ? errorColor : accentColor }
    private var labelFont: Font { Font(palette.uiFont(.body) as CTFont).weight(.semibold) }

    /// Two-color typed-prefix label: first `typedCount` chars in `prefixColor`,
    /// the rest in `foreground`.
    private var labelView: some View {
        let parts = PillLogic.splitLabel(label, typedCount: typedCount)
        return Text("\(Text(parts.prefix).foregroundColor(prefixColor))\(Text(parts.suffix).foregroundColor(foreground))")
            .font(labelFont)
            .lineLimit(1)
            .fixedSize()
    }

    /// The shape actually drawn (`.circle` degrades to `.pill` for multi-glyph).
    private var kind: Shape { PillLogic.resolvedShape(shape, label: label) }

    /// Type-erased SwiftUI shape for the surface + border (macOS 13+ `AnyShape`).
    private var pillShape: AnyShape {
        switch kind {
        case .pill:      return AnyShape(Capsule())
        case .square:    return AnyShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        case .circle:    return AnyShape(Circle())
        case .tag:       return AnyShape(TagShape())
        case .underline: return AnyShape(Rectangle())   // never drawn as a surface
        }
    }

    public var body: some View {
        content
            .compositingGroup()
            .modifier(PillShadow(palette: palette, enabled: elevated && kind != .underline))
            .transformEffect(transform)
            .opacity(opacity)
    }

    @ViewBuilder
    private var content: some View {
        if kind == .underline { underlineContent } else { filledContent }
    }

    /// Filled/bordered shapes: a scrim surface (+ optional Material frost) under
    /// the two-color label, a state-driven border, and an optional corner badge.
    private var filledContent: some View {
        labelView
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                ZStack {
                    if frosted { pillShape.fill(.ultraThinMaterial) }
                    ThemedBackdropView(palette: palette, in: pillShape,
                                       fill: .scrim(opacity: surfaceAlpha ?? 1))
                    // miss tints the surface with an error wash (perch parity:
                    // a miss swaps the fill, not just the border/prefix).
                    if state == .miss { pillShape.fill(errorColor.opacity(0.20)) }
                }
            }
            .overlay { borderOverlay }
            .overlay(alignment: .topTrailing) { badgeView }
    }

    /// Underline: no surface/border — a 2pt accent bar under the label, or (with
    /// an effect set) a neon bar.
    private var underlineContent: some View {
        labelView
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) { underlineBar }
            .overlay(alignment: .topTrailing) { badgeView }
    }

    /// The underline bar. With an effect set (and not a miss) the SAME
    /// `AnimatedBorderView` engine strokes a flat horizontal line (`HBarShape`),
    /// so the bar itself cycles colour and blooms — the underline has no closed
    /// surface to stroke, so it borrows the rim engine as a glowing bar. The
    /// frame is taller than the 2pt line to give the bloom vertical room. A miss
    /// (or no effect) keeps the static accent/error bar.
    @ViewBuilder
    private var underlineBar: some View {
        if PillLogic.showsEffectRim(hasEffect: borderEffect != nil, state: state) {
            effectRim(in: HBarShape())
                .frame(height: 8)
                .padding(.horizontal, 4)
        } else {
            Rectangle()
                .fill(state == .miss ? errorColor : accentColor)
                .frame(height: 2)
                .padding(.horizontal, 4)
        }
    }

    /// Border. With an effect set (and not a miss) the animated neon/effect rim
    /// REPLACES the static stroke — the rim already glows, so the idle hairline
    /// and the matched native shadow would only double it. Else the tri-state
    /// static border: matched = accent stroke + a native glow (fill UNCHANGED);
    /// miss = error stroke; idle = accent hairline.
    @ViewBuilder
    private var borderOverlay: some View {
        if PillLogic.showsEffectRim(hasEffect: borderEffect != nil, state: state) {
            effectRim(in: pillShape)
        } else {
            switch state {
            case .idle:
                pillShape.stroke(accentColor.opacity(0.55), lineWidth: 1)
            case .matched:
                pillShape.stroke(accentColor, lineWidth: 2)
                    .shadow(color: accentColor.opacity(0.5), radius: 7)
            case .miss:
                pillShape.stroke(errorColor, lineWidth: 2)
            }
        }
    }

    /// The animated neon/effect rim stroked along `shape` — the perch-deferred
    /// #17k capability, built entirely on the SwiftUI-native `AnimatedBorderView`
    /// (#17d). Fixed-width (no breathing) on a tight pill: the liveliness is the
    /// colour cycle + bloom, not a fattening stroke.
    private func effectRim<SH: SwiftUI.Shape>(in shape: SH) -> some View {
        AnimatedBorderView(palette: palette,
                           effect: borderEffect,
                           in: shape,
                           lineWidth: 1.5,
                           breathTo: 1.5,
                           cycleSeconds: borderCycleSeconds,
                           glow: borderGlow,
                           flashToken: flashToken,
                           previewFrozen: previewFrozen,
                           previewPhase: previewPhase)
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge)
                .font(Font(palette.uiFont(.caption) as CTFont).weight(.semibold))
                .foregroundColor(accentColor)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .offset(x: 4, y: -4)
        }
    }
}

// MARK: - Themed drop shadow (Elevation.dp2 token)

private struct PillShadow: ViewModifier {
    let palette: ResolvedPalette
    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            let s = palette.shadow(.dp2)   // (opacity: Float, radius: CGFloat, offsetY: CGFloat)
            content.shadow(color: .black.opacity(Double(s.opacity)),
                           radius: s.radius, x: 0, y: s.offsetY)
        } else {
            content
        }
    }
}

// MARK: - Underline bar shape: a flat horizontal line (stroked = a glowing bar)

/// A single horizontal line across the vertical centre. Stroked by
/// `AnimatedBorderView` it reads as a bar — the underline shape's effect rim,
/// reusing the neon engine instead of a bespoke fill path.
struct HBarShape: SwiftUI.Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Tag shape: rounded rect + left-pointing triangle (one path)

struct TagShape: SwiftUI.Shape {
    var radius: CGFloat = 10
    var notch: CGFloat = 6        // how far the point pokes left of the body
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let body = CGRect(x: rect.minX + notch, y: rect.minY,
                          width: max(0, rect.width - notch), height: rect.height)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius))
        var tri = Path()
        tri.move(to: CGPoint(x: body.minX, y: rect.midY - 4))
        tri.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        tri.addLine(to: CGPoint(x: body.minX, y: rect.midY + 4))
        tri.closeSubpath()
        p.addPath(tri)
        return p
    }
}
