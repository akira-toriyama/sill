// ThemeKit — shared themed AppKit widgets for the swift app family
// (facet / wand / perch / halo / glance). PaletteKit resolves the theme;
// ThemeKit draws in it.
//
// `ThemedTextField` (the first widget) is a Material-UI–style single-line
// text field rendered in a `ResolvedPalette`: a rounded OUTLINED box
// (default) — or FILLED / STANDARD (underline) — with an animated FLOATING
// LABEL, optional leading / trailing Phosphor-icon adornments, a focus-accent
// transition (border + label go `primary` while editing), helper / error
// text, and IME-safe editing.
//
// The family hand-draws this today (facet's tree filter + tag-rename
// fields); ThemeKit makes it ONE part. Themed by assignment — set
// `palette` and the field repaints. AppKit / @MainActor.

import AppKit
import Palette
import PaletteKit

@MainActor
public final class ThemedTextField: NSView {

    /// Visual style. `outlined` = rounded stroked box with a notched floating
    /// label (the MUI default); `filled` = filled rounded-top box + bottom
    /// rule; `standard` = bare bottom rule only.
    public enum Variant { case outlined, filled, standard }

    // MARK: - Public configuration

    /// The theme. Assigning re-themes the whole field.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    public var variant: Variant = .outlined { didSet { invalidate() } }

    /// The floating label (MUI). `nil` ⇒ a plain placeholder-only field (no
    /// float) — what facet's compact tree filter wants.
    public var label: String? {
        didSet { rebuildLabel(); syncFloat(animated: false); invalidate() }
    }

    /// Empty-state prompt. With a `label`, shown only while focused + empty
    /// (the label has floated up); without a label, shown whenever empty.
    public var placeholder: String = "" { didSet { syncPlaceholder(); syncAccessibility() } }

    /// Leading icon — a Phosphor slug (e.g. `"magnifying-glass"`), decorative.
    public var leadingSymbol: String? { didSet { invalidate() } }

    /// Trailing icon — a Phosphor slug (e.g. `"x-circle"`) — tappable via
    /// `onTrailingTap` (a clear button, say).
    public var trailingSymbol: String? { didSet { invalidate() } }
    public var onTrailingTap: (() -> Void)?

    /// A SECOND trailing icon, sitting INNER of `trailingSymbol` (drawn to
    /// its left), tappable via `onSecondTrailingTap`. `nil` (the default) ⇒ the
    /// single-trailing-icon geometry is byte-identical; the inner slot only
    /// engages when BOTH `trailingSymbol` and this are set (so it is always the
    /// inner of a pair — ThemedComboBox uses it for the clear-× tucked inside
    /// the disclosure chevron). Setting it without `trailingSymbol` draws no
    /// inner icon (use `trailingSymbol` for a lone trailing icon).
    public var secondTrailingSymbol: String? { didSet { invalidate() } }
    public var onSecondTrailingTap: (() -> Void)?

    /// Supporting line below the field. `errorText` (when set) supersedes it
    /// and flips the field into the error palette.
    public var helperText: String? { didSet { invalidate() } }
    public var errorText: String? { didSet { applyTheme(); invalidate() } }

    /// The colour BEHIND the field — used to "notch" the outlined border
    /// where the floating label sits. Defaults to `palette.background`; a host
    /// on a lifted panel should set the panel's colour so the notch is clean.
    /// `didSet` so setting the surface in ISOLATION repaints the notch / filled
    /// interior — without it (the only knob that lacked one) a direct adopter's
    /// `field.surfaceColor = panelColor` stayed stale until the next layout.
    public var surfaceColor: NSColor? { didSet { updateStroke(animated: false); needsDisplay = true } }

