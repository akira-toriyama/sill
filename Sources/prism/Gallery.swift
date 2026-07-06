// prism — the gallery: one card per theme, each rendered IN its own
// resolved palette so the colors read as they will in a real app.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects
import Motion
import ThemeKit
import ThemeKitUI

// MARK: - UI scale

/// One knob for the whole prism preview's type + metrics. Every font goes
/// through `sysFont`, and the fixed panel / swatch / icon / window sizes are
/// multiplied by this, so bumping it enlarges the entire gallery uniformly.
let uiScale: CGFloat = 1.5

/// A SwiftUI system font at the global `uiScale`. Drop-in for
/// `.system(size:weight:design:)` — same labels, just scaled.
func sysFont(_ size: CGFloat, weight: Font.Weight = .regular,
             design: Font.Design = .default) -> Font {
    .system(size: size * uiScale, weight: weight, design: design)
}

// MARK: - Gallery

struct Gallery: View {
    let config: PrismConfig

    /// Catalog names the theme Picker offers — the `random` meta-name is a roll
    /// action, not a persistent selection, so it's excluded. Internal (not
    /// `private`) so the sibling `FoundationAppPage` can reuse this same list for
    /// the palette page's 36-chip swatch wall.
    static let switchable = canonicalThemeNames.filter { $0 != "random" }

    /// The first real widget row's name — the fallback selection when the config
    /// deep-links neither a widget nor a family. Derived from the SAME
    /// `sidebarSections` registry the sidebar renders (first non-Foundations /
    /// non-Apps section, its first `.widget`), so it can't drift from the list.
    private static let firstWidgetName: String =
        sidebarSections
            .first { $0.title != "Foundations" && $0.title != "Apps" }?
            .items
            .compactMap { item -> String? in
                if case .widget(let n) = item { return n }
                return nil
            }
            .first ?? "ThemedButton"

    /// Which sidebar row is open — drives the detail page. Optional because
    /// `List(selection:)` binds a `Binding<SidebarItem?>`. Seeded from the config
    /// (widget deep-link → family → the first widget), then driven by the List
    /// (click or ↑/↓ when the List has focus).
    @State private var selection: SidebarItem?

    /// Live theme selection for the top-bar Picker: `"all"` (every theme) or one
    /// canonical theme name. Seeded from the config; the detail pages (Tasks 6-7)
    /// read it to render a widget in the chosen palette.
    @State private var selectedTheme: String

    /// The sidebar search query — a plain SwiftUI `TextField` in the sidebar
    /// header filters `sidebarSections` by it (see `filteredSections`).
    @State private var searchText = ""

    /// Whether the sidebar column is shown. The top-bar toggle flips it with an
    /// animation; the body simply drops the sidebar + its divider when false.
    @State private var sidebarVisible = true

    /// The live effect 演出 master toggle (派手 ON / 静か OFF). Seeded from the
    /// config's `show-effects`, then driven by the top-bar toggle at runtime — it
    /// flips the animated widget accents, the cycling card rim, and the effect
    /// strips together (the live mirror of the library's `effectsEnabled`).
    @State private var showEffects: Bool

    init(config: PrismConfig) {
        self.config = config
        let t = config.theme
        _selectedTheme = State(initialValue:
            (t == "all" || Gallery.switchable.contains(t)) ? t : "all")
        _showEffects = State(initialValue: config.showEffects)
        // Open on the config's widget deep-link if it names one, else its family
        // (a Foundation or an app tab), else the first widget row.
        _selection = State(initialValue:
            sidebarItem(forWidget: config.widget)
            ?? sidebarItem(forFamily: config.family)
            ?? .widget(Gallery.firstWidgetName))
    }

