// ThemeKitUI — ThemedChipView: the compact themed token (MUI <Chip> fused with
// HTML <kbd>), SwiftUI-native. Draws the SAME anatomy as ThemeKit's AppKit
// `ThemedChip` (which stays for AppKit hosts): `filled` = a calm `muted` wash
// for neutral / an opaque role fill otherwise, `outlined` = a stroked clear box
// whose role stroke rests at role@0.5 and sharpens on interaction, `keycap` = a
// mono, key-shaped <kbd> — each behind the variant's hover / press state layer,
// with the themed `primary` focus ring. There is NO elevation (MUI chips are
// flat) and no group seam; the pill corner is height/2, the keycap a 5 pt key.
//
// The chip is the one control with TWO independent affordances, so it does not
// reuse the ThemedControl press Bool: a `PressTarget` says what a press armed
// (the body vs the trailing ×) and each lights only its own target — the
// AppKit widget's `deleteHitRect` routing, re-expressed as one gesture plus one
// continuous-hover stream over the chip's own coordinate space. Interaction is
// OPT-IN: `clickable` gates hover / press / Space, `deletable` gates the × and
// Backspace / Delete, and a chip with neither is fully static. Space activates
// WITHOUT the keyboard flash — ThemedChip overrides `keyDown` and calls
// `activate()` directly, never touching the flash helper the button uses.
// The `preview…` overrides force each state for deterministic capture.
//
// `enabled` is this view's OWN argument, matching ThemedButtonView /
// ThemedFABView / ThemedCheckboxView — an ancestor `.disabled(true)` blocks hit
// testing but does not paint the disabled state. That is the opposite of the
// NSViewRepresentable bridge, and the swap fixes the direction that mattered:
// SwiftUI drives a hosted `NSControl`'s `isEnabled` from
// `@Environment(\.isEnabled)` AFTER `updateNSView`, so the bridge's
// `c.isEnabled = enabled` was clobbered on every update and
// `ThemedChipView(enabled: false)` rendered fully ENABLED (measured 2026-08-02;
// `testDisabledGreysTheFillAndInkRegardlessOfRole` is the regression guard).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import Motion

public struct ThemedChipView: View {
    @Environment(\.sillPalette) private var ambientPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var variant: ThemedChip.Variant
    var size: ThemedChip.Size
    var role: ThemedChip.Role
    var title: String
    var leading: String?
    var selected: Bool
    var enabled: Bool
    var previewHovered: Bool
    var previewPressed: Bool
    var previewFocused: Bool
    var clickable: Bool
    var deletable: Bool
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    /// What a press armed, so the release routes to the right action.
    private enum PressTarget { case none, body, delete }

    @State private var hovered = false
    @State private var deleteHovered = false
    @State private var pressTarget: PressTarget = .none
    /// Whether the pointer is still over the armed target (gates the press
    /// visual; a drag off cancels it, a drag back re-arms).
    @State private var pressArmed = false
    @State private var chipSize: CGSize = .zero
    /// The × icon's own frame in chip space (`.null` ⇒ no ×).
    @State private var deleteFrame: CGRect = .null
    @FocusState private var keyFocused: Bool

    /// The chip's own coordinate space — hover, press and the × frame are all
    /// measured in it, so the AppKit `deleteHitRect.contains(p)` routing
    /// translates literally.
    private let chipSpace = "sill.themedChip"

    public init(palette: ResolvedPalette? = nil, variant: ThemedChip.Variant = .filled,
                size: ThemedChip.Size = .medium, role: ThemedChip.Role = .neutral,
                title: String = "Tag", leading: String? = nil, selected: Bool = false,
                enabled: Bool = true, previewHovered: Bool = false,
                previewPressed: Bool = false, previewFocused: Bool = false,
                clickable: Bool = false, deletable: Bool = false,
                onTap: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.explicitPalette = palette
        self.variant = variant
        self.size = size
        self.role = role
        self.title = title
        self.leading = leading
        self.selected = selected
        self.enabled = enabled
        self.previewHovered = previewHovered
        self.previewPressed = previewPressed
        self.previewFocused = previewFocused
        self.clickable = clickable
        self.deletable = deletable
        self.onTap = onTap
        self.onDelete = onDelete
    }