    public var onChange: ((String) -> Void)?
    /// Fires when the field gains (`true`) / loses (`false`) focus — mirrors the
    /// internal accent transition, for a host that toggles affordances on focus.
    public var onFocusChange: ((Bool) -> Void)?
    /// Fires on END-EDITING — blur (tab away / window deactivation / click
    /// elsewhere) OR a Return that ends editing — and may carry text identical
    /// to the last `onChange`. NOT a submit signal: for a dedicated submit key
    /// use `onReturn` (named honestly, unlike a misleading `onCommit`).
    public var onEndEditing: ((String) -> Void)?

    /// Return / Escape seams. The host returns `true` to CONSUME the key (stop
    /// AppKit's default), `false` to let it fall through. Both are suppressed
    /// while the IME holds marked text (`isComposing`), so composition Return /
    /// Escape stay with the input method — the event `isComposing` was built to
    /// gate. (A search host wires `onReturn` to "accept the selection".)
    public var onReturn: (() -> Bool)?
    public var onEscape: (() -> Bool)?

    /// Down / Up arrow seams for an EMBEDDING widget (e.g. ThemedComboBox driving
    /// a popup highlight). The host returns `true` to CONSUME the key (suppress
    /// the field editor's own caret movement), `false` to let it fall through —
    /// the same contract as `onReturn` / `onEscape`, and suppressed identically
    /// while the IME holds marked text (`isComposing`) so candidate navigation
    /// stays with the input method. A bare ThemedTextField leaves both nil, so
    /// the arrows behave EXACTLY as before (the `?? false` falls through).
    public var onMoveDown: (() -> Bool)?
    public var onMoveUp: (() -> Bool)?

    /// Force the focused APPEARANCE (accent border + floated accent label)
    /// without being first responder — for previews / screenshots only.
    public var previewFocused: Bool = false {
        didSet {
            syncFloat(animated: false); updateStroke(animated: false)
            needsDisplay = true
        }
    }

