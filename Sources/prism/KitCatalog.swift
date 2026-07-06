// prism — the kit catalog: structured, paste-ready reference info for every
// ThemeKit widget. ONE source of truth: the per-widget "copy ref" button in the
// gallery serializes an entry to the clipboard (so another agent can FIND + USE
// the part), and the future DESIGN.md kit section reads the same array. Pure data
// + a serializer — no AppKit, no views.

import Foundation

/// The gallery's top-level tabs, in two GROUPS. The `kit` group is the library
/// showcase — `palette` (theme foundations), `icon`, and the real widget
/// families. The `app` group is one tab per family app, each rendering that
/// app's signature chrome mock (the old single `chrome` tab, split per app).
enum KitFamily: String, CaseIterable, Identifiable {
    // Kit group — foundations + the real ThemeKit widgets.
    case palette = "Palette", icon = "Icons", text = "Text", action = "Action",
         feedback = "Feedback", collection = "Collection", motion = "Motion",
         particles = "Particles"
    // App group — one per family app (replaces the single `chrome` tab).
    case facet = "facet", wand = "wand", perch = "perch",
         halo = "halo", glance = "glance"
    public var id: String { rawValue }

    enum Group { case kit, app }
    /// Which header row this tab lives in.
    var group: Group {
        switch self {
        case .facet, .wand, .perch, .halo, .glance: return .app
        default: return .kit
        }
    }
    /// The Kit row (foundations + widgets), in declaration order.
    static var kitCases: [KitFamily] { allCases.filter { $0.group == .kit } }
    /// The Apps row (one per app), in declaration order.
    static var appCases: [KitFamily] { allCases.filter { $0.group == .app } }
}

/// One ThemeKit component's identifying info — NOT its source. `pasteReadyCore`
/// is the paste-ready block the "copy ref" button puts on the clipboard.
struct KitComponent: Identifiable {
    let name, module, kind, summary, consumes: String
    let keyAPI, variants: [String]
    let family: KitFamily

    // Structured recipe fields (Task 3) — all defaulted so existing entries
    // compile unchanged; only a worked-example entry (ThemedListView) fills them.
    // NOTE: `var`, not `let` — a `let` property with an inline default is FIXED
    // (Swift's memberwise init omits it as a settable parameter entirely), which
    // would make it impossible to override per-entry.
    var defaultType: String = ""
    var imports: [String] = []
    var initSnippet: String = ""
    var cellType: String = ""
    var cellInit: String = ""
    var sourcePath: String = ""
    var appkitEscape: String = ""
    var isAtom: Bool = false

    var id: String { name }

    /// The paste-ready CORE: type-to-use + imports + a minimal compilable-shape
    /// init — what an agent needs to DROP the component into code. Falls back to
    /// gracefully omitting any section whose recipe field is empty (most entries,
    /// until they get their own recipe).
    var pasteReadyCore: String {
        var s = "\(name) — \(kind) (sill · \(module) widget)\n"
        if !defaultType.isEmpty { s += "TYPE TO USE (SwiftUI): \(defaultType)\n" }
        if !imports.isEmpty { s += "IMPORTS:\n" + imports.map { "  \($0)" }.joined(separator: "\n") + "\n" }
        if !initSnippet.isEmpty { s += (isAtom ? "USE:\n" : "MINIMAL:\n") + initSnippet + "\n" }
        if !cellInit.isEmpty { s += "CELL: \(cellInit)\n" }
        if !appkitEscape.isEmpty { s += "ESCAPE HATCH (AppKit only): \(appkitEscape)\n" }
        if !sourcePath.isEmpty { s += "SOURCE: \(sourcePath)  ·  ADVANCED (opt-in) → full API." }
        return s
    }

