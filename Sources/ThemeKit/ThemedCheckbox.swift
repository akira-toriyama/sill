// ThemeKit — ThemedCheckbox: a themed tri-state checkbox (MUI <Checkbox>, basic).
// A faithful AppKit port: a rounded-square box that is an empty outline when
// unchecked and a `primary`-filled box with a drawn checkmark (or dash, when
// indeterminate) when set, behind a circular hover/press state layer. Themed by
// assigning `palette`. AppKit / @MainActor.
//
// It is its OWN NSControl (a checkbox is not a button shape) but reuses every
// proven ThemedButton idiom verbatim: custom-storage isEnabled/target/action
// (cell-less NSControl), tracking-area hover, Space activation with the
// auto-repeat + in-flight guards, a themed `primary` focus ring (focusRingType
// .none), the 0.16s ease-out layerTxn snap-vs-animate split, preview overrides
// for deterministic capture, and a DEBUG probe. The check/dash glyph is a drawn
// CGPath whose `strokeEnd` animates the draw-in (the MUI-absent-but-tasteful
// 演出). The checkmark is painted in `onPrimary()` (best-contrast ink on the
// fill) — NOT a background knockout, which would vanish on dark/colored panels.

import AppKit
import Palette
import PaletteKit
import Motion

@MainActor
public final class ThemedCheckbox: NSControl {

    /// MUI size — only the box glyph shrinks; the padded square hit/hover area
    /// stays constant (MUI padding 9 both sizes).
    public enum Size { case small, medium }

    /// Colour role. `primary` is the MUI default and the contract-pinned accent;
    /// v1 ships `.primary` only.
    public enum Role { case primary }

    // MARK: - Public configuration

    public var palette: ResolvedPalette { didSet { applyTheme() } }

    public var size: Size = .medium { didSet { applyTheme(); relayout() } }
    public var role: Role = .primary { didSet { applyTheme() } }

    /// Tri-state as two orthogonal bools so a host can bind `Bool` directly.
    /// `isIndeterminate` draws the dash regardless of `isChecked`. Assigning
    /// either ANIMATES the glyph but does NOT fire `onChange` (no binding loop).
    public var isChecked: Bool = false       { didSet { syncAccessibility(); applyState(animated: true) } }
    public var isIndeterminate: Bool = false { didSet { syncAccessibility(); applyState(animated: true) } }

    /// Optional trailing label (MUI's FormControlLabel, folded in). It is part
    /// of the hit area + the intrinsic width; `nil` = a bare box.
    public var label: String? = nil { didSet { applyTheme(); relayout() } }

    /// Fires on a USER toggle (click / Space / keyEquivalent) only — never on a
    /// programmatic `isChecked =`. Argument = the value the box toggled TO.
    public var onChange: ((Bool) -> Void)?

    /// Optional key equivalent (MUI has none). Matched in performKeyEquivalent.
    public var keyEquivalent: String = ""
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags = []

    /// Force a state without events — deterministic still capture. Disabled
    /// boxes ignore the interaction ones; `previewChecked`/`previewIndeterminate`
    /// override the drawn glyph without mutating the host's bound value.
    public var previewHovered = false { didSet { applyState(animated: false) } }
    public var previewPressed = false { didSet { applyState(animated: false) } }
    public var previewFocused = false { didSet { applyState(animated: false) } }
    public var previewChecked: Bool?       = nil { didSet { syncAccessibility(); applyState(animated: false) } }
    public var previewIndeterminate: Bool? = nil { didSet { syncAccessibility(); applyState(animated: false) } }

    // MARK: - NSControl overrides (custom storage — cell-less)

    private var _enabled = true
    public override var isEnabled: Bool {
        get { _enabled }
        set {
            guard _enabled != newValue else { return }
            _enabled = newValue
            if !newValue {
                isHovered = false; isPressed = false
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            }
            applyTheme()
        }
    }
    private weak var _target: AnyObject?
    private var _action: Selector?
    public override var target: AnyObject? { get { _target } set { _target = newValue } }
    public override var action: Selector?  { get { _action } set { _action = newValue } }

    // MARK: - Internals

    private let hoverCircleLayer = CALayer()       // circular state layer behind the box
    private let boxFillLayer  = CAShapeLayer()     // filled rounded square when set
    private let boxStrokeLayer = CAShapeLayer()    // outline ring when unchecked
    private let glyphLayer    = CAShapeLayer()     // the check / dash (strokeEnd draws in)
    private let labelLayer    = CATextLayer()
    private let focusRingLayer = CAShapeLayer()    // themed primary ring (hugs the box)

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var isKeyFocused = false
    private var isFlashing = false
    private var labelTextSize: CGSize = .zero

    public override var isFlipped: Bool { false }

    // MARK: - Metrics

