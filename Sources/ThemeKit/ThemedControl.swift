// ThemeKit — ThemedControl: the shared base class for sill's single-control
// themed widgets (ThemedButton / ThemedFAB / ThemedCheckbox / ThemedChip). A
// VALUE-PRESERVING extraction (#14b): each of those four hand-rolled the SAME
// interaction machinery — hover / press / keyboard-focus / activation flash,
// the tracking-area lifecycle, the cell-less NSControl storage, the
// first-responder + Space wiring, and a themed focus ring — byte-for-byte. This
// base owns that one copy; per-widget divergence is exposed as overridable seams
// (NOT special-cased here). Behaviour is IDENTICAL to the old ThemedButton: the
// only intentional mechanism changes are (1) `appearanceGate` / `focusGate`
// predicates standing in for bare `isEnabled` at the paint / focus sites
// (default = `isEnabled`, so Button / FAB are unchanged), (2) `focusRingOutset`
// = `Space.xxs` (2) replacing the four duplicated `2` literals, (3) the focus
// ring drawn on a `zPosition`-raised layer instead of relying on add-last
// ordering, and (4) the template-method hooks.
//
// Subclasses `NSControl` for the real control contract — `isEnabled`,
// `target` / `action`, `sendAction`, key activation. The base is cell-less, so
// `isEnabled` / `target` / `action` use manual storage (the cell-backed
// accessors are unreliable without a cell). The base owns NO value semantics
// (Checkbox's tri-state, glyph, a11y value all stay in the subclass) and NO
// content layers beyond the focus ring — it only positions the ring; subclasses
// own their layer trees, layout, intrinsic size, colour computation, and ring
// SHAPE.
//
// @MainActor throughout (the whole module is). `public class`, not `open`: every
// subclass lives in this same module, so non-final members are overridable
// without `open`, and we dodge open-class API-stability burden. The flash's
// `DispatchQueue.main.asyncAfter` [weak self] stays fully inside the @MainActor
// base so activation never hops off the main actor.

import AppKit
import Palette
import PaletteKit
import QuartzCore

@MainActor
public class ThemedControl: NSControl {

    // MARK: - Theme

    /// The theme. Assigning re-themes the whole control via `applyTheme()`,
    /// which the subclass specializes through the snap / content / a11y hooks.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    // MARK: - NSControl overrides (custom storage — a cell-less NSControl must
    //         NOT lean on the cell-backed isEnabled / target / action).

    private var _enabled = true
    public override var isEnabled: Bool {
        get { _enabled }
        set {
            guard _enabled != newValue else { return }
            _enabled = newValue
            // Actively clear any in-flight hover / press — a disable can strand
            // them with no matching exit / up event (the stuck-hover gotcha).
            // This cleanup is FINAL base behaviour: the setter is not
            // overridable (no super-call to forget); a subclass extends it via
            // the `didDisable()` hook instead.
            if !newValue {
                isHovered = false; isPressed = false
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
                didDisable()
            }
            applyTheme()
        }
    }

    /// Overridable hook invoked when the control transitions to disabled, AFTER
    /// the base has cleared hover / press and resigned first responder. Default
    /// no-op; a subclass adds its own teardown without overriding the `isEnabled`
    /// setter (so it can never forget to run the base cleanup).
    func didDisable() {}

    private weak var _target: AnyObject?
    private var _action: Selector?
    public override var target: AnyObject? { get { _target } set { _target = newValue } }
    public override var action: Selector?  { get { _action } set { _action = newValue } }

    // MARK: - Key activation config

    /// Optional key equivalent (AppKit dialogs want a default button). Set to
    /// `"\r"` to make this the Return-activated default button. Matched in
    /// `performKeyEquivalent` against `keyEquivalentModifierMask`.
    public var keyEquivalent: String = ""
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags = []

    // MARK: - Interaction state storage

    // Core (always-on): hover / focus / flash. `isPressed` is the DEFAULT of an
    // open press seam — Button / FAB / Checkbox inherit it unchanged; Chip
    // replaces the whole trio with a PressTarget enum and never reads this Bool.
    // Subclass-visible (same module) so a subclass can read them in its colour /
    // overlay computation.
    var isHovered = false
    var isKeyFocused = false
    var isFlashing = false   // a keyboard-flash activation is in flight
    var isPressed = false

