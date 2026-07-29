// ThemeKitUI — ThemedButtonView: the themed three-variant push button, SwiftUI-
// native. Draws the SAME anatomy as ThemeKit's AppKit `ThemedButton` (which
// stays for AppKit hosts and for ThemedButtonGroup's grouped members): `text` =
// bare role-ink label, `contained` = role fill + the dp2→dp4/dp6/dp8 elevation
// ladder, `outlined` = the resting role@0.5 stroke that sharpens to full role
// on interaction — each behind the variant's hover / press state layer, with
// the themed `primary` focus ring (role-agnostic, per `ThemedControl`).
// Interaction parity with the `ThemedControl` machinery: hover, press with drag-out
// cancel, Tab focus + Space activation with the auto-repeat and in-flight
// flash guards, and the 0.16 s ease-out interaction transitions. The
// `preview…` overrides force each state for deterministic capture. Grouping
// (roundedCorners / drawnBorderEdges / groupedShadow) is a ThemedButtonGroup
// composition concern and stays on the AppKit widget — this view is the
// STANDALONE button.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import Motion

public struct ThemedButtonView: View {
    @Environment(\.sillPalette) private var ambientPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var variant: ThemedButton.Variant
    var size: ThemedButton.Size
    var role: ThemedButton.Role
    var title: String
    var leading: String?
    var trailing: String?
    var leadingImage: NSImage?      // pre-resolved icon (SVG / logo / …)
    var trailingImage: NSImage?
    var fullWidth: Bool
    var enabled: Bool
    var previewHovered: Bool
    var previewPressed: Bool
    var previewFocused: Bool
    var onTap: (() -> Void)?

    @State private var hovered = false
    @State private var pressed = false
    @State private var flashing = false      // a keyboard-flash activation is in flight
    @State private var hitSize: CGSize = .zero
    @FocusState private var keyFocused: Bool

    public init(palette: ResolvedPalette? = nil, variant: ThemedButton.Variant = .text,
                size: ThemedButton.Size = .medium, role: ThemedButton.Role = .primary,
                title: String = "Button", leading: String? = nil, trailing: String? = nil,
                leadingImage: NSImage? = nil, trailingImage: NSImage? = nil,
                fullWidth: Bool = false, enabled: Bool = true,
                previewHovered: Bool = false, previewPressed: Bool = false,
                previewFocused: Bool = false, onTap: (() -> Void)? = nil) {
        self.explicitPalette = palette
        self.variant = variant
        self.size = size
        self.role = role
        self.title = title
        self.leading = leading
        self.trailing = trailing
        self.leadingImage = leadingImage
        self.trailingImage = trailingImage
        self.fullWidth = fullWidth
        self.enabled = enabled
        self.previewHovered = previewHovered
        self.previewPressed = previewPressed
        self.previewFocused = previewFocused
        self.onTap = onTap
    }

    // MARK: - Metrics (mirror ThemedButton — MUI v5 Button values; heights are
    // the shared 30/36/42 control ladder (ThemeKit's `controlHeight`, internal
    // to that module) — a divergence here shows up in the prism before/after
    // comparison, so keep the two in lockstep)

    private struct Metrics {
        let height, hpad, radius, font, minWidth, iconPt, gap, outerAdj: CGFloat
    }
    private var m: Metrics {
        let height: CGFloat = size == .small ? 30 : size == .medium ? 36 : 42
        let font:   CGFloat = size == .small ? 13 : size == .medium ? 14 : 15
        let iconPt: CGFloat = size == .small ? 18 : size == .medium ? 20 : 22
        // MUI's negative outer icon margin (−2 small / −4 otherwise) tucks an
        // icon toward the edge by eating into the horizontal padding.
        let outerAdj: CGFloat = size == .small ? -2 : -4
        let hpad: CGFloat
        switch (variant, size) {
        case (.text, .small):       hpad = 5
        case (.text, .medium):      hpad = 8
        case (.text, .large):       hpad = 11
        case (.contained, .small):  hpad = 10
        case (.contained, .medium): hpad = 16
        case (.contained, .large):  hpad = 22
        case (.outlined, .small):   hpad = 9    // 1 pt less than contained: absorbs the border
        case (.outlined, .medium):  hpad = 15
        case (.outlined, .large):   hpad = 21
        }
        return Metrics(height: height, hpad: hpad, radius: CGFloat(Radius.sm), font: font,
                       minWidth: 64, iconPt: iconPt, gap: CGFloat(Space.md), outerAdj: outerAdj)
    }

