// swift-tools-version:6.0
// sill — shared theming library for the swift app family
// (facet / wand / perch / halo / glance).
//
// ONE repo, MANY modules, ONE version — the swift-collections layout:
//   * each public module is BOTH a target (Sources/<Name>/) AND its
//     own library product, all shipped under ONE git tag.
//   * the pure / AppKit split is enforced by the DEPENDENCY GRAPH, not
//     a SwiftPM flag: PaletteKit depends on Palette and imports AppKit;
//     Palette imports nothing platform-specific. A consumer that adds
//     only the `Palette` product transitively links ZERO AppKit.
//   * Effects is the shared DYNAMIC atom (Sendable spec + AppKit
//     animator behind `#if canImport(AppKit)`), depending on Palette
//     for the static base it animates. PaletteKit, in turn, depends on
//     Effects (one acyclic edge) for the `ResolvedPalette.animated(…)`
//     helper that grafts an animated accent onto a resolved palette;
//     Effects never depends back on PaletteKit (halo links it alone).
//
// No `Sill` prefix — bare names are idiomatic (swift-algorithms ships
// `Algorithms`; swift-collections ships `OrderedCollections`). The
// pure module is named `Palette` and its primary public type is
// `ThemeSpec` (NOT `Palette`), so there is no module/type collision
// and no umbrella-typealias dance is needed.
//
// macOS 26+ (t-tbar floor bump; consumers adopt when they next bump their
// sill pin). Spelled ".macOS("26.0")" — the string form is the only one both
// toolchains accept: CLT's PackageDescription 6.1 lacks the `.v26` case, and
// raising swift-tools-version to 6.2 would break CLT manifest parsing.
// Linkage is AUTOMATIC (no `type:`) so the consuming app picks static vs
// dynamic.

import PackageDescription