    public var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue; syncFloat(animated: false) }
    }

    /// Clear the field AS IF the user deleted all text: unlike `stringValue =
    /// ""` (a silent setter) this fires `onChange("")`, so a bound search list
    /// actually refreshes. The trailing clear button routes through here.
    public func clearText() { field.stringValue = ""; textChanged() }

    /// Begin editing programmatically (make the field first responder).
    /// `selectingAll` selects the whole value — what a host like facet's rename
    /// field wants on open. Returns whether focus moved. The host calls this
    /// rather than reaching for the (private) inner field / its field editor.
    @discardableResult
    public func focus(selectingAll: Bool = false) -> Bool {
        guard window?.makeFirstResponder(field) == true else { return false }
        if selectingAll { field.currentEditor()?.selectAll(nil) }
        return true
    }

    /// True while the IME holds uncommitted (marked) text — a host binding
    /// Return / Escape must pass them through while this is true.
    public var isComposing: Bool {
        (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
    }

    /// Mark the inner editable field as an accessibility COMBO BOX, so VoiceOver
    /// announces an embedding `ThemedComboBox` correctly. A no-op for a plain
    /// field (which stays a text field). The visible floating label / value are
    /// already exposed via `syncAccessibility`.
    public func markAccessibilityComboBox() { field.setAccessibilityRole(.comboBox) }

    // MARK: - Internals

    private let field = FocusReportingTextField()
    private let strokeLayer = CAShapeLayer()   // border (outlined) / rule (filled,standard)
    private let notchLayer = CALayer()         // surface fill cutting the outlined top rule
    private let labelLayer = CATextLayer()
    // STRONG: NSTextField.delegate is weak, so the field's only owner of this
    // box is here — `weak` here deallocated it instantly, silently killing the
    // focus / change callbacks (the float + border animation never fired).
    private var delegateBox: FieldDelegate?
    private var focused = false
    private var floated = false

    // Metrics
    private let boxH: CGFloat = 40
    private let padX: CGFloat = 12
    private let iconSize: CGFloat = 17
    private let helperH: CGFloat = 14
    private let helperGap: CGFloat = 4
    private var topPad: CGFloat { label == nil ? 0 : 9 }   // room for the float
    private var bodySize: CGFloat { 13 }
    /// The floated-label shrink RATIO (`floatSize / bodySize`) and the
    /// outlined-notch width — NOT a text size. The supporting/helper line
    /// is its own `.secondaryBody` role now, so this only governs the label
    /// animation + notch geometry.
    private var floatSize: CGFloat { 11 }

    public override var isFlipped: Bool { false }
    public override var intrinsicContentSize: NSSize {
        let h = topPad + boxH + (hasSupport ? helperGap + helperH : 0)
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }
    private var hasSupport: Bool { errorText != nil || helperText != nil }
    private var isError: Bool { errorText != nil }

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.alignment = .natural
        addSubview(field)

        let box = FieldDelegate(owner: self)
        delegateBox = box
        field.delegate = box
        // Focus is DERIVED from the settled first-responder state, never from a
        // single edge: begin/become/resign/end all just schedule a reconcile on
        // the next tick (see `scheduleFocusReconcile`). A bare click thrashes
        // through become→spurious-end within one runloop; reconciling AFTER it
        // settles collapses that to the real final state, so the highlight is
        // reliable (the earlier edge-driven approach blurred instantly).
        field.onResponderEdge = { [weak self] in self?.scheduleFocusReconcile() }

        // Order (bottom→top): stroke, notch, label — so the floated label sits
        // over the (notched) border. drawRect content (fill/icons/helper) is
        // below all three.
        strokeLayer.fillColor = NSColor.clear.cgColor
        strokeLayer.lineJoin = .round
        layer?.addSublayer(strokeLayer)
        notchLayer.opacity = 0
        layer?.addSublayer(notchLayer)

        labelLayer.anchorPoint = CGPoint(x: 0, y: 0.5)   // scale toward the left
        labelLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        labelLayer.truncationMode = .end
        labelLayer.isWrapped = false
        layer?.addSublayer(labelLayer)

        applyTheme()
        rebuildLabel()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    private func invalidate() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - Theming
    // Fonts come from `palette.uiFont(_:)` — the shared type-scale resolver:
    // `.body` (13pt) for the input + floating label, `.secondaryBody` (11pt
    // medium) for the supporting line. The old local `themedFont` only
    // branched `.mono` vs system and dropped `.rounded`/`.menu`.

    /// Focus appearance — real first-responder OR the preview override.
    private var isFocused: Bool { focused || previewFocused }

    /// Border / label / rule accent for the current state.
    private var accent: NSColor {
        isError ? palette.error : (isFocused ? palette.primary : palette.border)
    }
    private var labelColor: NSColor {
        isError ? palette.error : (isFocused ? palette.primary : palette.muted)
    }
    private var surface: NSColor { surfaceColor ?? palette.background ?? .textBackgroundColor }

    public func applyTheme() {
        field.font = palette.uiFont(.body)
        field.textColor = palette.foreground
        syncPlaceholder()
        syncAccessibility()
        // Snap label colour/font like the (snapped) stroke: these sublayers
        // have no action-disabling delegate, so an unwrapped mutation would
        // implicitly cross-fade ~0.25 s on a theme switch while the border
        // jumped — a visibly split transition. The float stays animated (its
        // own layerTxn(animated: true) path is untouched).
        layerTxn(animated: false) {
            self.labelLayer.foregroundColor = self.labelColor.cgColor
            self.labelLayer.font = self.palette.uiFont(.body)   // base; scaled via transform
            self.labelLayer.fontSize = self.bodySize
        }
        sizeLabel()
        updateStroke(animated: false)
        needsDisplay = true
    }

    /// Forward the semantic name to the inner field so VoiceOver has a stable
    /// accessible name — the visible floating label is a CATextLayer, which is
    /// invisible to the accessibility tree. Prefer `label` (survives typing);
    /// fall back to `placeholder`. Helper / error become the AX help.
    private func syncAccessibility() {
        field.setAccessibilityLabel(label ?? (placeholder.isEmpty ? nil : placeholder))
        field.setAccessibilityHelp(errorText ?? helperText)
    }

    private func syncPlaceholder() {
        // With a floating label the placeholder only shows once the label has
        // floated up (focused + empty); otherwise the label IS the prompt.
        let show = label == nil || (floated && field.stringValue.isEmpty)
        let f = field.font ?? palette.uiFont(.body)
        field.placeholderAttributedString = NSAttributedString(
            string: show ? placeholder : "",
            attributes: [.foregroundColor: palette.muted, .font: f])
    }

    private func rebuildLabel() {
        layerTxn(animated: false) {           // snap, don't cross-fade (see applyTheme)
            self.labelLayer.isHidden = (self.label == nil)
            self.labelLayer.string = self.label ?? ""
        }
        sizeLabel()
        syncAccessibility()
        invalidate()
    }

    /// CATextLayer renders nothing without a non-zero `bounds`; size it to the
    /// label text at the body font (the float just scales via transform).
    private func sizeLabel() {
        let s = ((label ?? "") as NSString)
            .size(withAttributes: [.font: palette.uiFont(.body)])
        layerTxn(animated: false) {           // snap the bounds change (see applyTheme)
            self.labelLayer.bounds = CGRect(x: 0, y: 0,
                                            width: ceil(s.width) + 2, height: ceil(s.height))
            self.labelLayer.alignmentMode = .left
        }
    }

    // MARK: - Focus

    /// True when the field (or its field editor) is the window's first
    /// responder — the GROUND TRUTH for focus, checked after edges settle.
    private var isFieldFirstResponder: Bool {
        guard let w = field.window else { return false }
        if w.firstResponder === field { return true }
        if let ed = field.currentEditor(), w.firstResponder === ed { return true }
        return false
    }

    /// Re-derive focus from the settled responder state on the NEXT runloop
    /// tick. Multiple edges in one turn (become → spurious end on a bare click)
    /// coalesce into a single correct result instead of a visible flicker.
    fileprivate func scheduleFocusReconcile() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setFocused(self.isFieldFirstResponder)
        }
    }

    private func setFocused(_ on: Bool) {
        guard focused != on else { return }
        focused = on
        syncFloat(animated: true)        // label floats / colours
        updateStroke(animated: true)     // border colour + width transition
        needsDisplay = true              // leading-icon colour (instant)
        onFocusChange?(on)
    }

    fileprivate func textChanged() {
        syncPlaceholder()
        syncFloat(animated: true)
        onChange?(field.stringValue)
    }

    fileprivate func endedEditing() { onEndEditing?(field.stringValue) }

    // MARK: - Floating-label animation

    private func syncFloat(animated: Bool) {
        let shouldFloat = label != nil && (isFocused || !field.stringValue.isEmpty)
        floated = shouldFloat
        syncPlaceholder()
        guard label != nil else { return }
        positionLabel(animated: animated)
    }

    /// Wrap layer mutations so they animate (0.16 s ease-out, like MUI) or
    /// snap, sharing one timing for the label float + the border transition.
    private func layerTxn(animated: Bool, _ body: () -> Void) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        body()
        CATransaction.commit()
    }

    private func positionLabel(animated: Bool) {
        let geo = geometry()
        let up = floated
        let pos = up ? geo.labelFloated : geo.labelResting
        let scale: CGFloat = up ? (floatSize / bodySize) : 1
        layerTxn(animated: animated) {
            self.labelLayer.position = pos
            self.labelLayer.transform = CATransform3DMakeScale(scale, scale, 1)
            self.labelLayer.foregroundColor = self.labelColor.cgColor
        }
    }

    /// Border (outlined) / rule (filled, standard) stroke + the outlined notch,
    /// driven through `layerTxn` so colour + width animate on focus.
    private func updateStroke(animated: Bool) {
        layerTxn(animated: animated) {
            self.strokeLayer.frame = self.bounds
            self.strokeLayer.path = self.strokePath()
            self.strokeLayer.fillColor = NSColor.clear.cgColor
            self.strokeLayer.strokeColor = self.accent.cgColor
            self.strokeLayer.lineWidth = self.isFocused ? 2 : 1
            self.layoutNotch()
        }
    }

    private func strokePath() -> CGPath {
        let box = geometry().box
        switch variant {
        case .outlined:
            return CGPath(roundedRect: box.insetBy(dx: 1, dy: 1),
                          cornerWidth: 8, cornerHeight: 8, transform: nil)
        case .filled, .standard:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: box.minX, y: box.minY + 1))
            p.addLine(to: CGPoint(x: box.maxX, y: box.minY + 1))
            return p
        }
    }

    /// The surface-coloured rect that cuts the outlined top rule under the
    /// floated label — faded in/out with the float (MUI's "notch"). It must be
    /// centred on the BORDER (the stroke path runs along `box.insetBy(dx:1,dy:1)`,
    /// i.e. its centre line is at `box.maxY - 1`, NOT `box.maxY`) and be tall
    /// enough to cover the focused 2 pt stroke — otherwise a sliver of the rule
    /// shows through behind the label text (the "line behind Filter").
    private func layoutNotch() {
        guard variant == .outlined, let lbl = label, floated else {
            notchLayer.opacity = 0; return
        }
        let geo = geometry()
        let f = floatSize / bodySize
        let w = ceil((lbl as NSString)
            .size(withAttributes: [.font: palette.uiFont(.body)]).width) * f + 8
        let ruleY = geo.box.maxY - 1            // stroke centre line
        let h: CGFloat = 6                       // ≥ 2 pt stroke + margin both sides
        notchLayer.backgroundColor = surface.cgColor
        notchLayer.frame = CGRect(x: geo.labelStartX - 4, y: ruleY - h / 2,
                                  width: w, height: h)
        notchLayer.opacity = 1
    }

    // MARK: - Layout

    private struct Geometry {
        var box: NSRect
        var textRect: NSRect
        var leadingIcon: NSRect?
        var trailingIcon: NSRect?
        var secondTrailingIcon: NSRect?
        var labelResting: CGPoint
        var labelFloated: CGPoint
        var labelStartX: CGFloat
    }

    private func geometry() -> Geometry {
        let w = bounds.width
        let supportH = hasSupport ? helperGap + helperH : 0
        // Centre the fixed-height box in the host's frame. Pinning it at a
        // constant y bottom-anchored the field (dead space above on an
        // over-tall frame; a top-edge clip on an under-tall one) — centring
        // makes both degrade to a symmetric trim.
        let slack = bounds.height - intrinsicContentSize.height
        let box = NSRect(x: 0, y: slack / 2 + supportH, width: w, height: boxH)

        var lead: NSRect?
        var trail: NSRect?
        var textMinX = box.minX + padX
        var textMaxX = box.maxX - padX

        if leadingSymbol != nil {
            lead = NSRect(x: box.minX + padX, y: box.midY - iconSize / 2,
                          width: iconSize, height: iconSize)
            textMinX = lead!.maxX + 8
        }
        if trailingSymbol != nil {
            trail = NSRect(x: box.maxX - padX - iconSize, y: box.midY - iconSize / 2,
                           width: iconSize, height: iconSize)
            textMaxX = trail!.minX - 8
        }
        // Inner second trailing icon — ONLY when BOTH symbols are set (it is the
        // inner of a pair). When nil the block is skipped and the single-icon
        // `textMaxX` above is byte-identical to the pre-edit layout.
        var trail2: NSRect?
        if trailingSymbol != nil, secondTrailingSymbol != nil, let t = trail {
            trail2 = NSRect(x: t.minX - 8 - iconSize, y: box.midY - iconSize / 2,
                            width: iconSize, height: iconSize)
            textMaxX = trail2!.minX - 8
        }

        let lineH = ceil((field.font ?? palette.uiFont(.body)).boundingRectForFont.height)
        let textRect = NSRect(x: textMinX, y: box.midY - lineH / 2,
                              width: max(textMaxX - textMinX, 0), height: lineH)

        // Label anchors (anchorPoint is left-centre). All variants float the
        // label to the box TOP, clear of the centred value text. Tucking it
        // inside the box (`box.maxY − 9`) collided with the value on
        // filled/standard — the 40 pt box is too short to hold a top-floated
        // label AND centred text — so float to the top edge like outlined
        // (which straddles the top rule there). No overlap on any variant.
        let startX = textMinX
        let resting = CGPoint(x: startX, y: box.midY)
        let floated = CGPoint(x: startX, y: box.maxY)

        return Geometry(box: box, textRect: textRect, leadingIcon: lead,
                        trailingIcon: trail, secondTrailingIcon: trail2,
                        labelResting: resting,
                        labelFloated: floated, labelStartX: startX)
    }

    public override func layout() {
        super.layout()
        field.frame = geometry().textRect
        positionLabel(animated: false)
        updateStroke(animated: false)
    }

    /// Keep the CATextLayer label + stroked border crisp across a window /
    /// display-scale change. `contentsScale` was captured once at init from
    /// `NSScreen.main` (before the view had a window) — stale after a move to
    /// a different-DPI display. AppKit calls this on window-enter and on any
    /// backing-scale change.
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        labelLayer.contentsScale = s
        strokeLayer.contentsScale = s
    }

    // MARK: - Drawing

    public override func draw(_ dirty: NSRect) {
        let geo = geometry()
        let box = geo.box

        // Border / rule / notch are animated CALayers (see updateStroke);
        // drawRect paints only the filled-variant interior + icons + helper.
        if variant == .filled {
            let r = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
            fieldFill.setFill(); r.fill()
        }

        // Adornments.
        if let sym = leadingSymbol, let r = geo.leadingIcon {
            drawSymbol(sym, in: r, color: isFocused ? palette.primary : palette.muted)
        }
        if let sym = trailingSymbol, let r = geo.trailingIcon {
            drawSymbol(sym, in: r, color: palette.muted)
        }
        if let sym = secondTrailingSymbol, let r = geo.secondTrailingIcon {
            drawSymbol(sym, in: r, color: palette.muted)
        }

        // Supporting line.
        if hasSupport {
            let msg = errorText ?? helperText ?? ""
            let color = isError ? palette.error : palette.muted
            let attrs: [NSAttributedString.Key: Any] = [
                .font: palette.uiFont(.secondaryBody),
                .foregroundColor: color]
            (msg as NSString).draw(
                at: NSPoint(x: padX, y: 0), withAttributes: attrs)
        }
    }

    private var fieldFill: NSColor {
        // A faint lift of the surface for the filled variant's interior.
        (surface.blended(withFraction: 0.06, of: .white) ?? surface)
    }

    private func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        guard let img = phosphorImage(name, pt: rect.height) else { return }
        let tinted = NSImage(size: img.size, flipped: false) { _ in
            color.set()
            img.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            NSRect(origin: .zero, size: img.size).fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    // MARK: - Hit testing / focus on click

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let geo = geometry()
        // Inner (second) icon first — its hit rect abuts the outer one, so the
        // inner must win where they meet. When `secondTrailingSymbol == nil`
        // this branch is skipped and the path is identical to before.
        if secondTrailingSymbol != nil,
           let r = geo.secondTrailingIcon, r.insetBy(dx: -6, dy: -6).contains(p) {
            onSecondTrailingTap?()
            return
        }
        if trailingSymbol != nil,
           let r = geo.trailingIcon, r.insetBy(dx: -6, dy: -6).contains(p) {
            onTrailingTap?()
            return
        }
        window?.makeFirstResponder(field)
    }

    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(field) ?? false
    }
}

