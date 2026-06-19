// prism — the kit catalog: structured, paste-ready reference info for every
// ThemeKit widget. ONE source of truth: the per-widget "copy ref" button in the
// gallery serializes an entry to the clipboard (so another agent can FIND + USE
// the part), and the future DESIGN.md kit section reads the same array. Pure data
// + a serializer — no AppKit, no views.

import Foundation

/// The gallery's top-level tabs. `palette` (theme foundations) and `chrome` (the
/// fake app mocks) carry no kit component; the other four group the real widgets.
enum KitFamily: String, CaseIterable, Identifiable {
    case palette = "Palette", text = "Text", action = "Action",
         feedback = "Feedback", collection = "Collection", chrome = "Chrome"
    public var id: String { rawValue }
}

/// One ThemeKit component's identifying info — NOT its source. `referenceText`
/// is the paste-ready block the "copy ref" button puts on the clipboard.
struct KitComponent: Identifiable {
    let name, module, kind, summary, consumes: String
    let keyAPI, variants: [String]
    let family: KitFamily
    var id: String { name }

    var referenceText: String {
        var s = "\(name) · \(module) (sill)\n\(kind)\n\n\(summary)\n\nUSE: \(consumes)\n\nKEY API:\n"
        s += keyAPI.map { "  • \($0)" }.joined(separator: "\n")
        s += "\n\nVARIANTS:\n" + variants.map { "  • \($0)" }.joined(separator: "\n")
        return s
    }
}