    // MARK: body — a custom split view (sidebar | detail column)
    //
    // A hand-rolled `HStack` split (NOT `NavigationSplitView`) so the shell keeps
    // full MUI-docs造形 control of both columns — decision D1. The sidebar + its
    // divider simply drop out of the layout when `sidebarVisible` is false; the
    // top-bar toggle animates that. Shell stays pure SwiftUI (CLAUDE.md AppKit
    // policy) — no window `NSToolbar`, so the top bar is in-content.

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar
                Divider()
            }
            detailColumn
        }
        .frame(minWidth: 920 * uiScale, minHeight: 600 * uiScale)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: detail column — an in-content top bar over the per-selection page

    private var detailColumn: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            detailPage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: top bar — sidebar toggle · theme Picker · effect master toggle

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { withAnimation { sidebarVisible.toggle() } } label: {
                phosphorIcon("list", 13)
            }
            .buttonStyle(.plain)
            .help("Toggle the sidebar")

            Picker("Theme", selection: $selectedTheme) {
                Text("All").tag("all")
                ForEach(Gallery.switchable, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 220 * uiScale)

            Spacer()
            EffectToggle(on: showEffects) { showEffects.toggle() }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: sidebar — a search field over the selectable widget List
    //
    // Plain SwiftUI throughout: a `TextField` (NOT `.searchable`, NOT an AppKit
    // ThemedTextField) filters the list; `List(selection:)` gives click + ↑/↓
    // selection when it holds focus. No `@FocusState` gymnastics are needed now
    // that `.searchable` is gone — the TextField doesn't grab first responder at
    // launch, so the List is free to take arrow-key focus on first click.

    private var sidebar: some View {
        VStack(spacing: 0) {
            TextField("Search widgets", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(sysFont(11))
                .padding(.horizontal, 10).padding(.vertical, 8)
            List(selection: $selection) {
                ForEach(filteredSections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Text(sidebarLabel(item)).tag(item)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 220 * uiScale)
    }

    /// `sidebarSections` filtered by `searchText` (case-insensitive over each
    /// item's `sidebarSearchText`). Empty query ⇒ the full registry; a section
    /// with no surviving items drops out entirely.
    private var filteredSections: [SidebarSection] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sidebarSections }
        return sidebarSections.compactMap { s in
            let items = s.items.filter { sidebarSearchText($0).contains(q) }
            return items.isEmpty ? nil : SidebarSection(title: s.title, items: items)
        }
    }

    // MARK: detail page — placeholder per selection (real pages: Tasks 6-7)

    @ViewBuilder private var detailPage: some View {
        if let selection {
            switch selection {
            case .widget(let name) where selectedTheme == "all":
                // "All" tiles the ONE selected widget's live mock across every
                // switchable theme — a comparison grid, and the deterministic
                // capture target for `theme="all"` deep-links. One mock per
                // theme (not the decomposed cell grid) keeps live-animation load
                // no worse than the prior single-theme "all" fallback.
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320 * uiScale), spacing: 16)], spacing: 16) {
                        ForEach(Gallery.switchable, id: \.self) { theme in
                            let base = resolve(paletteFor(theme))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(theme).font(sysFont(9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(nsColor: base.muted))
                                if showEffects, isAnimatableTheme(theme) {
                                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { t in
                                        mock(for: name, p: base.animated(forTheme: theme,
                                            at: CGFloat(t.date.timeIntervalSinceReferenceDate / effectCycleSeconds)),
                                            themeName: theme, showEffects: showEffects)
                                    }
                                } else {
                                    mock(for: name, p: base, themeName: theme, showEffects: showEffects)
                                }
                            }
                        }
                    }.padding(18)
                }
            case .widget(let name):
                // `ThemedListView` supplies decomposed `cells` (its 12 specimens)
                // so Overview shows a COMPACT prefix(2) while Specimens keeps the
                // whole grid; every other widget passes `cells: nil` (whole mock
                // in both). `section` seeds case-insensitively from the config;
                // `show-all` forces Specimens. `selectedTheme` is never "all"
                // here — the case above catches that.
                WidgetPage(
                    component: kitComponent(name),
                    themeName: selectedTheme,
                    showEffects: showEffects,
                    mock: { p in AnyView(mock(for: name, p: p,
                        themeName: selectedTheme, showEffects: showEffects)) },
                    cells: name == "ThemedListView" ? { p in MockList.cellViews(p: p) } : nil,
                    section: config.showAll ? .specimens
                        : (PageSection.allCases.first { $0.rawValue.lowercased() == config.section } ?? .overview))
            case .foundation, .app:
                FoundationAppPage(item: selection,
                                  themeName: selectedTheme,
                                  showEffects: showEffects)
            }
        } else {
            Text("Select a widget").foregroundColor(.secondary)
        }
    }
}