    private struct Metrics {
        let target, box, radius, stroke, labelFont, labelGap, focusInset: CGFloat
    }
    private var metrics: Metrics {
        switch size {
        case .small:  return Metrics(target: 38, box: 18, radius: CGFloat(Radius.xs), stroke: 1.5, labelFont: 14, labelGap: CGFloat(Space.xs), focusInset: -2)
        case .medium: return Metrics(target: 42, box: 20, radius: CGFloat(Radius.xs), stroke: 2,   labelFont: 16, labelGap: CGFloat(Space.xs), focusInset: -2)
        }
    }

    public override var intrinsicContentSize: NSSize {
        let m = metrics
        guard !(label ?? "").isEmpty else {
            return NSSize(width: m.target, height: m.target)
        }
        let tw = ceil(labelTextSize.width)
        let boxRightInTarget = (m.target + m.box) / 2
        let w = boxRightInTarget + m.labelGap + tw + (m.target - m.box) / 2
        return NSSize(width: ceil(w), height: m.target)
    }

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        focusRingType = .none

        let s = backingScale
        hoverCircleLayer.contentsScale = s
        hoverCircleLayer.masksToBounds = true
        layer?.addSublayer(hoverCircleLayer)

        boxFillLayer.contentsScale = s
        boxFillLayer.fillColor = NSColor.clear.cgColor
        layer?.addSublayer(boxFillLayer)

        boxStrokeLayer.contentsScale = s
        boxStrokeLayer.fillColor = NSColor.clear.cgColor
        layer?.addSublayer(boxStrokeLayer)

        glyphLayer.contentsScale = s
        glyphLayer.fillColor = NSColor.clear.cgColor
        glyphLayer.lineCap = .round
        glyphLayer.lineJoin = .round
        layer?.addSublayer(glyphLayer)

        labelLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        labelLayer.contentsScale = s
        labelLayer.alignmentMode = .left
        labelLayer.truncationMode = .end
        labelLayer.isWrapped = false
        layer?.addSublayer(labelLayer)

        focusRingLayer.contentsScale = s
        focusRingLayer.fillColor = NSColor.clear.cgColor
        focusRingLayer.lineWidth = 2
        focusRingLayer.opacity = 0
        layer?.addSublayer(focusRingLayer)

        setAccessibilityRole(.checkBox)
        applyTheme()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    private func relayout() { invalidateIntrinsicContentSize(); needsLayout = true }
    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    // MARK: - State helpers

    private var fxHovered: Bool { (isHovered || previewHovered) && isEnabled }
    private var fxPressed: Bool { (isPressed || previewPressed) && isEnabled }
    private var fxFocused: Bool { (isKeyFocused || previewFocused) && isEnabled }
    private var fxChecked: Bool { previewChecked ?? isChecked }
    private var fxIndeterminate: Bool { previewIndeterminate ?? isIndeterminate }
    private var eff: Bool { fxChecked || fxIndeterminate }   // box is "filled"

    // Fonts via `palette.uiFont(_:)` — the shared type-scale resolver
    // (honours .mono/.rounded/.menu; the old local helper dropped two).

