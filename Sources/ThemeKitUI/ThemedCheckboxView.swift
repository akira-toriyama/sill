// ThemeKitUI — ThemedCheckboxView: the themed tri-state checkbox, SwiftUI-
// native. Draws the SAME anatomy as ThemeKit's AppKit `ThemedCheckbox` (which
// stays for AppKit hosts): a rounded-square box — empty `foreground` outline
// when unchecked, `primary`-filled with a drawn-in check (or dash, when
// indeterminate) in `bestContrast` ink when set — behind a circular hover /
// press state layer, with a themed `primary` focus ring and an optional
// trailing label. Interaction parity with the `ThemedControl` machinery:
// hover, press with drag-out cancel, Tab focus + Space activation with the
// auto-repeat and in-flight flash guards, and the 0.16 s ease-out
// interaction transitions. The `preview…` overrides force each state for
// deterministic capture; `onChange` fires on USER toggles only.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import Motion

public struct ThemedCheckboxView: View {
    @Environment(\.sillPalette) private var ambientPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var size: ThemedCheckbox.Size
    var label: String?
    var isChecked: Bool
    var isIndeterminate: Bool
    var enabled: Bool
    var previewHovered: Bool
    var previewPressed: Bool
    var previewFocused: Bool
    var previewChecked: Bool?
    var previewIndeterminate: Bool?
    var onChange: ((Bool) -> Void)?

    // The widget owns its VISIBLE value between host updates (the AppKit
    // widget toggled its own `isChecked` the same way); a change to the
    // `isChecked` / `isIndeterminate` arguments re-drives it (controlled
    // component — the host may override from inside `onChange`).
    @State private var checkedState: Bool
    @State private var indeterminateState: Bool

    @State private var hovered = false
    @State private var pressed = false
    @State private var flashing = false      // a keyboard-flash activation is in flight
    @State private var hitSize: CGSize = .zero
    @FocusState private var keyFocused: Bool

    public init(palette: ResolvedPalette? = nil, size: ThemedCheckbox.Size = .medium,
                label: String? = nil, isChecked: Bool = false,
                isIndeterminate: Bool = false, enabled: Bool = true,
                previewHovered: Bool = false, previewPressed: Bool = false,
                previewFocused: Bool = false, previewChecked: Bool? = nil,
                previewIndeterminate: Bool? = nil, onChange: ((Bool) -> Void)? = nil) {
        self.explicitPalette = palette
        self.size = size
        self.label = label
        self.isChecked = isChecked
        self.isIndeterminate = isIndeterminate
        self.enabled = enabled
        self.previewHovered = previewHovered
        self.previewPressed = previewPressed
        self.previewFocused = previewFocused
        self.previewChecked = previewChecked
        self.previewIndeterminate = previewIndeterminate
        self.onChange = onChange
        self._checkedState = State(initialValue: isChecked)
        self._indeterminateState = State(initialValue: isIndeterminate)
    }

    // MARK: - Metrics (mirror ThemedCheckbox — a divergence here shows up in
    // the AppKit-vs-native parity render test, so keep the two in lockstep)

    private struct Metrics {
        let target, box, radius, stroke, labelFont, labelGap: CGFloat
    }
    private var m: Metrics {
        switch size {
        case .small:  return Metrics(target: 38, box: 18, radius: CGFloat(Radius.xs), stroke: 1.5, labelFont: 14, labelGap: CGFloat(Space.xs))
        case .medium: return Metrics(target: 42, box: 20, radius: CGFloat(Radius.xs), stroke: 2,   labelFont: 16, labelGap: CGFloat(Space.xs))
        }
    }

    // MARK: - Effective state (real || preview, the fx merges)