    // MARK: - Metrics (mirror ThemedChip — MUI v5 Chip values; small 24 /
    // medium 32. A divergence here shows up as a before/after diff in prism, so
    // keep the two in lockstep)

    private struct Metrics {
        let height, hpad, radius, font, iconPt, gap, minWidth, border, outerAdj: CGFloat
    }
    private var m: Metrics {
        let small = size == .small
        let h: CGFloat = small ? 24 : 32
        let hpad: CGFloat
        switch variant {
        case .keycap:            hpad = small ? 6 : 8
        case .filled, .outlined: hpad = small ? 8 : 12
        }
        return Metrics(height: h, hpad: hpad,
                       radius: variant == .keycap ? CGFloat(Radius.sm) : h / 2,  // pill, except the key
                       font: 13, iconPt: small ? 14 : 16, gap: 5,
                       minWidth: variant == .keycap ? h : 0,   // a 1-glyph key is square
                       border: (variant == .outlined || variant == .keycap) ? 1 : 0,
                       // Tuck a leading icon / × toward the edge by eating into
                       // the padding (MUI's negative outer icon margin).
                       outerAdj: -2)
    }

    // MARK: - Interaction gates (ThemedChip's `appearanceGate` / `focusGate`)

    /// Hover / press / focus PAINT shows only on a clickable body.
    private var isClickable: Bool { clickable && enabled }
    private var isDeletable: Bool { deletable }
    /// Focusable when EITHER affordance is live, so Backspace / Delete can
    /// reach a delete-only chip whose body never lights.
    private var isInteractive: Bool { enabled && (clickable || deletable) }

    // MARK: - Effective state (real || preview, AND the appearance gate)

    private var fxHovered: Bool { (hovered || previewHovered) && isClickable }
    private var fxPressed: Bool {
        ((pressTarget == .body && pressArmed) || previewPressed) && isClickable
    }
    private var fxFocused: Bool { (keyFocused || previewFocused) && isClickable }
    /// The ring is gated by `isInteractive`, NOT by the appearance gate.
    private var showFocusRing: Bool { (keyFocused || previewFocused) && isInteractive }

    // MARK: - Colours (the same role math as ThemedChip)

    /// `neutral` ⇒ `foreground`, matching the chip's prior direct
    /// `palette.foreground`.
    private var controlRole: ControlRole {
        switch role {
        case .neutral:   return .neutral
        case .primary:   return .primary
        case .secondary: return .secondary
        case .error:     return .error
        }
    }
    private var roleColor: NSColor { palette.color(for: controlRole) }

    /// The selected wash: the canonical `selection` for neutral, a role wash
    /// (≈ MUI's selected tint) otherwise.
    private var selectionFill: NSColor {
        role == .neutral ? palette.selection
                         : roleColor.withAlphaComponent(ResolvedPalette.InkTier.wash.alpha)
    }

    /// Does the resting fill present an OPAQUE role colour (so the ink must be
    /// the contrast black/white)? Only an enabled, unselected, role-coloured
    /// `filled`.
    private var hasOpaqueRoleFill: Bool {
        enabled && variant == .filled && !selected && role != .neutral
    }

    /// The stable fill. Disabled = a neutral wash; keycap = a faint key face;
    /// selected = the selection wash; else the variant's resting fill.
    private var baseFillColor: NSColor {
        guard enabled else {
            return variant == .filled ? palette.ink(.subtle, of: .muted) : .clear
        }
        switch variant {
        case .keycap:
            return palette.ink(.faint, of: .foreground)
        case .filled:
            if selected { return selectionFill }
            return role == .neutral ? palette.ink(.wash, of: .muted) : roleColor
        case .outlined:
            return selected ? selectionFill : .clear
        }
    }

    /// Label + leading-icon ink for the current state.
    private var inkColor: NSColor {
        guard enabled else { return palette.muted }
        if variant == .keycap { return palette.foreground }
        if hasOpaqueRoleFill {
            switch role {
            case .primary:   return palette.onPrimary()
            case .secondary: return palette.onSecondary()
            case .error:     return palette.bestContrast(on: palette.error)
            case .neutral:   return palette.foreground   // unreachable (guarded out)
            }
        }
        // On a translucent / clear surface: the role tint (neutral ⇒ foreground).
        return roleColor
    }

