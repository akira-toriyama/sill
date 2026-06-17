// ThemeKit — ThemedComboBox: an MUI <Autocomplete> (basic) for the family. A
// single-line filter field with a themed drop-down list of options. Themed by
// assigning a PaletteKit `ResolvedPalette`. AppKit / @MainActor.
//
// It is a per-field CONTROLLER (like `ThemedTooltip`, NOT an NSView): it COMPOSES
// a real `ThemedTextField` as its visible control (so cmd+a/c/v/x/z, the field
// editor, IME, the floating label all come for free) and OWNS a borderless,
// non-activating `NSPanel` that hosts the option list. The field stays first
// responder THROUGHOUT — the panel never becomes key — so typing keeps working
// while the list is up and clickable.
//
// The child-window machinery (panel config, the visibleFrame placement, the
// glue observers, the fade-token teardown, the nonisolated-safe deinit) is
// LIFTED from `ThemedTooltip` as ThemeKit-local code; the shared factory both
// would consume is still DEFERRED. The load-bearing DIFFERENCE: this popup is
// INTERACTIVE (`ignoresMouseEvents = false`), sized to N rows, and commits a
// row click SYNCHRONOUSLY on mouseUp so the value lands before the field's
// (async, next-tick) focus reconcile can run.
//
// Canonical roles only: `background` (surface) · `border` (edge) · `foreground`
// (row text) · `selection` (highlight wash) + a `primary` accent bar so the
// highlight reads on neon themes · `tertiary` (disabled) · `muted` ("No options"
// + icons). Focus/active affordances stay `primary` via the embedded field.

import AppKit
import QuartzCore
import Palette
import PaletteKit

@MainActor
public final class ThemedComboBox: NSObject {

    // MARK: - Item

    /// A single option. `id` is the stable identity surfaced in `onSelect`;
    /// `label` is the displayed + filtered text. `init(_:)` builds an item whose
    /// id == label (the common String case).
    public struct Item: Equatable, Sendable {
        public let id: String
        public let label: String
        public init(id: String, label: String) { self.id = id; self.label = label }
        public init(_ label: String) { self.id = label; self.label = label }
    }

    // MARK: - Public configuration

    /// The visible control. The controller CREATES + OWNS it; the host adds it to
    /// a view tree exactly as it would a bare `ThemedTextField`.
    public let field: ThemedTextField

    /// The theme. Assigning re-themes the field AND the (snapped) popup surface +
    /// rows — the mandated contract.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    /// The full option set. Assigning re-filters against the live query,
    /// reconciles the committed selection (an index into the OLD list may now be
    /// stale), and reframes an open popup (its height tracks the filtered count).
    public var options: [Item] = [] { didSet { optionsChanged() } }

    /// The committed selection index INTO `options` (nil = nothing / cleared).
    /// Assigning pushes the option's label into the field (silently — no
    /// `onChange`) and updates the blur-revert target. It does NOT fire `onSelect`
    /// (a programmatic set is not a user choice); routed through a backing var so
    /// the observer can't recurse.
    public var selectedIndex: Int? {
        get { _selectedIndex }
        set { setSelection(newValue) }
    }
    /// The committed Item, or nil.
    public var selectedItem: Item? {
        _selectedIndex.flatMap { options.indices.contains($0) ? options[$0] : nil }
    }

    /// MUI freeSolo. DEFAULT false = SELECT-ONLY: on blur with no committed pick
    /// the text REVERTS to the last committed value (MUI `clearOnBlur = !freeSolo`).
    /// When true the typed text is KEPT on blur and committed as a free item.
    public var allowsFreeText = false

    /// MUI clearOnEscape (DEFAULT false). When false, Esc only CLOSES the popup
    /// (and falls through to the host when already closed). When true, an Esc with
    /// the popup already closed CLEARS the field + selection.
    public var clearsOnEscape = false

    /// MUI openOnFocus (DEFAULT false). The popup opens on type / ArrowDown /
    /// chevron click, NOT on bare focus.
    public var opensOnFocus = false