    // MARK: - Effective state (real || preview, the fx merges)

    private var fxHovered: Bool { (hovered || previewHovered) && enabled }
    private var fxPressed: Bool { (pressed || previewPressed) && enabled }
    private var fxFocused: Bool { (keyFocused || previewFocused) && enabled }

    // MARK: - Colours (the same role math as ThemedButton)

    private var roleColor: NSColor {
        switch role {
        case .primary:   return palette.primary
        case .secondary: return palette.secondary
        case .error:     return palette.error
        }
    }
    /// Label + icon ink for the current state.
    private var titleColor: NSColor {
        guard enabled else { return palette.muted }
        switch variant {
        case .contained:        return palette.bestContrast(on: roleColor)
        case .text, .outlined:  return roleColor
        }
    }
    /// The stable fill (never animated on hover — the darken is the overlay).
    private var baseFillColor: NSColor {
        switch variant {
        case .contained:        return enabled ? roleColor : palette.ink(.subtle, of: .muted)
        case .text, .outlined:  return .clear
        }
    }
    /// The hover / press / focus state layer: contained = contrast ink on the
    /// role fill; text / outlined = the role colour at MUI's alpha band (and
    /// focus paints the hover tier — unlike contained, whose focus is ring +
    /// elevation only).
    private var overlayColor: NSColor {
        guard enabled else { return .clear }
        switch variant {
        case .contained:
            if fxPressed { return palette.stateOverlay(.pressed, on: .contrastInk(on: roleColor)) }
            if fxHovered { return palette.stateOverlay(.hover, on: .contrastInk(on: roleColor)) }
            return .clear
        case .text, .outlined:
            if fxPressed              { return palette.stateOverlay(.pressed, on: .roleTint(roleColor)) }
            if fxHovered || fxFocused { return palette.stateOverlay(.hover, on: .roleTint(roleColor)) }
            return .clear
        }
    }
    /// Outlined stroke: resting role@0.5 (MUI), full role on interaction,
    /// neutral `border` when disabled.
    private var borderColor: NSColor {
        guard variant == .outlined else { return .clear }
        if !enabled { return palette.disabledStroke }
        if fxHovered || fxPressed || fxFocused { return roleColor }
        return palette.restingStroke(of: roleColor)
    }
    /// Contained elevation per state (the #13 dp ladder: rest dp2 → hover dp4 →
    /// focus dp6 → press dp8); flat otherwise. Order pressed → focused → hovered
    /// so adding an interaction never LOWERS the shadow. `ElevationToken.dy` is
    /// y-down — SwiftUI's shadow direction (no AppKit y-up negation).
    private var elevation: ElevationToken {
        guard variant == .contained, enabled else { return Elevation.flat.token }
        if fxPressed { return Elevation.dp8.token }
        if fxFocused { return Elevation.dp6.token }
        if fxHovered { return Elevation.dp4.token }
        return Elevation.dp2.token
    }