    private var trackingArea: NSTrackingArea?

    // MARK: - Preview overrides (deterministic prism capture)

    /// Force the hovered / pressed / focused APPEARANCE without real events —
    /// for previews / screenshots only. Gated controls ignore them (the `fx*`
    /// merges AND in `appearanceGate`).
    public var previewHovered = false { didSet { applyState(animated: false) } }
    public var previewPressed = false { didSet { applyState(animated: false) } }
    public var previewFocused = false { didSet { applyState(animated: false) } }

    // MARK: - Gates (overridable seams)

    /// Gates the hover / press / focus PAINT (whether interaction appearance
    /// shows at all). Default = `isEnabled`; Chip overrides to `isClickable`.
    var appearanceGate: Bool { isEnabled }

    /// Gates `acceptsFirstResponder` + the focus ring (whether the control can
    /// take keyboard focus). Default = `isEnabled`; Chip overrides to
    /// `isInteractive` (its delete button stays focusable while the body is
    /// inert).
    var focusGate: Bool { isEnabled }

    // MARK: - fx merges (overridable) — real-state || preview, AND appearanceGate

    var fxHovered: Bool { (isHovered || previewHovered) && appearanceGate }
    var fxPressed: Bool { (isPressed || previewPressed) && appearanceGate }
    var fxFocused: Bool { (isKeyFocused || previewFocused) && appearanceGate }

    /// Whether the focus ring is painted. Default = `fxFocused`; an overridable
    /// seam for a widget that gates the ring differently.
    var showFocusRing: Bool { fxFocused }

    // MARK: - Focus ring (base-owned layer)

    /// The themed keyboard-focus ring. Base-owned and built in `init`; its SHAPE
    /// (path) is an overridable seam, but the layer, its stroke (= `primary`),
    /// its opacity gate, and its concentric inset math live here. `zPosition` is
    /// raised so it renders ON TOP regardless of the order the subclass adds its
    /// own sublayers — a visually-identical replacement for ThemedButton's
    /// "added last" ordering, but order-independent.
    let focusRingLayer = CAShapeLayer()

    /// How far the focus ring sits OUTSIDE the control's rounded box — the #14b
    /// token consolidation: one `Space.xxs` (2) replacing ThemedButton's `-2`/
    /// `+2` pair, FAB's `ringInset` 2, Chip's `-2`, and Checkbox's `focusInset`
    /// 2. Drives BOTH the rect inset (`-outset`) AND the radius bump
    /// (`+outset`), so the concentric pair never desyncs.
    public var focusRingOutset: CGFloat = CGFloat(Space.xxs)   // = 2

    /// The focus-ring path for the current geometry. Overridable seam: the
    /// default is an all-corners concentric ring; Button overrides with its
    /// selective-corner builder, FAB with a circle, Checkbox with a small
    /// rounded box, Chip with a full pill. `local` is the bounds-origin rect.
    func focusRingPath(in rect: CGRect) -> CGPath {
        concentricRingPath(in: rect, radius: 0)
    }

    /// The shared concentric-ring builder: insets `rect` by `-focusRingOutset`
    /// (so the ring sits outside the box) and bumps the radius by
    /// `+focusRingOutset` (so the rounded ring stays concentric with the box).
    /// All-corners ⇒ a plain `CGPath(roundedRect:)` (byte-identical to the old
    /// per-widget code); selective-corner ring construction stays inline in
    /// Button (CornerPath is deliberately NOT extracted — rule-of-three unmet).
    func concentricRingPath(in rect: CGRect, radius: CGFloat) -> CGPath {
        let r = rect.insetBy(dx: -focusRingOutset, dy: -focusRingOutset)
        return CGPath(roundedRect: r,
                      cornerWidth: radius + focusRingOutset,
                      cornerHeight: radius + focusRingOutset,
                      transform: nil)
    }

    static let allCorners: CACornerMask =
        [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]

    // MARK: - Two-tier theming template (base owns the transactions + the focus
    //         ring; the subclass fills its own layers via the hooks)