    /// The × tint: muted at rest, emphasised on hover (error role ⇒ `error`).
    /// Keyed off the RAW `previewHovered`, not the gated merge — a preview
    /// lights the × on a non-clickable chip too.
    private var deleteColor: NSColor {
        guard enabled else { return palette.ink(.subtle, of: .muted) }
        if deleteHovered || previewHovered {
            return role == .error ? palette.error : palette.foreground
        }
        return palette.muted
    }

    /// The hover / press / focus state layer — only on a clickable body.
    /// Contrast-ink overlay on an opaque role fill, role / foreground tint
    /// otherwise.
    private var overlayColor: NSColor {
        guard isClickable else { return .clear }
        if hasOpaqueRoleFill {
            if fxPressed { return palette.stateOverlay(.pressed, on: .contrastInk(on: roleColor)) }
            if fxHovered { return palette.stateOverlay(.hover, on: .contrastInk(on: roleColor)) }
            return .clear
        }
        let tint = role == .neutral ? palette.foreground : roleColor
        if fxPressed              { return palette.stateOverlay(.pressed, on: .roleTint(tint)) }
        if fxHovered || fxFocused { return palette.stateOverlay(.hover, on: .roleTint(tint)) }
        return .clear
    }

    /// Border (outlined / keycap only): neutral / keycap ⇒ the `border` role; a
    /// role outline rests at role@0.5 and goes full on interaction / selection.
    private var borderColor: NSColor {
        switch variant {
        case .filled:  return .clear
        case .keycap:  return palette.border
        case .outlined:
            if !enabled { return palette.disabledStroke }
            if role == .neutral { return palette.border }
            if selected || fxHovered || fxPressed || fxFocused { return roleColor }
            return palette.restingStroke(of: roleColor)
        }
    }

    // MARK: - Body

    public var body: some View {
        content
            .background { surface }
            .overlay { focusRing }
            .animation(interaction, value: fxHovered)
            .animation(interaction, value: fxPressed)
            .animation(interaction, value: fxFocused)
            .animation(interaction, value: deleteHovered)
            .contentShape(Rectangle())   // the AppKit hit area is the full bounds rect
            .coordinateSpace(.named(chipSpace))
            .onGeometryChange(for: CGSize.self, of: \.size) { chipSize = $0 }
            .onContinuousHover(coordinateSpace: .named(chipSpace)) { phase in
                guard enabled else { return }
                switch phase {
                case .active(let p): updateHover(at: p)
                case .ended:         clearHover()
                }
            }
            .gesture(pressGesture, isEnabled: enabled)
            .focusable(isInteractive)
            .focusEffectDisabled()   // the ring above is the themed replacement
            .onKeyPress(.space, phases: .down) { _ in       // .down only ⇒ auto-repeat never re-fires
                guard isClickable else { return .ignored }
                activateBody()
                return .handled
            }
            .onKeyPress(.delete, phases: .down) { _ in deleteKey() }
            .onKeyPress(.deleteForward, phases: .down) { _ in deleteKey() }
            .onChange(of: enabled) { _, new in
                // A disable can strand an in-flight hover / press with no
                // matching exit / up event (the ThemedControl stuck-hover
                // cleanup + ThemedChip's `didDisable`).
                if !new {
                    hovered = false; deleteHovered = false
                    pressTarget = .none; pressArmed = false
                }
            }
            .accessibilityRepresentation {
                // `.button` while clickable, `.staticText` otherwise — unlike
                // ThemedButton's fixed role, the chip's is dynamic.
                Group {
                    if isClickable {
                        Button(title) { activateBody() }
                    } else {
                        Text(title)
                    }
                }
                .disabled(!enabled)
                .accessibilityValue(selected ? "1" : "0")
            }
    }

