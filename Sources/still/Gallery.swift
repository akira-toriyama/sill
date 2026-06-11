// still — the gallery: one card per theme, each rendered IN its own
// resolved palette so the colors read as they will in a real app.

import SwiftUI
import Palette
import PaletteKit
import Effects

// MARK: - Gallery

struct Gallery: View {
    let config: StillConfig

    private var names: [String] {
        if config.theme == "all" {
            return canonicalThemeNames.filter { $0 != "random" }
        }
        // A single named theme (paletteFor falls back to terminal on typo).
        return [config.theme]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Text("still — \(names.count == 1 ? names[0] : "\(names.count) themes")")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(names, id: \.self) { name in
                    ThemeCard(name: name, scale: config.fontScale,
                              showEffects: config.showEffects)
                }
            }
            .padding(18)
        }
        .frame(minWidth: 920, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
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
                MockTree(p: p, scale: scale)
                MockPill(p: p, scale: scale)
                MockTome(p: p, scale: scale)
                MockMarkdown(p: p, scale: scale)
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
