// ThemeKitUI — ThemedToolBarView: the horizontal app bar / toolbar (MUI
// <AppBar> + <Toolbar>, fused), SwiftUI-native. Like ThemeKit's AppKit
// `ThemedToolBar` (which stays for AppKit hosts, and which `ThemedMenu`'s
// horizontal presentations still use as panel content) it draws the OUTER
// AppBar chrome — surface fill · elevation shadow · square/rounded corners ·
// the flat bar's bottom hairline — around an INNER content row with a fixed
// per-variant `minHeight`, leading/trailing gutters, and a left-to-right flex
// layout, and it COMPOSES `ThemedButtonView` / `ThemedDividerView` rather than
// re-drawing them.
//
// Items stay VALUE descriptors. The AppKit `ThemedToolBar.Item` carries a
// `.custom(NSView)` case and so cannot cross a SwiftUI update; that is why the
// bridge had its own `Item` enum, and the native view keeps exactly the same
// public one — no `.custom`, so the whole row is expressible in SwiftUI.
//
// The row is a custom `Layout`, not an HStack: `itemSpacing` applies only
// between adjacent CONTENT items (a space resets the run), `.flex` splits the
// slack equally the way MUI's `flexGrow: 1` does, and an icon-only button is a
// snug SQUARE at the control height — sidestepping ThemedButtonView's 64 pt
// `minWidth` floor without touching it, because a toolbar icon button is MUI's
// <IconButton>, not a min-width <Button>.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit

public struct ThemedToolBarView: View {

    /// A value descriptor for a row element — the subset that is not
    /// NSView-bearing, unchanged from the bridge.
    public enum Item {
        case button(title: String?, symbol: String?, trailingSymbol: String? = nil,
                    role: ThemedButton.Role = .primary, variant: ThemedButton.Variant = .text,
                    enabled: Bool = true)
        case label(String)
        case flex
        case fixed(CGFloat)
        case divider

        var isSpace: Bool {
            switch self { case .flex, .fixed: return true; default: return false }
        }
        var isButton: Bool {
            if case .button = self { return true }
            return false
        }
        /// Icon-only ⇒ a square button (no text, an icon present).
        var isIconOnly: Bool {
            guard case let .button(title, symbol, _, _, _, _) = self else { return false }
            return (title?.isEmpty ?? true) && symbol != nil
        }
    }

    @Environment(\.sillPalette) private var ambientPalette
    @Environment(\.displayScale) private var displayScale
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var items: [Item]
    var surface: ThemedToolBar.Surface
    var variant: ThemedToolBar.Variant
    var corners: ThemedToolBar.Corners
    var elevation: Int
    var trackingMode: ThemedToolBar.TrackingMode
    var previewHoveredItem: Int?
    var onItemClick: ((Int) -> Void)?

    /// Frozen pressed / focused button states for a static capture (t-avbj:
    /// hover was the only freezable state on a widget built for non-key panels,
    /// where nothing else can be driven live either). Set via the methods
    /// below, NOT init parameters — the API differ reads an init-label change
    /// as a removal (see `ListPreview.hovering`).
    var previewPressedItem: Int?
    var previewFocusedItem: Int?

    /// A copy with item `i`'s button frozen in its pressed pose.
    public func previewPressed(_ i: Int?) -> Self {
        var c = self; c.previewPressedItem = i; return c
    }
    /// A copy with item `i`'s button frozen in its keyboard-focused pose.
    public func previewFocused(_ i: Int?) -> Self {
        var c = self; c.previewFocusedItem = i; return c
    }

    /// Live mouse hover, used ONLY in `.nonActivatingPanel`, where the bar is
    /// the sole hover driver.
    @State private var hoveredItem: Int?

    public init(palette: ResolvedPalette? = nil, items: [Item],
                surface: ThemedToolBar.Surface = .surface,
                variant: ThemedToolBar.Variant = .regular,
                corners: ThemedToolBar.Corners = .square, elevation: Int = 0,
                trackingMode: ThemedToolBar.TrackingMode = .standard,
                previewHoveredItem: Int? = nil, onItemClick: ((Int) -> Void)? = nil) {
        self.explicitPalette = palette
        self.items = items
        self.surface = surface
        self.variant = variant
        self.corners = corners
        self.elevation = elevation
        self.trackingMode = trackingMode
        self.previewHoveredItem = previewHoveredItem
        self.onItemClick = onItemClick
    }

    // MARK: - Metrics (mirror ThemedToolBar)

