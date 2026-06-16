// still — the gallery: one card per theme, each rendered IN its own
// resolved palette so the colors read as they will in a real app.

import SwiftUI
import Palette
import PaletteKit
import Effects

// MARK: - Gallery

struct Gallery: View {
    let config: StillConfig

    /// Catalog names the header switcher offers — the `random` meta-name is
    /// a roll action, not a persistent selection, so it's excluded.
    private static let switchable = canonicalThemeNames.filter { $0 != "random" }

    /// Live selection: `"all"` (the full gallery) or one canonical theme.
    /// Seeded from the config so `theme = "dracula"` still opens on dracula;
    /// the header chips then drive it at runtime — no relaunch, no file edit.
    @State private var selected: String

    init(config: StillConfig) {
        self.config = config
        let t = config.theme
        _selected = State(initialValue:
            (t == "all" || Gallery.switchable.contains(t)) ? t : "all")
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
                        ThemeCard(name: name, scale: config.fontScale,
                                  showEffects: config.showEffects)
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: header — title + the theme-switch chip row

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("still — \(selected == "all" ? "\(Gallery.switchable.count) themes" : selected)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                    .font(.system(size: 11, weight: selected ? .bold : .medium,
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
    let scale: CGFloat
    let showEffects: Bool

    var body: some View {
        let spec = paletteFor(name)
        let p = resolve(spec)
        let cardBG = p.background.map { Color(nsColor: $0) }
            ?? Color(nsColor: .underPageBackgroundColor)
        let fg = Color(nsColor: p.foreground)

        VStack(alignment: .leading, spacing: 14) {
            // Header: name + font/mode badges
            HStack(spacing: 8) {
                Text(name)
                    .font(themeFont(spec.font, size: 16 * scale).weight(.bold))
                    .foregroundColor(fg)
                Text(spec.font.label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                if spec.background == nil {
                    Text("VIBRANCY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.muted))
                }
                Spacer()
            }

            SwatchRow(p: p)

            // Font specimen
            Text("AaBbCcGg 0123 — The quick brown fox jumps")
                .font(themeFont(spec.font, size: 15 * scale))
                .foregroundColor(fg)

            if showEffects, let fx = borderEffectFor(name) {
                EffectStrip(fx: fx)
            }

            // Mock chrome — drawn by still, never imported from an app.
            HStack(alignment: .top, spacing: 12) {
                MockTree(p: p)
                MockPill(p: p)
                MockTome(p: p)
                MockMarkdown(p: p)
            }
        }
        .padding(16)
        .background(cardBG)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(nsColor: p.border), lineWidth: 1))
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
            .frame(width: 50, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: ink).opacity(0.30), lineWidth: 1))

            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(Color(nsColor: ink)).opacity(0.9)
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 52)
            Text(color.map(hexString) ?? "nil")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Color(nsColor: muted))
                .lineLimit(1).minimumScaleFactor(0.6).frame(width: 52)
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

// MARK: - Effect flash palette (the dynamic atom, shown statically)

struct EffectStrip: View {
    let fx: EffectSpec

    var body: some View {
        HStack(spacing: 6) {
            Text(fx.cycles ? "effect · spectrum" : "effect · flash")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Color(nsColor: NSColor(hex: fx.steady)))
            ForEach(Array(fx.flash.enumerated()), id: \.offset) { _, hex in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: NSColor(hex: hex)))
                    .frame(width: 22, height: 12)
            }
        }
    }
}

// MARK: - Helpers

/// SwiftUI font for a `FontKind` (still-local; mirrors PaletteKit's uiFont
/// without touching the global `pal`). `.menu` ≈ system for a specimen.
func themeFont(_ kind: FontKind, size: CGFloat) -> Font {
    switch kind {
    case .mono:    return .system(size: size, design: .monospaced)
    case .rounded: return .system(size: size, design: .rounded)
    case .menu, .system: return .system(size: size)
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
