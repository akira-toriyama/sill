// prism — the single-widget detail page. A user lands here when they pick a
// widget in the sidebar: a header (name · MUI kind · family · copy-ref), an
// Overview | Specimens | API segmented control, and three anchored blocks the
// control (and a `section=` deep-link) scroll to. The widget renders LIVE in the
// chosen palette — cycling through `animated(forTheme:at:)` for an animatable
// theme with effects on, mirroring `ThemeCard`'s live-theming (Gallery.swift).
//
// Specimens ALWAYS renders the WHOLE `mock` (the full "everything" view — for
// the decomposed ThemedListView that IS its 12-cell grid, byte-identical). When
// Gallery supplies decomposed `cells`, Overview shows a COMPACT `cells.prefix(2)`;
// otherwise Overview falls back to the whole mock too. `import Effects` is here
// only for `isAnimatableTheme` (not re-exported by PaletteKit). `mock`/`cells`
// are plain stored closures — NOT `@ViewBuilder` stored properties (won't compile).

import SwiftUI
import Palette
import PaletteKit
import Effects      // isAnimatableTheme lives here (not re-exported by PaletteKit)

/// The three sections of a widget page — also the segmented-control tags and the
/// scroll-anchor ids. The `section=` config deep-link seeds the initial section
/// case-insensitively by matching `rawValue.lowercased()`.
enum PageSection: String, CaseIterable, Identifiable {
    case overview = "Overview", specimens = "Specimens", api = "API"
    var id: String { rawValue }
}

struct WidgetPage: View {
    let component: KitComponent
    let themeName: String
    let showEffects: Bool
    let mock: (ResolvedPalette) -> AnyView                     // whole-mock renderer (Gallery supplies)
    let cells: ((ResolvedPalette) -> [(String, AnyView)])?     // set by Task 8 for decomposed mocks; else nil
    @State var section: PageSection
    @State var showAll: Bool

    var body: some View {
        let base = resolve(paletteFor(themeName))
        // Header + segmented control are PINNED above the scroll region so the widget
        // name, copy-ref, and the Overview|Specimens|API tabs stay visible while the
        // section blocks scroll under them (MUI-docs layout). Only the blocks scroll.
        VStack(alignment: .leading, spacing: 12) {
            header(base)
            Picker("", selection: $section) {
                ForEach(PageSection.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        block(.overview, base) { overviewBody(base) }
                        block(.specimens, base) { specimensBody(base) }
                        block(.api, base) {
                            Text(component.fullAPI).font(sysFont(9, design: .monospaced))
                                .foregroundColor(Color(nsColor: base.foreground)).textSelection(.enabled)
                        }
                    }.padding(.top, 4)
                }
                .onChange(of: section) { _, s in withAnimation { proxy.scrollTo(s, anchor: .top) } }
                .onAppear { proxy.scrollTo(section, anchor: .top) }   // section= deep-link lands here, zero clicks
            }
        }.padding(18)
    }

    @ViewBuilder private func overviewBody(_ base: ResolvedPalette) -> some View {
        // Compact: the first two representative cells, each captioned like a specimen
        // (the whole grid lives under Specimens) so the two are self-identifying.
        if let cells { living(base) { p in AnyView(VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(cells(p).prefix(2).enumerated()), id: \.offset) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.element.0).font(sysFont(8, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                    item.element.1
                }
            } }) } }
        else { living(base, mock) }         // whole mock (compact enough or not yet decomposed)
    }
    @ViewBuilder private func specimensBody(_ base: ResolvedPalette) -> some View {
        living(base, mock)   // the whole mock IS the full "everything" view (byte-identical to today's grid)
    }

    // Live (animated) for animatable themes, else static — mirrors ThemeCard
    // (Gallery.swift widgetFamily live branch): a 30 Hz TimelineView drives the
    // palette through `animated(forTheme:at:)` so the widget breathes exactly as
    // it will in an app; otherwise the frozen `resolve` palette.
    @ViewBuilder private func living(_ base: ResolvedPalette, _ render: @escaping (ResolvedPalette) -> AnyView) -> some View {
        if showEffects, isAnimatableTheme(themeName) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { t in
                render(base.animated(forTheme: themeName, at: CGFloat(t.date.timeIntervalSinceReferenceDate / effectCycleSeconds)))
            }
        } else { render(base) }
    }

    @ViewBuilder private func header(_ p: ResolvedPalette) -> some View {
        HStack(spacing: 8) {
            Text(component.name).font(sysFont(16, weight: .bold)).foregroundColor(Color(nsColor: p.foreground))
            // `kind` already carries its "MUI <X>" label where applicable — don't prepend a second "MUI".
            Text("\(component.kind) · \(component.family.rawValue)")
                .font(sysFont(9, design: .monospaced)).foregroundColor(Color(nsColor: p.muted)).lineLimit(1)
            Spacer(); CopyRefButton(component: component, p: p)
        }
    }
    @ViewBuilder private func block<C: View>(_ s: PageSection, _ p: ResolvedPalette, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.rawValue.uppercased()).font(sysFont(9, weight: .bold, design: .monospaced)).foregroundColor(Color(nsColor: p.muted))
            c()
        }.id(s)
    }
}