    /// The filter. DEFAULT: localized "standard" contains (case- + diacritic- +
    /// width-insensitive substring, MUI `matchFrom: 'any'`). Override for
    /// startsWith / fuzzy. Order is preserved.
    public var filter: (_ options: [Item], _ query: String) -> [Item] = ThemedComboBox.defaultFilter

    /// Marks an option non-selectable: drawn `tertiary`, skipped by arrow nav,
    /// not clickable. DEFAULT nil (all enabled).
    public var isOptionDisabled: ((Item) -> Bool)?

    /// MUI label (floats) — forwarded to the embedded field.
    public var label: String? { didSet { field.label = label } }
    /// MUI placeholder — forwarded to the embedded field.
    public var placeholder: String {
        get { field.placeholder } set { field.placeholder = newValue }
    }
    /// Surface behind the field AND the popup (lifted-panel hosts set their panel
    /// colour). Defaults to `palette.background`.
    public var surfaceColor: NSColor? {
        didSet { field.surfaceColor = surfaceColor; applyListTheme() }
    }

    /// Shown as a single non-selectable row when the filter matches nothing AND
    /// `emptyActionRow` is nil (or returns nil for the query).
    public var noOptionsText = "No options"

    /// OPT-IN actionable empty state. When the filter matches NOTHING, this is
    /// called with the live query; return a row label (e.g. facet's
    /// `Create "#tag"`) to show an ACTIONABLE row in place of the inert
    /// `noOptionsText`, or nil to keep the inert text. The row participates in
    /// arrow-highlight / Enter / click exactly like a normal row, and committing
    /// it fires `onEmptyAction(query)`. DEFAULT nil ⇒ the empty state is the inert
    /// `noOptionsText`, unchanged. sill knows nothing about the domain — the
    /// consumer (facet) owns the label text, validity (return nil to stay inert),
    /// and what the action does.
    public var emptyActionRow: ((_ query: String) -> String?)? {
        didSet { refilter(); if isOpen { renderRows(); reframe() } }
    }
    /// Fired when the `emptyActionRow` row is committed (click / Enter), carrying
    /// the live query. The popup is dismissed + first responder re-asserted first
    /// (the synchronous-commit discipline), so the handler runs with the field
    /// focused and may freely re-drive it (clear, set options, reopen).
    public var onEmptyAction: ((_ query: String) -> Void)?

    // MARK: Callbacks

    /// Live typed text on every keystroke (mirrors `field.onChange`).
    public var onChange: ((String) -> Void)?
    /// A COMMITTED selection — a row click, Enter on the highlight, a clear (nil),
    /// or a freeSolo blur-commit. NOT fired by a programmatic `selectedIndex`.
    public var onSelect: ((Item?) -> Void)?
    /// Field focus edge — true on gain, false once a blur settles (mirrors
    /// `field.onFocusChange`; a row click is NOT reported as a blur).
    public var onFocusChange: ((Bool) -> Void)?
    /// Popup open / close edge.
    public var onOpenChange: ((Bool) -> Void)?

    // MARK: Preview / capture seam

    /// Force the popup OPEN inline — no dismiss monitors registered (an outside
    /// click must not tear down a forced capture), no fade — deterministic still
    /// capture + tests (the `previewVisible` analogue). Populated from the CURRENT
    /// filter.
    public var previewOpen = false {
        didSet {
            guard previewOpen != oldValue else { return }
            if previewOpen { presentPopup(animated: false, installDismiss: false) }
            else { dismissPopup(animated: false) }
        }
    }
    /// Force a highlighted row (index into the FILTERED list) for capture/tests;
    /// nil = the live highlight. Clamped on read.
    public var previewHighlight: Int? { didSet { renderRows() } }

    // MARK: - Internals

    private var _selectedIndex: Int?
    private var committedValue = ""             // last committed label; the blur-revert target
    private var filtered: [Item] = []

    private var panel: PopupPanel?
    private let container = NSView()             // rounded, bordered popup surface
    private let scrollView = NSScrollView()
    private var listView: ComboListView!         // flipped document view (custom-drawn rows)

    private var isOpen = false
    private var isInvalidated = false
    fileprivate var pointerInPopup = false       // raised on row mouseEntered/mouseDown, lowered on mouseExited/mouseUp + on any dismiss
    private var isCommitting = false             // raised for the synchronous commit window
    private var highlightedRow: Int?             // index into `filtered` (or 0 = the action row)
    private var emptyActionText: String?          // the resolved emptyActionRow label (nil ⇒ inert)

