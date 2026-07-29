// ThemeKitUI — ThemedFABView: the themed Floating Action Button, SwiftUI-
// native. Draws the SAME anatomy as ThemeKit's AppKit `ThemedFAB` (which stays
// for AppKit hosts): a circular icon-first accent (or the `extended` icon +
// label pill), `cornerRadius = height / 2`, floating on the dp8 elevation
// shadow that deepens to dp12 on press — behind a hover / press state layer in
// the contrast ink on the role fill, with a themed `primary` focus ring.
// Interaction parity with the `ThemedControl` machinery: hover, press with
// drag-out cancel, Tab focus + Space activation with the auto-repeat and
// in-flight flash guards, and the 0.16 s ease-out interaction transitions.
// The `preview…` overrides force each state for deterministic capture. A
// circular FAB sizes itself to a fixed square, so the explicit frame the
// bridge required at call sites is now optional (but still harmless).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import Motion

public struct ThemedFABView: View {
    @Environment(\.sillPalette) private var ambientPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var variant: ThemedFAB.Variant
    var size: ThemedFAB.Size
    var role: ThemedFAB.Role
    var symbol: String?
    var image: NSImage?          // pre-resolved icon (SVG / logo / …); wins over symbol
    var label: String
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

    public init(palette: ResolvedPalette? = nil, variant: ThemedFAB.Variant = .circular,
                size: ThemedFAB.Size = .large, role: ThemedFAB.Role = .primary,
                symbol: String? = "plus", image: NSImage? = nil, label: String = "",
                enabled: Bool = true, previewHovered: Bool = false,
                previewPressed: Bool = false, previewFocused: Bool = false,
                onTap: (() -> Void)? = nil) {
        self.explicitPalette = palette
        self.variant = variant
        self.size = size
        self.role = role
        self.symbol = symbol
        self.image = image
        self.label = label
        self.enabled = enabled
        self.previewHovered = previewHovered
        self.previewPressed = previewPressed
        self.previewFocused = previewFocused
        self.onTap = onTap
    }

    // MARK: - Metrics (mirror ThemedFAB — MUI v5 Fab values; circular diameters
    // 40/48/56, extended heights 34/40/48 — a divergence here shows up in the
    // prism before/after comparison, so keep the two in lockstep)

    private struct Metrics {
        let diameter, height, hpad, iconPt, font, gap: CGFloat
    }
    private var m: Metrics {
        let diameter: CGFloat = size == .small ? 40 : size == .medium ? 48 : 56
        let height:   CGFloat = size == .small ? 34 : size == .medium ? 40 : 48
        let iconPt:   CGFloat = size == .small ? 20 : size == .medium ? 24 : 28
        let font:     CGFloat = size == .small ? 13 : 14
        let hpad:     CGFloat = size == .small ? 8 : 16
        return Metrics(diameter: diameter, height: height, hpad: hpad,
                       iconPt: iconPt, font: font, gap: CGFloat(Space.md))
    }

    // MARK: - Effective state (real || preview, the fx merges)

    private var fxHovered: Bool { (hovered || previewHovered) && enabled }
    private var fxPressed: Bool { (pressed || previewPressed) && enabled }
    private var fxFocused: Bool { (keyFocused || previewFocused) && enabled }

    // MARK: - Colours (the same role math as ThemedFAB)

    private var roleColor: NSColor {
        switch role {
        case .primary:   return palette.primary
        case .secondary: return palette.secondary
        }
    }
    /// Best-contrast ink on the role fill (`onPrimary` / `onSecondary`) — so a
    /// secondary FAB on a neon theme still gets a legible glyph.
    private var roleInk: NSColor {
        switch role {
        case .primary:   return palette.onPrimary()
        case .secondary: return palette.onSecondary()
        }
    }
    /// Icon + extended-label ink for the current state (role contrast / muted).
    private var inkColor: NSColor { enabled ? roleInk : palette.disabledInk }
    /// The stable fill (never animated on hover — the darken is the overlay).
    private var baseFillColor: NSColor {
        enabled ? roleColor : palette.disabledFill
    }
    /// The hover / press state layer: the contrast ink on the role fill at
    /// MUI's hover / active alpha. Focus shows the ring only (no wash).
    private var overlayColor: NSColor {
        guard enabled else { return .clear }
        if fxPressed { return palette.stateOverlay(.pressed, on: .contrastInk(on: roleColor)) }
        if fxHovered { return palette.stateOverlay(.hover, on: .contrastInk(on: roleColor)) }
        return .clear
    }
    /// FAB elevation: resting dp8, deepening to dp12 on press — hover / focus
    /// do NOT bump it (a FAB is already raised). `ElevationToken.dy` is y-down,
    /// which is ALSO SwiftUI's shadow direction (the AppKit widget negated it
    /// for its y-up layer space).
    private var elevation: ElevationToken {
        guard enabled else { return Elevation.flat.token }
        return (fxPressed ? Elevation.dp12 : Elevation.dp8).token
    }

    public var body: some View {
        content
            .background {
                ZStack {
                    Capsule()
                        .fill(Color(nsColor: baseFillColor))
                        .shadow(color: .black.opacity(elevation.opacity),
                                radius: CGFloat(elevation.blur),
                                x: 0, y: CGFloat(elevation.dy))
                    Capsule().fill(Color(nsColor: overlayColor))
                }
            }
            .overlay {
                Capsule()
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
                // The original-case label (uppercasing is visual only); also the
                // AX name for a circular FAB, which draws no text.
                Button(label) { fire() }
                    .disabled(!enabled)
            }
    }

    /// The centred content row: the icon (the WHOLE control for `circular`),
    /// plus the uppercased tracked label for `extended`.
    @ViewBuilder
    private var content: some View {
        switch variant {
        case .circular:
            iconView
                .frame(width: m.diameter, height: m.diameter)
        case .extended:
            HStack(spacing: m.gap) {
                iconView
                if !label.isEmpty {
                    Text(label.uppercased())
                        .font(Font(palette.uiFont(m.font, .medium) as CTFont))
                        .kerning(0.4)
                        .foregroundColor(Color(nsColor: inkColor))
                        .fixedSize()
                }
            }
            .padding(.horizontal, m.hpad)
            .frame(height: m.height)
            .frame(minWidth: m.height)
        }
    }

    /// The icon slot: `image` (pre-resolved) wins over the Phosphor `symbol`;
    /// template ⇒ tinted to the state ink, multi-colour ⇒ drawn raw — the
    /// `applyIconSlot` contract.
    @ViewBuilder
    private var iconView: some View {
        if let icon = image ?? symbol.flatMap({ phosphorImage($0, pt: m.iconPt) }) {
            if icon.isTemplate {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .foregroundColor(Color(nsColor: inkColor))
            } else {
                Image(nsImage: icon)
            }
        }
    }

    /// `ThemedControl.focusRingOutset` — the ring sits 2 pt outside the pill.
    private var ringOutset: CGFloat { CGFloat(Space.xxs) }

    /// The `layerTxn(animated: true)` curve — and `nil` (snap) under Reduce
    /// Motion, so the hover fade and the elevation deepen settle instantly.
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

    /// The activation primitive — `ThemedFAB.activate()` minus the AppKit
    /// target/action channel (the SwiftUI front's only channel is `onTap`).
    private func fire() {
        guard enabled else { return }
        onTap?()
    }
}
