// prism — mock chrome specimens. Each is a tiny, deliberately-fake
// rendition of an app's signature surface, drawn HERE in the resolved
// palette. prism imports NO app View code — these mirror the apps by
// eye, so the preview can't couple the library to any app.

import AppKit
import SwiftUI
import PaletteKit
import ThemeKit

/// A Phosphor glyph as a tintable SwiftUI `Image` (template ⇒ adopts the
/// ancestor `.foregroundColor`). The mock specimens draw their accents this way
/// now that the family is full-SVG (no more `Image(systemName:)`).
@MainActor func phosphorIcon(_ name: String, _ pt: CGFloat,
                             weight: PhosphorWeight = .regular) -> some View {
    Image(nsImage: phosphorImage(name, pt: pt, weight: weight) ?? NSImage())
        .resizable()
        .renderingMode(.template)
        .frame(width: pt, height: pt)
}

/// The real macOS icon for the first installed bundle id in `ids`, or nil
/// (the caller then falls back to a theme-tinted tile). Mirrors the real
/// facet tree, which paints each row's ACTUAL app icon via
/// `AppIcons.icon(forPID:)` — here resolved by bundle id since the mock
/// has no live windows / pids.
@MainActor func appIcon(_ ids: [String]) -> NSImage? {
    let ws = NSWorkspace.shared
    for id in ids {
        if let url = ws.urlForApplication(withBundleIdentifier: id) {
            return ws.icon(forFile: url.path)
        }
    }
    return nil
}

/// Lift `p.background` toward its contrasting end — white on a dark theme,
/// black on a light one — by `fraction`. A neutral, hue-free elevation used
/// to stack surfaces off the card: card (0) < panel < field. The `system`
/// (vibrancy, nil-background) theme has no fixed base, so fall back to the
/// standard control surface.
@MainActor func elevate(_ p: ResolvedPalette, by fraction: Double) -> NSColor {
    guard let bg = p.background?.usingColorSpace(.sRGB) else {
        return .controlBackgroundColor
    }
    let lum = 0.299 * bg.redComponent + 0.587 * bg.greenComponent
        + 0.114 * bg.blueComponent
    let towards: NSColor = lum > 0.55 ? .black : .white
    return bg.blended(withFraction: fraction, of: towards) ?? bg
}

/// The mock panel border — a clearly-visible outline elevated well off the
/// card. A panel is filled in the SAME theme `background` as the card (so it
/// matches the `background` swatch), so the faint theme `border` vanished
/// where panel met card; this definite outline is what separates the two.
@MainActor func panelStroke(_ p: ResolvedPalette) -> NSColor { elevate(p, by: 0.24) }

// MARK: - Shared container

struct SpecimenBox<Content: View>: View {
    let title: String
    let p: ResolvedPalette
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
            content()
        }
        .padding(10)
        .frame(width: 246 * uiScale, alignment: .leading)
        // The panel fill IS the theme `background` (same as the `background`
        // swatch + the card), so a clearly-visible `panelStroke` outline — not
        // the faint theme `border` — is what separates the panel from the card.
        .background(p.background.map { Color(nsColor: $0) }
            ?? Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
    }
}

// MARK: - facet tree (panel)

/// A miniature of facet's tree-view PANEL (the `FacetViewTree` sidebar):
/// a pinned "Desktop N" handle band, a search field, then per-workspace
/// sections — each a 2-line caption (WS name + layout mode) over its
/// window rows (app icon · app name · title · status badges). Hardcoded
/// sample data; prism imports no app View, so this mirrors the real
/// `SidebarView+Draw` layout by eye only. Now panel-shaped (was a flat
/// 4-row list): selection = `selection` fill + a 3 px `primary` left bar,
/// a zebra stripe on alternating window rows, and master=crown /
/// float=macwindow / mark-pill / #tag badges — the same vocabulary the
/// real tree paints.
struct MockTree: View {
    let p: ResolvedPalette

    var body: some View {
        SpecimenBox(title: "facet · tree", p: p) {
            VStack(alignment: .leading, spacing: 0) {
                handleBand
                searchBar.padding(.top, 7).padding(.bottom, 5)
                section(ws: "code", mode: "bsp", modeIcon: "squares-four",
                        active: true, first: true) {
                    windowRow(app: "Safari", title: "GitHub — facet",
                              bundleIDs: ["com.apple.Safari"],
                              tile: p.secondary, ordinal: 0,
                              selected: true, master: true)
                    windowRow(app: "Code", title: "Specimens.swift",
                              bundleIDs: ["com.microsoft.VSCode", "com.apple.dt.Xcode"],
                              tile: p.primary, ordinal: 1, mark: "a", tag: "work")
                }
                section(ws: "media", mode: "stack", modeIcon: "stack",
                        active: false, first: false) {
                    windowRow(app: "Terminal", title: "zsh — sill",
                              bundleIDs: ["com.apple.Terminal"],
                              tile: p.secondary, ordinal: 2, float: true)
                    windowRow(app: "Notes", title: "scratch",
                              bundleIDs: ["com.apple.Notes"],
                              tile: p.muted, ordinal: 3, hidden: true)
                }
            }
        }
    }

