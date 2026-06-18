// prism — the gallery: one card per theme, each rendered IN its own
// resolved palette so the colors read as they will in a real app.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects

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

    /// Catalog names the header switcher offers — the `random` meta-name is
    /// a roll action, not a persistent selection, so it's excluded.
    private static let switchable = canonicalThemeNames.filter { $0 != "random" }

    /// Live selection: `"all"` (the full gallery) or one canonical theme.
    /// Seeded from the config so `theme = "dracula"` still opens on dracula;
    /// the header chips then drive it at runtime — no relaunch, no file edit.
    @State private var selected: String

    /// The widget-family tab in view. Each card renders ONLY this family's content,
    /// so a card stays short (no more 11-mock scroll). `.palette` = theme foundations.
    @State private var selectedFamily: KitFamily = .palette

    /// The live effect 演出 master toggle (派手 ON / 静か OFF). Seeded from the
    /// config's `show-effects`, then driven by the header toggle at runtime — it
    /// flips the animated widget accents, the cycling card rim, and the `.palette`
    /// `LiveEffectStrip` together (the live mirror of the library's `effectsEnabled`),
    /// with no relaunch or file edit.
    @State private var showEffects: Bool

    init(config: PrismConfig) {
        self.config = config
        let t = config.theme
        _selected = State(initialValue:
            (t == "all" || Gallery.switchable.contains(t)) ? t : "all")
        _showEffects = State(initialValue: config.showEffects)
    }

    /// The card(s) currently rendered: every theme when "all", else the one.
    private var shown: [String] {
        selected == "all" ? Gallery.switchable : [selected]
    }

    var body: some View {
        VStack(spacing: 0) {
            header                       // pinned — stays put as the cards scroll
            Divider()
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(shown, id: \.self) { name in
                        ThemeCard(name: name, family: selectedFamily, scale: config.fontScale,
                                  showEffects: showEffects)
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 920 * uiScale, minHeight: 600 * uiScale)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: header — title + the theme-switch chip row

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("prism — \(selected == "all" ? "\(Gallery.switchable.count) themes" : selected)")
                .font(sysFont(12, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            // A wrapping flow of theme buttons — "All" first, then the catalog
            // in order. Each chip is tinted in its own theme colours, so the
            // switch row doubles as an at-a-glance colour preview.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ThemeChip(name: "all", label: "All",
                          selected: selected == "all") { selected = "all" }
                ForEach(Gallery.switchable, id: \.self) { name in
                    ThemeChip(name: name, label: name,
                              selected: selected == name) { selected = name }
                }
            }
            // A rule separating the two control axes: WHICH theme (the colour chips
            // above) vs WHICH widget family (the tabs below).
            Divider()
            // Widget-family tabs — only the chosen family renders in each card, so
            // the bench is browsable by family instead of one painfully tall stack.
            HStack(spacing: 6) {
                ForEach(KitFamily.allCases) { fam in
                    FamilyTab(family: fam, selected: selectedFamily == fam) {
                        selectedFamily = fam
                    }
                }
                Spacer(minLength: 12)
                // The effect 演出 master toggle — flips the live animation across the
                // whole bench (派手 ON / 静か OFF). Trailing the family row so the two
                // global controls (WHICH family · animate-or-not) sit together.
                EffectToggle(on: showEffects) { showEffects.toggle() }
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Theme chip (one header switch button)

/// One header button: the theme name on a tile tinted with that theme's
/// OWN resolved colours (bg / foreground / primary), so the switch row is
/// itself a colour preview. `"all"` renders in neutral app chrome. The
/// selected chip gets a 2.5 px primary ring + bold label + a soft accent
/// glow; clicking it switches the gallery live (no relaunch).
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

// MARK: - Theme card

struct ThemeCard: View {
    let name: String
    let family: KitFamily
    let scale: CGFloat
    let showEffects: Bool

    var body: some View {
        let spec = paletteFor(name)
        let base = resolve(spec)
        let cardBG = base.background.map { Color(nsColor: $0) }
            ?? Color(nsColor: .underPageBackgroundColor)
        let fg = Color(nsColor: base.foreground)

        VStack(alignment: .leading, spacing: 14) {
            // Header: name + font/mode badges. Steady — only the accent cycles,
            // and the header reads none of the accent roles.
            HStack(spacing: 8) {
                Text(name)
                    .font(themeFont(spec.font, size: 16 * scale).weight(.bold))
                    .foregroundColor(fg)
                Text(spec.font.label.uppercased())
                    .font(sysFont(9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: base.muted))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: base.border), lineWidth: 1))
                if spec.background == nil {
                    Text("VIBRANCY")
                        .font(sysFont(9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(nsColor: base.muted))
                }
                Spacer()
            }

            // The body. `.palette` is the (static) theme foundations; the widget
            // families render the REAL ThemeKit widgets. For an animatable theme
            // those widgets cycle LIVE: a 30 Hz `TimelineView` drives each mock's
            // palette through `ResolvedPalette.animated(forTheme:at:)`, so a
            // button's accent / a list's selection wash / a FAB fill breathe
            // through the effect exactly as they will in an app — not the frozen
            // `resolve(spec)` accent the cards used to show.
            if family == .palette {
                paletteFoundations(spec: spec, p: base)
            } else if showEffects, isAnimatableTheme(name) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let live = base.animated(forTheme: name,
                                             at: CGFloat(now / effectCycleSeconds))
                    widgetFamily(p: live)
                }
            } else {
                widgetFamily(p: base)
            }
        }
        .padding(16)
        .background(cardBG)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // The card rim is the REAL shared `ThemedBorder` (dogfood) — the ONE part
        // every theme uses: a static `primary` stroke normally, the LIVE glowing /
        // breathing / cycling effect rim when the theme has an effect AND the master
        // `effectsEnabled` (here prism's `show-effects`) is on.
        .overlay {
            ThemedBorderView(
                palette: base,
                effect: isAnimatableTheme(name) ? borderEffectFor(name) : nil,
                effectsEnabled: showEffects,
                cornerRadius: 12, lineWidth: 1.5)
        }
    }

    /// The `.palette` family — the STATIC theme foundations: every resolved
    /// role as a swatch (kept static so the hex labels stay readable as
    /// documentation), a font specimen, and — for an animatable theme — the
    /// `LiveEffectStrip` (which animates on its own clock). The accent-cycling
    /// demo for the real widgets lives in the other families, not here.
    @ViewBuilder
    private func paletteFoundations(spec: ThemeSpec, p: ResolvedPalette) -> some View {
        SwatchRow(p: p)
        Text("AaBbCcGg 0123 — The quick brown fox jumps")
            .font(themeFont(spec.font, size: 15 * scale))
            .foregroundColor(Color(nsColor: p.foreground))
        if showEffects, let fx = borderEffectFor(name) {
            LiveEffectStrip(fx: fx, name: name, fallback: p.primary)
        }
    }

    /// The widget families — the REAL ThemeKit widgets, each over a `copy ref`
    /// section header. `p` is the LIVE (cycling) palette for an animatable
    /// theme, else the static resolve; the mocks re-theme by reassigning
    /// `palette` each frame (cheap — a snap-recolour, no animation restart).
    @ViewBuilder
    private func widgetFamily(p: ResolvedPalette) -> some View {
        switch family {
        case .palette:
            EmptyView()   // handled by `paletteFoundations`
        case .text:
            WidgetSection(kitComponent("ThemedTextField"), p: p) { MockField(p: p) }
            WidgetSection(kitComponent("ThemedComboBox"), p: p) { MockComboBox(p: p) }
        case .action:
            WidgetSection(kitComponent("ThemedButton"), p: p) { MockButton(p: p) }
            WidgetSection(kitComponent("ThemedButtonGroup"), p: p) { MockButtonGroup(p: p) }
            WidgetSection(kitComponent("ThemedCheckbox"), p: p) { MockCheckbox(p: p) }
            WidgetSection(kitComponent("ThemedFAB"), p: p) { MockFAB(p: p) }
        case .feedback:
            WidgetSection(kitComponent("ThemedDivider"), p: p) { MockDivider(p: p) }
            WidgetSection(kitComponent("ThemedBorder"), p: p) { MockBorder(p: p, themeName: name) }
            WidgetSection(kitComponent("ThemedSkeleton"), p: p) { MockSkeleton(p: p) }
            WidgetSection(kitComponent("ThemedTooltip"), p: p) { MockTooltip(p: p) }
        case .collection:
            WidgetSection(kitComponent("ThemedList"), p: p) { MockList(p: p) }
            WidgetSection(kitComponent("ThemedMenu"), p: p) { MockMenu(p: p) }
        case .chrome:
            Text("App chrome — fake perch / facet / wand / glance, drawn by prism (never imports an app's View).")
                .font(sysFont(9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                MockTree(p: p)
                MockPill(p: p)
                MockTome(p: p)
                MockMarkdown(p: p)
            }
        }
    }
}