    /// True when the filter is empty AND an actionable empty row is offered — the
    /// single row 0 is then the action row (highlightable / clickable / Enter).
    private var isActionRowActive: Bool { filtered.isEmpty && emptyActionText != nil }

    private var fadeGen = 0                       // monotonic fade token (tooltip discipline)
    nonisolated(unsafe) private var localMon: Any?

    /// The shared 0.12 s fade + host glue (combo dismisses on the host resigning key).
    private let fade = PopupFade(duration: 0.12)
    private let glue = PopupGlue()

    // Probe state (set by reframe()).
    private var lastPopupFrame: CGRect = .zero
    private var flippedAbove = false

    // MARK: Metrics (final — not configurable in BASIC)
    fileprivate let rowHeight: CGFloat = 30
    private let maxVisibleRows = 8
    private let gap: CGFloat = 4
    private let cornerRadius: CGFloat = 8
    // (the visible-frame margin now lives in the shared `popupScreenMargin`)
    private let rowInset: CGFloat = 12
    private let bodySize: CGFloat = 13
    private let accentBarWidth: CGFloat = 3

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        self.field = ThemedTextField(palette: palette)
        super.init()
        configureField()
        refilter()
        applyTheme()
    }

    /// Build + return the RETAINED controller (one-liner ergonomics, like
    /// `ThemedTooltip.attach`). The caller MUST retain it — the popup + monitors
    /// live as long as the controller does.
    @discardableResult
    public static func make(palette: ResolvedPalette, options: [Item] = []) -> ThemedComboBox {
        let c = ThemedComboBox(palette: palette)
        c.options = options
        return c
    }

    private func configureField() {
        field.trailingSymbol = "chevron.down"        // disclosure (outermost trailing icon)
        field.onTrailingTap = { [weak self] in self?.toggleOpen() }
        field.onSecondTrailingTap = { [weak self] in self?.clear(); self?.field.focus() }
        field.onChange = { [weak self] text in self?.fieldDidChange(text) }
        field.onFocusChange = { [weak self] on in self?.handleFocusChange(on) }
        field.onReturn = { [weak self] in self?.handleReturn() ?? false }
        field.onEscape = { [weak self] in self?.handleEscape() ?? false }
        field.onMoveDown = { [weak self] in self?.handleMoveDown() ?? false }
        field.onMoveUp = { [weak self] in self?.handleMoveUp() ?? false }
        field.markAccessibilityComboBox()
        syncTrailingIcons()
    }

    // MARK: - Default filter

    /// Localized "standard" contains — case-, diacritic- and width-insensitive
    /// substring, honouring the current locale (so "AP" finds "Grape", "café"
    /// finds "cafe"). Empty query ⇒ the full list.
    nonisolated static func defaultFilter(_ options: [Item], _ query: String) -> [Item] {
        guard !query.isEmpty else { return options }
        return options.filter { $0.label.localizedStandardContains(query) }
    }

    // MARK: - Theming

    public func applyTheme() {
        field.palette = palette
        applyListTheme()
    }

    private func applyListTheme() {
        // Snap the popup surface like ThemedTextField.applyTheme (these CALayer
        // props would otherwise implicitly cross-fade on a theme switch).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.layer?.backgroundColor = listSurface.cgColor
        container.layer?.borderColor = palette.border.cgColor
        CATransaction.commit()
        renderRows()                                // row text/highlight repaint
    }

    private var listSurface: NSColor {
        surfaceColor ?? palette.background ?? .textBackgroundColor
    }

    private func themedFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        switch palette.font {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: weight)
        default:    return .systemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: - Options / filter / selection

    private func optionsChanged() {
        // Re-resolve the committed selection: an index into the old list is
        // meaningless now. Keep it if the SAME item is still present, else clear.
        if let idx = _selectedIndex, options.indices.contains(idx) {
            committedValue = options[idx].label
        } else if !committedValue.isEmpty,
                  let again = options.firstIndex(where: { $0.label == committedValue }) {
            _selectedIndex = again
        } else {
            _selectedIndex = nil
            // committedValue stays as the literal typed/committed string so a
            // freeSolo revert target survives an options reload.
        }
        refilter()
        if isOpen { renderRows(); reframe() }
    }

    private func refilter() {
        filtered = filter(options, field.stringValue)
        // Resolve the actionable empty row (consumer decides per the live query).
        emptyActionText = filtered.isEmpty ? emptyActionRow?(field.stringValue) : nil
        // A filter change invalidates the old highlight index (MUI clears it;
        // the user re-arrows). Clamp rather than guess. Row 0 stays valid when the
        // action row is active (it is the single highlightable row).
        if let h = highlightedRow {
            let valid = isActionRowActive ? (h == 0) : filtered.indices.contains(h)
            if !valid { highlightedRow = nil }
        }
    }

    /// The ONLY internal selection mutator — bypasses the public `didSet` (which
    /// would recurse) and never fires `onSelect`. Pushes the label silently.
    private func setSelection(_ idx: Int?) {
        if let idx, options.indices.contains(idx) {
            _selectedIndex = idx
            committedValue = options[idx].label
            field.stringValue = committedValue       // silent setter (no onChange)
        } else {
            _selectedIndex = nil
            committedValue = ""
            field.stringValue = ""
        }
        syncTrailingIcons()
    }

    /// Clear field + selection AS A USER ACTION (the × button / Esc-clear): fires
    /// `onChange("")` (so a bound list refreshes) AND `onSelect(nil)` once.
    private func clear() {
        _selectedIndex = nil
        committedValue = ""
        field.clearText()                            // sets "" + fires field.onChange("") → fieldDidChange
        onSelect?(nil)
    }

    private func syncTrailingIcons() {
        // The clear-× appears (inner of the chevron) only when there is text.
        field.secondTrailingSymbol = field.stringValue.isEmpty ? nil : "xmark.circle.fill"
    }

    // MARK: - Field events

    private func fieldDidChange(_ text: String) {
        refilter()
        syncTrailingIcons()
        if isOpen {
            renderRows(); reframe()
        } else if !text.isEmpty || opensOnFocus {
            presentPopup()
        }
        onChange?(text)
    }

    private func handleFocusChange(_ focused: Bool) {
        if focused {
            onFocusChange?(true)
            if opensOnFocus { presentPopup(); highlightedRow = nil; renderRows() }
            return
        }
        // Blur. A row interaction in flight is NOT a real blur — the synchronous
        // commit re-asserts focus, so skip the dismiss/revert and don't report it.
        if pointerInPopup || isCommitting { return }
        if isOpen { dismissPopup() }
        if allowsFreeText {
            commitFreeText(field.stringValue)
        } else if field.stringValue != committedValue {
            field.stringValue = committedValue       // MUI clearOnBlur revert (silent)
            refilter()
        }
        syncTrailingIcons()
        onFocusChange?(false)
    }

    private func handleReturn() -> Bool {
        guard isOpen else { return false }           // closed → let the host's Return fire
        if isActionRowActive { fireEmptyAction(); return true }   // Enter commits the action row
        if let h = highlightedRow, filtered.indices.contains(h), !isDisabled(filtered[h]) {
            commitRow(h)
        } else {
            dismissPopup()
        }
        return true
    }

    private func handleEscape() -> Bool {
        if isOpen { dismissPopup(); return true }    // close only (MUI clearOnEscape=false)
        if clearsOnEscape { clear(); return true }
        return false                                  // let the host handle Esc (e.g. close a sheet)
    }

    private func handleMoveDown() -> Bool {
        if !isOpen { presentPopup(); highlightedRow = nil }
        moveHighlight(1)
        return true
    }

    private func handleMoveUp() -> Bool {
        if !isOpen { presentPopup(); highlightedRow = nil }
        moveHighlight(-1)
        return true
    }

    private func isDisabled(_ item: Item) -> Bool { isOptionDisabled?(item) ?? false }

    /// Advance the highlight to the next/previous ENABLED row, WRAPPING (MUI
    /// disableListWrap=false). All-disabled ⇒ no highlight.
    private func moveHighlight(_ delta: Int) {
        if isActionRowActive {                       // the single action row is the only target
            highlightedRow = 0; renderRows(); return
        }
        guard !filtered.isEmpty else { highlightedRow = nil; return }
        let n = filtered.count
        var idx = highlightedRow ?? (delta > 0 ? -1 : 0)
        for _ in 0..<n {
            idx = ((idx + delta) % n + n) % n
            if !isDisabled(filtered[idx]) {
                highlightedRow = idx
                renderRows()
                scrollHighlightVisible()
                return
            }
        }
        highlightedRow = nil
        renderRows()
    }

    // MARK: - Commit paths

    /// The SYNCHRONOUS commit (row click / Enter): set the value, close, re-assert
    /// first responder — all before the field's next-tick focus reconcile runs.
    private func commitRow(_ filteredIndex: Int) {
        guard filtered.indices.contains(filteredIndex) else { return }
        let item = filtered[filteredIndex]
        guard !isDisabled(item) else { return }
        isCommitting = true
        setSelection(options.firstIndex(of: item))
        onSelect?(selectedItem)
        dismissPopup(animated: false)
        field.focus(selectingAll: false)             // re-assert (harmless no-op if already FR)
        isCommitting = false
    }

    private func commitFreeText(_ text: String) {
        committedValue = text
        _selectedIndex = options.firstIndex(of: Item(id: text, label: text))
        onSelect?(Item(id: text, label: text))
    }

    /// Commit the actionable empty row — same synchronous discipline as commitRow
    /// (beat the field's async focus reconcile), then hand the query to the
    /// consumer, which may freely re-drive the field (clear / set options / reopen).
    private func fireEmptyAction() {
        guard isActionRowActive else { return }
        let query = field.stringValue
        isCommitting = true
        dismissPopup(animated: false)
        field.focus(selectingAll: false)             // keep first responder
        isCommitting = false
        onEmptyAction?(query)
    }

    fileprivate func handleRowClick(_ row: Int) {
        guard isOpen else { return }
        if isActionRowActive { if row == 0 { fireEmptyAction() }; return }
        guard !filtered.isEmpty, filtered.indices.contains(row) else { return }
        guard !isDisabled(filtered[row]) else { return }   // disabled: no commit, no dismiss
        commitRow(row)
    }

    fileprivate func hoverHighlight(_ row: Int?) {
        if isActionRowActive {                       // only row 0 (the action row) highlights
            if row == 0, highlightedRow != 0 { highlightedRow = 0; renderRows() }
            return
        }
        guard let row, filtered.indices.contains(row), !isDisabled(filtered[row]) else { return }
        guard row != highlightedRow else { return }
        highlightedRow = row
        renderRows()
    }

    // MARK: - Open / close

    private func toggleOpen() {
        if isOpen { dismissPopup() }
        else { field.focus(); presentPopup(); highlightedRow = nil; renderRows() }
    }

    private func presentPopup(animated: Bool = true, installDismiss: Bool = true) {
        guard !isInvalidated, field.window != nil else { return }
        if isOpen { reframe(); return }              // idempotent re-show
        fadeGen &+= 1
        ensurePanel()
        isOpen = true
        refilter()                                   // the field value may have changed since the last open
                                                     // (a commit pushes the label silently) → never reopen stale
        renderRows()
        reframe()
        if let panel { panel.orderFrontRegardless() }   // NEVER makeKey — keep the field first responder
        if installDismiss { startGlue(); installMouseMonitor() }
        fadeIn(animated: animated && !reduceMotion)
        onOpenChange?(true)
    }

    private func dismissPopup(animated: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        // Clear the in-flight-interaction guard on EVERY close path: a non-mouseUp
        // dismiss (Esc / Return-with-no-highlight / outside-click / didResignKey)
        // never gets a mouseExited if the pointer is parked over the (now hidden)
        // rows, so without this the guard would stay raised and swallow the NEXT
        // blur's clearOnBlur revert + onFocusChange(false). Harmless on the
        // synchronous-commit path (commitRow owns isCommitting + re-asserts focus).
        pointerInPopup = false
        highlightedRow = nil
        stopGlue()
        removeMouseMonitor()
        fadeOut(animated: animated && !reduceMotion)
        onOpenChange?(false)
    }

    /// Deterministic teardown — idempotent; also reached from `deinit`.
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        stopGlue()
        removeMouseMonitor()
        panel?.orderOut(nil)
        panel = nil
        isOpen = false
    }

    // MARK: - Panel + list tree

    private func ensurePanel() {
        guard panel == nil else { return }
        // INTERACTIVE (receives row clicks) + a `.list` AX role — the key deltas vs
        // the passive tooltip. The shared factory configures the rest of the panel.
        let p = themedPopupPanel(interactive: true, role: .list)

        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true        // rows clip to the rounded corners
        container.layer?.borderWidth = 1

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false

        let lv = ComboListView(combo: self)
        lv.rowHeight = rowHeight
        listView = lv
        scrollView.documentView = lv
        container.addSubview(scrollView)
        p.contentView = container
        p.contentView?.setAccessibilityElement(true)  // the popup IS a listbox (role set by the factory)
        // NOTE (BASIC limitation): individual rows are custom-drawn and do NOT
        // yet vend per-row AX elements. The field is marked .comboBox (see init)
        // so VoiceOver announces the control + reads the committed value; vending
        // a child element per option is a deferred enhancement.
        panel = p
        applyListTheme()
    }

    /// Place + size the popup against the field: width = the field's on-screen
    /// width, sits `gap` below, flips above only when it would underflow the
    /// visible frame. (1-D flip — no arrow. Reuses the tooltip's screen-by-geometry
    /// pick + margin clamp + invalidateShadow discipline.)
    private func reframe() {
        guard let panel, let win = field.window else { return }
        let onScreen = win.convertToScreen(field.convert(field.bounds, to: nil))

        let rowCount = filtered.isEmpty ? 1 : filtered.count
        let visibleRows = max(1, min(rowCount, maxVisibleRows))
        let height = CGFloat(visibleRows) * rowHeight + 2     // +2 for the 1pt border top/bottom

        // Shared engine: width = the field's on-screen width, sits `gap` below,
        // flips above only on underflow, clamp + setFrame + invalidateShadow.
        guard case let .anchorWidthBelow(frame, flipped)? =
                placePopup(panel, anchorRectOnScreen: onScreen,
                           .anchorWidthBelow(gap: gap, height: height))
        else { return }
        flippedAbove = flipped

        // Lay out the inner tree (panel content is NOT flipped → y-up).
        container.frame = CGRect(origin: .zero, size: frame.size)
        scrollView.frame = container.bounds.insetBy(dx: 1, dy: 1)
        let docWidth = scrollView.contentView.bounds.width
        listView.frame = CGRect(x: 0, y: 0, width: docWidth,
                                height: CGFloat(rowCount) * rowHeight)

        // Read the scale from the already-on-screen HOST window — the panel isn't
        // ordered in on the first present, so its backingScaleFactor is stale then.
        let s = win.backingScaleFactor
        container.layer?.contentsScale = s
        listView.layer?.contentsScale = s

        lastPopupFrame = frame
        renderRows()
        scrollHighlightVisible()
    }

    private func renderRows() { listView?.needsDisplay = true }

    private func scrollHighlightVisible() {
        guard let h = highlightedRow, let lv = listView else { return }
        // listView is flipped (row 0 at top) → row rect is straightforward.
        lv.scrollToVisible(CGRect(x: 0, y: CGFloat(h) * rowHeight,
                                  width: lv.bounds.width, height: rowHeight))
    }

    // MARK: - Row drawing (called by ComboListView.draw)

    fileprivate func drawRows(_ view: ComboListView, dirty: NSRect) {
        let width = view.bounds.width
        let textAttrs: (NSColor) -> [NSAttributedString.Key: Any] = { [self] c in
            [.font: themedFont(bodySize), .foregroundColor: c]
        }

        guard !filtered.isEmpty else {
            let r = NSRect(x: 0, y: 0, width: width, height: rowHeight)
            if let actionLabel = emptyActionText {
                // Actionable empty row (e.g. facet "Create #xyz"): foreground text,
                // highlightable like a normal row (selection wash + primary bar).
                if effectiveHighlight == 0 {
                    palette.selection.setFill(); r.fill()
                    palette.primary.setFill()
                    NSRect(x: 0, y: r.minY, width: accentBarWidth, height: rowHeight).fill()
                }
                drawText(actionLabel, in: r, attrs: textAttrs(palette.foreground))
            } else {
                // Inert "No options" — single muted, non-selectable row.
                drawText(noOptionsText, in: r, attrs: textAttrs(palette.muted))
            }
            return
        }

        let effHighlight = effectiveHighlight
        for (i, item) in filtered.enumerated() {
            let rowRect = NSRect(x: 0, y: CGFloat(i) * rowHeight, width: width, height: rowHeight)
            guard rowRect.intersects(dirty) else { continue }
            let disabled = isDisabled(item)
            if i == effHighlight && !disabled {
                palette.selection.setFill()
                rowRect.fill()
                palette.primary.setFill()                       // accent bar — reads on neon themes
                NSRect(x: 0, y: rowRect.minY, width: accentBarWidth, height: rowHeight).fill()
            }
            drawText(item.label, in: rowRect, attrs: textAttrs(disabled ? palette.tertiary : palette.foreground))
        }
    }

    /// The highlight to render — the preview override (clamped) or the live one.
    private var effectiveHighlight: Int? {
        if let pv = previewHighlight {
            if filtered.isEmpty { return isActionRowActive ? 0 : nil }   // only the action row
            return max(0, min(pv, filtered.count - 1))
        }
        return highlightedRow
    }

    private func drawText(_ s: String, in row: NSRect, attrs: [NSAttributedString.Key: Any]) {
        let str = s as NSString
        let size = str.size(withAttributes: attrs)
        // listView is flipped → y grows down; vertically centre the single line.
        let r = NSRect(x: row.minX + rowInset, y: row.minY + (rowHeight - size.height) / 2,
                       width: max(row.width - rowInset * 2, 0), height: size.height)
        str.draw(in: r, withAttributes: attrs)
    }

    // MARK: - Fade (tooltip discipline: monotonic fadeGen guards the orderOut)

    private func fadeIn(animated: Bool) {
        guard panel != nil, let cl = container.layer else { return }
        fade.fadeIn(cl, animated: animated)
    }

    private func fadeOut(animated: Bool) {
        guard let panel, let cl = container.layer else { return }
        // Order out only if this fade still stands (same generation, still closed).
        let gen = fadeGen
        fade.fadeOut(cl, panel: panel, animated: animated) { [weak self] in
            guard let self else { return false }
            return self.fadeGen == gen && !self.isOpen
        }
    }

    // MARK: - Outside-click dismiss (single LOCAL monitor + key-window glue)

    private func installMouseMonitor() {
        removeMouseMonitor()
        // ONE local monitor. Dismiss only when the click is OUTSIDE both the field
        // and the popup; ALWAYS return the event (never swallow the row click or a
        // field click). Cross-app / desktop clicks resign the window's key state →
        // handled by the `didResignKey` glue, not here.
        localMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
            guard let self else { return ev }
            if !self.clickIsInsideFieldOrPopup(ev) { self.dismissPopup() }
            return ev
        }
    }

    private func removeMouseMonitor() {
        if let m = localMon { NSEvent.removeMonitor(m); localMon = nil }
    }

    private func clickIsInsideFieldOrPopup(_ ev: NSEvent) -> Bool {
        if ev.window === panel { return true }
        if ev.window === field.window {
            let p = field.convert(ev.locationInWindow, from: nil)
            return field.bounds.contains(p)
        }
        return false
    }

    // MARK: - Glue (keep the popup pinned; dismiss on host move-out / resign)

    private func startGlue() {
        guard let win = field.window else { return }
        // Unlike the tooltip, the combo ALSO dismisses on the host resigning key
        // (a cross-app / desktop click) — the opt-in `onResignKey`.
        glue.start(window: win, clip: field.enclosingScrollView?.contentView,
                   onGeometryChange: { [weak self] in self?.hostGeometryChanged() },
                   onClose: { [weak self] in self?.dismissPopup(animated: false) },
                   onResignKey: { [weak self] in
                       guard let self, self.isOpen else { return }
                       self.dismissPopup(animated: false)
                   })
    }

    private func stopGlue() { glue.stop() }

    private func hostGeometryChanged() {
        guard isOpen else { return }
        if field.visibleRect.isEmpty { dismissPopup(); return }   // scrolled out of a clip → close
        reframe()
    }

    // MARK: - Helpers

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    deinit {
        // The glue observers are torn down by `PopupGlue`'s own deinit; only the
        // outside-click monitor needs the nonisolated-safe removal here.
        removeMonitorSafely(localMon)
    }
}