    // MARK: panel chrome (pinned above the scrolling list)

    private var handleBand: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                GripDots(color: p.muted)
                Text("Desktop 1")
                    .font(sysFont(12, weight: .bold)).kerning(0.5)
                    .foregroundColor(Color(nsColor: p.foreground))
                Spacer(minLength: 0)
            }
            hairline
        }
    }

    private var searchBar: some View {
        // The REAL ThemeKit field (outlined, leading magnifier), themed to
        // this panel — replacing the hand-drawn approximation.
        ThemedFieldView(palette: p, placeholder: "type to filter…",
                        leading: "magnifying-glass", surface: p.background)
            .frame(height: 40)   // ≥ the label-less field's 40pt box, else the top rule clips
    }

    // MARK: workspace section — 2-line header + its window rows

    @ViewBuilder
    private func section<Rows: View>(
        ws: String, mode: String, modeIcon: String, active: Bool, first: Bool,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        let accent = active ? p.primary : p.muted
        VStack(alignment: .leading, spacing: 2) {
            if !first { hairline.padding(.vertical, 8) }
            HStack(alignment: .top, spacing: 7) {
                GripDots(color: accent).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ws)            // line 1: WS name (bold; accent when active)
                        .font(sysFont(12, weight: active ? .bold : .semibold))
                        .kerning(0.6)
                        .foregroundColor(Color(nsColor: accent))
                    HStack(spacing: 4) {   // line 2: layout mode (icon + label)
                        phosphorIcon(modeIcon, 10)
                        Text(mode).font(sysFont(11, weight: active ? .semibold : .medium))
                    }
                    .foregroundColor(Color(nsColor: accent))
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)
            rows()
        }
    }

    // MARK: window row — icon · app · title · status badges

    @ViewBuilder
    private func windowRow(app: String, title: String, bundleIDs: [String],
                           tile: NSColor, ordinal: Int,
                           selected: Bool = false, master: Bool = false,
                           float: Bool = false, hidden: Bool = false,
                           mark: String? = nil, tag: String? = nil) -> some View {
        let ink = selected ? p.primary : p.foreground
        let dim = hidden && !selected
        let hasBadge = master || float || hidden || mark != nil || tag != nil
        // Centre the app icon against the WHOLE row (app · title · optional badge
        // line), not top-aligned with the first line — it read as sitting too high.
        HStack(alignment: .center, spacing: 8) {
            // The REAL macOS app icon (as the live facet tree paints), falling
            // back to a theme-tinted tile when the app isn't installed.
            if let img = appIcon(bundleIDs) {
                Image(nsImage: img).resizable().interpolation(.high)
                    .frame(width: 22 * uiScale, height: 22 * uiScale)
                    .opacity(hidden ? 0.4 : 1)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: tile).opacity(hidden ? 0.4 : 0.9))
                    .frame(width: 22 * uiScale, height: 22 * uiScale)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app)
                    .font(sysFont(12, weight: selected ? .semibold : .regular))
                    .foregroundColor(Color(nsColor: ink).opacity(dim ? 0.45 : 1))
                    .lineLimit(1)
                Text(title)
                    .font(sysFont(11))
                    .foregroundColor(Color(nsColor: p.muted).opacity(dim ? 0.45 : 1))
                    .lineLimit(1)
                if hasBadge {
                    HStack(spacing: 8) {
                        if let mark { markPill(mark) }
                        if let tag { badge("tag", tag, p.secondary) }
                        if master { badge("crown", "master", p.primary) }
                        if float { badge("app-window", "float", p.foreground) }
                        if hidden { badge("eye-slash", "hidden", p.muted) }
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(rowBackground(ordinal: ordinal, selected: selected))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            if selected {       // the 3 px primary bar marking the selected window
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: p.primary))
                    .frame(width: 3).padding(.vertical, 4)
            }
        }
    }

    /// Selection fill, else a faint zebra stripe on every other window row
    /// (`foreground@0.05`), else nothing — mirrors SidebarView+Draw.
    @ViewBuilder
    private func rowBackground(ordinal: Int, selected: Bool) -> some View {
        if selected {
            Color(nsColor: p.selection)
        } else if ordinal % 2 == 1 {
            Color(nsColor: p.foreground).opacity(0.05)
        } else {
            Color.clear
        }
    }

    /// The user's own `mark` handle — a rounded outline in the primary accent.
    private func markPill(_ s: String) -> some View {
        Text(s)
            .font(sysFont(11, weight: .medium))
            .foregroundColor(Color(nsColor: p.primary))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: p.primary), lineWidth: 1))
    }

    /// A borderless icon+text status badge (master / float / hidden / #tag) —
    /// glyph + colour carry the meaning, matching the real tree's clean look.
    private func badge(_ icon: String, _ text: String, _ color: NSColor) -> some View {
        HStack(spacing: 3) {
            phosphorIcon(icon, 10)
            Text(text).font(sysFont(11, weight: .medium))
        }
        .foregroundColor(Color(nsColor: color))
    }

    private var hairline: some View {
        Rectangle().fill(Color(nsColor: p.border)).frame(height: 1)
    }
}