    /// Re-theme: snaps the STABLE visuals (subclass fill / border / shadow via
    /// `applyThemeSnap`, plus the focus-ring stroke) in a non-animated
    /// transaction, then rebuilds content, syncs a11y, settles the interaction
    /// state, and requests layout. Snapping (not cross-fading) matches the other
    /// widgets — a theme switch must not smear.
    public func applyTheme() {
        layerTxn(animated: false) {
            self.applyThemeSnap()
            self.focusRingLayer.strokeColor = self.palette.primary.cgColor
        }
        rebuildContent()
        syncAccessibility()
        applyState(animated: false)
        needsLayout = true
    }

    /// Overridable: snap the subclass's stable visuals — fill colour, border
    /// visibility / width, shadow visibility. Runs inside the base's
    /// non-animated `layerTxn` (do NOT open another transaction).
    func applyThemeSnap() {}

    /// Overridable: rebuild the subclass's content layers — title text, icons,
    /// glyph path. Runs OUTSIDE the snap transaction (these may size text /
    /// re-rasterize icons, which manage their own snaps).
    func rebuildContent() {}

    /// Overridable: sync the subclass's accessibility (label / value / enabled).
    func syncAccessibility() {}

    /// The interaction-driven layer props — animated on a real hover / press /
    /// focus change, snapped from `applyTheme` / previews / layout. The base
    /// commits the focus-ring opacity; the subclass sets its overlay / border /
    /// elevation through `applyInteractionState`. One transaction wraps both so
    /// the ring and the overlay cross-fade together.
    func applyState(animated: Bool) {
        layerTxn(animated: animated) {
            self.applyInteractionState()
            self.focusRingLayer.opacity = self.showFocusRing ? 1 : 0
        }
    }

    /// Overridable: set the subclass's interaction-driven props (state overlay,
    /// border colour, elevation). Runs inside the base's `applyState` `layerTxn`
    /// (do NOT open another transaction).
    func applyInteractionState() {}

    // MARK: - Layout template (base positions the ring; subclass positions its
    //         own layers inside the SAME transaction — no nested begin)

    public override func layout() {
        super.layout()
        layerTxn(animated: false) {
            let local = CGRect(origin: .zero, size: self.bounds.size)
            self.positionLayers(in: self.bounds, local: local)
            self.focusRingLayer.frame = self.bounds
            self.focusRingLayer.path = self.focusRingPath(in: local)
        }
    }

    /// Overridable: position the subclass's own layers. `bounds` is the view
    /// frame (y-up); `local` is the same rect at origin `.zero`. Runs inside the
    /// base's non-animated `layerTxn` (do NOT open another transaction).
    func positionLayers(in bounds: CGRect, local: CGRect) {}