let package = Package(
    name: "sill",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Palette", targets: ["Palette"]),
        .library(name: "PaletteKit", targets: ["PaletteKit"]),
        .library(name: "Effects", targets: ["Effects"]),
        .library(name: "Motion", targets: ["Motion"]),
        .library(name: "ConfigSchema", targets: ["ConfigSchema"]),
        .library(name: "CLIKit", targets: ["CLIKit"]),
        .library(name: "Gesture", targets: ["Gesture"]),
        .library(name: "ListCore", targets: ["ListCore"]),
        .library(name: "GridCore", targets: ["GridCore"]),
        .library(name: "PixelArt", targets: ["PixelArt"]),
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
        .library(name: "ThemeKitUI", targets: ["ThemeKitUI"]),
        .library(name: "MarkdownKitUI", targets: ["MarkdownKitUI"]),
    ],
    dependencies: [
        // The family's ONE TOML implementation now lives in its own repo
        // (swift-toml-edit / Sill-1): a lossless, round-trippable `Toml.Annotated`
        // DOM that ALSO ships the lossy `parse` / `parseFlat` projection this
        // package used to vendor as `Sources/Toml`. The module name stays `Toml`,
        // so every consumer's `import Toml` survives untouched; ConfigSchema
        // decodes over that projection. See atelier docs/swift-toml-edit.md.
        // 2.0.0: `Toml.Value.arrayOfTables` now holds `[Toml.Row]` (row +
        // `SourceSpan`) and the `__line__` key is gone — additive for sill
        // (ConfigSchema decodes flat `parseFlat` tables, not `.arrayOfTables`),
        // so the floor moves to 2.x and the family unifies on it (chord#148).
        .package(url: "https://github.com/akira-toriyama/swift-toml-edit.git",
                 .upToNextMajor(from: "2.0.0")),

        // SwiftDraw (Zlib · zero deps · pure-Swift CoreGraphics SVG renderer,
        // macOS 10.15+) — ThemeKit's SVG rasterizer. The ONLY path that
        // resolves AND compiles on a CommandLineTools-only machine: ✗ NSImage's
        // direct SVG load is the private `_NSSVGImageRep` (nil on macOS 13);
        // ✗ asset catalogs need Xcode/actool. A ThemeKit-ONLY dependency — the
        // pure modules (Palette/…) never link it. See docs/ROADMAP.md item 1.
        //
        // PINNED < 0.25.0: 0.25.0 added `SVGView.swift`, a SwiftUI view whose
        // `#Preview` macro needs the `PreviewsMacros` plugin that ships ONLY with
        // full Xcode — it fails to compile under CommandLineTools (the local gate).
        // 0.24.0 predates SVGView and gives the same `SVG(fileURL:)` / `rasterize`
        // / `NSImage(_:)` API. Bump only if a CLT-buildable newer release lands.
        .package(url: "https://github.com/swhitty/SwiftDraw.git",
                 .upToNextMinor(from: "0.24.0")),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        // Pure, Sendable, AppKit-free. The shared base.
        .target(name: "Palette"),

        // Pure, Sendable, AppKit-free CLI argv tokenizer — the family's
        // ONE arity-driven parser for the yabai-style grammar (Phase 3),
        // replacing four hand-rolled argv loops. A pure atom alongside
        // Palette: zero AppKit, zero Palette. Mechanism only — the
        // app supplies the verb arity table; CLIKit owns no vocabulary.
        .target(name: "CLIKit"),

        // Pure, Sendable, AppKit-free GESTURE RECOGNITION — wand's mouse-
        // stroke recogniser, generalised. Turns timestamped points into a
        // coalesced 4-way direction string (`"DL"`); the app owns the action
        // table, the clock, and the input plumbing. A pure atom alongside
        // Palette / CLIKit: zero AppKit, zero Palette (only a `CGPoint` /
        // `TimeInterval` `Sample` convenience behind a CoreGraphics gate).
        // Mechanism only — `Gesture` owns no vocabulary and no timing.
        .target(name: "Gesture"),

        // Pure, Sendable, AppKit-free HEADLESS CORE for the stateful widgets —
        // selection resolution, roving-highlight math, ComboBox filter/reconcile,
        // Menu keycode→intent. ThemedList/ComboBox/Menu delegate to it as
        // byte-identical thin wrappers; #16/#17 SwiftUI will share the same core.
        // A pure leaf alongside Palette/Gesture/Motion: zero AppKit, zero Palette.
        .target(name: "ListCore"),

        // Pure, Sendable, AppKit-free GRID math — adaptive column count,
        // aspect-fit cell sizing, 2D roving-cursor navigation (ragged last row),
        // and selection reconciliation. The headless core behind ThemeKitUI's
        // native `ThemedGridView` (#17e); a pure leaf alongside Palette/ListCore:
        // zero AppKit, zero Palette (only CGSize/CGFloat behind a CoreGraphics
        // gate). The future `GridDnD.swift` (macOS-26 milestone) lands here.
        .target(name: "GridCore"),

        // Pure, Sendable, AppKit-free PIXEL-SPRITE atom — wand's chomp
        // (Pac-Man-style) arcade decals reinterpreted as resolution-independent
        // integer pixel grids: a `PixelSprite` (rows + palette), the
        // circle-minus-mouth `pacManCells` wedge, a stable `positionHash01`
        // jitter, and a `ScaleTier` size knob. A pure atom alongside Palette /
        // Gesture / CLIKit: zero AppKit, zero Palette (sprite-internal detail
        // colours are INTRINSIC, baked on the Effects draw side). atan2 comes
        // from Foundation. Mechanism only — no theming, no clock.
        .target(name: "PixelArt"),

        // Dynamic atom: Sendable EffectSpec + (macOS) AppKit animator.
        // Declared before PaletteKit, which now depends on it. Depends on
        // Motion since #12 Ph2: the pixel line-pets (chomp mouth-flap / ghost
        // waddle) step their sprites with `Motion.frameStep`. Acyclic — Motion
        // is a pure leaf (it depends on nothing); halo, which links Effects
        // alone, just transitively gains that zero-AppKit math atom.
        .target(name: "Effects", dependencies: ["Palette", "PixelArt", "Motion"]),

        // Pure, Sendable, AppKit-free ONE-SHOT animation math — the
        // `ThemedTransition` namespace (named Duration/Easing tokens, a
        // `Tween` value, `progress`/`lerp`/`spring`/`dampedSine`). The
        // counterpart to Effects (which owns CYCLIC color motion); this owns
        // TRANSIENT play-once motion. A pure atom alongside Palette/CLIKit:
        // zero AppKit (only `CGRect` lerp overloads behind a CoreGraphics
        // gate), zero Palette — the math is theme-independent.
        .target(name: "Motion"),

        // AppKit resolver. Depends on Effects for the `ResolvedPalette.
        // animated(forTheme:at:)` live-accent helper (composes an
        // `Effects.AnimatedFrame` onto a resolved palette).
        .target(name: "PaletteKit", dependencies: ["Palette", "Effects"]),

        // AppKit shared WIDGET KIT — MUI-style themed UI parts the family
        // draws by hand today (facet's tree filter / tag-rename fields, popup
        // menus, …). PaletteKit resolves the theme; ThemeKit draws in it.
        // `ThemedTextField` (the first widget) is a rounded/outlined (+ filled
        // / standard) text field: floating label, leading/trailing SF
        // adornments, focus-accent transition, helper/error, IME-aware. Themed
        // by assigning `palette`. @MainActor / AppKit.
        .target(name: "ThemeKit",
                dependencies: ["PaletteKit", "Palette", "Motion", "ListCore",
                               .product(name: "SwiftDraw", package: "SwiftDraw")],
                exclude: ["Resources/README.md"],   // doc, not a bundled resource
                resources: [.copy("Resources/Phosphor"),
                            .copy("Resources/SimpleIcons")]),

        // SwiftUI bridge layer atop ThemeKit — the family's `NSViewRepresentable`
        // wrappers (`ThemedButtonView`, `ThemedFieldView`, …) that host the REAL
        // AppKit widgets inside SwiftUI, so an app's *View* layer can drive sill
        // parts from an `NSHostingView` shell. The FIRST module in sill to import
        // SwiftUI — SwiftUI compiles on CommandLineTools; the Xcode-only hazard is
        // the `#Preview` macro/plugin, which these bridges DELIBERATELY avoid (a
        // static `previewFrozen`/`preview…` field on the widget gives deterministic
        // capture instead, same reason SwiftDraw is pinned < 0.25). prism is its
        // FIRST consumer (drops its in-tree bridges and `import ThemeKitUI` — no
        // drift). @MainActor / AppKit + SwiftUI; sits ABOVE ThemeKit and MUST
        // NEVER be a dependency of a pure `*Core` (a consumer linking only
        // `Palette` still links zero AppKit AND zero SwiftUI). Effects is declared
        // directly: `AnimatedBorderView` names `EffectSpec` in its own surface, and
        // ThemeKit only reaches Effects transitively (never re-exports it).
        // `Motion` + `PixelArt` are declared for the #17a effect bridges
        // (Particle/InkSplatter/PixelSprite/LinePets/PathPet/ChompCorridor): they
        // name `ThemedTransition.frameStep` (Motion) and `PixelSprite`/`ScaleTier`/
        // `pixelSize(cell:)` (PixelArt) directly (Trail geometry + the canonical
        // sprites/blitters already arrive via Effects).
        .target(name: "ThemeKitUI",
                dependencies: ["ThemeKit", "PaletteKit", "Palette", "Effects", "Motion", "PixelArt", "GridCore"]),

        // Pure, Sendable, AppKit-free. One declarative `Spec<Root>` that
        // BOTH decodes a `config.toml` (over `Toml`) and emits its JSON
        // Schema for taplo — so the two can never drift. A pure atom
        // alongside Palette (zero AppKit, zero Palette); its `Toml`
        // dependency is now the external swift-toml-edit package.
        .target(name: "ConfigSchema",
                dependencies: [.product(name: "Toml", package: "swift-toml-edit")]),

        // MarkdownKitUI now renders via an NSTextView (floor-3) renderer that parses
        // swift-markdown directly — the old pure `MarkdownKit` (MarkdownBlock model)
        // had no consumer left and was retired (#17f re-architecture).
        .target(
            name: "MarkdownKitUI",
            dependencies: ["PaletteKit", "Palette", "ThemeKit",
                           .product(name: "Markdown", package: "swift-markdown")]),

        // `prism` — the theme PREVIEW app. The one place in sill with a
        // config.toml. Renders every catalog theme (all roles + font +
        // its OWN mock chrome specimens — never imports an app's View, so
        // no drift debt). The visual verification bench for the catalog.
        .executableTarget(name: "prism", dependencies: ["Palette", "PaletteKit", "Effects", "Motion", "ThemeKit", "ThemeKitUI", "PixelArt", "MarkdownKitUI"]),

        .testTarget(name: "PaletteTests", dependencies: ["Palette"]),
        .testTarget(name: "PaletteKitTests", dependencies: ["PaletteKit", "Effects"]),
        .testTarget(name: "ThemeKitTests", dependencies: ["ThemeKit", "PaletteKit", "Palette", "Effects"]),
        .testTarget(name: "ThemeKitUITests", dependencies: ["ThemeKitUI", "PaletteKit", "Palette"]),
        .testTarget(name: "EffectsTests", dependencies: ["Effects", "Palette", "PixelArt"]),
        .testTarget(name: "MotionTests", dependencies: ["Motion"]),
        .testTarget(name: "ConfigSchemaTests",
                    dependencies: ["ConfigSchema",
                                   .product(name: "Toml", package: "swift-toml-edit")]),
        .testTarget(name: "CLIKitTests", dependencies: ["CLIKit"]),
        .testTarget(name: "GestureTests", dependencies: ["Gesture"]),
        .testTarget(name: "ListCoreTests", dependencies: ["ListCore"]),
        .testTarget(name: "GridCoreTests", dependencies: ["GridCore"]),
        .testTarget(name: "PixelArtTests", dependencies: ["PixelArt"]),
    ]
)
