import SwiftUI
import AppKit
import PaletteKit
import Palette

// ThemeKitUI — the DEFAULT cell content for `ThemedGridView` (#17e). 100% SwiftUI
// native: an image scaled to fill, or a SwiftUI shimmer while it loads, with an
// optional bottom-scrim label. Cell CHROME (selection ring / hover veil / focus
// ring / corner / elevation) is owned by `ThemedGridView`, NOT here.

public struct ThemedThumbnailCell: View {
    private let image: NSImage?
    private let label: String?
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }

    /// Frozen shimmer phase for a static capture: the sweep parks at this
    /// fraction of the travel (0 = entering left, 1 = leaving right) instead of
    /// animating. Without it every capture caught a different phase, so
    /// theme-to-theme comparison of the loading cell never compared like with
    /// like (t-avbj). Set via `.previewShimmerPhase(_:)`, not an init parameter
    /// (the API differ reads an init-label change as a removal — see
    /// `ListPreview.hovering`).
    var frozenShimmerPhase: CGFloat?

    /// A copy with the loading shimmer parked at `phase` (nil = live sweep).
    public func previewShimmerPhase(_ phase: CGFloat?) -> Self {
        var c = self; c.frozenShimmerPhase = phase; return c
    }

    public init(image: NSImage?, label: String? = nil, palette: ResolvedPalette? = nil) {
        self.image = image
        self.label = label
        self.explicitPalette = palette
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ShimmerPlaceholder(palette: palette, frozenPhase: frozenShimmerPhase)
            }
            if let label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: palette.foreground))
                    .lineLimit(1)
                    .padding(.horizontal, CGFloat(Space.xs))
                    .padding(.vertical, CGFloat(Space.xxs))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.clear,
                                                (palette.background.map { Color(nsColor: $0) } ?? .black).opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
        }
        .clipped()
    }
}

/// A SwiftUI-native loading shimmer (NO AppKit). A muted fill with a soft
/// highlight band sweeping across — replaces the AppKit-backed ThemedSkeletonView
/// so the grid stays AppKit-zero (#17e AppKit policy).
struct ShimmerPlaceholder: View {
    // Internal, and only ever built by ThemedThumbnailCell, which has already
    // resolved the three tiers — so this takes the answer, not the question.
    let palette: ResolvedPalette
    /// A frozen sweep position (0…1 across the travel); nil = animate live.
    var frozenPhase: CGFloat? = nil
    @State private var travel: CGFloat = -1
    /// A band sweeping across the cell FOREVER is the strongest motion in this
    /// module, so Reduce Motion drops the sweep entirely and leaves the muted
    /// fill — the same resting state `ThemedSkeleton` falls back to, so the two
    /// loading affordances agree.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color(nsColor: palette.muted).opacity(0.18))
                .overlay(sweep(geo))
                .clipped()
        }
    }

    /// The travelling highlight band — nothing at all under Reduce Motion.
    ///
    /// Absent rather than parked: a highlight frozen mid-cell reads as a
    /// rendering artefact, while the muted fill alone still says "loading".
    /// `.onAppear` lives inside this branch too, so the repeating animation is
    /// never STARTED under Reduce Motion — hiding a running animation would
    /// keep the timer alive for nothing.
    @ViewBuilder private func sweep(_ geo: GeometryProxy) -> some View {
        if let phase = frozenPhase {
            // A PARKED band, not a running animation: statically placed at the
            // frozen fraction of the live travel (-1 … 1.3), so a capture is
            // deterministic and theme-to-theme comparison compares like with
            // like. Static, so it draws under Reduce Motion too — there is no
            // motion to reduce.
            band(geo).offset(x: (-1 + min(max(phase, 0), 1) * 2.3) * geo.size.width)
        } else if !reduceMotion {
            band(geo)
                .offset(x: travel * geo.size.width)
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        travel = 1.3
                    }
                }
        }
    }

    private func band(_ geo: GeometryProxy) -> some View {
        LinearGradient(
            colors: [.clear,
                     Color(nsColor: palette.foreground).opacity(0.12),
                     .clear],
            startPoint: .leading, endPoint: .trailing)
            .frame(width: geo.size.width * 0.6)
    }
}
