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
// `preview…` overrides force each state for deterministic capture.
//
// `grouping` carries the joined-segment chrome — the SwiftUI mirror of the
// AppKit button's `roundedCorners` / `drawnBorderEdges` / `groupedShadow`.
// It lives HERE, not in the group, because the outlined border has to sharpen
// from `restingStroke` to the full role on THIS member's own hover / press /
// focus, and those are `@State` / `@FocusState` private to this view: a
// container drawing the seam from outside cannot see them. `nil` = standalone,
// which is byte-identical to a plain rounded rect.

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
    var grouping: Grouping?
    var onTap: (() -> Void)?

    /// Joined-segment chrome. A `ThemedButtonGroup` member rounds only the
    /// group's OUTER corners, drops the shared seam edge so two abutting
    /// strokes collapse to one hairline, and forgoes its own elevation so the
    /// group can own one continuous shadow. The vocabulary is the AppKit
    /// widget's, verbatim — `ThemedButtonGroup`'s position → corners / edges
    /// tables port line-for-line.
    /// `CACornerMask` is a QuartzCore `OptionSet` that ships neither `Hashable`
    /// nor `Sendable`, so both are written out here over the raw bit patterns —
    /// three PODs, no reference state.
    public struct Grouping: Hashable, @unchecked Sendable {
        public var roundedCorners: CACornerMask
        public var drawnBorderEdges: ThemedButton.BorderEdges
        public var groupedShadow: Bool

        /// The standalone default: all four corners, a closed perimeter, its
        /// own elevation.
        public static let standalone = Grouping()

        public init(roundedCorners: CACornerMask = .themedAllCorners,
                    drawnBorderEdges: ThemedButton.BorderEdges = .all,
                    groupedShadow: Bool = false) {
            self.roundedCorners = roundedCorners
            self.drawnBorderEdges = drawnBorderEdges
            self.groupedShadow = groupedShadow
        }

        public static func == (a: Grouping, b: Grouping) -> Bool {
            a.roundedCorners == b.roundedCorners
                && a.drawnBorderEdges == b.drawnBorderEdges
                && a.groupedShadow == b.groupedShadow
        }
        public func hash(into h: inout Hasher) {
            h.combine(roundedCorners.rawValue)
            h.combine(drawnBorderEdges.rawValue)
            h.combine(groupedShadow)
        }
    }

    private var g: Grouping { grouping ?? .standalone }

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
                previewFocused: Bool = false, grouping: Grouping? = nil,
                onTap: (() -> Void)? = nil) {
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
        self.grouping = grouping
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
                    SeamShape(corners: g.roundedCorners, radius: m.radius)
                        .fill(Color(nsColor: baseFillColor))
                        // `groupedShadow` zeroes the OPACITY only, so the ladder
                        // still computes (ThemedButton.applyInteractionState).
                        .shadow(color: .black.opacity(g.groupedShadow ? 0 : elevation.opacity),
                                radius: CGFloat(elevation.blur),
                                x: 0, y: CGFloat(elevation.dy))
                    SeamShape(corners: g.roundedCorners, radius: m.radius)
                        .fill(Color(nsColor: overlayColor))
                    SeamBorderShape(corners: g.roundedCorners, radius: m.radius,
                                    edges: g.drawnBorderEdges, inset: 0.5)
                        .stroke(Color(nsColor: borderColor), lineWidth: 1)
                        .opacity(variant == .outlined ? 1 : 0)
                }
            }
            .overlay {
                // `focusRingPath`: the box outset by 2 with its radius bumped by
                // the same 2, and the member's OWN corner mask — so a middle
                // segment rings square and a first segment rings on the left only.
                SeamShape(corners: g.roundedCorners, radius: m.radius + ringOutset)
                    .stroke(Color(nsColor: palette.primary), lineWidth: 2)
                    .padding(-ringOutset)
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
                    .frame(width: titleWidth)
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

    /// The label slot, measured exactly as `ThemedButton.rebuildTitle` measures
    /// it — `ceil(attributedWidth) + 2`, kerning included. SwiftUI's own `Text`
    /// layout is ~2.5 pt tighter; a standalone button hides that behind the
    /// 64 pt `minWidth`, but a ButtonGroup SUMS its members, so the divergence
    /// accumulates across a row.
    private var titleWidth: CGFloat? {
        guard !title.isEmpty else { return nil }
        let attr = NSAttributedString(string: title.uppercased(), attributes: [
            .font: palette.uiFont(m.font, .medium), .kern: 0.4])
        return ceil(attr.size().width) + 2
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

// MARK: - Corner-aware shapes
//
// Ports of `ThemedButton.closedCornerPath` / `borderPath`, which build their
// arcs explicitly. That is also what keeps the corner CIRCULAR: SwiftUI's
// `RoundedRectangle(cornerRadius:)` defaults to `.continuous`, and a squircle
// visibly diverges from `CALayer.cornerRadius` (caught in the ThemedChipView
// before/after raster, #164). AppKit's y is UP and SwiftUI's is DOWN, so the
// `CACornerMask` names map to the opposite vertical half here — the mapping is
// spelled out per point rather than left to the reader.

/// A CLOSED rounded-rect rounding only `corners` (the rest squared).
struct SeamShape: Shape {
    var corners: CACornerMask
    var radius: CGFloat
    /// `local.insetBy(dx:dy:)` — the AppKit border sits half a line-width in.
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let b = rect.insetBy(dx: inset, dy: inset)
        let r = min(radius, min(b.width, b.height) / 2)
        let p = CGMutablePath()
        let c = VisualCorners(b)
        func rad(_ mask: CACornerMask) -> CGFloat { corners.contains(mask) ? r : 0 }
        p.move(to: CGPoint(x: b.midX, y: b.maxY))          // the y-up "minY" mid-edge
        p.addArc(tangent1End: c.bottomRight, tangent2End: c.topRight, radius: rad(.layerMaxXMinYCorner))
        p.addArc(tangent1End: c.topRight, tangent2End: c.topLeft, radius: rad(.layerMaxXMaxYCorner))
        p.addArc(tangent1End: c.topLeft, tangent2End: c.bottomLeft, radius: rad(.layerMinXMaxYCorner))
        p.addArc(tangent1End: c.bottomLeft, tangent2End: c.bottomRight, radius: rad(.layerMinXMinYCorner))
        p.closeSubpath()
        return Path(p)
    }
}

/// The outlined border: a closed perimeter when `edges == .all`, else an OPEN
/// path that omits the shared seam edge so two abutting members stroke ONE
/// hairline. Only the two seam configurations a group produces are special-cased
/// — anything else falls back to the closed path, including a subset that still
/// holds both `.right` and `.bottom`. That last arm strokes an edge that was not
/// asked for; it is the AppKit widget's behaviour, kept so the two cannot drift.
struct SeamBorderShape: Shape {
    var corners: CACornerMask
    var radius: CGFloat
    var edges: ThemedButton.BorderEdges
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        guard edges != .all else {
            return SeamShape(corners: corners, radius: radius, inset: inset).path(in: rect)
        }
        let b = rect.insetBy(dx: inset, dy: inset)
        let r = min(radius, min(b.width, b.height) / 2)
        let c = VisualCorners(b)
        func rad(_ mask: CACornerMask) -> CGFloat { corners.contains(mask) ? r : 0 }
        let p = CGMutablePath()
        if !edges.contains(.right) {              // horizontal seam: open on the right
            p.move(to: c.topRight)                // the square endpoint never consults `rad`
            p.addArc(tangent1End: c.topLeft, tangent2End: c.bottomLeft, radius: rad(.layerMinXMaxYCorner))
            p.addArc(tangent1End: c.bottomLeft, tangent2End: c.bottomRight, radius: rad(.layerMinXMinYCorner))
            p.addLine(to: c.bottomRight)
        } else if !edges.contains(.bottom) {      // vertical seam: open on the bottom
            p.move(to: c.bottomRight)
            p.addArc(tangent1End: c.topRight, tangent2End: c.topLeft, radius: rad(.layerMaxXMaxYCorner))
            p.addArc(tangent1End: c.topLeft, tangent2End: c.bottomLeft, radius: rad(.layerMinXMaxYCorner))
            p.addLine(to: c.bottomLeft)
        } else {
            return SeamShape(corners: corners, radius: radius, inset: inset).path(in: rect)
        }
        return Path(p)
    }
}

/// The four corners of a SwiftUI (y-DOWN) rect, named by what they LOOK like —
/// so the `CACornerMask` cases, which are named for AppKit's y-UP layer space,
/// can be read off without re-deriving the flip at each call site.
private struct VisualCorners {
    let topLeft, topRight, bottomRight, bottomLeft: CGPoint
    init(_ b: CGRect) {
        topLeft     = CGPoint(x: b.minX, y: b.minY)   // .layerMinXMaxYCorner
        topRight    = CGPoint(x: b.maxX, y: b.minY)   // .layerMaxXMaxYCorner
        bottomRight = CGPoint(x: b.maxX, y: b.maxY)   // .layerMaxXMinYCorner
        bottomLeft  = CGPoint(x: b.minX, y: b.maxY)   // .layerMinXMinYCorner
    }
}

public extension CACornerMask {
    /// All four — the standalone button's mask, and `ThemedButtonGroup`'s
    /// `.lone` case.
    static let themedAllCorners: CACornerMask =
        [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]
}
