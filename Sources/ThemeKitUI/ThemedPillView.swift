import SwiftUI
import AppKit
import Palette
import PaletteKit

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
                opacity: Double = 1) {
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
        return (Text(parts.prefix).foregroundColor(prefixColor)
                + Text(parts.suffix).foregroundColor(foreground))
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

    /// Underline: no surface/border — a 2pt accent bar under the label.
    private var underlineContent: some View {
        labelView
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(state == .miss ? errorColor : accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
            .overlay(alignment: .topTrailing) { badgeView }
    }

    /// Tri-state border. matched = accent stroke + a native glow on the stroke
    /// (fill UNCHANGED); miss = error stroke; idle = accent hairline.
    @ViewBuilder
    private var borderOverlay: some View {
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
