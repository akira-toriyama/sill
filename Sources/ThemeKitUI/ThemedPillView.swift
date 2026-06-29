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

    // NOTE: Task-1 scaffold body = just the label. Task 2 composes the surface,
    // shapes, tri-state border, frost, drop shadow, badge, and motion passthrough.
    public var body: some View {
        labelView.padding(.horizontal, 10).padding(.vertical, 4)
    }
}
