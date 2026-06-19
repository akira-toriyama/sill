// prism — the SVG ICON bench (sill v1.8.0). Proves the new icon foundation LIVE
// across every theme: the `phosphorImage` / `simpleIconImage` loaders (Bundle.module
// → SwiftDraw rasterize), the six Phosphor weights, the Simple-Icons brand logos,
// and the new pre-resolved-image API on the real widgets (`ThemedButton.leadingImage`,
// `ThemedFAB.leadingImage`, `ThemedToolBar.ButtonItem.image`).
//
// The glyph gallery tints via SwiftUI's template rendering — the same role colour a
// widget would tint to — so a static screenshot shows each icon as it reads in-app.
// The widget strip below exercises the ACTUAL device-pixel tint path inside the
// shared widgets.

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit

// MARK: - Toolbar bridge (local — takes ThemedToolBar.Item directly, with `image` items)

private struct IconBarView: NSViewRepresentable {
    let palette: ResolvedPalette
    let items: [ThemedToolBar.Item]
    var surface: ThemedToolBar.Surface = .surface
    var variant: ThemedToolBar.Variant = .dense

    func makeNSView(context: Context) -> ThemedToolBar {
        let b = ThemedToolBar(palette: palette); apply(to: b); return b
    }
    func updateNSView(_ b: ThemedToolBar, context: Context) { apply(to: b) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThemedToolBar,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 420, height: nsView.intrinsicContentSize.height)
    }
    private func apply(to b: ThemedToolBar) {
        b.palette = palette
        b.surface = surface
        b.variant = variant
        b.items = items          // set last — rebuilds the composed buttons
    }
}

// MARK: - Showcase

struct MockIcons: View {
    let p: ResolvedPalette

    /// Glyphs shown across the full weight ramp.
    private static let ramp = ["heart", "star", "sun"]
    private static let weights: [PhosphorWeight] = [.thin, .light, .regular, .bold, .fill, .duotone]
    /// The vendored functional set (a slice of the eventual SF→Phosphor map, #2).
    private static let functional = [
        "magnifying-glass", "plus", "minus", "gear", "gear-six", "folder", "tag", "trash",
        "bell", "palette", "list", "list-bullets", "caret-down", "caret-right", "caret-up",
        "caret-left", "check", "x", "x-circle", "note-pencil", "export", "dots-three",
        "sliders-horizontal", "arrow-clockwise", "funnel", "info",
    ]
    private static let logos = ["github", "swift", "apple", "notion", "firefox"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ThemeKit · SVG icons — Phosphor (MIT) + Simple Icons (CC0), rasterized by SwiftDraw, tinted per theme")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            section("Phosphor — six weights (tinted primary)") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.ramp, id: \.self) { name in
                        HStack(spacing: 14) {
                            Text(name)
                                .font(sysFont(8.5, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(nsColor: p.muted))
                                .frame(width: 38 * uiScale, alignment: .leading)
                            ForEach(Self.weights, id: \.self) { w in
                                labeled(w.rawValue) {
                                    glyph(phosphorImage(name, pt: 26, weight: w),
                                          color: p.primary, side: 24)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            section("Phosphor — regular set (tinted foreground)") {
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    ForEach(Self.functional, id: \.self) { name in
                        labeled(name) {
                            glyph(phosphorImage(name, pt: 24), color: p.foreground, side: 22)
                        }
                    }
                }
            }

            section("Simple Icons — brand / app logos") {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Self.logos, id: \.self) { name in
                        labeled(name) {
                            glyph(simpleIconImage(name, pt: 24), color: p.foreground, side: 24)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            section("In the widgets — the new SVG image API (leadingImage · ButtonItem.image)") {
                VStack(alignment: .leading, spacing: 12) {
                    // The bar is a REAL widget at real points (48pt dense) — let it
                    // self-size via sizeThatFits rather than a uiScale-inflated frame
                    // that would leave an empty band below it.
                    IconBarView(palette: p, items: barItems)
                        .frame(height: 48)

                    HStack(spacing: 12) {
                        ThemedButtonView(palette: p, variant: .contained, title: "Export",
                                         leadingImage: phosphorImage("export", pt: 20))
                        ThemedButtonView(palette: p, variant: .outlined, title: "Edit",
                                         leadingImage: phosphorImage("note-pencil", pt: 20))
                        ThemedButtonView(palette: p, variant: .text, title: "More",
                                         trailingImage: phosphorImage("caret-down", pt: 20))
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 16) {
                        ThemedFABView(palette: p, variant: .circular, size: .medium, role: .primary,
                                      image: phosphorImage("plus", pt: 24, weight: .bold))
                            .frame(width: 48, height: 48)
                        ThemedFABView(palette: p, variant: .circular, size: .medium, role: .secondary,
                                      image: phosphorImage("heart", pt: 24, weight: .fill))
                            .frame(width: 48, height: 48)
                        ThemedFABView(palette: p, variant: .extended, size: .medium, role: .primary,
                                      image: phosphorImage("note-pencil", pt: 22), label: "Compose")
                            .fixedSize()
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
    }

    private var barItems: [ThemedToolBar.Item] {
        [
            .button(.init(image: phosphorImage("list", pt: 20), tooltip: "Menu")),
            .label("prism"),
            .flexibleSpace,
            .button(.init(image: phosphorImage("magnifying-glass", pt: 20), tooltip: "Search")),
            .button(.init(image: phosphorImage("gear", pt: 20), tooltip: "Settings")),
            .divider,
            .button(.init(image: simpleIconImage("github", pt: 18), tooltip: "GitHub")),
            .button(.init(title: "New", image: phosphorImage("plus", pt: 18, weight: .bold),
                          variant: .contained)),
        ]
    }

    // MARK: building blocks

    /// One tinted glyph. Template-renders the `.isTemplate` SVG mask so SwiftUI
    /// fills it with the role colour — the same treatment a widget applies.
    @ViewBuilder
    private func glyph(_ image: NSImage?, color: NSColor, side: CGFloat) -> some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: side * uiScale, height: side * uiScale)
                .foregroundStyle(Color(nsColor: color))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.red, lineWidth: 1)
                .frame(width: side * uiScale, height: side * uiScale)
        }
    }

    @ViewBuilder
    private func labeled<V: View>(_ tag: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 3) {
            content()
            Text(tag)
                .font(sysFont(6.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 46 * uiScale)
        }
    }

    @ViewBuilder
    private func section<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(sysFont(8, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            content()
        }
    }
}