    public var body: some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: m.radius)
                        .fill(Color(nsColor: baseFillColor))
                        .shadow(color: .black.opacity(elevation.opacity),
                                radius: CGFloat(elevation.blur),
                                x: 0, y: CGFloat(elevation.dy))
                    RoundedRectangle(cornerRadius: m.radius)
                        .fill(Color(nsColor: overlayColor))
                    RoundedRectangle(cornerRadius: m.radius)
                        .strokeBorder(Color(nsColor: borderColor), lineWidth: 1)
                        .opacity(variant == .outlined ? 1 : 0)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: m.radius)
                    .inset(by: -ringOutset)
                    .stroke(Color(nsColor: palette.primary), lineWidth: 2)
                    .opacity(fxFocused ? 1 : 0)
            }
            .animation(interaction, value: fxHovered)
            .animation(interaction, value: fxPressed)
            .animation(interaction, value: fxFocused)
            .contentShape(Rectangle())   // the AppKit hit area is the full bounds rect
            .onGeometryChange(for: CGSize.self, of: \.size) { hitSize = $0 }
            .onHover { inside in
                guard enabled else { return }
                withAnimation(interaction) { hovered = inside }
            }
            .gesture(pressGesture, isEnabled: enabled)
            .focusable(enabled)
            .focusEffectDisabled()   // the ring above is the themed replacement
            .onKeyPress(.space, phases: .down) { _ in    // .down only ⇒ auto-repeat never re-fires
                keyboardActivate()
                return .handled
            }
            .onChange(of: enabled) { _, new in
                // A disable can strand an in-flight hover / press with no
                // matching exit / up event (the ThemedControl stuck-hover cleanup).
                if !new { hovered = false; pressed = false }
            }
            .accessibilityRepresentation {
                // The original-case title (uppercasing is visual only).
                Button(title) { fire() }
                    .disabled(!enabled)
            }
    }

    /// The centred leading-icon / title / trailing-icon row. Per-side padding =
    /// `hpad`, pulled in by MUI's negative outer icon margin when that side has
    /// an icon; the whole row floors at `minWidth` (64) and stretches (content
    /// still centred) under `fullWidth`.
    @ViewBuilder
    private var content: some View {
        HStack(spacing: m.gap) {
            iconView(leadingImage, slug: leading)
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(Font(palette.uiFont(m.font, .medium) as CTFont))
                    .kerning(0.4)
                    .foregroundColor(Color(nsColor: titleColor))
                    .fixedSize()
            }
            iconView(trailingImage, slug: trailing)
        }
        .padding(.leading, m.hpad + (hasIcon(leadingImage, leading) ? m.outerAdj : 0))
        .padding(.trailing, m.hpad + (hasIcon(trailingImage, trailing) ? m.outerAdj : 0))
        .frame(height: m.height)
        .frame(minWidth: m.minWidth)
        .frame(maxWidth: fullWidth ? .infinity : nil)
    }

    private func hasIcon(_ image: NSImage?, _ slug: String?) -> Bool {
        image != nil || slug != nil
    }

    /// One icon slot: the pre-resolved `image` wins over the Phosphor slug;
    /// template ⇒ tinted to the label ink, multi-colour ⇒ drawn raw — the
    /// `applyIconSlot` contract.
    @ViewBuilder
    private func iconView(_ image: NSImage?, slug: String?) -> some View {
        if let icon = image ?? slug.flatMap({ phosphorImage($0, pt: m.iconPt) }) {
            if icon.isTemplate {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .foregroundColor(Color(nsColor: titleColor))
            } else {
                Image(nsImage: icon)
            }
        }
    }

    /// `ThemedControl.focusRingOutset` — the ring sits 2 pt outside the box.
    private var ringOutset: CGFloat { CGFloat(Space.xxs) }

    /// The `layerTxn(animated: true)` curve — and `nil` (snap) under Reduce
    /// Motion, so the hover fade and the elevation change settle instantly.
    private var interaction: Animation? {
        reduceMotion ? nil : .easeOut(duration: ThemedTransition.Duration.enter)
    }

    // MARK: - Interaction (the ThemedControl press trio + Space flash)

    /// Press with drag-out cancel: pressed while the pointer is inside, a
    /// release outside abandons the tap (the mouseDown/Dragged/Up trio).
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let inside = CGRect(origin: .zero, size: hitSize).contains(v.location)
                if pressed != inside { withAnimation(interaction) { pressed = inside } }
            }
            .onEnded { v in
                let inside = CGRect(origin: .zero, size: hitSize).contains(v.location)
                withAnimation(interaction) { pressed = false }
                if inside { fire() }
            }
    }

    /// A brief visible press before firing — keyboard activation has no
    /// natural down/up, so synthesize the flash. The `flashing` guard makes a
    /// flash atomic (a second Space inside the window is dropped), and the
    /// deferred fire re-checks `enabled` so an async disable mid-flash
    /// cancels it.
    private func keyboardActivate() {
        guard enabled, !flashing else { return }
        flashing = true
        withAnimation(interaction) { pressed = true }
        Task {
            try? await Task.sleep(for: .seconds(0.12))   // ThemedControl.flashDuration
            flashing = false
            withAnimation(interaction) { pressed = false }
            fire()
        }
    }

    /// The activation primitive — `ThemedButton.activate()` minus the AppKit
    /// target/action channel (the SwiftUI front's only channel is `onTap`).
    private func fire() {
        guard enabled else { return }
        onTap?()
    }
}
