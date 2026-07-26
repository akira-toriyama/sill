// PaletteKit — SwiftUI theme propagation.
//
// WHY THIS EXISTS
// ---------------
// Until now sill's SwiftUI front had no ambient theme: every widget took
// `palette: ResolvedPalette` as an explicit init argument, 61 declarations
// across 25 files, and exactly ONE `@Environment` appeared in all of Sources
// (a reduce-motion read). That is not a decision anyone recorded — the design
// docs never mention Environment at all — it is what happens when a library's
// only consumer is atypical.
//
// prism, the visual bench, renders EVERY catalog theme side by side, so
// prop-drilling is genuinely right for it. A real app has ONE current theme and
// a deep view tree, and prop-drilling is genuinely wrong for that: every
// intermediate view has to accept and forward a palette it does not use. Every
// mature design system propagates by context for exactly this reason (MUI's
// ThemeProvider, Radix's Theme).
//
// THREE TIERS, highest wins — the same shape as MUI's prop > ThemeProvider >
// default theme:
//
//   1. an explicit `palette:` argument   — prism, and any per-surface override
//   2. `.sillTheme(_:)` on an ancestor   — the app's current theme
//   3. the process-wide `pal`            — so a widget always resolves
//
// Tier 1 is kept, not deprecated: overriding one subtree's theme is a real
// need (prism does it 61 times, and an app previewing a theme picker will too).
// Making the argument OPTIONAL rather than removing it is what lets this be
// additive — every existing call site keeps compiling and keeps its meaning.
//
// The environment value is `ResolvedPalette?` rather than a non-optional with a
// default. That is forced, not stylistic: `ResolvedPalette` is `@MainActor`
// (NSColor is not Sendable), and a non-isolated `EnvironmentKey.defaultValue`
// static cannot produce one under Swift 6 strict concurrency. `nil` also
// carries the meaning "no ancestor set a theme", which tier 3 needs.

#if canImport(SwiftUI)
import SwiftUI
import Palette

private struct SillPaletteKey: EnvironmentKey {
    static let defaultValue: ResolvedPalette? = nil
}

public extension EnvironmentValues {
    /// The ambient sill theme, or `nil` when no ancestor set one.
    ///
    /// Widgets should not read this directly — read the resolved three-tier
    /// answer instead, which respects an explicit override:
    ///
    /// ```swift
    /// @Environment(\.sillPalette) private var ambientPalette
    /// private let explicitPalette: ResolvedPalette?
    /// private var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    /// ```
    var sillPalette: ResolvedPalette? {
        get { self[SillPaletteKey.self] }
        set { self[SillPaletteKey.self] = newValue }
    }
}

public extension View {
    /// Set the ambient sill theme for this view and everything below it.
    ///
    /// Nests: an inner `.sillTheme(_:)` overrides an outer one for its own
    /// subtree, so a theme picker can preview a candidate theme inside an app
    /// that is otherwise themed differently.
    func sillTheme(_ palette: ResolvedPalette) -> some View {
        environment(\.sillPalette, palette)
    }

    /// Set the ambient theme from a catalog `Theme`.
    ///
    /// Convenience for the common app case. Prefer the `ResolvedPalette`
    /// overload when you already hold a resolved palette, or when the theme
    /// needs `resolve`'s `bgOverride` / vibrancy arguments — this one resolves
    /// on every call, which is wasteful in a body that re-evaluates often.
    func sillTheme(_ theme: Theme) -> some View {
        environment(\.sillPalette, resolve(theme.spec))
    }
}
#endif