// MARK: - ComboListView (flipped, custom-drawn rows, mouse → controller)

@MainActor
private final class ComboListView: NSView {
    weak var combo: ThemedComboBox?           // WEAK — controller owns panel→container→scroll→self
    var rowHeight: CGFloat = 30
    private var trackingArea: NSTrackingArea?

    init(combo: ThemedComboBox) {
        self.combo = combo
        super.init(frame: .zero)
        wantsLayer = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }      // row 0 at top, y grows down
    // Commit on the FIRST click even though the panel isn't key (row enabled-ness
    // is filtered in mouseUp, so this is unconditional).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        combo?.drawRows(self, dirty: dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .mouseMoved,
                                         .inVisibleRect, .activeInActiveApp],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { combo?.pointerInPopup = true }
    override func mouseExited(with event: NSEvent) { combo?.pointerInPopup = false }
    override func mouseMoved(with event: NSEvent) {
        combo?.hoverHighlight(row(for: event))
    }
    override func mouseDown(with event: NSEvent) { combo?.pointerInPopup = true }
    override func mouseUp(with event: NSEvent) {
        if let r = row(for: event) { combo?.handleRowClick(r) }
        combo?.pointerInPopup = false
    }

    /// The row under the event, in this (flipped) doc view's own coordinates so
    /// `y` already includes the scroll offset.
    private func row(for event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        guard p.y >= 0, rowHeight > 0 else { return nil }
        return Int(p.y / rowHeight)
    }
}