// MARK: - Field editor delegate (change + blur/commit)

@MainActor
private final class FieldDelegate: NSObject, NSTextFieldDelegate {
    weak var owner: ThemedTextField?
    init(owner: ThemedTextField) { self.owner = owner }

    // Every editing edge just reconciles focus from the settled responder
    // state (see scheduleFocusReconcile); end-editing additionally commits.
    func controlTextDidBeginEditing(_ obj: Notification) { owner?.scheduleFocusReconcile() }
    func controlTextDidEndEditing(_ obj: Notification) {
        owner?.scheduleFocusReconcile(); owner?.endedEditing()
    }
    func controlTextDidChange(_ obj: Notification) { owner?.textChanged() }

    // Return / Escape seam. ThemedTextField OWNS this delegate slot (and hands
    // itself back as an opaque type), so a host has NO other way to intercept
    // these keys — this is what pairs the public `isComposing` flag with an
    // actual event. Forward to the host's onReturn / onEscape; return `true`
    // only when the host consumes, so unhandled keys fall through to AppKit.
    // Bail while composing so the IME keeps its commit / cancel Return-Escape.
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard let o = owner, !o.isComposing else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return o.onReturn?() ?? false
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            return o.onEscape?() ?? false
        }
        // Arrow-key seams for an embedding combo box. nil ⇒ `?? false` falls
        // through to the field editor exactly as before (a bare field).
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            return o.onMoveDown?() ?? false
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            return o.onMoveUp?() ?? false
        }
        return false
    }
}

