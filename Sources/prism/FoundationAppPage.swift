// prism — the Foundation / App detail page. The bespoke right-hand pane for a
// sidebar `.foundation` (Palette · Icons) or `.app` (facet · wand · perch · halo
// · glance) selection, rendered IN the top bar's chosen theme so the colours read
// as they will in a real app.
//
// The palette page PRESERVES the retired shell header's 36-chip theme-swatch wall
// (every catalog theme tinted in its own colours) above the live foundations
// (swatch / type-scale / token specimens + effect strip). The two foundation
// helpers below were LIFTED verbatim out of the now-deleted `ThemeCard` and
// parameterised (they read explicit args instead of `self`), so both this page and
// any future caller share ONE copy.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects

// MARK: - Foundation helpers (file-level; extracted from the retired ThemeCard)

/// The STATIC theme foundations: every resolved role as a swatch (kept static so
/// the hex labels stay readable as documentation), a font specimen, the live type
/// scale + design tokens, and — for an animatable theme with effects on — the
/// `LiveEffectStrip` (which animates on its own clock). Parameterised out of
/// `ThemeCard` (`name`/`scale`/`showEffects` were `self` reads there).
@MainActor
func paletteFoundations(spec: ThemeSpec, p: ResolvedPalette,
                        name: String, scale: CGFloat, showEffects: Bool) -> AnyView {
    AnyView(VStack(alignment: .leading, spacing: 14) {
        SwatchRow(p: p)
        Text("AaBbCcGg 0123 — The quick brown fox jumps")
            .font(themeFont(spec.font, size: 15 * scale))
            .foregroundColor(Color(nsColor: p.foreground))
        TypeScaleSpecimen(p: p)
        TokenSpecimen(p: p)
        if showEffects, let fx = borderEffectFor(name) {
            LiveEffectStrip(fx: fx, name: name, fallback: p.primary)
        }
    })
}

/// The per-app caption — what this app's surface is + what it ACTUALLY consumes
/// from sill + its notable themes (the consumer reality; apps barely use the
/// ThemeKit widgets the Kit tabs showcase). Grounded data, see `appChromes` in
/// KitCatalog.swift. Extracted from `ThemeCard` unchanged.
@MainActor
func appCaption(_ tab: KitFamily, p: ResolvedPalette) -> AnyView {
    guard let a = appChrome(tab) else { return AnyView(EmptyView()) }
    return AnyView(VStack(alignment: .leading, spacing: 2) {
        Text(a.blurb)
            .font(sysFont(10, weight: .medium))
            .foregroundColor(Color(nsColor: p.foreground))
        Text("uses: \(a.uses)")
            .font(sysFont(8.5, design: .monospaced))
            .foregroundColor(Color(nsColor: p.muted))
        Text(a.themes)
            .font(sysFont(8.5, design: .monospaced))
            .foregroundColor(Color(nsColor: p.muted))
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.bottom, 2))   // fidelity: matches the retired ThemeCard.appCaption gap
}

/// One app's signature chrome mock in a given palette (file-level so both this
/// page and Gallery's all-themes app tiling render it from ONE source). perch/halo
/// take the theme name + `showEffects` so their rims animate live when effects are on.
@MainActor @ViewBuilder
func appMockView(_ a: KitFamily, p: ResolvedPalette, themeName: String, showEffects: Bool) -> some View {
    switch a {
    case .facet:  MockTree(p: p)
    case .wand:   MockWandLauncher(p: p)
    case .perch:  MockPerchOverlay(p: p, themeName: themeName, showEffects: showEffects)
    case .halo:   MockHalo(p: p, themeName: themeName, showEffects: showEffects)
    case .glance: MockGlancePopover(p: p)
    default:      EmptyView()
    }
}

// MARK: - Foundation / App page

/// The detail pane for a `.foundation` or `.app` sidebar selection. Resolves the
/// top bar's chosen theme (`"all"` ⇒ dracula, a concrete palette must be picked
/// for a single page) and renders:
///   • Palette  → a header + the 36-chip theme-swatch wall + the live foundations
///   • Icons    → the `MockIcons` grid
///   • an app   → the app caption + that app's signature chrome mock
/// (`.widget` never routes here — Gallery sends those to `WidgetPage` — so it
/// falls to `default`.)
struct FoundationAppPage: View {
    let item: SidebarItem        // .foundation or .app only
    let themeName: String
    let showEffects: Bool
    let onPickTheme: (String) -> Void   // a chip click switches the shell's theme

    private var isAll: Bool { themeName == "all" }

    var body: some View {
        let name = themeName == "all" ? "dracula" : themeName
        let spec = paletteFor(name)
        let p = resolve(spec)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch item {
                case .foundation(.palette):
                    Text("Theme palette preview")
                        .font(sysFont(12, weight: .semibold))
                        .foregroundColor(Color(nsColor: p.foreground))
                    allThemeHint(p, "All → \(name) tokens · click a chip to switch theme")
                    themeChipGrid   // 36-chip wall — now the INTERACTIVE theme switcher
                    paletteFoundations(spec: spec, p: p, name: name,
                                       scale: 1.0, showEffects: showEffects)
                case .foundation(.icons):
                    allThemeHint(p, "All → showing \(name)")
                    MockIcons(p: p)
                case .app(let a):
                    appCaption(a, p: p)
                    appMockView(a, p: p, themeName: name, showEffects: showEffects)
                default:
                    EmptyView()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Every catalog theme tinted in its OWN colours — the retired shell header's
    /// swatch wall, now the palette page's INTERACTIVE theme switcher: clicking a
    /// chip switches the shell's theme, and the current theme's chip is ringed.
    private var themeChipGrid: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Gallery.switchable, id: \.self) { n in
                ThemeChip(name: n, label: n, selected: n == themeName) { onPickTheme(n) }
            }
        }
    }

    /// Shown only under "All": foundations resolve to one representative theme
    /// (they can't tile), so name it and point at the chips as the way to pick one.
    @ViewBuilder private func allThemeHint(_ p: ResolvedPalette, _ message: String) -> some View {
        if isAll {
            Text(message)
                .font(sysFont(9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
        }
    }
}