    /// Best-contrast ink on a fill (same WCAG path PaletteKit.onPrimary uses).
    private func ink(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent),
                                      b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }

    private var boxFillColor: NSColor {
        guard eff else { return .clear }
        return isEnabled ? palette.primary : palette.muted
    }
    private var boxStrokeColor: NSColor {
        isEnabled ? palette.ink(.strong, of: .foreground) : palette.muted
    }
    private var glyphColor: NSColor {
        ink(on: isEnabled ? palette.primary : palette.muted)
    }
    /// The circular state layer tint (hover/press/focus), rooted on `primary`
    /// when the box is set, else `foreground` — MUI's checked-vs-unchecked ripple.
    private var hoverCircleColor: NSColor {
        guard isEnabled else { return .clear }
        let root: ResolvedPalette.InkRoot = eff ? .primary : .foreground
        if fxPressed { return palette.ink(.subtle, of: root) }      // 0.16
        if fxHovered || fxFocused { return palette.ink(.faint, of: root) }  // 0.06
        return .clear
    }
    private var labelColor: NSColor { isEnabled ? palette.foreground : palette.muted }
    private var showFocusRing: Bool { fxFocused }

    // MARK: - Theming

    public func applyTheme() {
        layerTxn(animated: false) {
            self.focusRingLayer.strokeColor = self.palette.primary.cgColor
            self.boxStrokeLayer.lineWidth = self.metrics.stroke
            self.glyphLayer.lineWidth = self.metrics.box * 2 / 24
        }
        rebuildLabel()
        syncAccessibility()
        applyState(animated: false)
        needsLayout = true
    }

    private func applyState(animated: Bool) {
        // The glyph PATH (tick vs dash) snaps; only its strokeEnd draw-in animates.
        // Assign only when there IS a glyph — on uncheck we keep the prior path so
        // strokeEnd 1→0 retracts it (assigning nil would snap the tick away).
        layerTxn(animated: false) { if let path = self.glyphPath() { self.glyphLayer.path = path } }
        layerTxn(animated: animated) {
            self.boxFillLayer.fillColor = self.boxFillColor.cgColor
            self.boxStrokeLayer.strokeColor = self.boxStrokeColor.cgColor
            self.boxStrokeLayer.opacity = self.eff ? 0 : 1     // ring fades as the fill arrives
            self.glyphLayer.strokeColor = self.glyphColor.cgColor
            self.glyphLayer.strokeEnd = self.eff ? 1 : 0       // draw-in
            self.hoverCircleLayer.backgroundColor = self.hoverCircleColor.cgColor
            self.focusRingLayer.opacity = self.showFocusRing ? 1 : 0
        }
    }

    private func rebuildLabel() {
        let f = palette.uiFont(metrics.labelFont)
        let s = label ?? ""
        let attr = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: labelColor])
        labelTextSize = attr.size()
        layerTxn(animated: false) {
            self.labelLayer.string = s.isEmpty ? nil : attr
            self.labelLayer.foregroundColor = self.labelColor.cgColor
            self.labelLayer.isHidden = s.isEmpty
            self.labelLayer.bounds = CGRect(x: 0, y: 0,
                width: ceil(self.labelTextSize.width) + 2, height: ceil(self.labelTextSize.height))
        }
    }

    private func syncAccessibility() {
        setAccessibilityLabel(label)
        setAccessibilityEnabled(isEnabled)
        // -1 mixed (indeterminate) / 1 on / 0 off
        setAccessibilityValue(fxIndeterminate ? -1 : (fxChecked ? 1 : 0))
    }

    // MARK: - Glyph paths (box-local coords, y-up)

    /// The check or dash path normalized into the box rect; empty when unset.
    private func glyphPath() -> CGPath? {
        let b = metrics.box
        let p = CGMutablePath()
        if fxIndeterminate {            // a centred horizontal bar (≈ MUI's ~58% dash)
            p.move(to: CGPoint(x: b * 0.20, y: b * 0.5))
            p.addLine(to: CGPoint(x: b * 0.80, y: b * 0.5))
            return p
        }
        if fxChecked {                  // a checkmark (down-left → bottom → up-right; y-up)
            p.move(to: CGPoint(x: b * 0.22, y: b * 0.50))
            p.addLine(to: CGPoint(x: b * 0.42, y: b * 0.32))
            p.addLine(to: CGPoint(x: b * 0.78, y: b * 0.68))
            return p
        }
        return nil
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        let m = metrics
        layerTxn(animated: false) {
            let targetRect = NSRect(x: 0, y: (self.bounds.height - m.target) / 2,
                                    width: m.target, height: m.target)
            let boxRect = NSRect(x: targetRect.midX - m.box / 2, y: targetRect.midY - m.box / 2,
                                 width: m.box, height: m.box)
            let boxLocal = CGRect(origin: .zero, size: boxRect.size)

            self.hoverCircleLayer.frame = targetRect
            self.hoverCircleLayer.cornerRadius = m.target / 2

            self.boxFillLayer.frame = boxRect
            self.boxFillLayer.path = CGPath(roundedRect: boxLocal,
                cornerWidth: m.radius, cornerHeight: m.radius, transform: nil)

            self.boxStrokeLayer.frame = boxRect
            let si = m.stroke / 2
            let ringRadius = max(0, m.radius - si)   // stay concentric with the fill's corner
            self.boxStrokeLayer.path = CGPath(roundedRect: boxLocal.insetBy(dx: si, dy: si),
                cornerWidth: ringRadius, cornerHeight: ringRadius, transform: nil)

            self.glyphLayer.frame = boxRect   // path is box-local

            self.focusRingLayer.frame = boxRect
            self.focusRingLayer.path = CGPath(
                roundedRect: boxLocal.insetBy(dx: m.focusInset, dy: m.focusInset),
                cornerWidth: m.radius - m.focusInset, cornerHeight: m.radius - m.focusInset, transform: nil)

            if !(self.label ?? "").isEmpty {
                self.labelLayer.position = CGPoint(x: boxRect.maxX + m.labelGap, y: targetRect.midY)
            }
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = backingScale
        for l in [hoverCircleLayer, boxFillLayer, boxStrokeLayer, glyphLayer, focusRingLayer] {
            l.contentsScale = s
        }
        labelLayer.contentsScale = s
        needsLayout = true
    }

    // MARK: - Snap-vs-animate (verbatim ThemedTextField idiom)

    private func layerTxn(animated: Bool, _ body: () -> Void) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(ThemedTransition.Duration.enter)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        body()
        CATransaction.commit()
    }

    // MARK: - Hover

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t); trackingArea = nil }
        let t = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
        if isHovered, let w = window {
            let local = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(local) { isHovered = false; applyState(animated: false) }
        }
    }
    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true; applyState(animated: true)
    }
    public override func mouseExited(with event: NSEvent) {
        guard isHovered else { return }
        isHovered = false; applyState(animated: true)
    }

    // MARK: - Press (toggles on mouse-up inside; the whole control incl. label)

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEnabled }
    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true; applyState(animated: true)
    }
    public override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed { isPressed = inside; applyState(animated: true) }
    }
    public override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if isPressed { isPressed = false; applyState(animated: true) }
        if inside { toggle(fromUser: true) }
    }

    // MARK: - Keyboard + focus

    public override var acceptsFirstResponder: Bool { isEnabled }
    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { isKeyFocused = true; applyState(animated: true) }
        return ok
    }
    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { isKeyFocused = false; applyState(animated: true) }
        return ok
    }
    public override func keyDown(with event: NSEvent) {
        if isEnabled, event.keyCode == 49 {   // Space toggles
            if !event.isARepeat { flashAndToggle() }
            return
        }
        super.keyDown(with: event)
    }
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isEnabled, !keyEquivalent.isEmpty,
              event.charactersIgnoringModifiers == keyEquivalent,
              mods == keyEquivalentModifierMask else {
            return super.performKeyEquivalent(with: event)
        }
        flashAndToggle()
        return true
    }

    /// A visible press bump, then toggle — keyboard has no natural down/up. The
    /// `isFlashing` guard makes it atomic; the deferred path re-checks isEnabled.
    private func flashAndToggle() {
        guard !isFlashing else { return }
        isFlashing = true
        isPressed = true; applyState(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.isFlashing = false
            self.isPressed = false; self.applyState(animated: true)
            self.toggle(fromUser: true)
        }
    }

    /// unchecked→checked→unchecked; indeterminate→checked (cleared). Fires
    /// onChange + target/action only on a user toggle; the host may override the
    /// value from inside onChange (controlled component).
    private func toggle(fromUser: Bool) {
        guard isEnabled else { return }
        let next: Bool
        if isIndeterminate {
            isIndeterminate = false
            isChecked = true
            next = true
        } else {
            next = !isChecked
            isChecked = next
        }
        if fromUser {
            onChange?(next)
            if let a = _action { NSApp.sendAction(a, to: _target, from: self) }
        }
    }
}

