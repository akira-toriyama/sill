// ThemeKitUI — ThemedComboBox: an MUI <Autocomplete> (basic) for the family. A
// single-line filter field with a themed drop-down list of options. Themed by
// assigning a PaletteKit `ResolvedPalette`. AppKit shell + SwiftUI list / @MainActor.
//
// It is a per-field CONTROLLER (like `ThemedTooltip`, NOT an NSView): it COMPOSES
// a real `ThemedTextField` as its visible control (so cmd+a/c/v/x/z, the field
// editor, IME, the floating label all come for free) and OWNS a borderless,
// non-activating `PopupPanel` that hosts the option list. The field stays first
// responder THROUGHOUT — the panel never becomes key — so typing keeps working
// while the list is up and clickable.
//
// #17b M3: the drop-down rows are now the SwiftUI-native `ThemedListView` (via
// `HostedThemedList`/`ListController`, hosted in a `HostingListView`), NOT the AppKit
// `ThemedList`. That move is WHY this widget lives in ThemeKitUI (the SwiftUI front)
// while its non-key `PopupPanel` shell + `ThemedTextField` field-editor come from
// ThemeKit (the AppKit floors it depends on) — the reverse edge would cycle. The
// controller is configured `selectionMode = .none` (the COMBO owns the committed
// pick; the dropdown only HIGHLIGHTS) · `hoverStyle = .wash` (+ a `primary` accent
// bar that reads on neon) · `wrapsHighlight` · `highlightFollowsHover` · `hosted`
// (the field keeps first responder; the combo forwards ↑↓/⏎ into the controller and
// the AppKit `mouseUp` commits a row click SYNCHRONOUSLY so the value lands before
// the field's async next-tick focus reconcile). The empty / actionable-empty rows
// are modelled as sentinel-id `ListItem`s (see `emptyActionRowID`/`noOptionsRowID`),
// reusing the list's normal row draw + hit-test.
//
// Canonical roles only: `background` (surface) · `border` (edge) · `foreground`
// (row text) · `selection` (highlight wash) + a `primary` accent bar so the
// highlight reads on neon themes · `tertiary` (disabled) · `muted` ("No options"
// + icons). Focus/active affordances stay `primary` via the embedded field.

