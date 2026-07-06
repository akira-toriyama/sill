// prism — the sidebar's single source of truth. A SidebarItem enum + the
// sidebarSections registry, DERIVED from kitCatalog/KitFamily (no duplicated
// widget list to drift). The render-map completeness test (PrismLogicTests)
// asserts wiredMockNames exactly equals the .widget rows this file produces —
// that's what keeps this registry honest against Gallery.mock(for:).

import Foundation

enum PrismFoundation: String, CaseIterable, Hashable { case palette = "Palette", icons = "Icons" }

enum SidebarItem: Identifiable, Hashable {
    case foundation(PrismFoundation), widget(String), app(KitFamily)
    var id: String {
        switch self {
        case .foundation(let f): return "foundation:\(f.rawValue)"
        case .widget(let n):     return "widget:\(n)"
        case .app(let a):        return "app:\(a.rawValue)"
        }
    }
}
struct SidebarSection: Identifiable { let title: String; let items: [SidebarItem]; var id: String { title } }

private let excludedStandalone: Set<String> = ["MarkdownView"]

let sidebarSections: [SidebarSection] = {
    var out: [SidebarSection] = [
        SidebarSection(title: "Foundations", items: PrismFoundation.allCases.map { .foundation($0) })
    ]
    for fam in KitFamily.kitCases where fam != .palette && fam != .icon {
        let widgets = kitCatalog.filter { $0.family == fam && !excludedStandalone.contains($0.name) }
                                .map { SidebarItem.widget($0.name) }
        if !widgets.isEmpty { out.append(SidebarSection(title: fam.rawValue, items: widgets)) }
    }
    out.append(SidebarSection(title: "Apps", items: KitFamily.appCases.map { .app($0) }))
    return out
}()

func sidebarLabel(_ item: SidebarItem) -> String {
    switch item { case .foundation(let f): return f.rawValue; case .widget(let n): return n; case .app(let a): return a.rawValue }
}
func sidebarSearchText(_ item: SidebarItem) -> String {
    switch item {
    case .foundation(let f): return f.rawValue.lowercased()
    case .widget(let n): let c = kitComponent(n); return "\(c.name) \(c.module) \(c.kind) \(c.family.rawValue)".lowercased()
    case .app(let a): return "\(a.rawValue) app".lowercased()
    }
}
func sidebarItem(forWidget name: String) -> SidebarItem? {
    let lower = name.lowercased()
    for s in sidebarSections { for case let .widget(n) in s.items where n.lowercased() == lower { return .widget(n) } }
    return nil
}
func sidebarItem(forFamily raw: String) -> SidebarItem? {
    let lower = raw.lowercased()
    if let f = PrismFoundation.allCases.first(where: { $0.rawValue.lowercased() == lower }) { return .foundation(f) }
    if let a = KitFamily.appCases.first(where: { $0.rawValue.lowercased() == lower }) { return .app(a) }
    return nil
}

/// Hand-kept mirror of the `mock(for:)` / `mockHandles` case list in Gallery.swift
/// (Task 6 Step 1) — NOT itself checked against that switch by the compiler, so
/// two tests pin the three pieces together: `testRenderMapExactlyMatchesWidgetRows`
/// (PrismLogicTests) asserts this set exactly equals the catalog-derived `.widget`
/// sidebar rows, and `testEveryWiredMockNameIsRendered` asserts every name here is
/// actually handled by `mockHandles` (i.e. `mock(for:)` has a real case, not the
/// `default: EmptyView()` blank-page fallback).
let wiredMockNames: [String] = [
    "ThemedTextField", "ThemedComboBox",
    "ThemedButton", "ThemedButtonGroup", "ThemedToolBar", "ThemedChip", "ThemedPill", "ThemedCheckbox", "ThemedFAB",
    "ThemedDivider", "AnimatedBorderView", "ThemedSkeleton", "ThemedTooltip", "ThemedBackdrop", "WindowShell",
    "ThemedListView", "ThemedMenu", "ThemedGrid",
    "ThemedTransition",
    "ParticleBurst", "SplatterShape", "TrailGeometry", "PixelSprite",
]