// MARK: - Widget section (kit-widget header + copy-ref button + the live mock)

/// A kit-widget block inside a theme card: a header row — the component name, its
/// MUI kind, and a `copy ref` button that puts the component's IDENTIFYING info on
/// the clipboard — over the live `Mock<Widget>`. The header is the only addition
/// vs the old flat stack; the mock itself is unchanged.
struct WidgetSection<Content: View>: View {
    let component: KitComponent
    let p: ResolvedPalette
    let content: Content

    init(_ component: KitComponent, p: ResolvedPalette,
         @ViewBuilder content: () -> Content) {
        self.component = component
        self.p = p
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(component.name)
                    .font(sysFont(11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.foreground))
                Text(component.kind)
                    .font(sysFont(8.5, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                CopyRefButton(component: component, p: p)
            }
            content
        }
    }
}

/// Copies a component's `referenceText` (name · module · kind · key API · variants)
/// to the clipboard — so the user can paste it into ANOTHER Claude Code session
/// that then FINDS + uses the part. Flashes a check on copy.
struct CopyRefButton: View {
    let component: KitComponent
    let p: ResolvedPalette
    @State private var copied = false

    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(component.referenceText, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { copied = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
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

// MARK: - Family tab (one widget-family selector in the header)

/// One widget-family tab. Neutral app chrome (it selects across ALL themes, so it
/// is NOT theme-tinted like the ThemeChip row); the selected tab fills with the
/// system accent.
struct FamilyTab: View {
    let family: KitFamily
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(family.rawValue)
                .font(sysFont(11, weight: selected ? .bold : .medium, design: .monospaced))
                .foregroundColor(selected ? Color.white : Color(nsColor: .labelColor))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color(nsColor: .controlAccentColor)
                                   : Color(nsColor: .controlColor)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor),
                            lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .help("Show the \(family.rawValue) family")
    }
}

// MARK: - Effect toggle (the 演出 master switch in the header)

/// The bench-wide effect master toggle. Neutral app chrome like `FamilyTab`
/// (it spans every theme), styled as a pill: ON fills with the system accent +
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
                Image(systemName: on ? "sparkles" : "moon.zzz")
                    .font(.system(size: 10, weight: .semibold))
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