import AppKit
import QuartzCore
import Palette
import PaletteKit
import Motion
import ListCore
import ThemeKit          // PopupPanel/themedPopupPanel/placePopup/PopupFade/PopupGlue shell + ThemedTextField field (AppKit floors)

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
    /// caret click, NOT on bare focus.
    public var opensOnFocus = false

    /// The filter. DEFAULT: localized "standard" contains (case- + diacritic- +
    /// width-insensitive substring, MUI `matchFrom: 'any'`). Override for
    /// startsWith / fuzzy. Order is preserved.
    public var filter: (_ options: [Item], _ query: String) -> [Item] = ThemedComboBox.defaultFilter

    /// Marks an option non-selectable: drawn `tertiary`, skipped by arrow nav,
    /// not clickable. DEFAULT nil (all enabled).
    public var isOptionDisabled: ((Item) -> Bool)? { didSet { if isOpen { syncList() } } }

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
    public var noOptionsText = "No options" { didSet { if isOpen { syncList() } } }

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
        didSet { refilter(); if isOpen { syncList(); reframe() } }
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
    public var previewHighlight: Int? { didSet { syncPreviewHighlight() } }

    // MARK: - Internals

    private var _selectedIndex: Int?
    private var committedValue = ""             // last committed label; the blur-revert target
    private var filtered: [Item] = []

    private var panel: PopupPanel?
    private let container = NSView()             // rounded, bordered popup surface
    // #17b M3: the SwiftUI list, driven imperatively via `controller`, hosted in an
    // AppKit `HostingListView` (its `mouseUp` does the synchronous row-click commit).
    private let controller = ListController<String>()
    private var hosting: HostingListView<String>!

    /// Sentinel row ids for the empty states (the SwiftUI list draws + hit-tests them
    /// as normal rows; `controller.onActivate` routes them). Chosen to never collide
    /// with a real option id.
    static let emptyActionRowID = "\u{7f}combo.emptyAction"
    static let noOptionsRowID   = "\u{7f}combo.noOptions"

    private var isOpen = false
    private var isInvalidated = false
    fileprivate var pointerInPopup = false       // raised while the pointer is over a row, lowered on exit + on any dismiss
    private var isCommitting = false             // raised for the synchronous commit window
    private var emptyActionText: String?          // the resolved emptyActionRow label (nil ⇒ inert)

    /// True when the filter is empty AND an actionable empty row is offered — the
    /// single row 0 is then the action row (highlightable / clickable / Enter).
    private var isActionRowActive: Bool { filtered.isEmpty && emptyActionText != nil }

    private var fadeGen = 0                       // monotonic fade token (tooltip discipline)
    nonisolated(unsafe) private var localMon: Any?

    /// The shared 0.12 s fade + host glue (combo dismisses on the host resigning key).
    private let fade = PopupFade(duration: ThemedTransition.Duration.exit)
    private let glue = PopupGlue()

    // Probe state (set by reframe()).
    private var lastPopupFrame: CGRect = .zero
    private var flippedAbove = false

    // MARK: Metrics (final — not configurable in BASIC)
    fileprivate let rowHeight: CGFloat = 30       // == ListMetrics `.comfortable` singleRow
    private let maxVisibleRows = 8
    private let gap: CGFloat = CGFloat(Space.xs)
    private let cornerRadius: CGFloat = CGFloat(Radius.lg)
    // (the visible-frame margin now lives in the shared `popupScreenMargin`;
    //  row insets / fonts / accent-bar now live in ListMetrics `.comfortable`.)

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
        field.trailingSymbol = "caret-down"          // disclosure (outermost trailing icon)
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
        comboFilter(options, query: query, label: { $0.label })
    }

    // MARK: - Theming

    public func applyTheme() {
        field.palette = palette
        applyListTheme()
    }

    private func applyListTheme() {
        // Snap the popup surface like ThemedTextField.applyTheme (these CALayer
        // props would otherwise implicitly cross-fade on a theme switch). The
        // container edge + surface are ALSO read back by `comboProbe` as the real
        // rendered state, so keep painting them here even though the hosted list
        // paints its own surface on top.
        // Snap (no implicit cross-fade) — a theme switch must not smear the surface.
        layerTxn(animated: false) {
            container.layer?.backgroundColor = listSurface.cgColor
            container.layer?.borderColor = palette.border.cgColor
        }
        rehostList()          // re-render the SwiftUI list with the new palette + surface
    }

    private var listSurface: NSColor {
        surfaceColor ?? palette.background ?? .textBackgroundColor
    }

    /// The dropdown's list config — `.none` selection (combo owns the pick), wash +
    /// accent-bar highlight, wrap, hover-drives-highlight, image-less flush rows,
    /// and `hosted` (AppKit `mouseUp` owns the click; the SwiftUI rows are inert).
    private func comboListStyle() -> ThemedListStyle {
        var style = ThemedListStyle()
        style.density = .comfortable
        style.selectionMode = .none
        style.hoverStyle = .wash
        style.wrapsHighlight = true
        style.highlightFollowsHover = true
        style.showsDividers = false
        style.reservesLeadingImageColumn = false   // option rows carry no image → text flush at leadingInset
        style.surfaceColor = listSurface
        style.hosted = true
        return style
    }

    /// Re-render the hosted SwiftUI list (palette/surface live in the value-typed
    /// root, so a theme change rebuilds it; `@Bindable` handles items/highlight).
    private func rehostList() {
        controller.style = comboListStyle()
        hosting?.rootView = HostedThemedList(controller: controller, style: controller.style, palette: palette)
    }

    // MARK: - Options / filter / selection

    private func optionsChanged() {
        let r = reconcileSelection(selectedIndex: _selectedIndex,
                                   committedValue: committedValue,
                                   labels: options.map { $0.label })
        _selectedIndex = r.selectedIndex
        committedValue = r.committedValue
        refilter()
        if isOpen { syncList(); reframe() }
    }

    private func refilter() {
        filtered = filter(options, field.stringValue)
        // Resolve the actionable empty row (consumer decides per the live query).
        emptyActionText = filtered.isEmpty ? emptyActionRow?(field.stringValue) : nil
        // (The highlight index is OWNED by the hosted list now — its `reload`
        // reconciles a stale highlight when `items` change, so the combo no longer
        // clamps a highlight index here.)
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
        field.announceAccessibilityValue(nil)
    }

    private func syncTrailingIcons() {
        // The clear-× appears (inner of the caret) only when there is text.
        field.secondTrailingSymbol = field.stringValue.isEmpty ? nil : "x-circle"
    }

    // MARK: - List sync (push the filtered options into the hosted ThemedList)

    /// Map `filtered` → the list's rows + the live query. The list owns the empty /
    /// actionable-empty rendering (via the `emptyActionRow`/`query` it was wired
    /// with), the highlight, hover, dividers and drawing. A no-op before the panel
    /// (and its list) is lazily created.
    private func syncList() {
        controller.query = field.stringValue
        if filtered.isEmpty {
            // Model the empty state as ONE sentinel row so the list's normal row draw
            // + hit-test cover it: an ENABLED actionable row (→ onEmptyAction) when the
            // consumer offers one, else the inert `tertiary` "No options" row.
            if let label = emptyActionText {
                controller.items = [ListItem(id: Self.emptyActionRowID, primary: label)]
            } else {
                controller.items = [ListItem(id: Self.noOptionsRowID, primary: noOptionsText, isDisabled: true)]
            }
        } else {
            controller.items = filtered.map {
                ListItem(id: $0.id, primary: $0.label, isDisabled: isDisabled($0))
            }
        }
        syncPreviewHighlight()
    }

    /// Forward the combo's index-based `previewHighlight` (capture/test override) to the
    /// controller's id-based highlight; the action row maps to its sentinel id. A nil
    /// `previewHighlight` leaves the LIVE highlight untouched.
    private func syncPreviewHighlight() {
        guard previewHighlight != nil else { return }
        if let pv = previewHighlight, !filtered.isEmpty {
            controller.highlight = filtered[max(0, min(pv, filtered.count - 1))].id
        } else if isActionRowActive {
            controller.highlight = Self.emptyActionRowID
        } else {
            controller.highlight = nil
        }
    }

    // MARK: - Field events

    private func fieldDidChange(_ text: String) {
        refilter()
        syncTrailingIcons()
        if isOpen {
            syncList(); reframe()
        } else if !text.isEmpty || opensOnFocus {
            presentPopup()
        }
        onChange?(text)
    }

    private func handleFocusChange(_ focused: Bool) {
        if focused {
            onFocusChange?(true)
            if opensOnFocus { presentPopup(); controller.clearHighlight() }
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
        // The action row fires even when un-highlighted (combo parity). Otherwise a
        // highlighted row commits (`controller.activateHighlight` → `onActivate` →
        // `commitItem`); with NO highlight, Enter just closes.
        if isActionRowActive {
            fireEmptyAction()
        } else if controller.highlightedID != nil {
            controller.activateHighlight()
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
        if !isOpen { presentPopup(); controller.clearHighlight() }
        controller.moveHighlight(1)
        return true
    }

    private func handleMoveUp() -> Bool {
        if !isOpen { presentPopup(); controller.clearHighlight() }
        controller.moveHighlight(-1)
        return true
    }

    private func isDisabled(_ item: Item) -> Bool { isOptionDisabled?(item) ?? false }

    // MARK: - Commit paths

    /// The SYNCHRONOUS commit (row click via the list's `onActivate`, or Enter via
    /// `activateHighlight`): set the value, close, re-assert first responder — all
    /// before the field's next-tick focus reconcile runs.
    private func commitItem(_ id: String) {
        guard let idx = options.firstIndex(where: { $0.id == id }) else { return }
        isCommitting = true
        setSelection(idx)
        onSelect?(selectedItem)
        dismissPopup(animated: false)
        field.focus(selectingAll: false)             // re-assert (harmless no-op if already FR)
        isCommitting = false
        field.announceAccessibilityValue(selectedItem?.label)
    }

    private func commitFreeText(_ text: String) {
        committedValue = text
        _selectedIndex = options.firstIndex(of: Item(id: text, label: text))
        onSelect?(Item(id: text, label: text))
        field.announceAccessibilityValue(text.isEmpty ? nil : text)
    }

    /// Programmatic commit that FIRES `onSelect` — the firing counterpart of
    /// assigning `selectedIndex` (silent). An out-of-range / nil index clears the
    /// selection and fires `onSelect(nil)`. (User picks still route through
    /// `commitItem`, which also dismisses the popup and re-asserts field focus.)
    public func commitSelection(_ index: Int?) {
        if let index, options.indices.contains(index) {
            setSelection(index)          // silent: sets _selectedIndex + committedValue + field text
            onSelect?(selectedItem)
            field.announceAccessibilityValue(selectedItem?.label)
        } else {
            setSelection(nil)
            onSelect?(nil)
            field.announceAccessibilityValue(nil)
        }
    }

    /// Commit the actionable empty row (via the list's `onEmptyAction`) — same
    /// synchronous discipline as commitItem (beat the field's async focus
    /// reconcile), then hand the query to the consumer, which may freely re-drive
    /// the field (clear / set options / reopen).
    private func fireEmptyAction() {
        guard isActionRowActive else { return }
        let query = field.stringValue
        isCommitting = true
        dismissPopup(animated: false)
        field.focus(selectingAll: false)             // keep first responder
        isCommitting = false
        onEmptyAction?(query)
    }

    // MARK: - Open / close

    private func toggleOpen() {
        if isOpen { dismissPopup() }
        else { field.focus(); presentPopup(); controller.clearHighlight() }
    }

    private func presentPopup(animated: Bool = true, installDismiss: Bool = true) {
        guard !isInvalidated, field.window != nil else { return }
        if isOpen { reframe(); return }              // idempotent re-show
        fadeGen &+= 1
        ensurePanel()
        isOpen = true
        refilter()                                   // the field value may have changed since the last open
                                                     // (a commit pushes the label silently) → never reopen stale
        syncList()
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
        // never gets a hover-exit if the pointer is parked over the (now hidden)
        // rows, so without this the guard would stay raised and swallow the NEXT
        // blur's clearOnBlur revert + onFocusChange(false). Harmless on the
        // synchronous-commit path (commitItem owns isCommitting + re-asserts focus).
        pointerInPopup = false
        controller.clearHighlight()
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

    // MARK: - Panel + hosted list

    private func ensurePanel() {
        guard panel == nil else { return }
        // INTERACTIVE (receives row clicks) + a `.list` AX role — the key deltas vs
        // the passive tooltip. The shared factory configures the rest of the panel.
        let p = themedPopupPanel(interactive: true, role: .list)

        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true        // rows clip to the rounded corners
        container.layer?.borderWidth = 1

        // The hosted shared list — the dropdown engine. Configured to keep the
        // FIELD first responder (managesFirstResponder = false), to only ever
        // HIGHLIGHT (selectionMode = .none — the combo owns the committed pick),
        // to wash + accent-bar the highlight (reads on neon), to wrap, and to let
        // the pointer drive the same highlight the arrows do.
        // Route a row COMMIT (AppKit mouseUp → controller.fireActivate, or Enter →
        // activateHighlight): a sentinel id fires the actionable-empty action; the
        // inert "No options" row is a no-op; a real id commits.
        controller.onActivate = { [weak self] id in
            guard let self else { return }
            if id == Self.emptyActionRowID { self.fireEmptyAction() }
            else if id == Self.noOptionsRowID { /* inert row — no-op */ }
            else { self.commitItem(id) }
        }
        // Drive the `pointerInPopup` guard off the list's hover edge (enter ⇒ id,
        // exit ⇒ nil) — the synchronous mouseUp commit (pointer necessarily over a
        // row, so the guard is already raised) is unaffected.
        controller.onHover = { [weak self] id in self?.pointerInPopup = (id != nil) }
        controller.style = comboListStyle()

        let root = HostedThemedList(controller: controller, style: controller.style, palette: palette)
        let h = HostingListView(controller: controller, rootView: root)
        hosting = h
        container.addSubview(h)
        p.contentView = container
        p.contentView?.setAccessibilityElement(true)  // the popup IS a listbox (role set by the factory)
        // NOTE (BASIC limitation): the field is marked .comboBox (see init) so
        // VoiceOver announces the control + reads the committed value; per-row AX
        // elements are NOT vended (the list's `vendsRowAXElements` stays false — a
        // deferred enhancement, as documented for the combo).
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

        // Lay out the inner tree (panel content is NOT flipped → y-up). The hosted
        // SwiftUI list fills the container inside its 1pt border; it owns its scrolling.
        container.frame = CGRect(origin: .zero, size: frame.size)
        hosting.frame = container.bounds.insetBy(dx: 1, dy: 1)

        // Read the scale from the already-on-screen HOST window — the panel isn't
        // ordered in on the first present, so its backingScaleFactor is stale then.
        // The hosted list draws rows via NSView.draw, whose context scale AppKit
        // derives from the window on display — it owns its backing scale; only the
        // container's bg/border layer needs this explicit pre-order-in sync.
        container.layer?.contentsScale = win.backingScaleFactor

        lastPopupFrame = frame
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
        // No-options text are NOT probed as colours: the hosted list reads the
        // palette roles directly, so a probe field would just echo the input. The
        // row rendering is proven LIVE in prism across light/dark/neon instead.
        let noOptions: Bool
        let emptyActionActive: Bool     // an actionable empty row is offered (0 matches + emptyActionRow)
        let emptyActionLabel: String?   // its resolved label
        let hasOpacityAnimation: Bool
        let reduceMotionRespected: Bool
    }

    /// The highlight index INTO `filtered` — the preview override (clamped) or the
    /// live highlight read back from the hosted list's id-based `highlightedID`.
    private var effectiveHighlight: Int? {
        if let pv = previewHighlight {
            if filtered.isEmpty { return isActionRowActive ? 0 : nil }
            return max(0, min(pv, filtered.count - 1))
        }
        guard let id = controller.highlightedID else { return nil }
        if id == Self.emptyActionRowID { return isActionRowActive ? 0 : nil }
        if id == Self.noOptionsRowID { return nil }
        return filtered.firstIndex(where: { $0.id == id })
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