    // MARK: - Surface
    //
    // The shape is `.circular`, NOT SwiftUI's default `.continuous`: the AppKit
    // widget's corner is `CALayer.cornerRadius`, a true circular arc, and at the
    // pill's radius = height/2 a continuous (squircle) corner visibly flattens
    // the caps and notches the outlined stroke (caught in the prism before/after
    // — nothing in the colour probes could see it). `Capsule` IS that pill, so
    // the two branches are shapes rather than one radius.

    @ViewBuilder private var surface: some View {
        if variant == .keycap {
            surfaceStack(RoundedRectangle(cornerRadius: m.radius, style: .circular))
        } else {
            surfaceStack(Capsule(style: .circular))
        }
    }

    /// Fill · state layer · border, all on the SAME shape — which is also what
    /// clips the state layer (the AppKit `fillLayer.masksToBounds` child).
    private func surfaceStack<S: InsettableShape>(_ s: S) -> some View {
        ZStack {
            s.fill(Color(nsColor: baseFillColor))
            s.fill(Color(nsColor: overlayColor))
            s.strokeBorder(Color(nsColor: borderColor), lineWidth: m.border)
        }
    }

    /// `concentricRingPath`: the box outset by 2 with its radius bumped by the
    /// same 2. For the pill that is just the outset capsule.
    @ViewBuilder private var focusRing: some View {
        Group {
            if variant == .keycap {
                RoundedRectangle(cornerRadius: m.radius + ringOutset, style: .circular)
                    .stroke(Color(nsColor: palette.primary), lineWidth: 2)
            } else {
                Capsule(style: .circular)
                    .stroke(Color(nsColor: palette.primary), lineWidth: 2)
            }
        }
        .padding(-ringOutset)
        .opacity(showFocusRing ? 1 : 0)
    }

    /// The leading Phosphor glyph, resolved once (nil ⇒ the slot is absent, and
    /// its padding adjustment drops with it — the `leadingImageSize` gate).
    private var leadingIcon: NSImage? {
        leading.flatMap { phosphorImage($0, pt: m.iconPt) }
    }
    /// The trailing × (`x-circle`, matching ThemedComboBox's clear glyph).
    private var deleteIcon: NSImage? {
        isDeletable ? phosphorImage("x-circle", pt: m.iconPt) : nil
    }

    /// The centred leading-icon / title / × row — `gap` between PRESENT pieces
    /// only, per-side padding pulled in by the negative outer icon margin when
    /// that side has an icon, floored at `minWidth` (the keycap square).
    private var content: some View {
        HStack(spacing: m.gap) {
            if let icon = leadingIcon { iconView(icon, tint: inkColor) }
            if !title.isEmpty {
                Text(title)                       // drawn AS-IS — chips are not uppercased
                    .font(Font(titleFont as CTFont))
                    .foregroundColor(Color(nsColor: inkColor))
                    .fixedSize()
                    .frame(width: titleWidth)
            }
            if let x = deleteIcon {
                iconView(x, tint: deleteColor)
                    .onGeometryChange(for: CGRect.self,
                                      of: { $0.frame(in: .named(chipSpace)) }) { deleteFrame = $0 }
            }
        }
        .padding(.leading, m.hpad + (leadingIcon != nil ? m.outerAdj : 0))
        .padding(.trailing, m.hpad + (deleteIcon != nil ? m.outerAdj : 0))
        .frame(height: m.height)
        .frame(minWidth: m.minWidth)
    }

    /// One icon slot: template ⇒ tinted, multi-colour ⇒ drawn raw — the
    /// `applyIconSlot` contract.
    @ViewBuilder
    private func iconView(_ icon: NSImage, tint: NSColor) -> some View {
        if icon.isTemplate {
            Image(nsImage: icon)
                .renderingMode(.template)
                .foregroundColor(Color(nsColor: tint))
        } else {
            Image(nsImage: icon)
        }
    }

    private var titleFont: NSFont {
        variant == .keycap
            ? .monospacedSystemFont(ofSize: m.font, weight: .medium)
            : palette.uiFont(.body)
    }