    /// MUI Toolbar density → `minHeight`.
    private var minHeight: CGFloat {
        switch variant { case .regular: return 64; case .dense: return 48; case .compact: return 40 }
    }
    /// MUI gutters, per density.
    private var gutter: CGFloat {
        switch variant { case .regular: return 24; case .dense: return 16; case .compact: return 8 }
    }
    private var itemSpacing: CGFloat { CGFloat(Space.md) }
    private var controlSize: ThemedButton.Size {
        switch variant { case .regular: return .medium; case .dense, .compact: return .small }
    }
    /// The composed-button height (the 30/36/42 ladder — ThemeKit's
    /// `controlHeight` is internal to that module, so it is mirrored here as
    /// `ThemedButtonView` does).
    private var controlHeight: CGFloat {
        switch controlSize { case .small: return 30; case .medium: return 36; case .large: return 42 }
    }
    private var cornerRadius: CGFloat { corners == .rounded ? CGFloat(Radius.lg) : 0 }
    private var dividerHeight: CGFloat { max(16, minHeight * 0.5) }
    private var hairlineThickness: CGFloat { displayScale > 0 ? 1 / displayScale : 1 }
    private var labelFontSize: CGFloat { variant == .regular ? 14 : 13 }

    // MARK: - Chrome

    /// MUI AppBar `color` → the surface fill. `surface` honours
    /// `backgroundAlpha` (the panel translucency knob); `transparent` paints
    /// nothing.
    private var surfaceFill: NSColor? {
        switch surface {
        case .primary:   return palette.color(for: .primary)
        case .secondary: return palette.color(for: .secondary)
        case .surface:
            let base = palette.background ?? .windowBackgroundColor
            if let a = palette.backgroundAlpha { return base.withAlphaComponent(a) }
            return base
        case .transparent: return nil
        }
    }
    /// Ink for the bar's OWN label (contrast on a coloured bar, else foreground).
    private var barInk: NSColor {
        switch surface {
        case .primary:   return palette.onPrimary()
        case .secondary: return palette.onSecondary()
        case .surface, .transparent: return palette.foreground
        }
    }
    /// On a coloured bar a composed button inks with the bar's CONTRAST, not its
    /// own accent (which would vanish into the same-hue fill) — MUI's
    /// `color="inherit"`. `.error` is left intact so a destructive action stays
    /// red.
    private var buttonPalette: ResolvedPalette {
        guard surface == .primary || surface == .secondary else { return palette }
        let ink = barInk
        return palette.with(foreground: ink, primary: ink, secondary: ink, border: ink)
    }
    /// A flat square bar reads with a bottom hairline instead of a shadow.
    private var showsHairline: Bool {
        elevation == 0 && corners == .square && surface != .transparent
    }
    /// MUI AppBar `elevation` (0–24) → a shadow scaled from the value.
    private var elevationSpec: (opacity: Float, radius: CGFloat, offsetY: CGFloat) {
        guard elevation > 0 else { return (0, 0, 0) }
        let dp = CGFloat(min(max(elevation, 1), 24))
        return (0.24, 1 + dp * 0.5, -(0.5 + dp * 0.25))
    }

    // MARK: - Hover
    //
    // `.standard` leaves the visuals to the buttons, which track themselves.
    // `.nonActivatingPanel` makes the BAR the sole driver: under an LSUIElement
    // / non-key panel a button's own `.activeInActiveApp` tracking area never
    // fires, so the bar reads the pointer and pushes the state down. A
    // `previewHoveredItem` forces an item in either mode.

    private var drivesHoverAppearance: Bool { trackingMode == .nonActivatingPanel }
    private var forcedItem: Int? {
        previewHoveredItem ?? (drivesHoverAppearance ? hoveredItem : nil)
    }

    // MARK: - Body

