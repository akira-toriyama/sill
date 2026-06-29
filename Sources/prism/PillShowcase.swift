import SwiftUI
import Palette
import PaletteKit
import ThemeKitUI

/// prism showcase for `ThemedPill` (display / indicator). Named `MockThemedPill`
/// to avoid colliding with the perch app-specimen `MockPerchOverlay`
/// (PerchShowcase.swift), which rebuilds the whole overlay scene from this widget.
/// prism imports `ThemeKitUI` only — never an app's View, so there's no drift.
struct MockThemedPill: View {
    let p: ResolvedPalette

    private let shapes: [(ThemedPillView.Shape, String)] = [
        (.pill, "pill"), (.square, "square"), (.circle, "circle"),
        (.underline, "underline"), (.tag, "tag"),
    ]
    private let states: [(ThemedPillView.State, String)] = [
        (.idle, "idle"), (.matched, "matched"), (.miss, "miss"),
    ]

    private func cap(_ s: String) -> some View {
        Text(s).font(sysFont(8, design: .monospaced))
            .foregroundColor(Color(nsColor: p.tertiary))
            .frame(width: 64, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // shape × state
            ForEach(states, id: \.1) { state, sname in
                HStack(spacing: 10) {
                    cap(sname)
                    ForEach(shapes, id: \.1) { shape, _ in
                        ThemedPillView(palette: p,
                                       label: shape == .circle ? "G" : "GH",
                                       shape: shape, state: state, typedCount: 1)
                    }
                }
            }
            // two-color typed-prefix progression (pill, idle)
            HStack(spacing: 10) {
                cap("typed 0→3")
                ForEach(0..<4, id: \.self) { n in
                    ThemedPillView(palette: p, label: "ABC",
                                   shape: .pill, state: .idle, typedCount: n)
                }
            }
            // frost + badge
            HStack(spacing: 10) {
                cap("frost/badge")
                ThemedPillView(palette: p, label: "F", shape: .pill,
                               surfaceAlpha: 0.3, frosted: true)
                ThemedPillView(palette: p, label: "GH", shape: .pill,
                               state: .matched, badge: "⌘")
                ThemedPillView(palette: p, label: "GH", shape: .tag, badge: "⌥")
            }
        }
        .padding(10)
    }
}