#if DEBUG
// Test-only window into the rendered state, so a deterministic test can assert
// per-state colours / glyph WITHOUT synthetic events (drive via the preview…
// overrides). Same-file extension so it reads the private layers.
extension ThemedCheckbox {
    struct CheckboxProbe {
        public let boxFill: CGColor?
        public let boxStroke: CGColor?
        public let strokeVisible: Bool          // unchecked ring shown
        public let glyphColor: CGColor?
        public let glyphStrokeEnd: CGFloat       // 1 when fully drawn
        public let glyphIsDash: Bool             // indeterminate vs check path
        public let glyphPresent: Bool
        public let hoverCircleColor: CGColor?
        public let focusRingOpacity: Float
        public let focusRingStroke: CGColor?
        public let labelColor: CGColor?
        public let target: CGFloat
        public let isCheckedEffective: Bool
        public let isIndeterminateEffective: Bool
    }
    var checkboxProbe: CheckboxProbe {
        CheckboxProbe(
            boxFill: boxFillLayer.fillColor,
            boxStroke: boxStrokeLayer.strokeColor,
            strokeVisible: boxStrokeLayer.opacity > 0.5,
            glyphColor: glyphLayer.strokeColor,
            glyphStrokeEnd: glyphLayer.strokeEnd,
            glyphIsDash: fxIndeterminate,
            glyphPresent: glyphLayer.path != nil,
            hoverCircleColor: hoverCircleLayer.backgroundColor,
            focusRingOpacity: focusRingLayer.opacity,
            focusRingStroke: focusRingLayer.strokeColor,
            labelColor: labelLayer.foregroundColor,
            target: metrics.target,
            isCheckedEffective: fxChecked,
            isIndeterminateEffective: fxIndeterminate)
    }
    /// Drive the user-toggle path without synthetic events.
    func toggleForTesting() { toggle(fromUser: true) }
    /// Drive the real Space-key plumbing (flash + isFlashing guard + deferred
    /// toggle) — the keyboard entry the bare toggleForTesting bypasses.
    func spaceKeyForTesting() { flashAndToggle() }
    var isFlashingForTesting: Bool { isFlashing }
}
#endif
