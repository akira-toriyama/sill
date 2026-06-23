// prism — ThemeKit Tooltip bench. A tooltip lives on its OWN borderless child
// window, which `screencapture -l<winid>` of prism's main window can NEVER
// include — so the per-theme grid draws an INLINE MOCK of the rendered bubble
// (the exact fill `foreground@0.92`, best-contrast text, radius 4, padding 4×8,
// the palette font, and the edge arrow) across all four placements + a wrapped
// 300 px variant. A single LIVE anchor row hosts the REAL `ThemedTooltip`
// attached to a real control so the hover-show / fade / placement-flip 演出 can
// be felt by hand (it just won't appear in a static capture).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import ThemeKitUI

// MARK: - Best-contrast ink on the inverted surface (mirrors the widget)

@MainActor private func tooltipInk(_ p: ResolvedPalette) -> NSColor {
    let s = p.foreground.usingColorSpace(.sRGB) ?? p.foreground
    let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                  g: Double(s.greenComponent),
                                  b: Double(s.blueComponent))
    return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
}

@MainActor private func tooltipFont(_ p: ResolvedPalette) -> Font {
    p.font == .mono ? .system(size: 11, weight: .medium, design: .monospaced)
                    : .system(size: 11, weight: .medium)
}

// MARK: - Inline mock of the rendered bubble (for the static grid)

private enum ArrowDir { case up, down, left, right }

private struct Triangle: Shape {
    let dir: ArrowDir
    func path(in r: CGRect) -> Path {
        var p = Path()
        switch dir {
        case .up:    p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        case .down:  p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        case .left:  p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        case .right: p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        }
        p.closeSubpath()
        return p
    }
}

/// A faithful static render of the tooltip bubble: rounded inverted fill +
/// best-contrast wrapped text + the edge arrow pointing toward where the anchor
/// would sit. `placement` = which side the bubble sits on (arrow on the
/// anchor-facing edge).
private struct BubbleMock: View {
    let p: ResolvedPalette
    let text: String
    let placement: ThemedTooltip.Placement
    var maxWidth: CGFloat = 300

    private var fill: Color { Color(nsColor: p.foreground.withAlphaComponent(0.92)) }
    private var ink:  Color { Color(nsColor: tooltipInk(p)) }

    private var surface: some View {
        Text(text)
            .font(tooltipFont(p))
            .foregroundColor(ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth - 16, alignment: .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(fill))
    }

    private func arrow(_ dir: ArrowDir) -> some View {
        let w: CGFloat = (dir == .up || dir == .down) ? 11 : 8
        let h: CGFloat = (dir == .up || dir == .down) ? 8 : 11
        return Triangle(dir: dir).fill(fill).frame(width: w, height: h)
    }

    var body: some View {
        // `placement` is where the bubble sits; the arrow points back at the
        // anchor (opposite the bubble's offset direction).
        switch placement {
        case .bottom, .auto:
            VStack(spacing: -1) { arrow(.up); surface }
        case .top:
            VStack(spacing: -1) { surface; arrow(.down) }
        case .leading:
            HStack(spacing: -1) { surface; arrow(.right) }
        case .trailing:
            HStack(spacing: -1) { arrow(.left); surface }
        }
    }
}

// MARK: - Showcase

struct MockTooltip: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ThemeKit · Tooltip — inverted bubble (foreground@0.92). Top row is the REAL control on its own window (hover live); grid below is a static mock of the bubble.")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .fixedSize(horizontal: false, vertical: true)

            // LIVE — hover the real anchors; their tooltips appear on a separate
            // child window (won't show in a prism screenshot, but proves the 演出).
            HStack(spacing: 24) {
                liveCell("bottom (auto)", placement: .auto)
                liveCell("top",          placement: .top)
                liveCell("trailing",     placement: .trailing)
                Spacer(minLength: 0)
            }

            // Static mock grid — the rendered bubble per placement.
            HStack(alignment: .center, spacing: 28) {
                mockCell("top")      { BubbleMock(p: p, text: "Add item", placement: .top) }
                mockCell("bottom")   { BubbleMock(p: p, text: "Add item", placement: .bottom) }
                mockCell("leading")  { BubbleMock(p: p, text: "Add item", placement: .leading) }
                mockCell("trailing") { BubbleMock(p: p, text: "Add item", placement: .trailing) }
                Spacer(minLength: 0)
            }

            // Wrapped (300 px) two-line variant.
            mockCell("wrapped · 300px max") {
                BubbleMock(p: p,
                           text: "Tooltips wrap past 300 points so a longer hint stays readable.",
                           placement: .bottom)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
    }

    @ViewBuilder
    private func liveCell(_ caption: String, placement: ThemedTooltip.Placement) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            ThemedTooltipAnchorView(palette: p, text: "A live themed tooltip", placement: placement)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func mockCell<V: View>(_ caption: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.tertiary))
            HStack(spacing: 0) { content(); Spacer(minLength: 0) }
        }
    }
}