let kitCatalog: [KitComponent] = [
    KitComponent(
        name: "ThemedTextField", module: "ThemeKit",
        kind: "MUI <TextField> (single-line, outlined/filled/standard with animated floating label)",
        summary: "Themed single-line AppKit text field; re-themes by assigning a ResolvedPalette.",
        consumes: "Embed the NSView directly: `ThemedTextField(palette:)` (a final NSView subclass), addSubview it, set props; it owns its inner field/field-editor and key handling. No child window or controller.",
        keyAPI: [
                 "palette: ResolvedPalette — assign to (re)theme the whole field",
                 "label: String? — floating label; nil = placeholder-only field",
                 "placeholder / helperText / errorText: String? — prompt + support line; errorText flips to error palette",
                 "leadingSymbol / trailingSymbol / secondTrailingSymbol: String? — SF-Symbol adornments (inner slot needs both trailing set)",
                 "onChange / onEndEditing / onFocusChange: closures — text-changed, blur/return-end, focus gained(true)/lost(false)",
                 "onReturn / onEscape / onMoveDown / onMoveUp: (() -> Bool)? — key seams; return true to consume (suppressed while isComposing)",
                 "onTrailingTap / onSecondTrailingTap: (() -> Void)? — tappable trailing icons (e.g. clear)",
                 "stringValue: String get/set; clearText() fires onChange(\"\"); focus(selectingAll:) -> Bool; isComposing: Bool; markAccessibilityComboBox()",
             ],
        variants: [
                 "Variant: .outlined (default, notched floating label) / .filled / .standard (underline)",
                 "States: resting / focused (border+label go primary, 2pt stroke) / error (error palette) / filled-with-clear",
                 "previewFocused: Bool — forces focused appearance for screenshots (no first responder)",
                 "surfaceColor: NSColor? — backdrop for the outlined notch (defaults to palette.background)",
             ],
        family: .text),
    KitComponent(
        name: "ThemedComboBox", module: "ThemeKit",
        kind: "MUI <Autocomplete> (basic, select-only filter field with themed drop-down list)",
        summary: "Per-field controller composing a ThemedTextField + child-window popup; themed by assigning a ResolvedPalette.",
        consumes: "A retained CONTROLLER (not an NSView): `let combo = ThemedComboBox.make(palette:options:)` (or init), then add `combo.field` (a ThemedTextField) to the view tree like a bare field; the controller owns the borderless non-key child-window popup and must be retained for its lifetime (call invalidate() to tear down).",
        keyAPI: [
                 "options: [Item] — full option set (Item.init(_:) makes id==label); reassign re-filters/reframes",
                 "selectedIndex: Int? / selectedItem: Item? — committed pick; setter pushes label silently, does NOT fire onSelect",
                 "onSelect: ((Item?)->Void)? — fired on user commit (row click / Enter / clear / freeSolo blur), nil on clear",
                 "onChange: ((String)->Void)? — live typed text per keystroke; onFocusChange/onOpenChange — edge callbacks",
                 "filter: (([Item],String)->[Item]) — default localized contains; override for startsWith/fuzzy",
                 "emptyActionRow: ((String)->String?)? + onEmptyAction: ((String)->Void)? — opt-in actionable 0-match row (e.g. Create \"#tag\")",
                 "isOptionDisabled: ((Item)->Bool)? — non-selectable rows (tertiary, skipped by nav)",
                 "allowsFreeText / clearsOnEscape / opensOnFocus: Bool — MUI freeSolo / clearOnEscape / openOnFocus toggles (all default false)",
                 "label / placeholder: String? / surfaceColor: NSColor? — forwarded to the embedded field",
             ],
        variants: [
                 "mode: select-only (default, reverts text on blur) vs freeSolo (allowsFreeText, keeps typed text)",
                 "empty state: inert noOptionsText vs actionable emptyActionRow",
                 "popup: open / closed; flips above on underflow; row states = highlighted (selection wash + primary accent bar) / disabled (tertiary) / hovered",
                 "preview seam: previewOpen / previewHighlight force deterministic open+highlight for capture/tests (DEBUG comboProbe)",
             ],
        family: .text),
    KitComponent(
        name: "ThemedButton", module: "ThemeKit",
        kind: "MUI <Button> (basic, three-variant push button)",
        summary: "Themed AppKit push button; re-themes by assigning a PaletteKit ResolvedPalette.",
        consumes: "Embed the NSView directly: it is a public final class ThemedButton: NSControl, init(palette:); add as a subview / wrap in NSViewRepresentable (no controller, no child window).",
        keyAPI: [
                 "palette: ResolvedPalette — theme; assigning re-themes the whole button (didSet)",
                 "title: String — label (drawn UPPERCASE w/ tracking; AX name keeps original case)",
                 "onTap: (() -> Void)? — sill-idiom tap handler; fires alongside NSControl target/action on mouse-up-inside/Space/keyEquivalent",
                 "leadingSymbol/trailingSymbol: String? — SF-Symbol start/end icons tinted to label color",
                 "isEnabled: Bool — NSControl; disabled greys out, clears hover/press, drops first responder",
                 "target/action: AnyObject?/Selector? — standard NSControl activation (custom cell-less storage)",
                 "keyEquivalent/keyEquivalentModifierMask: String/NSEvent.ModifierFlags — set \"\\r\" for the Return default button",
                 "fullWidth: Bool — MUI fullWidth; drops intrinsic width so host/AutoLayout sizes it",
             ],
        variants: [
                 "variant: text / contained / outlined",
                 "size: small / medium / large",
                 "role: primary / secondary / error (ignored while disabled)",
                 "live interaction states: hover / pressed / keyboard-focus(themed ring) / disabled",
                 "previewHovered/previewPressed/previewFocused: Bool — force appearance for deterministic capture",
                 "grouping (ThemedButtonGroup): roundedCorners: CACornerMask, drawnBorderEdges: BorderEdges, groupedShadow: Bool",
             ],
        family: .action),
    KitComponent(
        name: "ThemedButtonGroup", module: "ThemeKit",
        kind: "MUI <ButtonGroup> (basic, joined) — composes real ThemedButtons into one control; .segmented mode adds exclusive single-select",
        summary: "AppKit NSView row/column of joined ThemedButtons, themed by assigning a ResolvedPalette.",
        consumes: "Embed the NSView directly: `ThemedButtonGroup(palette:)`, set segments + props, add as a subview (it sizes via intrinsicContentSize / fullWidth). No controller or child window.",
        keyAPI: [
                 "segments: [Segment] — members; Segment(title, leading:/trailing: SF-symbol, isEnabled:)",
                 "palette: ResolvedPalette — assign to (re)theme group + all members",
                 "mode: Mode — .actions (no selection) vs .segmented (exclusive single-select)",
                 "onTap: ((Int)->Void)? — fires per member tap in .actions mode",
                 "selectedIndex: Int? / onSelect: ((Int)->Void)? — selection in/out for .segmented mode",
                 "variant: ThemedButton.Variant — .text/.outlined(default)/.contained; size: .small/.medium/.large; role: .primary/.secondary/.error",
                 "orientation: Orientation — .horizontal/.vertical (arrows rove focus in segmented)",
                 "isEnabled: Bool / fullWidth: Bool / disableElevation: Bool — group-wide flags fanned to members",
                 "previewSelectedIndex/previewHoveredIndex/previewFocusedIndex: Int? — force state for deterministic capture",
             ],
        variants: [
                 "variant: text / outlined (default) / contained",
                 "size: small / medium / large",
                 "role: primary / secondary / error",
                 "orientation: horizontal / vertical",
                 "mode: actions / segmented",
                 "fullWidth on/off; disableElevation; per-member + group isEnabled",
                 "demoed states: live actions+segmented, hover/focus/selected member, disabled member, fullWidth",
             ],
        family: .action),
    KitComponent(
        name: "ThemedCheckbox", module: "ThemeKit",
        kind: "MUI <Checkbox> (basic, tri-state) — outline-box ↔ primary-filled box with a draw-in checkmark/dash",
        summary: "Themed tri-state AppKit checkbox; styled by assigning a ResolvedPalette.",
        consumes: "Embed directly as an NSView (a self-contained NSControl, no child window/controller): `let c = ThemedCheckbox(palette:)`, set isChecked/label/size + onChange, add to your view; in SwiftUI host via the prism `ThemedCheckboxView: NSViewRepresentable` pattern.",
        keyAPI: [
                 "palette: ResolvedPalette — assign to (re)theme; repaints via didSet",
                 "isChecked: Bool — bound on/off; assigning animates glyph but does NOT fire onChange",
                 "isIndeterminate: Bool — draws dash regardless of isChecked (tri-state)",
                 "onChange: ((Bool)->Void)? — fires ONLY on user toggle (click/Space/keyEquiv); arg = value toggled TO; host may re-set isChecked inside (controlled)",
                 "label: String? — optional trailing label, part of hit area + intrinsic width; nil = bare box",
                 "isEnabled: Bool — NSControl; disabled ignores interaction, drops first-responder",
                 "size: ThemedCheckbox.Size — .small/.medium (box glyph only; hit/hover area constant)",
                 "keyEquivalent/keyEquivalentModifierMask — optional shortcut matched in performKeyEquivalent",
                 "target/action: AnyObject?/Selector? — fired alongside onChange on user toggle",
             ],
        variants: [
                 "size: small / medium",
                 "role: .primary only (v1)",
                 "glyph state: unchecked / checked / indeterminate",
                 "interaction: hover, pressed, focus (themed primary ring), disabled",
                 "preview overrides for deterministic capture: previewHovered/Pressed/Focused + previewChecked/previewIndeterminate (Bool?) — force visuals without mutating bound value or firing events",
             ],
        family: .action),
    KitComponent(
        name: "ThemedFAB", module: "ThemeKit",
        kind: "MUI <Fab> (basic) — circular icon FAB + extended icon+label pill, accent-only",
        summary: "AppKit floating action button, themed by assigning a PaletteKit ResolvedPalette.",
        consumes: "Embed the NSView directly: `let f = ThemedFAB(palette:)`, set leadingSymbol/label/variant/size/role/onTap, add as a subview. No controller/child-window. Circular needs an explicit square frame or it stretches to a pill; extended sizes to intrinsicContentSize.",
        keyAPI: [
                 "palette: ResolvedPalette — assign to (re)theme; didSet repaints",
                 "leadingSymbol: String? — SF Symbol name; whole control if circular, leading adornment if extended",
                 "label: String — extended-only visible text (UPPERCASEd); also AX name for circular",
                 "onTap: (() -> Void)? — tap handler; fires on mouse-up-inside / Space / keyEquivalent (alongside target/action)",
                 "isEnabled: Bool — overridden custom storage; disabled = muted fill, no events/focus",
                 "keyEquivalent: String + keyEquivalentModifierMask — set \"\\r\" to make it the Return default action",
                 "variant/size/role: Variant/Size/Role — see variants",
                 "previewHovered/previewPressed/previewFocused: Bool — force appearance for screenshots only",
             ],
        variants: [
                 "Variant: .circular (icon-only round, default) | .extended (icon+label pill)",
                 "Size: .small | .medium | .large (default; circular dia 40/48/56, extended height 34/40/48)",
                 "Role: .primary (default) | .secondary — accent only, no neutral/error role",
                 "States: rest / hover (0.08 overlay) / pressed (0.12 overlay + deepened elevation) / keyboard-focus (themed primary ring) / disabled",
             ],
        family: .action),
    KitComponent(
        name: "ThemedDivider", module: "ThemeKit",
        kind: "MUI <Divider> (themed device-pixel hairline rule, optional text-in-divider)",
        summary: "A 1-device-pixel separator tinted with the palette's `border` role; horizontal or vertical.",
        consumes: "Embed the NSView directly: `let d = ThemedDivider(palette:); d.orientation/variant/label = …` then add as a subview (decorative — AX-ignored, hitTest returns nil so clicks pass through). No controller, no child window. init?(coder:) is unavailable. Width/height comes from intrinsicContentSize on the thin axis; host sizes the long axis.",
        keyAPI: [
                 "palette: ResolvedPalette — the theme; assigning re-themes the rule (uses the `border` role)",
                 "orientation: Orientation — .horizontal (default) | .vertical (fills host height)",
                 "variant: Variant — .fullWidth (default) | .inset (leading inset, h-only) | .middle (symmetric long-axis margin)",
                 "inset: CGFloat — leading inset for .inset on horizontal rules (default 72; MUI list gutter)",
                 "thickness: CGFloat — point thickness, honored only when deviceHairline=false (default 1)",
                 "deviceHairline: Bool — true (default) = one device pixel, pixel-snapped; false = literal `thickness`",
                 "label: String? — optional centred text-in-divider, horizontal-only (default nil)",
                 "surfaceColor: NSColor? — colour filling the label gap so the rule reads as cut (default palette.background)",
             ],
        variants: [
                 "orientation: horizontal / vertical",
                 "variant: fullWidth / inset / middle (vertical treats .inset as fullWidth)",
                 "deviceHairline true (1px) vs false (literal thickness, e.g. 2pt heavier rule)",
                 "plain rule vs text-in-divider (label, horizontal only)",
             ],
        family: .feedback),
    KitComponent(
        name: "ThemedBorder", module: "ThemeKit",
        kind: "Themed surface border — universal: static primary stroke ↔ live effect rim (glow/breathe/cycle)",
        summary: "The family's ONE themed surface outline; static `primary` stroke by default, the shared `resolveBorder` animator (glowing/breathing/cycling) when given an effect with effects ON. Themed by assigning a ResolvedPalette.",
        consumes: "Embed/overlay the NSView directly: `ThemedBorder(palette:, effect:)` (a final NSView), size it to the surface and add it as a top sibling/overlay (decorative — hitTest returns nil, AX-ignored). It owns its 30 Hz redraw clock + window-visibility/reduce-motion lifecycle. No controller/child window. Resolve the effect from a theme name via `borderEffectFor(_:)` (Effects).",
        keyAPI: [
                 "palette: ResolvedPalette — theme; the static stroke + cycle fallback resolve from `primary`",
                 "effect: EffectSpec? — nil = static primary border; set = the live effect rim (resolve via borderEffectFor(themeName))",
                 "effectsEnabled: Bool — MASTER switch (default true); false rests to the static primary stroke even with an effect set. Pass the SAME flag to ResolvedPalette.animated(forTheme:at:enabled:) so border + widget accents rest together",
                 "cornerRadius / lineWidth: CGFloat — match the host surface; the effect breathes between lineWidth and ~2.5×",
                 "glow: Glow — .none (flat) / .bloom (default, neon halo scaled by the breathing width; the effect rim only)",
                 "previewFrozen: Bool + previewPhase: CGFloat — hold a fixed-phase frame for deterministic capture",
                 "init(palette:effect:) — sole initializer; init?(coder:) unavailable; no callbacks (decorative)",
             ],
        variants: [
                 "mode: static primary stroke (no effect / effects off) vs live effect rim (effect + effects on)",
                 "glow: none / bloom",
                 "states: live-cycling / frozen (previewFrozen) / reduce-motion (rests on the effect steady hue) / auto-stopped when window hidden-miniaturized-occluded",
                 "the effect rim reuses Effects.resolveBorder (rainbow hue-rotate, flash blend, breathing width) — the same animator halo/facet drive",
             ],
        family: .feedback),
    KitComponent(
        name: "ThemedSkeleton", module: "ThemeKit",
        kind: "MUI <Skeleton> (low-alpha loading placeholder with pulse/wave ambient animation)",
        summary: "Themed grey-wash loading placeholder; themed by assigning a ResolvedPalette.",
        consumes: "Embed directly: a host instantiates ThemedSkeleton(palette:) — a plain NSView — sets variant/animation/optional width/height, and adds it as a subview (or bridges it via NSViewRepresentable as prism's ThemedSkeletonView does). No controller or child window.",
        keyAPI: [
                 "palette: ResolvedPalette — theme; init-required and didSet re-tints the wash (muted .subtle ink) live without disturbing a running animation",
                 "variant: Variant — .text/.circular/.rectangular/.rounded shape (default .text)",
                 "animation: Animation — .pulse/.wave/.none ambient motion (default .pulse)",
                 "width: CGFloat? — explicit width; nil ⇒ intrinsic (text/rect span host)",
                 "height: CGFloat? — explicit height; nil ⇒ intrinsic (text from font line, circular = diameter)",
                 "previewFrozen: Bool — hold a fixed mid-cycle phase for deterministic screenshots only (default false)",
                 "init(palette:) — sole initializer; init?(coder:) is unavailable",
                 "no callbacks — purely presentational, AX-ignored placeholder",
             ],
        variants: [
                 "variant: text / circular / rectangular / rounded",
                 "animation: pulse (opacity breath) / wave (gradient sweep) / none (static)",
                 "size: explicit width/height vs intrinsic (text from font, circular diameter, block default)",
                 "states: live-animating / frozen (previewFrozen) / reduce-motion-respecting / auto-torn-down when window hidden-miniaturized-occluded",
             ],
        family: .feedback),
    KitComponent(
        name: "ThemedTooltip", module: "ThemeKit",
        kind: "MUI <Tooltip> (basic) — passive pointer-driven hint bubble",
        summary: "Hover-triggered inverted bubble on a floating child panel; themed by a ResolvedPalette.",
        consumes: "A per-anchor CONTROLLER that owns a free borderless NSPanel (not an NSView you embed); call ThemedTooltip.attach(to:text:palette:placement:) and RETAIN the returned controller (AppKit holds the tracking-area owner weakly — dropping it removes the tooltip).",
        keyAPI: [
                 "text: String — the hint string; reassigning re-measures, repositions, updates anchor AX help",
                 "palette: ResolvedPalette — theme; reassigning re-themes the bubble (mandated contract)",
                 "placement: Placement — preferred side; .auto/.top/.bottom/.leading/.trailing, auto-flips on overflow",
                 "enterDelay: TimeInterval — hover dwell before show (default 0.5s)",
                 "leaveDelay: TimeInterval — grace before hide after exit (default 0.1s)",
                 "show()/hide()/invalidate() — programmatic show, hide, and deterministic teardown (bypass delays)",
                 "previewVisible: Bool — test/capture seam: force-show inline, skip delays+fade",
                 "anchor: NSView (weak, init-only) — the view the tooltip describes; tracking area lives on it",
             ],
        variants: [
                 "Placement axis: top / bottom / leading / trailing / auto (4-side edge-flip)",
                 "States: hidden / hover-dwell-show / shown / fade-out (0.16s fade, respects reduce-motion)",
                 "Text: single-line vs wrapped (wraps past 300px max width)",
                 "Color: inverted surface foreground@0.92 with best-contrast (WCAG) black/white ink — robust on light/dark/neon themes",
             ],
        family: .feedback),
    KitComponent(
        name: "ThemedList", module: "ThemeKit",
        kind: "MUI <List> (basic) — an embeddable themed list/menu row-painter",
        summary: "Embeddable NSView list of mixed-height rows; themed by assigning a PaletteKit ResolvedPalette.",
        consumes: "A host EMBEDS it as a plain NSView (init(palette:), addSubview) — not a child-window controller like ThemedComboBox/ThemedTooltip; it is itself screencapturable. In prism it bridges via ListView: NSViewRepresentable (makeNSView builds ThemedList(palette:), configure closure sets items + props).",
        keyAPI: [
                 "items: [ListItem] — rows (id, image: pre-resolved NSImage?, primary/secondary text, badges: [Badge], trailing: TrailingAccessory, tint: ListTint, kind: .row/.sectionHeader/.separator, isDisabled, axChecked, indentLevel: Int); assign relayouts+repaints",
                 "HIERARCHY (additive, default off): ListItem.indentLevel:Int (0=top; shifts the leading cluster — the image/text, plus a collapsible header's disclosure triangle — right by indentLevel×indentStep; selection/hover fill + leading tint bar stay FULL-BLEED, the MUI tree model) + Kind.sectionHeader(subtitle:collapsed:Bool?) — collapsed nil=plain header (unchanged), false=collapsible+expanded (▾), true=collapsed (▸); a leading disclosure triangle + a clickable header. onToggleSection: ((String)->Void)? fires on a collapsible header click (incl. the pinned sticky header). The kit hides NOTHING — the host owns the collapsed set + rebuilds items (React-component contract). Keyboard toggle + collapsible non-header rows are documented non-goals (v1).",
                 "palette: ResolvedPalette — theme; assigning re-resolves all role colors at draw",
                 "selectedID: String? — committed selection (silent setter); selectRow(_:) is the user-intent variant that fires onSelectionChange",
                 "onActivate: ((ListItem)->Void)? — click/Enter on a row (host's 実処理)",
                 "onSelectionChange: ((String?)->Void)? — committed selection changed by user",
                 "onHover: ((String?)->Void)? — hovered row id (nil on exit)",
                 "emptyActionRow: ((query:String)->String?)? + query + onEmptyAction: ((String)->Void)? — actionable empty state (else noOptionsText)",
                 "setLeadingImage(_:forID:) — patch one row's icon (async favicon) without reload; rowFrame(for:)/scrollToRow/fittingWidth(maxWidth:)/contentHeight — sizing & geometry for a host container",
                 "moveHighlight(_:Int)/activateHighlight()/clearHighlight() — host drives keyboard nav when managesFirstResponder is false",
                 "DRAG LAYER (opt-in, default off): draggable=true gate + dragMode (.dropOnto/.reorderBetween/.both) + onDrop((DragContext,DropTarget)->Void) (host's 実処理 move) + dropTargetValidator((DragContext,DropTarget)->Bool) (domain veto; kit pre-rejects onto-self / no-move / separator / chunk-internal) + dragImageProvider((String)->NSImage?) (the source/header id; override the snapshot ghost). DragContext = { sourceID, memberIDs:[String] } — memberIDs always filled ([sourceID] solo, [header,…children] for a chunk). DropPlacement = .onto(id:) / .between(beforeID:String?)  (nil beforeID = end gap)",
                 "keyboard lift (accessible DnD): beginDrag(id)/moveDragTarget(±1)/commitDrag()/cancelDrag()/isDragging — a managesFirstResponder list routes Space(lift/commit)·↑↓(aim)·⏎(commit)·Esc(cancel) automatically; mouse-drag is the down→drag(threshold 4pt)→up sequence with a non-key child-window ghost. Single-row + chunk lifts share ONE internal KeyboardDragController engine (only the candidate set differs)",
                 "CHUNK REORDER (v1.6.0; the section-header drag — standard once draggable, no opt-in flag): lifting a section HEADER carries the header + its child rows (down to the next header) as ONE unit; onDrop's DragContext.memberIDs is the whole chunk and the host decides reorder-vs-swap (the kit is reorder-only, knows no domain). A chunk can't land inside itself (auto-rejected). Keyboard arrows aim by SECTION boundary (one stop per section, not per row). A non-header row still lifts SOLO. showsReorderGrip:Bool=true draws a 2×3 grip on each draggable header; previewDragChunk:[String]? + previewDropTarget force the static chunk affordance for a prism shot",
             ],
        variants: [
                 "density: .comfortable (30pt rows, combo-parity) / .compact",
                 "selectionMode: .none (hover-only, wand tome) / .single",
                 "hoverStyle: .wash (selection fill + 3pt primary bar, default) / .solidAccent (opaque primary + onPrimary ink)",
                 "roundedSelection (6pt pill) · showsDividers · reservesLeadingImageColumn (default true; false = combo flush) · wrapsHighlight · highlightFollowsHover (menu model)",
                 "FACET POLISH (additive, default off): highlightStyle .fill (default, menu/combo look) / .outline (a stroked primary ring so a keyboard cursor reads distinct from a filled selection) · alternatingRowBackground (zebra; hover@0.4 stripe, no new role; data rows only, parity resets per section header) · horizontalContentScroll (doc widens to the natural content width, text clips not ellipsizes, a themed horizontal ThemedScroller appears, trailing right-aligns to the content edge + scrolls with the row — no frozen column)",
                 "managesFirstResponder (list takes FR + drives ↑↓/⏎/Esc) vs host-driven nav",
                 "vendsRowAXElements (synthetic per-row .menuItem AX children) · surfaceColor override (vibrancy escape hatch)",
                 "row kinds: .row / .sectionHeader(subtitle:collapsed:) (sticky, 1- or 2-line; collapsed Bool? opts into a disclosure triangle) / .separator; indentLevel:Int nests any row/header; ListTint: none/primary/secondary/error/.custom(HexColor); BadgeRole: neutral/primary/secondary/error; TrailingAccessory: none/chevron/shortcut(String)/custom(NSImage)",
                 "drag affordance: .onto lights the target row (2pt primary ring + faint fill); .between draws a 2pt primary insertion line + leading dot in the gap; the lifted source row dims. A CHUNK lift dims EVERY member row and draws a THICKER full-bleed section insertion bar (coarser than a single row's line); the floating ghost is the members' capped (60%) union with an 'N items' badge. grid/rail/real-window drag stay app-side (not in sill); autoscroll-on-drag is a documented follow-up",
                 "capture seams: previewHighlight/previewSelection/previewScrollY/previewScrollX + previewDragSource/previewDropTarget/previewDragChunk (id-keyed, deterministic prism shots — the live ghost is a child window, hand-checked)",
                 "themed scroll: the vertical scroller is a ThemedScroller (public, reusable on any NSScrollView) — its overlay knob is painted palette.muted instead of macOS grey, auto-hiding (shown only while scrolling)",
             ],
        family: .collection),
    KitComponent(
        name: "ThemedMenu", module: "ThemeKit",
        kind: "MUI <Menu> (basic) — a themed floating pop-up menu of action rows",
        summary: "Floating action-menu controller owning a non-key child panel; themed by assigning a ResolvedPalette.",
        consumes: "A retained CONTROLLER (NSObject), not an NSView: build via ThemedMenu.make(palette:items:) (or init), retain it, then call present(from:)/present(at:in:); it owns a borderless non-key PopupPanel hosting a ThemedList — the host window stays key.",
        keyAPI: [
                 "palette: ResolvedPalette — assign to (re)theme; repaints list + panel surface/edge",
                 "items: [MenuItem] — rows; each MenuItem carries title/icon/shortcut/isChecked/isDestructive/isEnabled + its own action closure (実処理). .separator(id:)/.header(_:id:) statics build non-interactive rows",
                 "MenuItem.submenu: [MenuItem] — non-empty ⇒ a ONE-LEVEL cascade: the row opens a child menu beside it (hover-intent / → / click); auto-sets hasSubmenu; the row's own action is ignored (opening the child IS its activation); a child's submenu is ignored (one-level cap)",
                 "present(from: NSView, gap:) — open as a drop-down below an anchor (flips up on underflow)",
                 "present(at: CGPoint, in: NSWindow) — open as a context menu at a point (e.g. event.locationInWindow)",
                 "dismiss(animated:) — close (idempotent); invalidate() — deterministic teardown",
                 "onOpenChange: ((Bool)->Void)? — open/close edge callback",
                 "density: ThemedList.Density — .compact (26pt) or .comfortable (30pt)",
                 "highlightsFirstOnOpen: Bool — pre-light first enabled row on open (default false)",
                 "surfaceColor: NSColor? — override opaque menu surface (defaults to palette.background)",
             ],
        variants: [
                 "row kinds: item / .separator / .header",
                 "item adornments: leading icon, leading checkmark (isChecked), trailing ⌘-shortcut lozenge, trailing submenu chevron (hasSubmenu / non-empty submenu)",
                 "row states: enabled / disabled (isEnabled) / destructive error-tint (isDestructive)",
                 "density: compact (26pt) vs comfortable (30pt)",
                 "placement: anchor drop-down vs context-menu point; one-level submenu child beside its row (.submenu placement, flips left on overflow); corner-anchored Grow scale+fade (reduce-motion gated)",
                 "interaction states demoed: hover/highlight (solidAccent), ↑↓ nav, ⏎/Space activate, → open submenu / ← + Esc close one level, Esc/Tab dismiss",
             ],
        family: .collection),
]

/// Look up a component by its public type name (the names are fixed in the gallery).
func kitComponent(_ name: String) -> KitComponent {
    kitCatalog.first { $0.name == name }
        ?? KitComponent(name: name, module: "ThemeKit", kind: "", summary: "",
                        consumes: "", keyAPI: [], variants: [], family: .text)
}