    public var body: some View {
        ToolBarRowLayout(gutter: gutter, spacing: itemSpacing, kinds: items.map(rowKind),
                         minHeight: minHeight) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                itemView(i, item)
            }
        }
        .frame(height: minHeight)
        .background { chrome }
        .modifier(BarElevation(spec: elevation > 0 ? elevationSpec : nil, radius: cornerRadius))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard drivesHoverAppearance else { return }
            switch phase {
            case .active:  break            // per-item hover comes from the items
            case .ended:   hoveredItem = nil
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The surface fill, its rounded clip, and the flat bar's bottom hairline.
    @ViewBuilder private var chrome: some View {
        ZStack(alignment: .bottom) {
            if let fill = surfaceFill {
                RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                    .fill(Color(nsColor: fill))
            }
            if showsHairline {
                Rectangle()
                    .fill(Color(nsColor: palette.border))
                    .frame(height: hairlineThickness)
            }
        }
    }

    @ViewBuilder
    private func itemView(_ i: Int, _ item: Item) -> some View {
        switch item {
        case let .button(title, symbol, trailing, role, variant, enabled):
            ThemedButtonView(palette: buttonPalette, variant: variant, size: controlSize,
                             role: role, title: title ?? "", leading: symbol,
                             trailing: trailing, fullWidth: true, enabled: enabled,
                             previewHovered: forcedItem == i,
                             previewPressed: previewPressedItem == i,
                             previewFocused: previewFocusedItem == i,
                             onTap: { onItemClick?(i) })
                .asIconButton(item.isIconOnly)
                // The bar frames every item, so the member takes the width it is
                // given — which is how an icon-only item becomes a square.
                .onContinuousHover { phase in
                    guard drivesHoverAppearance else { return }
                    if case .active = phase { hoveredItem = i } else if hoveredItem == i { hoveredItem = nil }
                }
        case .label(let text):
            Text(text)
                .font(Font(palette.uiFont(labelFontSize, .medium) as CTFont))
                .foregroundColor(Color(nsColor: barInk))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize()
        case .divider:
            ThemedDividerView(palette: palette, orientation: .vertical)
        case .flex, .fixed:
            Color.clear
        }
    }

    // MARK: - Measurement
    //
    // The row Layout needs each item's width BEFORE placing it, and two kinds
    // do not answer with the number the bar wants: an icon-only button would
    // report ThemedButtonView's 64 pt `minWidth`, and a truncating label
    // underreports (it advertises that it CAN shrink). Both are computed here
    // instead, the way `ThemedToolBar.itemWidth` computes them.

    /// Measure the string directly — the AppKit bar does the same, and for the
    /// same reason.
    private func labelWidth(_ text: String) -> CGFloat {
        let font = palette.uiFont(labelFontSize, .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 4
    }

    private func rowKind(_ item: Item) -> ToolBarRowLayout.Kind {
        ToolBarRowLayout.Kind(
            isSpace: item.isSpace,
            isFlex: { if case .flex = item { return true }; return false }(),
            fixedWidth: { if case .fixed(let w) = item { return w }; return nil }(),
            overrideWidth: {
                switch item {
                case .button: return item.isIconOnly ? controlHeight : nil
                case .label(let t): return labelWidth(t)
                case .divider: return 1
                default: return nil
                }
            }(),
            height: {
                switch item {
                case .button:  return controlHeight
                case .divider: return dividerHeight
                default:       return nil          // label / space: its own
                }
            }())
    }
}

/// The MUI Toolbar flex row: gutters both sides, `spacing` only between
/// adjacent CONTENT items (a space resets the run), and `.flex` items splitting
/// whatever slack is left, equally. A port of `ThemedToolBar.intrinsicContentSize`
/// + `layout()`.
struct ToolBarRowLayout: Layout {
    struct Kind {
        var isSpace: Bool
        var isFlex: Bool
        var fixedWidth: CGFloat?
        /// The bar's own answer for this item's width, when the subview's is not
        /// the one to use (an icon-only square, a truncating label, a hairline).
        var overrideWidth: CGFloat?
        var height: CGFloat?
    }

    var gutter: CGFloat
    var spacing: CGFloat
    var kinds: [Kind]
    var minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let hasFlex = kinds.contains { $0.isFlex }
        let fixed = fixedExtent(subviews)
        // AppKit answers `noIntrinsicMetric` when a flexible space is present;
        // a Layout must return a number, so an unspecified proposal falls back
        // to the collapsed row.
        return CGSize(width: hasFlex ? max(proposal.width ?? fixed, fixed) : ceil(fixed),
                      height: minHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let fixed = fixedExtent(subviews)
        let flexCount = kinds.filter(\.isFlex).count
        let perFlex = flexCount > 0 ? max(0, bounds.width - fixed) / CGFloat(flexCount) : 0

        var x = bounds.minX + gutter
        var prevContent = false
        for (i, kind) in kinds.enumerated() {
            if kind.isFlex { x += perFlex; prevContent = false; continue }
            if let w = kind.fixedWidth { x += w; prevContent = false; continue }
            if prevContent { x += spacing }
            let w = width(i, subviews)
            let h = kind.height ?? subviews[i].sizeThatFits(.unspecified).height
            subviews[i].place(at: CGPoint(x: x, y: bounds.minY + (bounds.height - h) / 2),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(width: w, height: h))
            x += w
            prevContent = true
        }
    }

    /// Everything except the flexible spaces — the extent the slack is measured
    /// against.
    private func fixedExtent(_ subviews: Subviews) -> CGFloat {
        var total = gutter + gutter
        var prevContent = false
        for (i, kind) in kinds.enumerated() {
            if kind.isFlex { prevContent = false; continue }
            if let w = kind.fixedWidth { total += w; prevContent = false; continue }
            if prevContent { total += spacing }
            total += width(i, subviews)
            prevContent = true
        }
        return total
    }

    private func width(_ i: Int, _ subviews: Subviews) -> CGFloat {
        kinds[i].overrideWidth ?? subviews[i].sizeThatFits(.unspecified).width
    }
}

/// The AppBar's elevation shadow, or none. `offsetY` is the AppKit y-UP value,
/// so it is negated for SwiftUI's y-down shadow direction.
struct BarElevation: ViewModifier {
    var spec: (opacity: Float, radius: CGFloat, offsetY: CGFloat)?
    var radius: CGFloat

    func body(content: Content) -> some View {
        if let s = spec {
            content
                .compositingGroup()
                .shadow(color: .black.opacity(Double(s.opacity)), radius: s.radius,
                        x: 0, y: -s.offsetY)
        } else {
            content
        }
    }
}