    /// The label slot, measured exactly as `ThemedChip.rebuildTitle` measures
    /// it — `ceil(attributedWidth) + 2`. SwiftUI's own `Text` layout is ~2.5 pt
    /// tighter, and since a chip HUGS its label that showed up as every chip
    /// being narrower than the AppKit one (measured, not eyeballed). Keeping
    /// the AppKit yardstick keeps the two in lockstep.
    private var titleWidth: CGFloat? {
        guard !title.isEmpty else { return nil }
        let attr = NSAttributedString(string: title, attributes: [.font: titleFont])
        return ceil(attr.size().width) + 2
    }

    /// `ThemedControl.focusRingOutset` — the ring sits 2 pt outside the box.
    private var ringOutset: CGFloat { CGFloat(Space.xxs) }

    /// The `layerTxn(animated: true)` curve — and `nil` (snap) under Reduce
    /// Motion, so the state-layer cross-fade settles instantly.
    private var interaction: Animation? {
        reduceMotion ? nil : .easeOut(duration: ThemedTransition.Duration.enter)
    }

    // MARK: - Hit routing (the AppKit `deleteHitRect` geometry)

    /// The × hit-target, expanded by half a gap on each side and to the full
    /// chip height so it is easy to click.
    private var deleteHitRect: CGRect {
        guard !deleteFrame.isNull, deleteIcon != nil else { return .null }
        return CGRect(x: deleteFrame.minX - m.gap / 2, y: 0,
                      width: deleteFrame.width + m.gap, height: chipSize.height)
    }

    private var boundsRect: CGRect { CGRect(origin: .zero, size: chipSize) }

    /// Track body-hover (clickable) and ×-hover (deletable) separately so each
    /// affordance lights only its own target.
    private func updateHover(at p: CGPoint) {
        let overDelete = isDeletable && deleteHitRect.contains(p)
        let overBody = boundsRect.contains(p) && !overDelete
        guard hovered != overBody || deleteHovered != overDelete else { return }
        withAnimation(interaction) { hovered = overBody; deleteHovered = overDelete }
    }

    private func clearHover() {
        guard hovered || deleteHovered else { return }
        withAnimation(interaction) { hovered = false; deleteHovered = false }
    }

    /// What a press at `p` arms — the × wins over the body (the AppKit
    /// `mouseDown` order).
    private func target(at p: CGPoint) -> PressTarget {
        guard enabled else { return .none }
        if isDeletable, deleteHitRect.contains(p) { return .delete }
        return isClickable ? .body : .none
    }

    /// Is `p` still over the armed target?
    private func pointer(_ p: CGPoint, over target: PressTarget) -> Bool {
        switch target {
        case .delete: return deleteHitRect.contains(p)
        case .body:   return boundsRect.contains(p) && !(isDeletable && deleteHitRect.contains(p))
        case .none:   return false
        }
    }

    /// Press with drag-out cancel, routed per target (the mouseDown / Dragged /
    /// Up trio). Arming happens on the first change, which a
    /// `minimumDistance: 0` drag delivers on press.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(chipSpace))
            .onChanged { v in
                if pressTarget == .none {
                    let t = target(at: v.startLocation)
                    guard t != .none else { return }
                    pressTarget = t
                    withAnimation(interaction) { pressArmed = true }
                }
                let inside = pointer(v.location, over: pressTarget)
                if pressArmed != inside { withAnimation(interaction) { pressArmed = inside } }
            }
            .onEnded { v in
                // A press so brief that `onChanged` never landed still arms off
                // the start location, so the tap is not swallowed.
                let t = pressTarget != .none ? pressTarget : target(at: v.startLocation)
                pressTarget = .none
                withAnimation(interaction) { pressArmed = false }
                guard enabled, pointer(v.location, over: t) else { return }
                switch t {
                case .delete: onDelete?()
                case .body:   activateBody()
                case .none:   break
                }
            }
    }

    // MARK: - Activation

    /// Space activates a clickable chip. Unlike the button there is NO flash —
    /// `ThemedChip.keyDown` calls `activate()` straight through.
    private func activateBody() {
        guard isClickable else { return }
        onTap?()
    }

    /// Backspace / forward-Delete fire the × while the chip is focused (MUI).
    private func deleteKey() -> KeyPress.Result {
        guard enabled, isDeletable else { return .ignored }
        onDelete?()
        return .handled
    }
}