/// An `NSTextField` that pings on EVERY first-responder edge (gain AND loss).
/// The owner doesn't trust the edge's direction — it reconciles focus from the
/// settled responder state afterwards — so this only needs to say "something
/// changed", which `controlTextDidBeginEditing` doesn't reliably do on a bare
/// click (and the editable field redirects to its field editor, so `super`'s
/// return is unreliable too).
@MainActor
private final class FocusReportingTextField: NSTextField {
    var onResponderEdge: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        onResponderEdge?()
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        onResponderEdge?()
        return ok
    }
}

#if DEBUG
// Test-only window into the live focus appearance, so a deterministic test can
// assert the highlight engaged on a BARE focus (no typing) WITHOUT synthetic
// mouse events — the open question synthetic cliclick tests couldn't settle.
// Same-file extension so it can read the private state; not built into release.
extension ThemedTextField {
    struct FocusProbe {
        public let focused: Bool
        public let floated: Bool
        public let borderWidth: CGFloat
        public let borderColor: CGColor?
        public let labelColor: CGColor?
    }
    var focusProbe: FocusProbe {
        FocusProbe(focused: isFocused, floated: floated,
                   borderWidth: strokeLayer.lineWidth,
                   borderColor: strokeLayer.strokeColor,
                   labelColor: labelLayer.foregroundColor)
    }

