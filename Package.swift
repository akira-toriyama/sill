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
//     for the static base it animates.
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
        .library(name: "Toml", targets: ["Toml"]),
    ],
    targets: [
        // Pure, Sendable, AppKit-free. The shared base.
        .target(name: "Palette"),

        // Pure, Sendable, AppKit-free TOML subset parser — the family's
        // ONE hand-rolled parser (replaces four in-tree copies). A second
        // pure atom alongside Palette: links zero AppKit and zero Palette.
        .target(name: "Toml"),

        // AppKit resolver. The ONLY target that `import AppKit`.
        .target(name: "PaletteKit", dependencies: ["Palette"]),

        // Dynamic atom: Sendable EffectSpec + (macOS) AppKit animator.
        .target(name: "Effects", dependencies: ["Palette"]),

        // `still` — the theme PREVIEW app. The one place in sill with a
        // config.toml. Renders every catalog theme (all roles + font +
        // its OWN mock chrome specimens — never imports an app's View, so
        // no drift debt). The visual verification bench for the catalog.
        .executableTarget(name: "still", dependencies: ["Palette", "PaletteKit", "Effects"]),

        .testTarget(name: "PaletteTests", dependencies: ["Palette"]),
        .testTarget(name: "PaletteKitTests", dependencies: ["PaletteKit"]),
        .testTarget(name: "EffectsTests", dependencies: ["Effects", "Palette"]),
        .testTarget(name: "TomlTests", dependencies: ["Toml"],
                    resources: [.copy("Fixtures")]),
    ]
)
