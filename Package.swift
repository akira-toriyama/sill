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
// macOS 13+ (facet's floor). Linkage is AUTOMATIC (no `type:`) so the
// consuming app picks static vs dynamic.

import PackageDescription

let package = Package(
    name: "sill",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Palette", targets: ["Palette"]),
        .library(name: "PaletteKit", targets: ["PaletteKit"]),
        .library(name: "Effects", targets: ["Effects"]),
        .library(name: "Motion", targets: ["Motion"]),
        .library(name: "ConfigSchema", targets: ["ConfigSchema"]),
        .library(name: "CLIKit", targets: ["CLIKit"]),
        .library(name: "Gesture", targets: ["Gesture"]),
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
    ],
    dependencies: [
        // The family's ONE TOML implementation now lives in its own repo
        // (swift-toml-edit / Sill-1): a lossless, round-trippable `Toml.Annotated`
        // DOM that ALSO ships the lossy `parse` / `parseFlat` projection this
        // package used to vendor as `Sources/Toml`. The module name stays `Toml`,
        // so every consumer's `import Toml` survives untouched; ConfigSchema
        // decodes over that projection. See atelier docs/swift-toml-edit.md.
        .package(url: "https://github.com/akira-toriyama/swift-toml-edit.git",
                 .upToNextMinor(from: "1.0.0")),

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

        // Dynamic atom: Sendable EffectSpec + (macOS) AppKit animator.
        // Declared before PaletteKit, which now depends on it.
        .target(name: "Effects", dependencies: ["Palette"]),

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
                dependencies: ["PaletteKit", "Palette",
                               .product(name: "SwiftDraw", package: "SwiftDraw")],
                exclude: ["Resources/README.md"],   // doc, not a bundled resource
                resources: [.copy("Resources/Phosphor"),
                            .copy("Resources/SimpleIcons")]),

        // Pure, Sendable, AppKit-free. One declarative `Spec<Root>` that
        // BOTH decodes a `config.toml` (over `Toml`) and emits its JSON
        // Schema for taplo — so the two can never drift. A pure atom
        // alongside Palette (zero AppKit, zero Palette); its `Toml`
        // dependency is now the external swift-toml-edit package.
        .target(name: "ConfigSchema",
                dependencies: [.product(name: "Toml", package: "swift-toml-edit")]),

        // `prism` — the theme PREVIEW app. The one place in sill with a
        // config.toml. Renders every catalog theme (all roles + font +
        // its OWN mock chrome specimens — never imports an app's View, so
        // no drift debt). The visual verification bench for the catalog.
        .executableTarget(name: "prism", dependencies: ["Palette", "PaletteKit", "Effects", "Motion", "ThemeKit"]),

        .testTarget(name: "PaletteTests", dependencies: ["Palette"]),
        .testTarget(name: "PaletteKitTests", dependencies: ["PaletteKit", "Effects"]),
        .testTarget(name: "ThemeKitTests", dependencies: ["ThemeKit", "PaletteKit", "Palette", "Effects"]),
        .testTarget(name: "EffectsTests", dependencies: ["Effects", "Palette"]),
        .testTarget(name: "MotionTests", dependencies: ["Motion"]),
        .testTarget(name: "ConfigSchemaTests",
                    dependencies: ["ConfigSchema",
                                   .product(name: "Toml", package: "swift-toml-edit")]),
        .testTarget(name: "CLIKitTests", dependencies: ["CLIKit"]),
        .testTarget(name: "GestureTests", dependencies: ["Gesture"]),
    ]
)