    /// Test-only window into the laid-out adornment geometry, so a deterministic
    /// test can prove the second-trailing-icon slot is dormant (byte-identical)
    /// when unset and shrinks the text rect by exactly one icon + a gap when set.
    struct GeometryProbe {
        let textRect: NSRect
        let trailingIcon: NSRect?
        let secondTrailingIcon: NSRect?
        let labelStartX: CGFloat
    }
    var geometryProbe: GeometryProbe {
        let g = geometry()
        return GeometryProbe(textRect: g.textRect, trailingIcon: g.trailingIcon,
                             secondTrailingIcon: g.secondTrailingIcon,
                             labelStartX: g.labelStartX)
    }

    /// The GROUND-TRUTH first-responder state (field or its field editor), for an
    /// embedding ThemedComboBox to assert the popup never stole focus.
    var isFirstResponderNow: Bool { isFieldFirstResponder }

    /// The supporting/helper-line font — `.secondaryBody` (11pt medium),
    /// the #8 readability fix. Distinct code path from the floated label.
    func _supportFont() -> NSFont { palette.uiFont(.secondaryBody) }
    /// The floated-label shrink ratio. Guards that decoupling the helper
    /// line from `floatSize` left the label animation untouched (11/13).
    var _floatScale: CGFloat { floatSize / bodySize }
}
#endif