// MARK: - Widget mock map (file-level; one case per wired widget)

/// The single widget's live mock for `WidgetPage` — the SOLE widget-mock map now
/// that the retired `ThemeCard.widgetFamily(p:)` is gone (its cases were folded
/// here). Every case renders a `Mock…(p:)`; `themeName` is threaded to the two
/// that need it (`MockThemedPill`, `MockBorder`). App mocks (MockTree/…/
/// MockGlancePopover) are NOT here — they belong to the app page.
///
/// MUST be kept in sync with `mockHandles` below (same case list) — that
/// twin function is what makes this render map itself testable
/// (`testEveryWiredMockNameIsRendered` in PrismLogicTests). `wiredMockNames`
/// (SidebarModel.swift) is a hand-kept mirror of this case list; see that
/// file's doc comment for how the three pieces (catalog rows →
/// `wiredMockNames` → this switch) are pinned together.
@MainActor @ViewBuilder func mock(for name: String, p: ResolvedPalette, themeName: String, showEffects: Bool) -> some View {
    switch name {
    case "ThemedTextField":    MockField(p: p)
    case "ThemedComboBox":     MockComboBox(p: p)
    case "ThemedButton":       MockButton(p: p)
    case "ThemedButtonGroup":  MockButtonGroup(p: p)
    case "ThemedToolBar":      MockToolBar(p: p)
    case "ThemedChip":         MockChip(p: p)
    case "ThemedPill":         MockThemedPill(p: p, themeName: themeName)
    case "ThemedCheckbox":     MockCheckbox(p: p)
    case "ThemedFAB":          MockFAB(p: p)
    case "ThemedDivider":      MockDivider(p: p)
    case "AnimatedBorderView": MockBorder(p: p, themeName: themeName)
    case "ThemedSkeleton":     MockSkeleton(p: p)
    case "ThemedTooltip":      MockTooltip(p: p)
    case "ThemedBackdrop":     MockBackdrop(p: p)
    case "WindowShell":        MockWindowShell(p: p)
    case "ThemedListView":     MockList(p: p)
    case "ThemedMenu":         MockMenu(p: p)
    case "ThemedGrid":         MockThumbnailGrid(p: p)
    case "ThemedTransition":   MockMotion(p: p)
    case "ParticleBurst":      MockParticles(p: p)
    case "SplatterShape":      MockSplatter(p: p)
    case "TrailGeometry":      MockTrail(p: p)
    case "PixelSprite":        MockPixelArt(p: p)
    default:                   EmptyView()
    }
}

/// Whether `mock(for:)` above has a real case for `name` (vs. falling to its
/// `default: EmptyView()` — a blank page, the CLAUDE.md #17f failure mode).
/// MUST be kept in sync with `mock(for:)` (same case list) — this twin function
/// exists solely so the render map is testable without instantiating SwiftUI
/// views (`testEveryWiredMockNameIsRendered` in PrismLogicTests).
func mockHandles(_ name: String) -> Bool {
    switch name {
    case "ThemedTextField", "ThemedComboBox",
         "ThemedButton", "ThemedButtonGroup", "ThemedToolBar", "ThemedChip", "ThemedPill", "ThemedCheckbox", "ThemedFAB",
         "ThemedDivider", "AnimatedBorderView", "ThemedSkeleton", "ThemedTooltip", "ThemedBackdrop", "WindowShell",
         "ThemedListView", "ThemedMenu", "ThemedGrid",
         "ThemedTransition",
         "ParticleBurst", "SplatterShape", "TrailGeometry", "PixelSprite":
        return true
    default:
        return false
    }
}

// MARK: - Theme chip (a theme swatch tile)