    private var fxChecked: Bool { previewChecked ?? checkedState }
    private var fxIndeterminate: Bool { previewIndeterminate ?? indeterminateState }
    private var eff: Bool { fxChecked || fxIndeterminate }   // box is "filled"
    private var fxHovered: Bool { (hovered || previewHovered) && enabled }
    private var fxPressed: Bool { (pressed || previewPressed) && enabled }
    private var fxFocused: Bool { (keyFocused || previewFocused) && enabled }

    // MARK: - Colours (the same role math as ThemedCheckbox)

    private var boxFillColor: NSColor {
        guard eff else { return .clear }
        return enabled ? palette.primary : palette.disabledInk
    }
    private var boxStrokeColor: NSColor {
        enabled ? palette.ink(.strong, of: .foreground) : palette.disabledInk
    }
    private var glyphColor: NSColor {
        palette.bestContrast(on: enabled ? palette.primary : palette.disabledInk)
    }
    /// The circular state layer tint (hover/press/focus), rooted on `primary`
    /// when the box is set, else `foreground` — MUI's checked-vs-unchecked ripple.
    private var hoverCircleColor: NSColor {
        guard enabled else { return .clear }
        let tint = eff ? palette.primary : palette.foreground
        if fxPressed              { return palette.stateOverlay(.pressed, on: .roleTint(tint)) }
        if fxHovered || fxFocused { return palette.stateOverlay(.hover, on: .roleTint(tint)) }
        return .clear
    }
    private var labelColor: NSColor { enabled ? palette.foreground : palette.disabledInk }

    // MARK: - Body