#if DEBUG
// Test-only window into the resolved popup state, mirroring `tooltipProbe`. Read
// via `previewOpen`/`previewHighlight` (no synthetic events). Same-file extension
// so it can read the private state; not built into release.
extension ThemedComboBox {
    struct ComboProbe {
        let isOpen: Bool
        let filteredCount: Int
        let highlightedIndex: Int?
        let committedValue: String
        let popupFrame: CGRect
        let flippedAbove: Bool
        let panelOrderedIn: Bool
        let fieldIsFirstResponder: Bool
        let surfaceColor: CGColor?      // read back from container.layer (real rendered state)
        let borderColor: CGColor?       // read back from container.layer (real rendered state)
        // The row highlight (selection wash + primary accent bar) + disabled/
        // No-options text are NOT probed as colours: drawRows reads the palette
        // roles directly, so a probe field would just echo the input. The row
        // rendering is proven LIVE in still across light/dark/neon instead.
        let noOptions: Bool
        let emptyActionActive: Bool     // an actionable empty row is offered (0 matches + emptyActionRow)
        let emptyActionLabel: String?   // its resolved label
        let hasOpacityAnimation: Bool
        let reduceMotionRespected: Bool
    }
    var comboProbe: ComboProbe {
        let animating = container.layer?.animation(forKey: "opacity") != nil
        return ComboProbe(
            isOpen: isOpen,
            filteredCount: filtered.count,
            highlightedIndex: effectiveHighlight,
            committedValue: committedValue,
            popupFrame: lastPopupFrame,
            flippedAbove: flippedAbove,
            panelOrderedIn: panel?.isVisible ?? false,
            fieldIsFirstResponder: field.isFirstResponderNow,
            surfaceColor: container.layer?.backgroundColor,
            borderColor: container.layer?.borderColor,
            noOptions: filtered.isEmpty,
            emptyActionActive: isActionRowActive,
            emptyActionLabel: emptyActionText,
            hasOpacityAnimation: animating,
            reduceMotionRespected: !(reduceMotion && animating))
    }
}
#endif