/// One theme swatch tile: the theme name on a tile tinted with that theme's
/// OWN resolved colours (bg / foreground / primary), so a wall of them is
/// itself a colour preview. `"all"` renders in neutral app chrome. A
/// `selected` chip gets a 2.5 px primary ring + bold label + a soft accent
/// glow. The palette foundation page tiles the whole catalog into a swatch
/// grid (non-interactive, `selected: false`); the `action` closure lets a
/// caller make a chip a live switcher.
struct ThemeChip: View {
    let name: String          // "all" or a canonical theme name
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let isAll = (name == "all")
        let p = isAll ? nil : resolve(paletteFor(name))
        let bg = p?.background.map { Color(nsColor: $0) }
            ?? Color(nsColor: .controlColor)
        let fg = p.map { Color(nsColor: $0.foreground) }
            ?? Color(nsColor: .labelColor)
        let accent = p.map { Color(nsColor: $0.primary) }
            ?? Color(nsColor: .controlAccentColor)

        Button(action: action) {
            HStack(spacing: 5) {
                // A dot in the theme's accent so two same-background themes
                // still read apart at the chip's leading edge.
                if !isAll {
                    Circle().fill(accent).frame(width: 6, height: 6)
                }
                Text(label)
                    .font(sysFont(11, weight: selected ? .bold : .medium,
                                  design: .monospaced))
                    .foregroundColor(fg)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(accent, lineWidth: selected ? 2.5 : 1)
                .opacity(selected ? 1 : 0.6))
            .shadow(color: accent.opacity(selected ? 0.5 : 0),
                    radius: selected ? 4 : 0)
        }
        .buttonStyle(.plain)
        .help(isAll ? "Show every theme" : "Switch to \(name)")
    }
}

// MARK: - Flow layout (wrapping row of chips)

/// A minimal left-to-right wrapping layout (macOS 13's `Layout` protocol):
/// lays subviews along a line at their natural width, wrapping to the next
/// line when the next subview would overflow. Used for the variable-width
/// theme chips, which a `LazyVGrid` would force to a uniform column width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxW {        // wrap before this subview
                y += lineH + lineSpacing; x = 0; lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(maxW, widest), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {   // wrap
                y += lineH + lineSpacing; x = bounds.minX; lineH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                     proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

// MARK: - Copy-ref button

/// Copies a component's `pasteReadyCore` (type-to-use · imports · a minimal
/// compilable-shape init) to the clipboard — so the user can paste it into
/// ANOTHER Claude Code session that then DROPS the part straight into code.
/// Flashes a check on copy.
struct CopyRefButton: View {
    let component: KitComponent
    let p: ResolvedPalette
    @State private var copied = false

    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(component.pasteReadyCore, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { copied = false }
        } label: {
            HStack(spacing: 4) {
                phosphorIcon(copied ? "check" : "copy", 10)
                Text(copied ? "copied" : "copy ref")
            }
            .font(sysFont(8.5, weight: .medium, design: .monospaced))
            .foregroundColor(Color(nsColor: copied ? p.primary : p.muted))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: copied ? p.primary : p.border), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Copy \(component.name) reference info to the clipboard (paste it to another agent)")
    }
}

// MARK: - Effect toggle (the 演出 master switch in the top bar)

/// The bench-wide effect master toggle. Neutral app chrome (it spans every
/// theme), styled as a pill: ON fills with the system accent +
/// a `sparkles` glyph (派手); OFF rests neutral and dimmed with a `moon.zzz`
/// glyph (静か). Flipping it drives prism's `showEffects` — the live mirror of
/// the library's `effectsEnabled` — so the animated widget accents, the cycling
/// card rim, and the `.palette` `LiveEffectStrip` all start / stop together.
struct EffectToggle: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                phosphorIcon(on ? "sparkle" : "moon", 11)
                Text("Effects \(on ? "ON" : "OFF")")
                    .font(sysFont(11, weight: on ? .bold : .medium, design: .monospaced))
            }
            .foregroundColor(on ? Color.white : Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(on ? Color(nsColor: .controlAccentColor)
                         : Color(nsColor: .controlColor)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: on ? 0 : 1))
        }
        .buttonStyle(.plain)
        .help("Toggle the effect 演出 (live animation) across the bench — 派手 ON / 静か OFF")
    }
}