/// The 2-column dot grid facet paints as its universal "drag handle"
/// affordance (the Desktop band + every workspace header) — `drawGripDots`
/// in FacetView, here a tiny static SwiftUI echo.
private struct GripDots: View {
    let color: NSColor
    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 2.5) {
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 2, height: 2)
                }
            }
        }
        .foregroundColor(Color(nsColor: color).opacity(0.5))
    }
}

// MARK: - perch hint pills

struct MockPill: View {
    let p: ResolvedPalette

    var body: some View {
        SpecimenBox(title: "perch · hints", p: p) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    pill("J", fill: nil)
                    pill("K", fill: p.primary)        // matched
                    pill("L", fill: nil)
                }
                HStack(spacing: 6) {
                    pill("⌫", fill: p.error)          // no-match / cancel
                    Text("type to filter")
                        .font(sysFont(10))
                        .foregroundColor(Color(nsColor: p.muted))
                }
            }
        }
    }

    @ViewBuilder private func pill(_ key: String, fill: NSColor?) -> some View {
        let matched = fill != nil
        Text(key)
            .font(sysFont(12, weight: .bold, design: .monospaced))
            .foregroundColor(Color(nsColor: matched ? p.onPrimary() : p.foreground))
            .frame(width: 26, height: 22)
            .background(Color(nsColor: fill ?? p.background ?? .clear).opacity(matched ? 1 : 0.9))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(nsColor: matched ? .clear : p.border), lineWidth: 1))
    }
}

// MARK: - wand tome (launcher)

struct MockTome: View {
    let p: ResolvedPalette

    /// A tome row's icon — mirrors wand's icon-spec vocabulary: `app:<id>`
    /// resolves a real app icon (falling back to a tinted tile), `symbol:<slug>`
    /// a tinted Phosphor glyph.
    private enum RowIcon {
        case app([String])
        case symbol(String, NSColor)
    }

    var body: some View {
        SpecimenBox(title: "wand · tome", p: p) {
            VStack(alignment: .leading, spacing: 6) {
                // Launcher query field — the REAL ThemeKit field (replacing the
                // hand-drawn one) so the tome mirrors the shared component.
                ThemedFieldView(palette: p, placeholder: "open…",
                                leading: "magnifying-glass", surface: p.background)
                    .frame(height: 40)   // ≥ the label-less field's 40pt box, else the top rule clips

                // Rows: an app-launch result (real icon) + two action items
                // (tinted Phosphor glyphs) — the app:/icon: mix the real tome renders.
                row(.app(["com.apple.Safari"]), title: "Safari", sub: "launch",
                    selected: true)
                row(.symbol("gear", p.secondary), title: "System Settings",
                    sub: "⌘ ,", selected: false)
                row(.symbol("palette", p.primary), title: "Switch theme",
                    sub: "rainbow", selected: false)
            }
        }
    }

    @ViewBuilder private func row(_ icon: RowIcon, title: String, sub: String,
                                  selected: Bool) -> some View {
        HStack(spacing: 8) {
            iconView(icon).frame(width: 18 * uiScale, height: 18 * uiScale)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(sysFont(11, weight: .medium))
                    .foregroundColor(Color(nsColor: selected ? p.primary : p.foreground))
                Text(sub).font(sysFont(9, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(selected ? Color(nsColor: p.selection) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder private func iconView(_ icon: RowIcon) -> some View {
        switch icon {
        case .app(let ids):
            if let img = appIcon(ids) {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: p.secondary))
            }
        case .symbol(let name, let tint):
            Image(nsImage: phosphorImage(name, pt: 18, weight: .fill) ?? NSImage())
                .resizable()
                .renderingMode(.template)
                .foregroundColor(Color(nsColor: tint))
        }
    }
}

// MARK: - glance markdown

struct MockMarkdown: View {
    let p: ResolvedPalette

    var body: some View {
        SpecimenBox(title: "glance · markdown", p: p) {
            VStack(alignment: .leading, spacing: 5) {
                Text("# Heading")
                    .font(sysFont(13, weight: .bold))
                    .foregroundColor(Color(nsColor: p.primary))
                Text("Body text with a")
                    .font(sysFont(11))
                    .foregroundColor(Color(nsColor: p.foreground))
                + Text(" link")
                    .font(sysFont(11, weight: .medium))
                    .foregroundColor(Color(nsColor: p.primary))
                Text("inline_code()")
                    .font(sysFont(10, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.foreground))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(nsColor: p.selection))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text("error: not found")
                    .font(sysFont(10, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.error))
                Text("caption · least emphasis")
                    .font(sysFont(9))
                    .foregroundColor(Color(nsColor: p.tertiary))
            }
        }
    }
}