    /// Layout mirrors `intrinsicContentSize` + `positionLayers`: the box sits
    /// centred in a `target`-square hit area at the leading edge; the label
    /// starts `labelGap` after the BOX edge (inside the target square — the
    /// AppKit metric), and the trailing pad is the box-to-target margin.
    public var body: some View {
        HStack(spacing: m.labelGap) {
            box
            if let label, !label.isEmpty {
                Text(label)
                    .font(Font(palette.uiFont(m.labelFont) as CTFont))
                    .foregroundColor(Color(nsColor: labelColor))
                    .fixedSize()
            }
        }
        .padding(.horizontal, (m.target - m.box) / 2)
        .frame(height: m.target)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self, of: \.size) { hitSize = $0 }
        .onHover { inside in
            guard enabled else { return }
            withAnimation(interaction) { hovered = inside }
        }
        .gesture(pressGesture, isEnabled: enabled)
        .focusable(enabled)
        .focusEffectDisabled()   // the ring below is the themed replacement
        .onKeyPress(.space, phases: .down) { _ in    // .down only ⇒ auto-repeat never re-fires
            keyboardActivate()
            return .handled
        }
        .onChange(of: isChecked) { _, new in checkedState = new }
        .onChange(of: isIndeterminate) { _, new in indeterminateState = new }
        .onChange(of: enabled) { _, new in
            // A disable can strand an in-flight hover / press with no matching
            // exit / up event (the ThemedControl stuck-hover cleanup).
            if !new { hovered = false; pressed = false }
        }
        .accessibilityRepresentation {
            Toggle(label ?? "", isOn: Binding(get: { fxChecked },
                                              set: { _ in toggleFromUser() }))
                .disabled(!enabled)
        }
    }

    /// The `target`-square stack: hover circle, box fill, outline ring, glyph,
    /// focus ring — the ThemedCheckbox sublayer tree, top to bottom.
    private var box: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: hoverCircleColor))
                .frame(width: m.target, height: m.target)
            RoundedRectangle(cornerRadius: m.radius)
                .fill(Color(nsColor: boxFillColor))
                .frame(width: m.box, height: m.box)
            RoundedRectangle(cornerRadius: m.radius)
                .strokeBorder(Color(nsColor: boxStrokeColor), lineWidth: m.stroke)
                .frame(width: m.box, height: m.box)
                .opacity(eff ? 0 : 1)
            CheckboxGlyph(dash: fxIndeterminate)
                .trim(from: 0, to: eff ? 1 : 0)   // strokeEnd — the draw-in 演出
                .stroke(Color(nsColor: glyphColor),
                        style: StrokeStyle(lineWidth: m.box * 2 / 24,
                                           lineCap: .round, lineJoin: .round))
                .frame(width: m.box, height: m.box)
            RoundedRectangle(cornerRadius: m.radius + ringOutset)
                .stroke(Color(nsColor: palette.primary), lineWidth: 2)
                .frame(width: m.box + 2 * ringOutset, height: m.box + 2 * ringOutset)
                .opacity(fxFocused ? 1 : 0)
        }
        .frame(width: m.box, height: m.target)   // layout slot = the box; the
        // circle / ring overdraw into the surrounding padding (masksToBounds off)
        .animation(interaction, value: fxHovered)
        .animation(interaction, value: fxPressed)
        .animation(interaction, value: fxFocused)
        .animation(interaction, value: eff)
    }

    /// `ThemedControl.focusRingOutset` — the ring sits 2 pt outside the box.
    private var ringOutset: CGFloat { CGFloat(Space.xxs) }

    /// The `layerTxn(animated: true)` curve — and `nil` (snap) under Reduce
    /// Motion, so the hover fade and the glyph draw-in settle instantly.
    private var interaction: Animation? {
        reduceMotion ? nil : .easeOut(duration: ThemedTransition.Duration.enter)
    }

    // MARK: - Interaction (the ThemedControl press trio + Space flash)

    /// Press with drag-out cancel: pressed while the pointer is inside, a
    /// release outside abandons the toggle (the mouseDown/Dragged/Up trio).
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let inside = CGRect(origin: .zero, size: hitSize).contains(v.location)
                if pressed != inside { withAnimation(interaction) { pressed = inside } }
            }
            .onEnded { v in
                let inside = CGRect(origin: .zero, size: hitSize).contains(v.location)
                withAnimation(interaction) { pressed = false }
                if inside { toggleFromUser() }
            }
    }

    /// A brief visible press before toggling — keyboard activation has no
    /// natural down/up, so synthesize the flash. The `flashing` guard makes a
    /// flash atomic (a second Space inside the window is dropped), and the
    /// deferred toggle re-checks `enabled` so an async disable mid-flash
    /// cancels it.
    private func keyboardActivate() {
        guard enabled, !flashing else { return }
        flashing = true
        withAnimation(interaction) { pressed = true }
        Task {
            try? await Task.sleep(for: .seconds(0.12))   // ThemedControl.flashDuration
            flashing = false
            withAnimation(interaction) { pressed = false }
            toggleFromUser()
        }
    }

    /// unchecked→checked→unchecked; indeterminate→checked (cleared). Fires
    /// `onChange` with the value the box toggled TO; the host may override the
    /// value from outside (controlled component).
    private func toggleFromUser() {
        guard enabled else { return }
        let next: Bool
        if indeterminateState {
            indeterminateState = false
            checkedState = true
            next = true
        } else {
            next = !checkedState
            checkedState = next
        }
        onChange?(next)
    }
}

/// The check / dash path in box-local coordinates — `ThemedCheckbox.glyphPath`
/// with its y-up coordinates flipped for SwiftUI.
private struct CheckboxGlyph: Shape {
    var dash: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        if dash {                       // a centred horizontal bar (≈ MUI's ~58% dash)
            p.move(to: CGPoint(x: rect.minX + w * 0.20, y: rect.minY + h * 0.5))
            p.addLine(to: CGPoint(x: rect.minX + w * 0.80, y: rect.minY + h * 0.5))
        } else {                        // a checkmark (down-left → bottom → up-right)
            p.move(to: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.50))
            p.addLine(to: CGPoint(x: rect.minX + w * 0.42, y: rect.minY + h * 0.68))
            p.addLine(to: CGPoint(x: rect.minX + w * 0.78, y: rect.minY + h * 0.32))
        }
        return p
    }
}