// MARK: - Swatch row (every resolved role)

struct SwatchRow: View {
    let p: ResolvedPalette

    var body: some View {
        let roles: [(String, NSColor?)] = [
            ("background", p.background), ("foreground", p.foreground),
            ("muted", p.muted), ("tertiary", p.tertiary),
            ("primary", p.primary), ("secondary", p.secondary),
            ("border", p.border), ("hover", p.hover),
            ("selection", p.selection), ("error", p.error),
        ]
        HStack(alignment: .top, spacing: 7) {
            ForEach(roles, id: \.0) { role in
                Swatch(label: role.0, color: role.1, ink: p.foreground, muted: p.muted)
            }
        }
    }
}

/// The #8 type scale, live — every `TypeRole` drawn at its REAL resolved
/// font (`p.uiFont(role)`, so the rounded/menu family fix shows too), with
/// its pt·weight annotated. On the static `.palette` tab for deterministic
/// capture; re-themes per card like the swatches.
struct TypeScaleSpecimen: View {
    let p: ResolvedPalette
    private let roles: [(TypeRole, String)] = [
        (.body, "body"), (.secondaryBody, "secondaryBody"), (.caption, "caption"),
        (.sectionHeader, "sectionHeader"), (.sectionTitle, "sectionTitle"),
        (.badge, "badge"), (.shortcut, "shortcut"), (.tooltip, "tooltip"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(roles, id: \.1) { role, label in
                let t = role.token
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(label) — Quick brown fox 0123")
                        .font(Font(p.uiFont(role) as CTFont))
                        .foregroundColor(Color(nsColor: muted(role) ? p.muted : p.foreground))
                    Spacer(minLength: 8)
                    Text("\(Int(t.pt))pt · \(weightLabel(t.weight))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                }
            }
        }
    }
    private func muted(_ r: TypeRole) -> Bool { r == .secondaryBody || r == .caption }
    private func weightLabel(_ w: TypeWeight) -> String {
        switch w {
        case .regular:  return "regular"
        case .medium:   return "medium"
        case .semibold: return "semibold"
        }
    }
}

/// #13 design-token specimen — sill's fixed `Space` / `Radius` / `Elevation`
/// scales rendered live so the maintainer can eyeball the ramps per theme.
/// The Elevation row drives `ResolvedPalette.shadow(_:)` (the PaletteKit
/// resolver), so this is also the live exercise of that table while the
/// widgets still hand-roll their own elevation (consolidation is #14a).
struct TokenSpecimen: View {
    let p: ResolvedPalette
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Radius ramp — a filled tile per step, rounded by the token.
            tokenRow("Radius") {
                ForEach(Radius.scale, id: \.name) { step in
                    swatchCol("\(step.name)·\(Int(step.pt))") {
                        RoundedRectangle(cornerRadius: CGFloat(step.pt) * uiScale)
                            .fill(Color(nsColor: p.primary).opacity(0.85))
                            .frame(width: 44 * uiScale, height: 30 * uiScale)
                    }
                }
            }
            // Space ramp — two accent bars separated by the token's gap.
            tokenRow("Space") {
                ForEach(Space.scale, id: \.name) { step in
                    swatchCol("\(step.name)·\(Int(step.pt))") {
                        HStack(spacing: 0) {
                            accentBar
                            Color.clear.frame(width: CGFloat(step.pt) * uiScale)
                            accentBar
                        }
                        .frame(height: 28 * uiScale)
                    }
                }
            }
            // Elevation ladder — a surface card per depth, shadow from the
            // resolver (offsetY is pre-negated for AppKit y-up; SwiftUI's y is
            // down, so re-negate here).
            tokenRow("Elevation") {
                ForEach(Elevation.allCases, id: \.self) { level in
                    let s = p.shadow(level)
                    swatchCol(elevationLabel(level)) {
                        RoundedRectangle(cornerRadius: CGFloat(Radius.sm) * uiScale)
                            .fill(Color(nsColor: p.background ?? .windowBackgroundColor))
                            .frame(width: 40 * uiScale, height: 30 * uiScale)
                            .overlay(RoundedRectangle(cornerRadius: CGFloat(Radius.sm) * uiScale)
                                .stroke(Color(nsColor: p.border), lineWidth: 1))
                            .shadow(color: .black.opacity(Double(s.opacity)),
                                    radius: s.radius, x: 0, y: -s.offsetY)
                            .padding(4 * uiScale)
                    }
                }
            }
        }
    }

    private var accentBar: some View {
        Rectangle().fill(Color(nsColor: p.primary)).frame(width: 4 * uiScale)
    }
    private func swatchCol<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 3) {
            content()
            Text(label)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
        }
    }
    @ViewBuilder private func tokenRow<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(sysFont(10, weight: .semibold))
                .foregroundColor(Color(nsColor: p.muted))
            HStack(alignment: .bottom, spacing: 10 * uiScale) { content() }
        }
    }
    private func elevationLabel(_ e: Elevation) -> String {
        switch e {
        case .flat: return "flat"
        case .dp2:  return "dp2"
        case .dp4:  return "dp4"
        case .dp6:  return "dp6"
        case .dp8:  return "dp8"
        case .dp12: return "dp12"
        }
    }
}