    /// The full descriptive reference (name/module/kind/summary/key API/variants) —
    /// the ADVANCED, opt-in dump behind `pasteReadyCore`'s "SOURCE" pointer.
    var fullAPI: String {
        var s = "\(name) · \(module) (sill)\n\(kind)\n\n\(summary)\n\nKEY API:\n"
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
                 "leadingSymbol / trailingSymbol / secondTrailingSymbol: String? — Phosphor-slug adornments (inner slot needs both trailing set)",
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
        family: .text,
        defaultType: "ThemedTextFieldView",
        imports: [
            "import ThemeKitUI   // ThemedTextFieldView — the SwiftUI front",
            "import ThemeKit     // ThemedTextField.Variant (.outlined/.filled/.standard)",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
ThemedTextFieldView(palette: resolve(themeSpec), label: "Filter",
                     placeholder: "type to filter…",
                     leading: "magnifying-glass")
""",
        sourcePath: "ThemeKitUI/ThemedTextFieldView.swift",
        appkitEscape: "ThemedTextField (NSView, module ThemeKit) — only if NOT in SwiftUI; ThemedTextFieldView wraps it via NSViewRepresentable for the IME field-editor floor"),
    KitComponent(
        name: "ThemedComboBox", module: "ThemeKitUI",
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
        family: .text,
        defaultType: "ThemedComboBoxView",
        imports: [
            "import ThemeKitUI   // ThemedComboBoxView — the SwiftUI front",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
ThemedComboBoxView(palette: resolve(themeSpec), options: ["Apple", "Banana", "Grape"],
                    label: "Fruit", placeholder: "type to filter…")
""",
        sourcePath: "ThemeKitUI/ThemedComboBoxView.swift",
        appkitEscape: "ThemedComboBox (NSObject controller, module ThemeKit) — a per-field CONTROLLER (not an NSView) that composes a real ThemedTextField as `combo.field` + owns a borderless non-activating PopupPanel; only reach for it directly (skipping ThemedComboBoxView) if you need the controller API (options/selectedIndex/onSelect/commitSelection/emptyActionRow) outside a SwiftUI tree."),
    KitComponent(
        name: "ThemedButton", module: "ThemeKit",
        kind: "MUI <Button> (basic, three-variant push button)",
        summary: "Themed AppKit push button; re-themes by assigning a PaletteKit ResolvedPalette.",
        consumes: "Embed the NSView directly: it is a public final class ThemedButton: NSControl, init(palette:); add as a subview / wrap in NSViewRepresentable (no controller, no child window).",
        keyAPI: [
                 "palette: ResolvedPalette — theme; assigning re-themes the whole button (didSet)",
                 "title: String — label (drawn UPPERCASE w/ tracking; AX name keeps original case)",
                 "onTap: (() -> Void)? — sill-idiom tap handler; fires alongside NSControl target/action on mouse-up-inside/Space/keyEquivalent",
                 "leadingSymbol/trailingSymbol: String? — Phosphor-slug start/end icons tinted to label color",
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
        family: .action,
        defaultType: "ThemedButtonView",
        imports: [
            "import ThemeKitUI    // ThemedButtonView — the SwiftUI front",
            "import PaletteKit    // ResolvedPalette + resolve(_:)",
            "import ThemeKit      // ThemedButton.Variant/Size/Role types used as param defaults",
        ],
        initSnippet: """
ThemedButtonView(
    palette: resolve(themeSpec),
    variant: .contained,
    title: "Button",
    onTap: { }
)
""",
        sourcePath: "ThemeKitUI/ThemedButtonView.swift",
        appkitEscape: "ThemedButton (NSView, module ThemeKit) — only if NOT in SwiftUI; ThemedButtonView is an NSViewRepresentable wrapping it"),
    KitComponent(
        name: "ThemedButtonGroup", module: "ThemeKit",
        kind: "MUI <ButtonGroup> (basic, joined) — composes real ThemedButtons into one control; .segmented mode adds exclusive single-select",
        summary: "AppKit NSView row/column of joined ThemedButtons, themed by assigning a ResolvedPalette.",
        consumes: "Embed the NSView directly: `ThemedButtonGroup(palette:)`, set segments + props, add as a subview (it sizes via intrinsicContentSize / fullWidth). No controller or child window.",
        keyAPI: [
                 "segments: [Segment] — members; Segment(title, leading:/trailing: Phosphor slug, isEnabled:)",
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
        family: .action,
        defaultType: "ThemedButtonGroupView",
        imports: [
            "import SwiftUI       // View front",
            "import ThemeKitUI    // ThemedButtonGroupView — the SwiftUI front",
            "import PaletteKit    // ResolvedPalette + resolve(_:)",
            "import ThemeKit      // ThemedButtonGroup.Orientation / ThemedButton.Variant,Size,Role types used as param defaults",
        ],
        initSnippet: """
ThemedButtonGroupView(
    palette: resolve(themeSpec),
    titles: ["Cut", "Copy", "Paste"],
    onTap: { index in }
)
""",
        sourcePath: "ThemeKitUI/ThemedButtonGroupView.swift",
        appkitEscape: "ThemedButtonGroup (NSView, module ThemeKit) — only if NOT in SwiftUI; ThemedButtonGroupView is an NSViewRepresentable wrapping it"),
    KitComponent(
        name: "ThemedToolBar", module: "ThemeKit",
        kind: "MUI <AppBar> + <Toolbar> (fused) — a horizontal app bar that composes real ThemedButtons",
        summary: "AppKit NSView horizontal app bar (surface fill + elevation + density variants + flex sections), themed by assigning a ResolvedPalette.",
        consumes: "Embed the NSView directly: `ThemedToolBar(palette:)`, set `items` + surface/variant, add as a subview; it sizes via intrinsicContentSize (or stretch it when an item is .flexibleSpace). No controller / child window.",
        keyAPI: [
                 "palette: ResolvedPalette — assign to (re)theme the bar + every composed item",
                 "items: [Item] — .button(ButtonItem) composes a real ThemedButton (title==nil+symbol ⇒ square icon button); .label(String) themed title; .custom(NSView) host view; .flexibleSpace / .fixedSpace(w) / .divider",
                 "surface: .surface(default)/.primary/.secondary/.transparent — MUI AppBar color; a coloured bar re-inks its buttons+label with the contrast (MUI color=inherit)",
                 "variant: .regular(64)/.dense(48)/.compact(40) — MUI Toolbar density; gutter: CGFloat? (nil=24/16/8, 0=disableGutters); itemSpacing: CGFloat",
                 "elevation: Int — 0 = flat + bottom hairline; >0 = drop shadow; corners: .square/.rounded (8pt panel)",
                 "onItemClick: ((Int)->Void)? — item button activation; onItemHover: ((Int?)->Void)? — hovered item changed",
                 "trackingMode: .standard/.nonActivatingPanel — .activeAlways + bar-driven item hover for a non-key launcher panel",
                 "frameOnScreen(ofItem:) -> NSRect? — anchor a child panel below a folder button; previewHoveredItem: Int? — force hover for capture",
             ],
        variants: [
                 "surface: surface / primary / secondary / transparent",
                 "variant: regular / dense / compact",
                 "corners: square (bottom hairline) / rounded (panel); elevation 0 (flat) … 24 (shadow)",
                 "sections: 1 flexibleSpace = left group + right group; 2 = centred element",
                 "items: icon-only square button / icon+label button / label / custom view / divider / fixed+flexible spaces",
                 "tracking: standard (items self-hover) / nonActivatingPanel (bar-driven hover, .activeAlways)",
                 "NOTE: responsive overflow (… menu) is a follow-up; an over-long row extends past the bar",
             ],
        family: .action,
        defaultType: "ThemedToolBarView",
        imports: [
            "import ThemeKitUI   // ThemedToolBarView — the SwiftUI bridge for ThemeKit's ThemedToolBar",
            "import ThemeKit     // ThemedToolBar.Surface / .Variant / .Corners / .TrackingMode enums referenced by the bridge's params",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
let palette = resolve(themeSpec)
let items: [ThemedToolBarView.Item] = [
    .button(title: nil, symbol: "list"),
    .label("Inbox"),
    .flex,
    .button(title: "Compose", symbol: "note-pencil", variant: .contained),
]
ThemedToolBarView(palette: palette, items: items) { index in
    // onItemClick — index into `items`
}
""",
        cellType: "ThemedToolBarView.Item",
        cellInit: ".button(title: nil, symbol: \"list\")",
        sourcePath: "ThemeKitUI/ThemedToolBarView.swift",
        appkitEscape: "ThemedToolBar (NSView, module ThemeKit) — only if NOT in SwiftUI; ThemedToolBarView.makeNSView hosts it directly"),
    KitComponent(
        name: "ThemedChip", module: "ThemeKit",
        kind: "MUI <Chip> fused with HTML <kbd> — a compact token: tag / status pill / keycap",
        summary: "Themed compact AppKit token (tag / status / keycap), themed by assigning a ResolvedPalette.",
        consumes: "Embed the NSView directly: it is a public final class ThemedChip: NSControl, init(palette:); add as a subview / wrap in NSViewRepresentable (no controller, no child window). Hugs its label (intrinsicContentSize, minWidth 0).",
        keyAPI: [
                 "palette: ResolvedPalette — theme; assigning re-themes the whole chip (didSet)",
                 "title: String — label drawn AS-IS (not uppercased); a keycap's glyph run, e.g. \"⇧⌘N\"",
                 "leadingSymbol: String? / leadingImage: NSImage? — Phosphor-slug or pre-resolved leading icon (image wins); NO trailing icon slot (the trailing end is the × delete)",
                 "isSelected: Bool — filter-chip ON; paints the canonical selection wash (neutral) / a role wash (otherwise)",
                 "onTap: (() -> Void)? — non-nil ⇒ CLICKABLE (hover/press/focus ring/Space + NSControl target/action); nil ⇒ static",
                 "onDelete: (() -> Void)? — non-nil ⇒ trailing × (Phosphor x-circle, own hover; Backspace/Delete fires it while focused)",
                 "isEnabled: Bool — NSControl; disabled greys out + clears hover/press + drops first responder",
                 "previewHovered/previewPressed/previewFocused: Bool — force appearance for deterministic capture (DEBUG chipProbe)",
             ],
        variants: [
                 "variant: filled (default, calm muted wash for neutral / opaque role fill) / outlined (stroked, clear) / keycap (mono, key-shaped <kbd>, role ignored)",
                 "size: small (24h) / medium (32h) — MUI Chip has no large",
                 "role: neutral (default) / primary / secondary / error — keycap is always neutral",
                 "corner: pill (height/2) for filled+outlined; 5pt key for keycap; minWidth = height for a 1-glyph keycap (square)",
                 "interaction (clickable only): hover / pressed / keyboard-focus (themed ring) / disabled",
                 "selected: emphasized fill (selection wash) — independent of clickable",
             ],
        family: .action,
        defaultType: "ThemedChipView",
        imports: [
            "import ThemeKitUI   // ThemedChipView — the public SwiftUI front",
            "import ThemeKit     // ThemedChip.Variant / .Size / .Role enums",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
  let palette = resolve(themeSpec)
  ThemedChipView(palette: palette, variant: .filled, size: .medium, role: .neutral,
                 title: "Tag", leading: nil, selected: false, enabled: true,
                 clickable: true, deletable: false, onTap: { })
""",
        sourcePath: "ThemeKitUI/ThemedChipView.swift",
        appkitEscape: "ThemedChip (NSView, module ThemeKit) — the real AppKit chip ThemedChipView wraps via NSViewRepresentable; drop to it only if ThemedChipView can't be hosted (e.g. non-SwiftUI AppKit call site)"),
    KitComponent(
        name: "ThemedPill", module: "ThemeKitUI",
        kind: "Display/indicator pill — perch's universal hint pill in ONE SwiftUI surface (tag/badge/status/search-indicator)",
        summary: "Pure-SwiftUI display pill: 5 shapes, two-color typed-prefix label, idle/matched/miss, frost, drop shadow, corner badge. Non-interactive (use ThemedChip for clickable tokens).",
        consumes: "A SwiftUI View: ThemedPillView(palette:label:…). Composes ThemedBackdropView for the surface; hit-test passes through (host in any SwiftUI hierarchy, e.g. a perch overlay via NSHostingView).",
        keyAPI: [
                 "palette: ResolvedPalette — theme (canonical roles only)",
                 "label: String + typedCount: Int — two-color typed-prefix (first N chars in accent/miss colour, rest in foreground)",
                 "shape: .pill / .square / .circle / .underline / .tag",
                 "state: .idle / .matched / .miss — border/glow per result (fill unchanged on matched, error wash on miss)",
                 "accent: Color? — override palette.primary (perch [overlay].accent); surfaceAlpha: Double? + frosted: Bool — translucency + .ultraThinMaterial",
                 "badge: String? — optional top-right corner badge; elevated: Bool — themed drop shadow; transform/opacity — app-driven motion passthrough",
                 "borderEffect: EffectSpec? — animated neon/effect rim across ALL shapes (#17k, built on AnimatedBorderView; nil = static tri-state border). borderGlow / borderCycleSeconds / flashToken tune it",
             ],
        variants: [
                 "shape: pill (capsule) / square (r1) / circle (single-glyph, else pill) / underline (body-less + accent bar) / tag (rounded + left triangle)",
                 "state: idle (accent hairline) / matched (accent stroke + glow, fill unchanged) / miss (error fill + error border + error prefix)",
                 "fill: solid / scrim(surfaceAlpha) / frosted (Material)",
                 "borderEffect: nil (static tri-state) / set (animated neon rim — cycles + blooms on idle/matched, suppressed on miss; underline becomes a neon bar)",
             ],
        family: .action,
        defaultType: "ThemedPillView",
        imports: [ "import ThemeKitUI   // ThemedPillView", "import PaletteKit   // resolve(_:) → ResolvedPalette" ],
        initSnippet: """
  let palette = resolve(themeSpec)
  ThemedPillView(palette: palette, label: "GH")
""",
        sourcePath: "ThemeKitUI/ThemedPillView.swift"),
    KitComponent(
        name: "ThemedCheckbox", module: "ThemeKit",
        kind: "MUI <Checkbox> (basic, tri-state) — outline-box ↔ primary-filled box with a draw-in checkmark/dash",
        summary: "Themed tri-state AppKit checkbox; styled by assigning a ResolvedPalette.",
        consumes: "Embed directly as an NSView (a self-contained NSControl, no child window/controller): `let c = ThemedCheckbox(palette:)`, set isChecked/label/size + onChange, add to your view; in SwiftUI host via ThemeKitUI's `ThemedCheckboxView: NSViewRepresentable`.",
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
        family: .action,
        defaultType: "ThemedCheckboxView",
        imports: [
            "import ThemeKitUI   // ThemedCheckboxView — SwiftUI front (NSViewRepresentable)",
            "import ThemeKit     // ThemedCheckbox.Size (the .small/.medium enum used by the view)",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
ThemedCheckboxView(
    palette: resolve(themeSpec),
    label: "Enable notifications",
    isChecked: on,
    onChange: { on = $0 }
)
""",
        sourcePath: "ThemeKitUI/ThemedCheckboxView.swift",
        appkitEscape: "ThemedCheckbox (NSControl, module ThemeKit) — only if NOT usable via SwiftUI; ThemedCheckboxView already wraps it as makeNSView/updateNSView."),
    KitComponent(
        name: "ThemedFAB", module: "ThemeKit",
        kind: "MUI <Fab> (basic) — circular icon FAB + extended icon+label pill, accent-only",
        summary: "AppKit floating action button, themed by assigning a PaletteKit ResolvedPalette.",
        consumes: "Embed the NSView directly: `let f = ThemedFAB(palette:)`, set leadingSymbol/label/variant/size/role/onTap, add as a subview. No controller/child-window. Circular needs an explicit square frame or it stretches to a pill; extended sizes to intrinsicContentSize.",
        keyAPI: [
                 "palette: ResolvedPalette — assign to (re)theme; didSet repaints",
                 "leadingSymbol: String? — Phosphor slug; whole control if circular, leading adornment if extended",
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
        family: .action,
        defaultType: "ThemedFABView",
        imports: [ "import ThemeKitUI   // ThemedFABView (the SwiftUI front)",
                   "import ThemeKit     // ThemedFAB.Variant / .Size / .Role enums",
                   "import PaletteKit   // ResolvedPalette + resolve(_:)" ],
        initSnippet: """
  ThemedFABView(palette: resolve(themeSpec), variant: .circular, size: .large,
                role: .primary, symbol: "plus")
      .frame(width: 56, height: 56)
""",
        sourcePath: "ThemeKitUI/ThemedFABView.swift",
        appkitEscape: "ThemedFAB (NSView, module ThemeKit) — only if NOT in SwiftUI"),
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
        family: .feedback,
        defaultType: "ThemedDividerView",
        imports: [
            "import PaletteKit   // ResolvedPalette + resolve(themeSpec)",
            "import ThemeKit     // ThemedDivider.Orientation / .Variant enums",
            "import ThemeKitUI   // ThemedDividerView (SwiftUI front)",
        ],
        initSnippet: """
ThemedDividerView(
    palette: resolve(themeSpec),
    orientation: .horizontal,
    variant: .fullWidth,
    label: nil,
    surface: nil
)
""",
        sourcePath: "ThemeKitUI/ThemedDividerView.swift",
        appkitEscape: "ThemedDivider (NSView, module ThemeKit) — only if NOT in SwiftUI; ThemedDividerView is an NSViewRepresentable hosting it"),
    KitComponent(
        name: "AnimatedBorderView", module: "ThemeKitUI",
        kind: "Themed surface border — universal: static primary stroke ↔ live effect rim (glow/breathe/cycle), SwiftUI-native (#17d)",
        summary: "The family's ONE themed surface outline; a `Shape` stroked in `primary` by default, the shared `resolveBorder` animator (glowing/breathing/cycling neon/rainbow rim) when given an effect with effects ON. Pure SwiftUI (TimelineView(.animation)+Canvas, two-stop Canvas bloom). Themed by assigning a ResolvedPalette.",
        consumes: "Overlay it on the surface: `surface.overlay(AnimatedBorderView(palette:, effect:, in: shape, lineWidth:))`, or the DRY `.animatedBorder(…)` modifier. It owns its TimelineView(.animation) clock; reduce-motion (SwiftUI `@Environment`) rests on the steady hue. Generic over `Shape` (rounded rect / square / circle). Resolve the effect from a theme name via `borderEffectFor(_:)` (Effects). Bump `flashToken` to roll a focus/WS-switch blink burst.",
        keyAPI: [
                 "palette: ResolvedPalette — theme; the static stroke + cycle fallback resolve from `primary`",
                 "effect: EffectSpec? — nil = static primary border; set = the live effect rim (resolve via borderEffectFor(themeName))",
                 "effectsEnabled: Bool — MASTER switch (default true); false rests to the static primary stroke even with an effect set. Pass the SAME flag to ResolvedPalette.animated(forTheme:at:enabled:) so border + widget accents rest together",
                 "in shape: S: Shape — the stroked mask (default continuous rounded rect r=10); pass RoundedRectangle/Rectangle/Circle to match the host surface",
                 "lineWidth / breathTo: CGFloat — resting width; the effect breathes lineWidth…breathTo (nil ⇒ ×2.5; pass ==lineWidth for no breath, e.g. wand/perch)",
                 "cycleSeconds: Double — one full colour cycle (default 5; wand 4)",
                 "glow: AnimatedBorderGlow — .none (flat) / .bloom (default, two-stop neon halo scaled by the breathing width; the effect rim only)",
                 "flashToken: Int — bump to roll a focus/WS-switch blink burst (rolled internally on the view's own clock so the epoch matches)",
                 "previewFrozen: Bool + previewPhase: CGFloat — hold a fixed-phase frame for deterministic capture",
             ],
        variants: [
                 "mode: static primary stroke (no effect / effects off) vs live effect rim (effect + effects on)",
                 "shape: rounded rect (wand r8 / facet tree r12) / square (facet grid/rail) / circle (a ring)",
                 "glow: none / bloom (two-stop)",
                 "states: live-cycling / frozen (previewFrozen) / reduce-motion (rests on the effect steady hue)",
                 "the effect rim reuses Effects.resolveBorder (rainbow hue-rotate, flash blend, breathing width) — the same animator facet/halo/perch drive",
             ],
        family: .feedback,
        defaultType: "AnimatedBorderView",
        imports: [
            "import SwiftUI       // View front (Shape, RoundedRectangle default)",
            "import ThemeKitUI    // AnimatedBorderView — the SwiftUI front",
            "import PaletteKit    // ResolvedPalette + resolve(_:)",
            "import Effects       // EffectSpec (.rainbow, etc.) for the live rim",
        ],
        initSnippet: """
AnimatedBorderView(
    palette: resolve(themeSpec),
    effect: .rainbow,
    effectsEnabled: true
)
""",
        sourcePath: "ThemeKitUI/AnimatedBorderView.swift"),
    KitComponent(
        name: "ThemedSkeleton", module: "ThemeKit",
        kind: "MUI <Skeleton> (low-alpha loading placeholder with pulse/wave ambient animation)",
        summary: "Themed grey-wash loading placeholder; themed by assigning a ResolvedPalette.",
        consumes: "Embed directly: a host instantiates ThemedSkeleton(palette:) — a plain NSView — sets variant/animation/optional width/height, and adds it as a subview (or bridges it via NSViewRepresentable as ThemeKitUI's ThemedSkeletonView does). No controller or child window.",
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
        family: .feedback,
        defaultType: "ThemedSkeletonView",
        imports: [
            "import ThemeKitUI   // ThemedSkeletonView — the public SwiftUI front",
            "import ThemeKit     // ThemedSkeleton.Variant / .Animation enums",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
  let palette = resolve(themeSpec)
  ThemedSkeletonView(palette: palette, variant: .text, animation: .pulse,
                      width: 120, height: nil)
""",
        sourcePath: "ThemeKitUI/ThemedSkeletonView.swift",
        appkitEscape: "ThemedSkeleton (NSView, module ThemeKit) — the real AppKit loading placeholder ThemedSkeletonView wraps via NSViewRepresentable; drop to it only if ThemedSkeletonView can't be hosted (e.g. non-SwiftUI AppKit call site)"),
    KitComponent(
        name: "ThemedTooltip", module: "ThemeKitUI",
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
        family: .feedback,
        defaultType: "ThemedTooltipAnchorView",
        imports: [
            "import ThemeKitUI   // ThemedTooltipAnchorView — the SwiftUI front",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
ThemedTooltipAnchorView(palette: resolve(themeSpec), text: "A live themed tooltip",
                         placement: .auto)
""",
        sourcePath: "ThemeKitUI/ThemedTooltipAnchorView.swift",
        appkitEscape: "ThemedTooltip (NSObject controller, module ThemeKitUI) — a per-anchor CONTROLLER (not an NSView) that owns a free, click-through, non-activating NSPanel floating above the host window; its anchor is a real ThemedButton (module ThemeKit, NSView). Only reach for ThemedTooltip.attach(to:text:palette:placement:) directly (skipping ThemedTooltipAnchorView) if you need the controller API (show()/hide()/invalidate(), enterDelay/leaveDelay, previewVisible) on an existing NSView outside a SwiftUI tree."),
    KitComponent(
        name: "ThemedBackdrop", module: "ThemeKitUI",
        kind: "SwiftUI-native themed backdrop surface — what panels/pills/cards sit on (solid or alpha scrim, any Shape; NO blur)",
        summary: "Pure-SwiftUI surface: a Shape filled with the theme's background (opaque, or a translucent scrim via backgroundAlpha) + optional hairline; re-themes by reassigning ResolvedPalette. Replaces each app's behind-window NSVisualEffectView blur (床2個 kept — blur was cosmetic, #17c).",
        consumes: "A SwiftUI View: `ThemedBackdropView(palette:in:fill:bordered:)`, or the `.themedBackdrop(_:in:fill:bordered:)` modifier to put it behind any view; host it (NSHostingView) at the back of a panel/pill/card.",
        keyAPI: [
                 "palette: ResolvedPalette — theme; reassigning re-themes the surface",
                 "in shape: some Shape — the mask (default continuous rounded-rect r=10); Capsule() for pills, RoundedRectangle(cornerRadius:12) for panels",
                 "fill: BackdropFill — .auto (from palette) / .solid (opaque) / .scrim(opacity:) (translucent, NOT blurred) / .clear (border-only)",
                 "bordered: Bool — 1pt hairline in palette.border",
                 "View.themedBackdrop(_:in:fill:bordered:) — DRY ergonomic for .background(ThemedBackdropView(...))",
             ],
        variants: [
                 "fill: auto (concrete bg ⇒ opaque or backgroundAlpha scrim; vibrancy theme ⇒ system scrim @ backgroundAlpha ?? 0.85) / solid / scrim(opacity) / clear",
                 "shape: any SwiftUI Shape — rounded-rect (cards), Capsule (pills), custom",
                 "bordered on/off; live re-theme by reassigning palette",
             ],
        family: .feedback,
        defaultType: "ThemedBackdropView",
        imports: [
            "import PaletteKit   // ResolvedPalette + resolve(themeSpec)",
            "import ThemeKitUI   // ThemedBackdropView (pure SwiftUI, no AppKit wrap)",
        ],
        initSnippet: """
ThemedBackdropView(
    palette: resolve(themeSpec)
)
""",
        sourcePath: "ThemeKitUI/ThemedBackdropView.swift"),
    KitComponent(
        name: "WindowShell", module: "ThemeKit",
        kind: "The family's ONE parameterized AppKit window-shell factory — a long-lived non-activating NSPanel whose key behavior / chrome / level / collectionBehavior / click-through are knobs; content is SwiftUI via NSHostingView (the permitted 「窓の殻」 AppKit floor). SEPARATE from the internal transient-popup machinery (themedPopupPanel / placePopup / PopupFade).",
        summary: "Builds a configured ShellPanel from a value-type WindowShellSpec, plus the helpers a floating shell needs (window fade, auto-size, screen-union, Esc/outside-click dismiss). The shell that the 5 apps' overlays/popovers/launchers (perch/glance/wand + facet KeyablePanel) move onto.",
        consumes: "Free functions + value types, no controller: `let panel = makeWindowShell(WindowShellSpec(keyMode:.onDemand, chrome:.borderless))`, set `panel.contentView = NSHostingView(rootView: yourSwiftUIView)`, position it, show with `ShellFade().fadeIn(panel)`. Retain the panel + any monitors/glue for the shell's lifetime; dismiss with `ShellFade().fadeOut(panel)`.",
        keyAPI: [
                 "WindowShellSpec — value type: keyMode (.never/.onDemand/.always) · chrome (.borderless/.titled(resizable:closable:)/.hud) · nonactivating:Bool · level:NSWindow.Level · collectionBehavior · clickThrough:Bool · hasShadow/isOpaque/backgroundColor. resolvedStyleMask computes the styleMask",
                 "makeWindowShell(_:WindowShellSpec) -> ShellPanel — builds the panel (isFloatingPanel, hidesOnDeactivate=false; becomesKeyOnlyIfNeeded when .onDemand). Assign an NSHostingView to contentView",
                 "ShellPanel: NSPanel — canBecomeKey driven by keyMode (never⇒false, onDemand/always⇒true); canBecomeMain stays NSPanel default (false)",
                 "unionFrame(of:[CGRect]) -> CGRect (pure, unit-testable) + screenUnionFrame() -> CGRect (all attached displays) + ScreenReconfigGlue.start(onChange:) — re-evaluate on display attach/detach",
                 "sizeShellToContent(_:max:) — fit the panel to its content's fittingSize, top-left pinned, invalidateShadow",
                 "ShellFade(duration:) — fadeIn/fadeOut the WHOLE window (animator().alphaValue); fadeOut gated by a monotonic shouldOrderOut token (quick re-show safe)",
                 "ShellDismissMonitor.start(panel:onEscape:onOutsideClick:dismiss:) — Esc (key 53) + same-app outside-click dismissal; cross-app (resign-key) is the caller's to wire",
             ],
        variants: [
                 "keyMode: never (transient-popup discipline) / onDemand (key only when a subview needs it — facet KeyablePanel, IME edit) / always (editable launcher window)",
                 "chrome: borderless (overlays/popovers/launchers) / titled(resizable:closable:) / hud (.hudWindow). nonactivating toggles .nonactivatingPanel",
                 "click-through (ignoresMouseEvents) — pure pass-through overlay (shares the helper with halo's raw NSWindow overlay)",
                 "screen-union contentRect spanning every display; live hotplug reflow needs real multi-display hardware (union MATH is unit-tested)",
                 "prism: inline mock of a shell surface + live triggers spawning the REAL shell (key-on-demand typing, click-through, titled-resizable, HUD, screen-union) for single-display verification",
             ],
        family: .feedback,
        imports: [
            "import AppKit   // ShellPanel (NSPanel) + NSHostingView host content SwiftUI",
            "import SwiftUI  // NSHostingView(rootView:) wraps the shell's content",
            "import ThemeKit // WindowShellSpec, makeWindowShell(_:), ShellPanel, ShellFade",
        ],
        initSnippet: """
  let spec = WindowShellSpec(keyMode: .onDemand)   // all WindowShellSpec params are defaulted
  let panel: ShellPanel = makeWindowShell(spec)
  panel.contentView = NSHostingView(rootView: MyShellContent())
  panel.setFrame(CGRect(x: 0, y: 0, width: 380, height: 200), display: true)
  ShellFade().fadeIn(panel)   // orderFrontRegardless + animator().alphaValue fade
""",
        sourcePath: "ThemeKit/WindowShell.swift",
        isAtom: true),
    KitComponent(
        name: "ThemedListView", module: "ThemeKitUI",
        kind: "MUI <List> (basic) — the SwiftUI-native themed list/menu row renderer",
        summary: "SwiftUI list of mixed-height themed rows (#17b M2; it RETIRED the AppKit ThemedList at M5); themed by passing a PaletteKit ResolvedPalette.",
        consumes: "A host embeds it as a plain SwiftUI View — ThemedListView(items:selection:collapsed:highlight:style:palette:…callbacks…): data in [ListItem<ID>], config in a ThemedListStyle value, state in Bindings. Standalone (style.hosted=false) the rows own tap/hover/keyboard; the popup widgets (ThemedComboBox/ThemedMenu) host it non-key via ListController + HostingListView, where an AppKit mouseUp fires the synchronous commit.",
        keyAPI: [
                 "items: [ListItem<ID>] (ThemeKitUI; ID: Hashable & Sendable) — rows (id, image: pre-resolved NSImage?, primary/secondary text, badges: [Badge], trailing: TrailingAccessory, tint: ListTint, kind: .row/.sectionHeader/.separator, isDisabled, axChecked, indentLevel: Int); a value change re-renders",
                 "HIERARCHY: ListItem.indentLevel:Int (0=top; shifts the leading cluster — the image/text, plus a collapsible header's disclosure triangle — right by indentLevel×indentStep; selection/hover fill + leading tint bar stay FULL-BLEED, the MUI tree model) + Kind.sectionHeader(subtitle:collapsed:Bool?) — collapsed nil=plain header, false=collapsible+expanded (▾), true=collapsed (▸). collapsed: Binding<Set<ID>> is the collapse STATE (id ∈ set ⇒ that section's body rows hide, row-diff ANIMATED, caret rotates); onToggleSection(ID) fires on a header click (incl. the pinned sticky header) and the HOST mutates the bound set (the host owns the tree shape — React-component contract)",
                 "palette: ResolvedPalette — theme; passing a new palette re-resolves all role colors at draw",
                 "selection: Binding<Set<ID>> + onSelectionChange(Set<ID>) — committed selection (single or multiple per style.selectionMode; ⌘-toggle/⇧-range/⌘A route through ListCore.MultiSelection)",
                 "highlight: Binding<ID?> — the keyboard cursor, distinct from selection; standalone ↑↓/⏎/Esc drive it via .onKeyPress + a focus ring",
                 "onActivate(ID) — click/Enter on a row (host's 実処理); onHover(ID?) — hovered row id (nil on exit)",
                 "emptyActionRow: ((query:String)->String?)? + query + onEmptyAction — actionable empty state (else noOptionsText)",
                 "hosted popups: ListController<ID> (@Observable) re-vends the imperative contract (moveHighlight/activateHighlight/clearHighlight, items/highlight/selection mutation from key monitors) + sync measurement (contentHeight()/fittingWidth(maxWidth:palette:)/rowRectOnScreen(_:) — menu sizing + submenu anchoring); onRowRects reports per-row viewport frames for the host's mouseUp hit-test",
                 "DRAG LAYER (opt-in): style.draggable=true + style.dragMode (.dropOnto/.reorderBetween/.both) + onDrop((DragContext<ID>,DropTarget<ID>)->Void) (host's 実処理 move; the kit pre-rejects onto-self / no-move / separator / chunk-internal via ListCore resolvers). DragContext = { sourceID, memberIDs } — memberIDs always filled ([sourceID] solo, [header,…children] for a chunk). DropPlacement = .onto(id:) / .between(beforeID:) (nil beforeID = end gap). The floating ghost is a SwiftUI OVERLAY (the AppKit child-window ghost died with the widget); keyboard drag: Space lift · ↑↓ aim · ⏎ commit · Esc cancel",
                 "CHUNK REORDER (standard once draggable): lifting a section HEADER carries the header + its child rows as ONE unit; onDrop's memberIDs is the whole chunk and the host decides reorder-vs-swap. A chunk can't land inside itself (auto-rejected); keyboard arrows aim by SECTION boundary. style.showsReorderGrip=true (default) draws a 2×3 grip on each draggable header",
             ],
        variants: [
                 "density: .comfortable (30pt rows, combo-parity) / .compact — pure ListMetrics.forDensity table, the AppKit widget's constants 1:1",
                 "selectionMode: .none (hover-only, wand tome) / .single / .multiple (⌘/⇧/⌘A — M2b)",
                 "hoverStyle: .wash (selection fill + 3pt primary bar, default) / .solidAccent (opaque primary + onPrimary ink)",
                 "roundedSelection (6pt pill) · showsDividers · reservesLeadingImageColumn (default true; false = combo flush) · wrapsHighlight · highlightFollowsHover (menu model)",
                 "highlightStyle .fill (default, menu/combo look) / .outline (a stroked primary ring so a keyboard cursor reads distinct from a filled selection) · zebra (hover@0.4 stripe, no new role; data rows only, parity resets per section header) · horizontalContentScroll (doc widens to the natural content width; facet mode)",
                 "hosted (popup: inert rows, host drives commit/hover) vs standalone (rows own tap/.onHover + .onKeyPress focus nav)",
                 "vendsRowAXElements (opt-in per-row AX with a \"checked\" marker for menu rows) · surfaceColor override (vibrancy escape hatch) · backgroundAlpha (ThemedToolBar idiom)",
                 "row kinds: .row / .sectionHeader(subtitle:collapsed:) (sticky, 1- or 2-line; collapsed Bool? opts into a disclosure triangle) / .separator; indentLevel:Int nests any row/header; ListTint: none/primary/secondary/error/.custom(HexColor); BadgeRole: neutral/primary/secondary/error; TrailingAccessory: none/chevron/shortcut(String)/custom(NSImage)",
                 "drag affordance: .onto lights the target row (2pt primary ring + faint fill); .between draws a 2pt primary insertion line + leading dot in the gap; the lifted source row dims. A CHUNK lift dims EVERY member row and draws a THICKER full-bleed section insertion bar; the overlay ghost is the members' capped (60%) union with an 'N items' badge. grid/rail/real-window drag stay app-side (not in sill)",
                 "capture seams: preview: ListPreview(selection:highlight:scrollX:scrollY:dragSource:dropTarget:dragChunk:) — one frozen value pins every interactive state for a deterministic prism shot",
             ],
        family: .collection,
        // Structured recipe (Task 3 worked example) — verified against the real
        // ThemedListView.swift / ListStyle.swift / ListItem.swift init signatures.
        defaultType: "ThemedListView<ID>",
        imports: [
            "import ThemeKitUI   // ThemedListView, ListItem, ThemedListStyle, Badge/TrailingAccessory/ListTint",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
          let palette = resolve(themeSpec)              // @MainActor; themeSpec: ThemeSpec
          var style = ThemedListStyle()                 // selectionMode defaults to .single
          ThemedListView(
              items: [ ListItem(id: "inbox",   primary: "Inbox"),
                       ListItem(id: "starred", primary: "Starred", secondary: "3 unread") ],
              style: style,
              palette: palette,
              onActivate: { id in open(id) })           // id IS the ListItem.id
        """,
        cellType: "ListItem",
        cellInit: "ListItem(id:primary:) — only id + primary required (image/secondary/badges/trailing/tint/kind default).",
        sourcePath: "ThemeKitUI/ThemedListView.swift",
        appkitEscape: ""),
    KitComponent(
        name: "ThemedMenu", module: "ThemeKitUI",
        kind: "MUI <Menu> — a themed floating pop-up menu of action rows with N-level submenu cascade + horizontal (menu-bar) presentation",
        summary: "Floating action-menu controller owning a non-key child panel; themed by assigning a ResolvedPalette. Vertical drop-down OR a horizontal menu bar (composing the real ThemedToolBar).",
        consumes: "A retained CONTROLLER (NSObject), not an NSView: build via ThemedMenu.make(palette:items:) (or init), retain it, then call present(from:)/present(at:in:); it owns a borderless non-key PopupPanel hosting the SwiftUI ThemedListView (vertical) or a ThemedToolBar (horizontal) — the host window stays key.",
        keyAPI: [
                 "palette: ResolvedPalette — assign to (re)theme; repaints list + panel surface/edge",
                 "items: [MenuItem] — rows; each MenuItem carries title/icon/shortcut/isChecked/isDestructive/isEnabled + its own action closure (実処理). .separator(id:)/.header(_:id:) statics build non-interactive rows",
                 "MenuItem.submenu: [MenuItem] — non-empty ⇒ a cascade: the row opens a child menu beside it (hover-intent / → / click); auto-sets hasSubmenu; the row's own action is ignored (opening the child IS its activation); the child's submenu rows cascade further (N-level, arbitrary depth)",
                 "MenuItem.submenuProvider: (@MainActor () async -> [MenuItem])? — DEFERRED children: opening the row shows a disabled Loading… row, then fills from the awaited closure (No items on []); re-invoked per open (cache-free); static submenu wins if both are set; the in-flight fetch is cancelled on close. Consumer: wand's real launcher (async PanelTree walk)",
                 "present(from: NSView, gap:) — open as a drop-down below an anchor (flips up on underflow)",
                 "present(at: CGPoint, in: NSWindow) — open as a context menu at a point (e.g. event.locationInWindow)",
                 "dismiss(animated:) — close (idempotent); invalidate() — deterministic teardown",
                 "onOpenChange: ((Bool)->Void)? — open/close edge callback",
                 "density: Density (ThemeKitUI) — .compact (26pt) or .comfortable (30pt)",
                 "highlightsFirstOnOpen: Bool — pre-light first enabled row on open (default false)",
                 "surfaceColor: NSColor? — override opaque menu surface (defaults to palette.background)",
                 "presentation: .vertical (default) / .toolbar (icon-only bar) / .labeledToolbar (icon+label bar) — a horizontal root composes the real ThemedToolBar; a folder bar-item opens its vertical submenu BELOW it; children stay vertical (menu bar)",
             ],
        variants: [
                 "row kinds: item / .separator / .header",
                 "item adornments: leading icon, leading checkmark (isChecked), trailing ⌘-shortcut lozenge, trailing submenu chevron (hasSubmenu / non-empty submenu)",
                 "row states: enabled / disabled (isEnabled) / destructive error-tint (isDestructive)",
                 "density: compact (26pt) vs comfortable (30pt)",
                 "placement: anchor drop-down vs context-menu point; a VERTICAL parent's submenu child sits beside its row (.submenu, flips left on overflow), a HORIZONTAL parent's child drops BELOW the bar item (.anchorCorner drop-down); corner-anchored Grow scale+fade (reduce-motion gated)",
                 "presentation: .vertical drop-down list, .toolbar icon-only bar, .labeledToolbar icon+label bar",
                 "interaction states demoed: hover/highlight (solidAccent), ↑↓ nav (vertical) / ←→ nav (horizontal bar), ⏎/Space activate, → open submenu (vertical) / ↓ open submenu (horizontal) / ← + Esc close one level, Esc/Tab dismiss",
             ],
        family: .collection,
        defaultType: "ThemedMenuTriggerView",
        imports: [
            "import ThemeKitUI   // ThemedMenuTriggerView — the SwiftUI front; ThemedMenu.MenuItem lives here too",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
let items: [ThemedMenu.MenuItem] = [
    ThemedMenu.MenuItem("New Window", shortcut: "⌘N") {},
    ThemedMenu.MenuItem("Open…") {},
    .separator(),
    ThemedMenu.MenuItem("Delete", isDestructive: true) {},
]
ThemedMenuTriggerView(palette: resolve(themeSpec), title: "Actions", items: items)
""",
        cellType: "ThemedMenu.MenuItem",
        cellInit: "MenuItem(_:icon:shortcut:isEnabled:isDestructive:submenu:action:submenuProvider:) — MenuItem(\"Title\") { } — only the title is required (icon/shortcut/isEnabled/isDestructive/submenu/action/submenuProvider all default; a submenuProvider makes the row a deferred folder; `.separator(id:)`/`.header(_:id:)` build non-interactive rows).",
        sourcePath: "ThemeKitUI/ThemedMenuTriggerView.swift",
        appkitEscape: "ThemedButton (NSView, module ThemeKit) — the trigger button ThemedMenuTriggerView hosts. ThemedMenu ITSELF (module ThemeKitUI, Sources/ThemeKitUI/ThemedMenu.swift) is an NSObject CONTROLLER — not an NSView — that owns a borderless non-key ThemeKit PopupPanel; only reach for it directly (skipping the trigger view) if you need the controller API (ThemedMenu.make(palette:items:) + present(from:)/present(at:in:)/dismiss()/onOpenChange) outside a SwiftUI tree, e.g. a context menu opened from a raw NSEvent."),
    KitComponent(
        name: "ThemedGrid", module: "ThemeKitUI",
        kind: "MUI <ImageList> (basic) — a general, content-agnostic themed thumbnail/photo grid; ThemedGrid is the batteries-included form (ThemedThumbnailGridView) of the generic ThemedGridView (#17e)",
        summary: "100% SwiftUI-native grid: responsive LazyVGrid/LazyHGrid layout (ScrollView + GeometryReader), themed cell chrome (rest/hover/selected/keyboard-focused ring+fill+shadow, canonical roles), controlled/uncontrolled selection, 2D keyboard nav (onMoveCommand, a single roving cursor) + double-click/Return activation. ThemedThumbnailGridView supplies the default cell (image fill or a SwiftUI shimmer placeholder + optional bottom-scrim label) over ThemedGridView's generic cell-content seam; themed by passing a ResolvedPalette. NO AppKit (#17e AppKit policy) — DnD + carousel/hero are out of scope.",
        consumes: "A SwiftUI View: `ThemedThumbnailGridView(items:[ThumbnailItem], selection:, layout:, axis:, aspectRatio:, palette:, onActivate:)` — multi-select via `Binding<Set<String>>?` or the single-select convenience over `Binding<String?>` (bridged to a 0/1 set internally); embed directly, it owns its own scrolling + responsive columns. For a custom cell, drop to the generic `ThemedGridView<Data,ID,Cell>(_:id:selection:layout:axis:aspectRatio:palette:onActivate:allowsMultiSelect:cell:)` and supply your own `@ViewBuilder` cell — it still owns all chrome/selection/keyboard nav.",
        keyAPI: [
                 "items: [ThumbnailItem] — id: String, image: NSImage?, label: String?; nil image renders a SwiftUI shimmer placeholder (no AppKit)",
                 "selection: Binding<Set<String>>? (multi-select init) or Binding<String?> (single-select convenience) — nil ⇒ uncontrolled (internal @State)",
                 "layout: GridLayout — .fixed(columns:) fixed column count / .adaptive(minCellWidth:) as many columns as fit (default, 160pt)",
                 "axis: Axis — .vertical (LazyVGrid, default) / .horizontal (LazyHGrid)",
                 "aspectRatio: CGFloat? — fixes each cell's w/h ratio; nil = natural cell sizing",
                 "palette: ResolvedPalette — theme; drives fill/stroke/shadow/focus-ring canonical roles (selection/hover/muted/border/primary/foreground)",
                 "onActivate: ((String) -> Void)? — fires on double-click or Return-on-cursor",
                 "allowsMultiSelect: Bool — set internally by which init is used (multi-select ⇒ true, single-select convenience ⇒ false); Cmd-click toggles only when true, else replaces",
                 "keyboard: onMoveCommand arrow keys move a single roving cursor that REPLACES the selection (macOS grid convention); Return activates the cursor",
                 "GridCellState (isSelected/isHovered/isFocused) is handed to a custom cell builder so it can layer its own emphasis atop the kit's chrome",
             ],
        variants: [
                 "layout: fixed(columns:) / adaptive(minCellWidth:)",
                 "axis: vertical / horizontal",
                 "cell states: rest / hovered / selected / keyboard-focused (each its own fill+stroke+shadow+focus-ring per canonical roles)",
                 "default cell (ThemedThumbnailCell): image (resizable, .fill aspect) or shimmer-loading placeholder (nil image) + optional bottom-scrim label",
                 "selection: uncontrolled / controlled, single-select / multi-select (Cmd-click toggle, plain click replaces)",
                 "DnD + carousel/hero are OUT OF SCOPE (design spec §3.2/§11)",
             ],
        family: .collection,
        defaultType: "ThemedThumbnailGridView",
        imports: [
            "import SwiftUI      // View front",
            "import ThemeKitUI   // ThemedThumbnailGridView + ThumbnailItem",
            "import PaletteKit   // ResolvedPalette + resolve(_:)",
        ],
        initSnippet: """
let palette = resolve(themeSpec)
let items: [ThumbnailItem] = [
    ThumbnailItem(id: "1", image: nil, label: "One"),
    ThumbnailItem(id: "2", image: nil, label: "Two"),
]
ThemedThumbnailGridView(items, palette: palette)
""",
        cellType: "ThumbnailItem",
        cellInit: "ThumbnailItem(id: \"1\", image: nil, label: \"One\")",
        sourcePath: "ThemeKitUI/ThemedThumbnailGridView.swift"),
    KitComponent(
        name: "ThemedTransition", module: "Motion",
        kind: "MUI theme.transitions analog — pure one-shot animation math (Duration/Easing tokens, Tween, lerp, spring, frameStep)",
        summary: "The family's shared TRANSIENT (play-once) motion math: named durations + easing curves + a Tween value + interpolation + a DISCRETE frame sampler. Pure, Sendable, AppKit-free; the counterpart to Effects (which owns CYCLIC color motion). The app owns the clock and samples these per frame.",
        consumes: "Pure functions — no view, no NSView, no instance. `import Motion`, then read tokens / sample math off a wall-clock `now` (CACurrentMediaTime()) inside your existing redraw loop: e.g. `let s = ThemedTransition.Tween(start: t0, duration: .move, easing: .easeOutCubic); pillX = s.value(at: now, from: x0, to: x1)`. Nothing to retain.",
        keyAPI: [
                 "ThemedTransition.Duration — named TimeInterval (seconds) tokens: .snap(0) / .exit(.12) / .enter(.16, default) / .move(.18) / .emphasis(.22) / .staggerStep(.03). Calibrated to the family's measured band, NOT MUI's slower web ladder",
                 "ThemedTransition.Easing — a Sendable f(t)->value (input clamped 0…1, output not). Power: .linear/.easeOutQuad/.easeOutCubic(default)/.easeOutQuint/.easeInOutCubic. Material bezier (exact solver): .standard/.decelerate/.accelerate/.sharp. .spring(zeta:omega:) overshoots. .cubicBezier(x1,y1,x2,y2) for a custom curve",
                 "ThemedTransition.Tween(start:duration:delay:easing:) — the (when, how-long, delay, curve) value every app re-derives. value(at:now) / value(at:from:to:) / rawProgress(at:) / isComplete(at:)",
                 "ThemedTransition.progress(now:start:duration:delay:) -> 0…1 clamped; .eased(now:…:easing:) runs it through a curve",
                 "ThemedTransition.lerp(a,b,t) — Double + (CoreGraphics) CGFloat/CGPoint/CGSize/CGRect overloads. spring(t,zeta:omega:) underdamped step. dampedSine(p,frequency:decay:) shake/vibrate envelope",
                 "ThemedTransition.frameStep(now:hz:frames:[T]) -> T — DISCRETE sprite-swap sampler (the counterpart to the continuous curves): index = floor(now·hz·count) wrapped, so frames cycle hz complete times/sec. Hard cuts, not blends — the chomp mouth [0,0.5,1,0.5]@5Hz, a 2-pose ghost waddle, a blinking caret. Negative-now total; frames must be non-empty",
                 "ThemedTransition.autoDuration(forExtent:) — MUI's size→duration heuristic (sublinear). scaled(_:by:) — clamp+multiply for an app speed knob (perch duration-scale)",
             ],
        variants: [
                 "Duration ladder: snap / exit / enter / move / emphasis / staggerStep",
                 "Easing: linear · easeOutQuad/Cubic/Quint · easeInOutCubic · standard/decelerate/accelerate/sharp (Material) · spring · custom cubicBezier",
                 "Primitives: Tween · progress/eased · lerp (scalar + CG) · spring · dampedSine · frameStep (discrete) · autoDuration · scaled",
                 "DIVISION OF LABOUR: Motion = one-shot (slide/fade/pop/reorder); Effects = cyclic (border breathe/flash, rainbow, line-pets). No timer/state here — app owns the clock (sill f(now) convention)",
             ],
        family: .motion,
        imports: [
            "import Motion   // ThemedTransition namespace — Tween/Easing/Duration, pure math, no palette needed",
        ],
        initSnippet: """
// ThemedTransition is a pure, caseless-enum NAMESPACE — never instantiated.
// Store a Tween in your animation cell, sample it each frame off your own
// wall-clock (CACurrentMediaTime()-style `now`); nothing to retain/init.
let tween = ThemedTransition.Tween(
    start: now,
    duration: ThemedTransition.Duration.move,   // .snap/.exit/.enter(default)/.move/.emphasis
    delay: 0,
    easing: .easeOutCubic
)
let x = tween.value(at: now, from: x0, to: x1)   // eased lerp, this frame
""",
        sourcePath: "Motion/ThemedTransition.swift",
        isAtom: true),
    KitComponent(
        name: "ParticleBurst", module: "Effects",
        kind: "Celebratory particle burst — 紙吹雪 / 花火 (confetti / fireworks). The FlashState pre-roll → wall-clock decay pattern, scaled to a field of moving particles",
        summary: "The family's shared one-shot particle burst: roll once at the trigger, resolve each particle in CLOSED FORM per frame (ballistic arc + flutter + spin + fade), draw the rich look (glowing sparks / tumbling paper) or your own. Pure + Sendable; the app owns the clock, NSColor, and the off gate — like the border flash + line-pets.",
        consumes: "Pure functions + an AppKit draw helper — no instance to retain. `import Effects`. On the celebratory moment: `burst = rollBurst(emission: .confetti, from: [pt], colors: EffectSpec.rainbow.flash + [accentHex], intensity: cfg.intensity, now: CACurrentMediaTime())` into one stored `ParticleBurst?` cell; tick your redraw clock while `burst.isActive(now:)`; each frame call `drawParticles(burst, now:)` in an isFlipped view (or draw from `resolveParticles(burst, now:)` yourself). Clear the cell when it settles.",
        keyAPI: [
                 "rollBurst(emission:from:colors:intensity:now:duration:count:) -> ParticleBurst — roll N particles per emitter (Double-tuple or CGPoint emitters). colors are 0xRRGGBB candidates each particle picks from; intensity (subtle…wild) scales count + reach (hard-capped 6…40/emitter)",
                 "resolveParticles(_:now:) -> [ResolvedParticle] — pure closed form: x=x₀+vx·t+sway·sin(…), y=y₀+vy·t+½g·t², alpha=1−t/(dur·life), rotation=spin·t. Drops dead particles (organic dissolve); [] before roll / after settle",
                 "ParticleBurst — Sendable rolled value (particles + startedAt + duration + gravity + emission). isActive(now:) gates the redraw clock; progress(now:) is 0…1",
                 "drawParticles(_:now:scale:) — @MainActor AppKit renderer (glowing spark / edge-flipping paper) into the current NSGraphicsContext; the drawLinePets analog. +y is DOWN — host in an isFlipped view, or negate gravity for y-up",
                 "ParticleEmission { fireworks (radial, light gravity), confetti (popper cone, strong gravity) }; ParticleShape { spark, paper }; EffectIntensity (Palette) scales count + reach",
             ],
        variants: [
                 "Emission: .fireworks (radial omni glow) / .confetti (up-and-out popper, tumbling paper)",
                 "Shape: .spark (glow dot + hot core) / .paper (tumbling, edge-on flip)",
                 "Intensity: subtle 0.6× / normal 1.0× / bold 1.6× / wild 2.5× (count + reach)",
                 "DIVISION OF LABOUR: a burst is one-shot, but it lives in Effects (not Motion) — it is the color-dynamic FlashState pattern at scale, and reuses the EffectSpec palettes + NSColor bridge. No timer/state — app owns the clock (sill f(now) convention)",
             ],
        family: .particles,
        defaultType: "ParticleBurstView",
        imports: [
            "import ThemeKitUI   // ParticleBurstView — the public SwiftUI front (pure Canvas, no AppKit wrap)",
            "import Effects      // ParticleEmission / EffectIntensity enums used as param types",
        ],
        initSnippet: """
ParticleBurstView(
    emission: .fireworks,
    colors: [0xFFD700, 0xFF6EC7, 0x00E5FF],
    intensity: .bold,
    loopPeriod: 1.5
)
""",
        sourcePath: "ThemeKitUI/ParticleBurstView.swift",
        appkitEscape: "drawParticles(_:now:scale:) (free function, module Effects, @MainActor) — the pre-#17a AppKit draw helper; paints a rolled ParticleBurst's resolveParticles() into the CURRENT NSGraphicsContext. Only reach for it hosting inside a plain NSView.draw(_:), not SwiftUI."),
    KitComponent(
        name: "SplatterShape", module: "Effects",
        kind: "Ink-splat decal — Splatoon-style post-fire splatter. The roll → resolve-alpha → draw pattern, but a static shape that only fades (a stamp, not a burst)",
        summary: "The family's shared ink-splatter decal: roll the whole geometry once (deterministic from a seed), resolve only its alpha per frame (hold ⅔ → fade ⅓), draw the rich look (2–3 tendril-blob units + wet rim + droplets) or your own. Pure + Sendable; the app owns the clock, NSColor, and the off gate — like the particle burst, but the shape is static.",
        consumes: "Pure functions + an AppKit draw helper — no instance to retain. `import Effects`. On the celebratory moment: `decal = rollSplatter(at: pt, size: 120, colors: [accentHex] + festive, now: CACurrentMediaTime())` into one stored `SplatterShape?` cell; tick your redraw clock while `decal.isActive(now:)`; each frame call `drawInkSplatter(decal, now:)` (or fill `decal.units` yourself). Pass a fixed `seed:` for a reproducible shape; clear the cell when it settles.",
        keyAPI: [
                 "rollSplatter(at:size:colors:seed:now:duration:) -> SplatterShape — roll 2–3 ink-splat units at a point (Double-tuple or CGPoint). size = footprint pt; colors are 0xRRGGBB candidates each unit picks from (one decal can stack 2–3 colors); seed nil = fresh UInt64.random, fixed = reproducible",
                 "SplatterShape — Sendable rolled value: units (each a tendril body + wet rim + droplet specks, as pure vertex rings in absolute coords) + startedAt + duration. alpha(now:) = hold holdFraction(0.66) then linear fade; isActive(now:) gates the clock",
                 "SplatterShape.Unit — center, color (UInt32), body/rim/droplets vertex rings (smoothed at draw time)",
                 "drawInkSplatter(_:now:) — @MainActor AppKit renderer (Catmull-Rom-smoothed blobs: darker wet rim → body → droplets) into the current NSGraphicsContext, faded to alpha(now:). Radial → orientation-agnostic",
             ],
        variants: [
                 "Geometry (wand DecalManager port): lead unit near centre (largest) + 1–2 orbit units; each a 22–29-vertex 3-tier tendril blob (body 60% / short tendril 30% / long spike 10%) + 1.08× rim + 3–6 droplets",
                 "Color: per-unit pick from the palette (Splatoon multi-shot); rim = darker blend of the unit ink",
                 "Lifetime: hold 66% at full → linear fade to 0; static shape (only alpha moves)",
                 "DIVISION OF LABOUR: lives in Effects with the particle burst (fire-moment FX). Pure vertices (Double tuples), Catmull-Rom + NSColor stay in the gated draw helper. No timer/state — app owns the clock",
             ],
        family: .particles,
        defaultType: "InkSplatterView",
        imports: [
            "import ThemeKitUI   // InkSplatterView (pure SwiftUI Canvas, no AppKit wrap)",
        ],
        initSnippet: """
InkSplatterView(
    colors: [0xFFD700, 0xFF6EC7, 0x00E5FF]
)
.frame(width: 160, height: 150)
""",
        sourcePath: "ThemeKitUI/InkSplatterView.swift"),
    KitComponent(
        name: "TrailGeometry", module: "Effects",
        kind: "Path-geometry primitives — arc-length resampler + corner rounding (wand's gesture-trail tooling, generalized)",
        summary: "Pure geometry the family re-implements to lay marks along, or round the corners of, a polyline. NOT an f(now) effect — coordinate-agnostic functions over (x:y:) points. resampleAlongPolyline drives every 'glyphs along a path' style; roundedCornerPath softens a snapped gesture polyline.",
        consumes: "Pure functions + one AppKit path builder — no instance. `import Effects`. Lay glyphs: `for m in resampleAlongPolyline(points, interval: 24) { drawGlyph(at: m.point, angle: atan2(m.tangent.y, m.tangent.x)) }`. Round corners: `nsBezierPath(roundedCornerPath(corners, radius: lineWidth*4)).stroke()`. (Double-tuple or CGPoint overloads.)",
        keyAPI: [
                 "resampleAlongPolyline(_:interval:trimTail:) -> [TrailMark] — march a polyline emitting a point + UNIT tangent every `interval` of arc length (carry across joins). First + last always emitted; trimTail>0 stops that far short (wand's Chomp gap). [] for interval<=0 / empty / trimTail>length",
                 "TrailMark — { point:(x,y), tangent:(x,y) } — place + orient a glyph",
                 "roundedCornerPath(_:radius:) -> [PathStep] — cut each interior corner back by radius (capped to ½ each leg) + a quadratic bridge. PathStep = .move/.line/.quadCurve(to:control:). wand's lineWidth*4 radius",
                 "nsBezierPath(_:lineWidth:) -> NSBezierPath — @MainActor: PathStep list → round-capped NSBezierPath (quadCurve → cubic w/ both controls at the corner). The drawLinePets-style AppKit materializer",
             ],
        variants: [
                 "resampleAlongPolyline: drives pixel / ascii / arrow-chain / paws / chomp-pellet placement (uniform spacing through corners)",
                 "roundedCornerPath: the straightened-gesture trail's corner softening (PathStep is cross-platform; NSBezierPath stays gated)",
                 "DIVISION OF LABOUR: pure geometry in Effects (no f(now), no theming); NSBezierPath behind canImport(AppKit). Color cycling for a trail reuses Effects.blendThrough; fade reuses Motion",
             ],
        family: .particles,
        imports: [
            "import Effects   // resampleAlongPolyline, roundedCornerPath, TrailMark, PathStep",
        ],
        initSnippet: """
let points: [(x: Double, y: Double)] = [(0, 0), (40, 0), (40, 40), (80, 40)]

// (a) lay glyphs along the path, oriented by the local tangent
for m in resampleAlongPolyline(points, interval: 24) {
    let angle = atan2(m.tangent.y, m.tangent.x)
    // drawGlyph(at: m.point, angle: angle)
}

// (b) soften the polyline's interior corners into a pure step list
let steps = roundedCornerPath(points, radius: 8)   // [PathStep] — .move/.line/.quadCurve
""",
        sourcePath: "Effects/Trail.swift",
        appkitEscape: "nsBezierPath(_:lineWidth:) -> NSBezierPath (Effects, @MainActor) — turns a [PathStep] into a round-capped NSBezierPath; only needed outside SwiftUI. In SwiftUI, translate PathStep into a Path yourself (ThemeKitUI's swiftUIPath(from:) is `internal`, not public API) via .move(to:)/.addLine(to:)/.addQuadCurve(to:control:)",
        isAtom: true),
    KitComponent(
        name: "PixelSprite", module: "PixelArt + Effects",
        kind: "Pixel-art sprite atom — wand's chomp (Pac-Man) arcade decals as resolution-independent integer pixel grids (#12 Ph1+Ph2: line-pets unified to pixel, mouth/waddle via Motion.frameStep; Ph3: ghost line-pet is UPRIGHT + directional)",
        summary: "Pure PixelArt grids (PixelSprite = rows:[String] + palette:[Character:UInt32], flattened by cells()) + the circle-minus-mouth pacManCells wedge + a stable positionHash01 jitter + a ScaleTier size knob; Effects owns the @MainActor blitter (drawPixelSprite/drawPacMan, antialias OFF for crisp pixels). Colours are INTRINSIC arcade constants (pac-yellow/ghost-red/eye-white/pupil-blue/cherry/brown), reconciled to ThemeSpec.chomp roles where one exists — so chomp reads identically across every theme (self-contained arcade look, not role-driven).",
        consumes: "`import PixelArt` for the pure grids/geometry; `import Effects` for the @MainActor draw, hosted in an isFlipped view (row 0 = top). Pac-Man: `drawPacMan(diameterCells:mouthHalfRad:cell:at:)`. Generic: `drawPixelSprite(CanonicalSprite.ghost, cell:at:)`. Clock injected as now:Double. Ph2: the unified line-pets (drawLinePets) are now PIXEL — the mouth flaps via ThemedTransition.frameStep(now:hz:chompMouthHz, frames:chompMouthFrames) and the ghost waddles at CanonicalSprite.waddleHz. Ph3: the ghost line-pet stays UPRIGHT (no longer tumbles with the lap) and only its eyes swivel — drawLinePets snaps the travel tangent to a cardinal via GhostLook.facing(dx:dy:) and blits CanonicalSprite.ghostFrames(look:); pac still rotates.",
        keyAPI: [
                 "PixelSprite { rows:[String], palette:[Character:UInt32] }.cells() -> [(col:Int,row:Int,color:UInt32)] — transparent sentinel '.' omitted, row-major; width/height/pixelSize(cell:)",
                 "pacManCells(diameterCells:mouthHalfRad:) -> [(col:Int,row:Int)] — circle minus mouth wedge (excl. cx²+cy²>r², excl. |atan2(cy,cx)|<mouthHalfRad); mouth opens +x",
                 "mouthHalfRad(phase:) -> Double — 5° + 55°·phase (the chomp gape). chompMouthFrames [0,0.5,1,0.5] + chompMouthHz 5 = the canonical mouth swap (fed to Motion.frameStep)",
                 "positionHash01(x:y:) -> Double in 0..<1 — stable per-cell jitter (Knuth-mult mix, wrapping, negative-safe)",
                 "ScaleTier {.s,.m,.l}.multiplier -> 2 / 3 / 4.5 — generic size knob",
                 "drawPixelSprite(_:cell:at:color:) / drawPacMan(diameterCells:mouthHalfRad:cell:at:color:) — @MainActor AppKit blit, antialias OFF; color: overrides the sprite's intrinsic cells",
                 "CanonicalSprite.cherry (12×13) / .ghost / .ghostAlt (14×14, 2-pose waddle); .waddleFrames [ghost,ghostAlt] + .waddleHz 1.5; SpriteColor.* intrinsic 0xRRGGBB constants",
                 "GhostLook {.up,.right,.down,.left} + .facing(dx:dy:) snaps a travel tangent to a cardinal (y-up); CanonicalSprite.ghostSprite(feet:look:) / .ghostFrames(look:) build the upright directional ghost (#12 Ph3 — body fixed, pupils track travel)",
             ],
        variants: [
                 "Pac-Man = geometry (rigid grid; the draw context rotates by the travel tangent to aim the mouth) — cherry/ghost = literal authored sprites; ghost has a 2-pose skirt for the waddle and (Ph3) is UPRIGHT in the line-pet — only its pupils swivel to the travel cardinal, while pac keeps rotating",
                 "DIVISION OF LABOUR: pure grids + circle/wedge/hash math in PixelArt (zero AppKit, zero Palette — intrinsic UInt32 colours); NSRect fill behind canImport(AppKit) in Effects. Theme-INVARIANT by design (chomp is always yellow/red/blue/black)",
                 "Ph roadmap (#12): Ph1 sprites+blitter ✓ → Ph2 unify line-pets + Motion.frameStep ✓ → Ph3 upright directional-eye ghost ✓ (this) + PathPet next → Ph4 neon corridor + pellets → Ph5 eat + rainbow flash + score",
             ],
        family: .particles,
        defaultType: "PixelSpriteView",
        imports: [
            "import ThemeKitUI   // PixelSpriteView — pure SwiftUI front (Image + .interpolation(.none), no AppKit wrap)",
            "import Effects      // CanonicalSprite.cherry — a ready-made PixelSprite value (also re-exports PixelArt's PixelSprite type)",
        ],
        initSnippet: """
PixelSpriteView(sprite: CanonicalSprite.cherry, cell: 6)
""",
        sourcePath: "ThemeKitUI/PixelSpriteView.swift",
        appkitEscape: "drawPixelSprite(_:cell:at:color:) (free function, module Effects, @MainActor) — the pre-#17a AppKit blit; fills each opaque PixelSprite cell as an antialias-off NSRect into the CURRENT NSGraphicsContext (host in an isFlipped NSView). Only reach for it outside SwiftUI."),
    KitComponent(
        name: "MarkdownView", module: "MarkdownKitUI",
        kind: "Themed Markdown renderer — full GFM, selectable NSTextView (AppKit floor-3)",
        summary: "Renders a GFM string into ONE selectable/copyable NSTextView themed by ResolvedPalette: inline code is a rounded pill (fillBackgroundRectArray), tables/code-blocks/blockquotes get real NSTextTable rules. Re-themes by reassigning palette. (A SwiftUI textRenderer pill can't coexist with .textSelection — hence the floor-3 AppKit render core.)",
        consumes: "A SwiftUI View: `MarkdownView(palette:source:)`. Content-sized — embed directly, or wrap in a ScrollView for a clamped popover. Backed by an NSViewRepresentable over a TextKit-1 NSTextView (InlineCodePillLayoutManager).",
        keyAPI: [
                 "palette: ResolvedPalette — theme; drives all colour roles (foreground, primary, tertiary, border) + ink(.wash/.subtle/.strong) overlays",
                 "source: String — raw GFM Markdown; parsed by swift-markdown into one NSAttributedString",
                 "style: MarkdownStyle — baseFontSize, headingScales, line spacing, pill corner radius (default: .default)",
                 "highlighter: MarkdownHighlighter? — optional syntax-highlight hook (AttributedString) bridged to NSColor runs; nil ⇒ plain themed mono",
             ],
        variants: [
                 "Block elements: heading (h1–h6, h1/h2 underline) / paragraph / blockquote (NSTextTable left bar) / fenced code block (NSTextTable bg + lang label + highlight) / bullet list / ordered list / task list (☑/☐) / GFM table (NSTextTable, column alignment) / thematic break (hr)",
                 "Inline elements: bold / italic / strikethrough / inline code (rounded pill) / link (primary, underline) / image stub / raw-HTML passthrough",
                 "MarkdownStyle: baseFontSize, headingScales, bodyLineSpacing, pillCornerRadius — all in pt, scalable",
                 "Natively selectable + ⌘C copy (the NSTextView handles ⌘C itself, so copy works in a menu-less / non-activating host)",
             ],
        family: .glance),
]

/// Look up a component by its public type name (the names are fixed in the gallery).
func kitComponent(_ name: String) -> KitComponent {
    kitCatalog.first { $0.name == name }
        ?? KitComponent(name: name, module: "ThemeKit", kind: "", summary: "",
                        consumes: "", keyAPI: [], variants: [], family: .text)
}

/// Per-app prism-tab metadata: a one-line blurb + what the app ACTUALLY consumes
/// from sill + its notable themes (grounded in the app-repo survey 2026-06-21).
/// Drives the caption under each per-app tab so the bench shows the CONSUMER
/// reality (apps are theme + effect-painted bespoke chrome — they barely use the
/// ThemeKit widgets, which exist for build-best-then-migrate).
struct AppChrome: Identifiable {
    let tab: KitFamily       // .facet/.wand/.perch/.halo/.glance
    let blurb: String        // what the app's surface is
    let uses: String         // sill modules / widgets / effects it consumes
    let themes: String       // notable themes it ships
    var id: String { tab.rawValue }
}

let appChromes: [AppChrome] = [
    AppChrome(tab: .facet,
        blurb: "window/workspace manager — sidebar tree · grid · rail overlays",
        uses: "Palette · PaletteKit · Effects · ThemedScroller · border/flash/pets",
        themes: "14 themes (terminal · chomp · rainbow · …)"),
    AppChrome(tab: .wand,
        blurb: "gesture daemon — fullscreen trail + non-activating launcher tome",
        uses: "Palette · Effects · CLIKit · ThemedMenu (tome cascade + .toolbar/.labeledToolbar bar) · line-pets (trail bespoke)",
        themes: "7 themes (chomp · splatoon · neon · vapor · mono · …)"),
    AppChrome(tab: .perch,
        blurb: "keyboard hint overlay — frosted hint pills over clickables",
        uses: "Palette · PaletteKit · Effects · CLIKit · border · particles",
        themes: "8 themes (system · dracula · nord · …)"),
    AppChrome(tab: .halo,
        blurb: "focus ring — thin click-through glow around the focused window",
        uses: "Palette · Effects · border · flash · line-pets (no widgets)",
        themes: "6 themes (neon · cyber · vapor · kawaii · rainbow · chomp)"),
    AppChrome(tab: .glance,
        blurb: "markdown popover — non-activating panel, fixed dark preset",
        uses: "Palette · PaletteKit only (no Effects, no theme switching)",
        themes: "fixed catppuccin-mocha"),
]

/// The metadata for an app tab, or nil for a Kit tab.
func appChrome(_ tab: KitFamily) -> AppChrome? {
    appChromes.first { $0.tab == tab }
}