    /// Keep text / strokes / symbols crisp across a display-scale change —
    /// `contentsScale` was captured once at init (before a window). The base
    /// re-scales its focus ring; the subclass re-scales its layers and
    /// re-rasterizes icons via `updateContentsScale`.
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = themeBackingScale
        focusRingLayer.contentsScale = s
        updateContentsScale(s)
    }

    /// Overridable: re-scale the subclass's layers' `contentsScale` to `s` and
    /// re-rasterize any device-scale-dependent bitmaps (icons / glyphs).
    func updateContentsScale(_ s: CGFloat) {}

    public override var isFlipped: Bool { false }   // y-up: a downward shadow is −y

    // MARK: - Tracking + mouse (hoisted from ThemedButton)

    /// The tracking-area options. Overridable seam, but every current widget
    /// uses this exact set. `.inVisibleRect` makes the `rect: .zero` area track
    /// the whole visible bounds.
    var trackingOptions: NSTrackingArea.Options {
        [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t); trackingArea = nil }
        let t = NSTrackingArea(rect: .zero, options: trackingOptions, owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
        // A geometry change can move the view out from under a stationary
        // pointer with no exit event — clear a now-false hover.
        if isHovered, let w = window {
            let local = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(local) { isHovered = false; applyState(animated: false) }
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        guard appearanceGate else { return }
        isHovered = true; applyState(animated: true)
    }
    public override func mouseExited(with event: NSEvent) {
        guard isHovered else { return }
        isHovered = false; applyState(animated: true)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { appearanceGate }

    /// Shared drag-cancel helper: is the event's location inside the bounds?
    /// Used by the mouse trio to track whether a press is still "inside" as the
    /// pointer drags.
    func pressInside(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }

    // The default Bool-`isPressed` press trio (Button / FAB / Checkbox inherit
    // unchanged; Chip overrides the whole trio for its PressTarget). A click
    // presses + activates but deliberately does NOT take first responder —
    // standard macOS push-button behaviour (keyboard focus + the themed ring
    // arrive via Tab; Return via performKeyEquivalent). A future click-to-focus
    // widget would override `mouseDown` to add a `makeFirstResponder`.
    public override func mouseDown(with event: NSEvent) {
        guard appearanceGate else { return }
        isPressed = true; applyState(animated: true)
    }
    public override func mouseDragged(with event: NSEvent) {
        guard appearanceGate else { return }
        let inside = pressInside(event)
        if inside != isPressed { isPressed = inside; applyState(animated: true) }
    }
    public override func mouseUp(with event: NSEvent) {
        guard appearanceGate else { return }
        let inside = pressInside(event)
        if isPressed { isPressed = false; applyState(animated: true) }
        if inside { activate() }
    }

    // MARK: - Keyboard + focus

    public override var acceptsFirstResponder: Bool { focusGate }

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
        if isEnabled, event.keyCode == 49 {   // Space activates the focused control
            // Activate once per press; swallow auto-repeat (a held Space must
            // not re-fire) — consume the repeat too, so it doesn't beep.
            if !event.isARepeat { keyboardActivate() }
            return
        }
        super.keyDown(with: event)
    }

    /// Return / a set key equivalent activates via the window's default-button
    /// path (delivered BEFORE keyDown, regardless of first responder).
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isEnabled, !keyEquivalent.isEmpty,
              event.charactersIgnoringModifiers == keyEquivalent,
              mods == keyEquivalentModifierMask else {
            return super.performKeyEquivalent(with: event)
        }
        keyboardActivate()
        return true
    }

    /// A brief visible press before running `action` — keyboard activation has
    /// no natural down/up, so synthesize the flash. The `isFlashing` guard makes
    /// a single flash atomic: a second Space/Return inside the 0.12 s window is
    /// dropped (no double-fire), and the deferred block re-runs through the
    /// caller's `action` (which re-checks `isEnabled` via `activate`) so an async
    /// disable mid-flash cancels it. Stays fully on the main actor.
    func flashThenActivate(_ action: @escaping () -> Void) {
        guard !isFlashing else { return }
        isFlashing = true
        isPressed = true; applyState(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration) { [weak self] in
            guard let self else { return }
            self.isFlashing = false
            self.isPressed = false; self.applyState(animated: true)
            action()
        }
    }

    static let flashDuration: TimeInterval = 0.12

    /// Keyboard / key-equivalent activation. Default = flash, then `activate()`
    /// (Button / FAB). Overridable seam: Checkbox flashes then TOGGLES (not a
    /// fire-and-forget send) while reusing this flash helper; Chip may override.
    func keyboardActivate() {
        flashThenActivate { [weak self] in self?.activate() }
    }

    /// Send the cell-less `action` to the `target` (resolved through the
    /// responder chain when `target` is nil).
    func sendActionToTarget() {
        if let a = _action { NSApp.sendAction(a, to: _target, from: self) }
    }

    /// The activation primitive — sends the action, guarding `isEnabled`
    /// authoritatively (even against an in-flight flash). Overridable seam:
    /// Button overrides to fire its `onTap` closure first, then `super.activate()`.
    func activate() {
        guard isEnabled else { return }
        sendActionToTarget()
    }

    // MARK: - Icon slot (shared by ThemedButton / ThemedChip / ThemedFAB)

    /// Resolve an icon slot into `iconLayer`: a pre-resolved `image` (wins) renders
    /// via `renderedIcon`; otherwise `symbol` is a Phosphor slug loaded via
    /// `phosphorImage` and template-tinted through the same `renderedIcon` recipe
    /// (one tint path for the image and slug channels). Hides the layer when empty.
    /// Returns the POINT size for layout, or nil when empty.
    @discardableResult
    func applyIconSlot(_ iconLayer: CALayer, symbol: String?, image: NSImage?,
                       pt: CGFloat, tint: NSColor, scale: CGFloat) -> CGSize? {
        let resolved: (CGImage, CGSize)?
        if let image {
            resolved = renderedIcon(image, pt: pt, tint: tint, scale: scale)
        } else if let name = symbol, let base = phosphorImage(name, pt: pt) {
            resolved = renderedIcon(base, pt: pt, tint: tint, scale: scale)
        } else {
            resolved = nil
        }
        guard let (img, sz) = resolved else {
            layerTxn(animated: false) { iconLayer.contents = nil; iconLayer.isHidden = true }
            return nil
        }
        layerTxn(animated: false) {
            iconLayer.contents = img
            iconLayer.contentsScale = scale
            iconLayer.isHidden = false
        }
        return sz
    }

    // MARK: - Centered content row (shared by ThemedButton / ThemedFAB / ThemedChip)

    /// Place `segs` (each `(layer, size, isTitle)`) as one horizontally-centred row
    /// in `b`: sum the widths + inter-segment `gap`, centre the block, then walk left
    /// to right vertically centring each. The title segment gets `.position` (its
    /// layer is centre-anchored); icon segments get `.frame`. Returns each segment's
    /// frame in order so a caller can read one back (Chip sizes its × hit-target from
    /// the delete layer's frame). Button / FAB / Chip each had this exact loop inline.
    @discardableResult
    func layoutCenteredRow(_ segs: [(CALayer, CGSize, Bool)], in b: CGRect, gap: CGFloat) -> [CGRect] {
        let total = segs.reduce(0) { $0 + $1.1.width }
                  + CGFloat(max(0, segs.count - 1)) * gap
        var x = (b.width - total) / 2
        let cy = b.midY
        var frames: [CGRect] = []
        for (lyr, sz, isTitle) in segs {
            let frame = CGRect(x: x, y: cy - sz.height / 2, width: sz.width, height: sz.height)
            if isTitle {
                lyr.position = CGPoint(x: x + sz.width / 2, y: cy)
            } else {
                lyr.frame = frame
            }
            frames.append(frame)
            x += sz.width + gap
        }
        return frames
    }

    /// The intrinsic width of a centred row: `leadingPad + Σ widths + gaps + trailingPad`,
    /// floored at `minWidth` then `ceil`-ed. `gaps` counts only the PRESENT (width > 0)
    /// segments, matching the layout loop. The addition order is kept identical to the
    /// per-widget copies so the `ceil` result is bit-for-bit unchanged.
    func centeredRowWidth(_ widths: [CGFloat], gap: CGFloat,
                          leadingPad: CGFloat, trailingPad: CGFloat, minWidth: CGFloat) -> CGFloat {
        let present = widths.filter { $0 > 0 }.count
        let gaps = CGFloat(max(0, present - 1)) * gap
        var content = leadingPad
        for w in widths { content += w }
        content += gaps
        content += trailingPad
        return max(minWidth, ceil(content))
    }

    // MARK: - Init

    /// Designated initializer. Stores the palette, becomes layer-backed, opts out
    /// of clipping (the focus ring lives outside bounds) and AppKit's stock focus
    /// ring, then builds the base-owned focus-ring layer (raised `zPosition` so it
    /// stays on top of subclass sublayers) and adds it. A subclass calls
    /// `super.init(palette:)`, THEN builds its own layers, THEN sets its
    /// accessibility role and calls `applyTheme()`.
    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false        // the focus ring / shadow live outside bounds
        focusRingType = .none               // we draw our own themed ring

        let s = themeBackingScale
        focusRingLayer.fillColor = NSColor.clear.cgColor
        focusRingLayer.lineWidth = 2
        focusRingLayer.opacity = 0
        focusRingLayer.contentsScale = s
        focusRingLayer.zPosition = 1000     // render on top regardless of add-order
        layer?.addSublayer(focusRingLayer)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }
}