struct Swatch: View {
    let label: String
    let color: NSColor?
    let ink: NSColor
    let muted: NSColor

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Checkerboard behind every swatch so a TRANSLUCENT role
                // (border @0.10, hover @0.05) and a nil/transparent
                // background read as see-through — the alpha is visible
                // against both the light and dark checker cells.
                Checker()
                if let c = color {
                    Rectangle().fill(Color(nsColor: c))
                }
            }
            .frame(width: 50 * uiScale, height: 32 * uiScale)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: ink).opacity(0.30), lineWidth: 1))

            Text(label)
                .font(sysFont(8.5, weight: .medium))
                .foregroundColor(Color(nsColor: ink)).opacity(0.9)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 52 * uiScale)
            Text(color.map(hexString) ?? "nil")
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: muted))
                .lineLimit(1).minimumScaleFactor(0.6).frame(width: 52 * uiScale)
        }
    }
}

/// A small grey checkerboard — the universal "transparent" backdrop so a
/// translucent swatch's alpha is legible on any theme background.
struct Checker: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(white: 0.80)))
            let cell: CGFloat = 5
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 1 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell,
                                         width: cell, height: cell)),
                             with: .color(Color(white: 0.52)))
                }
            }
        }
    }
}

// MARK: - Effect flash palette
//
// The effect preview moved to EffectShowcase.swift's `LiveEffectStrip` — the
// old static `EffectStrip` only listed the flash palette, so the dynamic atom
// looked disabled. The live version drives `resolveBorder` off a clock, so the
// effect actually animates (cycling chip + glowing card border + a "live" dot).

// MARK: - Helpers

/// SwiftUI font for a `FontKind` (prism-local; mirrors PaletteKit's uiFont
/// without touching the global `pal`). `.menu` ≈ system for a specimen.
func themeFont(_ kind: FontKind, size: CGFloat) -> Font {
    switch kind {
    case .mono:    return sysFont(size, design: .monospaced)
    case .rounded: return sysFont(size, design: .rounded)
    case .menu, .system: return sysFont(size)
    }
}

extension FontKind {
    var label: String {
        switch self {
        case .mono: return "mono"; case .rounded: return "rounded"
        case .menu: return "menu"; case .system: return "system"
        }
    }
}

/// `#RRGGBB` (+ `·NN%` when translucent) for a resolved NSColor.
func hexString(_ c: NSColor) -> String {
    guard let s = c.usingColorSpace(.sRGB) else { return "—" }
    let r = Int((s.redComponent * 255).rounded())
    let g = Int((s.greenComponent * 255).rounded())
    let b = Int((s.blueComponent * 255).rounded())
    let base = String(format: "#%02X%02X%02X", r, g, b)
    return s.alphaComponent < 0.99
        ? base + String(format: "·%.0f%%", s.alphaComponent * 100)
        : base
}
