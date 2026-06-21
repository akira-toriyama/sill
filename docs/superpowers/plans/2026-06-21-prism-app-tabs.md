# prism per-app tabs (#10) + effect-toggle relocation (#11) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split prism's single "Chrome" tab into one tab per family app (facet / wand / perch / halo / glance), keep the widget-family (Kit) tabs, and move the bench-wide Effects master toggle out of the tab row up to the title row.

**Architecture:** prism's gallery has two control axes — a theme-chip row (WHICH theme) and a tab row (WHICH content). Today the tab row is one `KitFamily` enum mixing foundations (Palette/Icons), kit widgets (Text/Action/Feedback/Collection/Motion/Particles), and a single catch-all `Chrome` tab that crams 4 app mocks side-by-side. This plan replaces `.chrome` with 5 per-app cases, groups the tab row into a labeled "Kit" row + "Apps" row (each a wrapping `FlowLayout`), adds a new halo ring mock, and relocates `EffectToggle` to the title line. No library/product code changes — `Sources/prism/` only.

**Tech Stack:** Swift, SwiftUI + AppKit (prism is the one `executableTarget`). Reuses existing prism types: `KitFamily`, `FamilyTab`, `EffectToggle`, `FlowLayout`, `ThemedBorderView`, `SpecimenBox`, the `Mock*` specimens, `borderEffectFor`/`isAnimatableTheme`.

## Global Constraints

- **prism has NO XCTest target** (it is an `executableTarget`; only the library modules have tests). Therefore: `swift build` is the LOCAL gate (compiles on CommandLineTools), and prism behavior is proven LIVE via screenshots (per CLAUDE.md). `swift test` runs in CI on full Xcode but covers the LIBRARY only — these prism changes cannot break a library test (verified: no Tests/ reference `KitFamily`/prism). Do NOT claim a tab works off an unrun test — capture it.
- **Verification per task = `swift build` green** (run from the worktree root). The FINAL task does the live prism capture across themes + each app tab.
- **prism-only change ⇒ default NO version tag** (no library product consumers pin prism). Confirm at merge; if bundled with anything library-facing, then `v<x.y.0>` + tag per CLAUDE.md. (Past prism-only polish rode along with a library bump; a standalone prism PR does not require one.)
- **Breaking the prism tab set is explicitly approved** (user 2026-06-21: 全ての破壊的変更OK・リファクタOK). The `Chrome` tab is removed, not deprecated.
- Commits: **gitmoji + Conventional Commits** (commit-lint enforced), scope `prism`, e.g. `:lipstick: feat(prism): …`. Squash-merge; `(#N)` appended by GitHub.
- Work happens in the worktree `/Volumes/workspace/github.com/akira-toriyama/sill-wt-prism` (branch `feat-prism-app-tabs`, off clean `origin/main`). Never touch the parallel `sill-wt-9d` worktree.

## Design decisions (resolved this session)

- **Tab architecture = Option A** (user-confirmed 2026-06-21): keep Kit (widget-family) tabs; split the single Chrome tab into per-app tabs. The full theme grid is preserved (no per-app theme filtering — that was Option B, rejected).
- **halo IS included** (5 app tabs, not the 4 in ROADMAP #10's facet/wand/perch/glance text). Rationale: halo is a real family GUI app and the purest Effects/border consumer; the user approved the 5-app list by choosing Option A (which named halo). This is the one intentional deviation from #10's wording — flagged here so it is not implicit.
- **Each app tab = its existing signature mock + a one-line "uses" caption** (what it actually consumes from sill, grounded in the 2026-06-21 app survey). Richer mocks (facet grid/rail surfaces, a wand gesture-trail using `TrailGeometry`) are a documented FOLLOW-UP, not required for #10 — see "Deferred / follow-up" at the end.

## Grounding: what each app actually consumes from sill (survey 2026-06-21)

| app | sill pin | modules | ThemeKit widgets | effects | themes (notable) | signature surface (the mock) |
|---|---|---|---|---|---|---|
| facet | 0.9.0 | Palette · PaletteKit · Effects · ConfigSchema | **ThemedScroller** | border · flash · blendThrough · line-pets | 14 (terminal, chomp, rainbow, …) | sidebar tree (`MockTree`) |
| wand | 0.11.0 | Palette · Effects · ConfigSchema · CLIKit | none | line-pets (trail is bespoke) | 7 (chomp, splatoon, neon, vapor, mono, …) | launcher tome (`MockTome`) |
| perch | 1.10.0 | Palette · PaletteKit · Effects · ConfigSchema · CLIKit | none | border · particles | 8 (system, dracula, nord, …) | hint pills (`MockPill`) |
| halo | 0.11.0 | Palette · Effects · ConfigSchema | none | border · flash · line-pets | 6 (neon, cyber, vapor, kawaii, rainbow, chomp) | focused-window ring (`MockHalo` — NEW) |
| glance | 0.6.0 | Palette · PaletteKit | none | none | 1 (catppuccin-mocha, fixed) | markdown popover (`MockMarkdown`) |

Key fact this design rests on: **apps barely use ThemeKit widgets** (only facet, only `ThemedScroller`). They are theme + effect-painted bespoke chrome. The Kit tabs remain the *library* showcase (build-best-then-migrate); the App tabs show the *consumer* reality.

---

### Task 1: Add the halo ring mock (`MockHalo`)

halo has no existing mock. It draws a thin, glowing, click-through ring around the focused window — so the mock is a small fake "window" (title dots + a couple of content lines) wrapped in the REAL shared `ThemedBorderView` (the same dogfooded border the theme cards use), so the ring glows/cycles live for animatable themes exactly as halo ships.

**Files:**
- Create: `Sources/prism/HaloShowcase.swift`

**Interfaces:**
- Consumes: `SpecimenBox<Content>` (Specimens.swift), `elevate(_:by:)` (Specimens.swift), `ThemedBorderView` (ThemeKit, already used in Gallery's card overlay), `borderEffectFor(_:)` + `isAnimatableTheme(_:)` (Effects/prism helpers), `uiScale` + `sysFont` (Gallery.swift), `ResolvedPalette` (PaletteKit).
- Produces: `struct MockHalo: View { let p: ResolvedPalette; let themeName: String; let showEffects: Bool }` — used by Task 3's tab switch.

- [ ] **Step 1: Create the file with `MockHalo`**

```swift
// prism — halo mock chrome. halo draws a thin, glowing, click-through ring
// around the FOCUSED macOS window (RingView, sampling Effects.resolveBorder at
// 30 Hz). This mock is a tiny fake "window" wrapped in the REAL shared
// ThemedBorderView, so the ring breathes / cycles live for an animatable theme
// exactly as halo ships — prism imports no app View (mirrors by eye only).

import SwiftUI
import AppKit
import PaletteKit   // ResolvedPalette
import Effects      // borderEffectFor, isAnimatableTheme
// NOTE: SpecimenBox, elevate, uiScale, sysFont, and ThemedBorderView are all
// prism-LOCAL (Specimens.swift / Gallery.swift / BorderShowcase.swift) — same
// target, no import needed. ThemedBorderView is prism's NSViewRepresentable
// bridge that wraps ThemeKit's ThemedBorder, so ThemeKit need not be imported here.

/// A miniature of halo's signature surface: a fake focused window (traffic-light
/// dots + a title + two content bars) hugged by the live effect ring. The ring
/// IS the shared `ThemedBorderView` (dogfood) — static `primary` stroke when the
/// theme has no effect / effects are off, the glowing breathing cycle otherwise.
struct MockHalo: View {
    let p: ResolvedPalette
    let themeName: String
    let showEffects: Bool

    var body: some View {
        SpecimenBox(title: "halo · ring", p: p) {
            ZStack {
                // The "focused window" the ring hugs — elevated off the panel so
                // the ring reads as surrounding a distinct surface.
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: elevate(p, by: 0.10)))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Color(nsColor: p.muted).opacity(0.6))
                                .frame(width: 6, height: 6)
                        }
                        Text("focused window")
                            .font(sysFont(9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(nsColor: p.muted))
                        Spacer(minLength: 0)
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: p.foreground).opacity(0.18))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: p.foreground).opacity(0.10))
                        .frame(width: 120 * uiScale, height: 8)
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .frame(height: 92 * uiScale)
            // The live ring — the REAL shared ThemedBorder widget.
            .overlay {
                ThemedBorderView(
                    palette: p,
                    effect: isAnimatableTheme(themeName) ? borderEffectFor(themeName) : nil,
                    effectsEnabled: showEffects,
                    cornerRadius: 10, lineWidth: 2)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` (MockHalo is an unused new type — a warning is acceptable, an error is not). If `elevate`/`SpecimenBox`/`ThemedBorderView` resolve, the file is wired correctly.

- [ ] **Step 3: Commit**

```bash
git add Sources/prism/HaloShowcase.swift
git commit -m ":sparkles: feat(prism): halo ring mock (MockHalo) for the per-app tab"
```

---

### Task 2: Per-app metadata (`AppChrome`) + restructure the tab enum

Replace the single `.chrome` case with 5 per-app cases and add a `group` discriminator so the header can render two labeled rows. Add an `AppChrome` table holding each app's caption data (grounded in the survey). This task changes ONLY `KitCatalog.swift`; the build stays RED until Task 3 updates Gallery's switch — so Task 2 and Task 3 are committed together is NOT required, but **run `swift build` only after Task 3** (note in Step 3). To keep each task independently green, Task 2 keeps a temporary `.chrome`-compatible path is NOT used; instead the enum change and the switch change are paired. **Do Task 2 and Task 3 back-to-back; the first green build is at the end of Task 3.**

**Files:**
- Modify: `Sources/prism/KitCatalog.swift:9-16` (the `KitFamily` enum + doc comment)
- Modify: `Sources/prism/KitCatalog.swift` (append the `AppChrome` table)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `enum KitFamily` cases gain `.facet/.wand/.perch/.halo/.glance`, lose `.chrome`; gains `enum Group { case kit, app }`, `var group: Group`, `static var kitCases: [KitFamily]`, `static var appCases: [KitFamily]`.
  - `struct AppChrome { let tab: KitFamily; let blurb, uses, themes: String }` + `let appChromes: [AppChrome]` + `func appChrome(_ tab: KitFamily) -> AppChrome?`.

- [ ] **Step 1: Rewrite the `KitFamily` enum + doc comment**

Replace `KitCatalog.swift:9-16` with:

```swift
/// The gallery's top-level tabs, in two GROUPS. The `kit` group is the library
/// showcase — `palette` (theme foundations), `icon`, and the real widget
/// families. The `app` group is one tab per family app, each rendering that
/// app's signature chrome mock (the old single `chrome` tab, split per app).
enum KitFamily: String, CaseIterable, Identifiable {
    // Kit group — foundations + the real ThemeKit widgets.
    case palette = "Palette", icon = "Icons", text = "Text", action = "Action",
         feedback = "Feedback", collection = "Collection", motion = "Motion",
         particles = "Particles"
    // App group — one per family app (replaces the single `chrome` tab).
    case facet = "facet", wand = "wand", perch = "perch",
         halo = "halo", glance = "glance"
    public var id: String { rawValue }

    enum Group { case kit, app }
    /// Which header row this tab lives in.
    var group: Group {
        switch self {
        case .facet, .wand, .perch, .halo, .glance: return .app
        default: return .kit
        }
    }
    /// The Kit row (foundations + widgets), in declaration order.
    static var kitCases: [KitFamily] { allCases.filter { $0.group == .kit } }
    /// The Apps row (one per app), in declaration order.
    static var appCases: [KitFamily] { allCases.filter { $0.group == .app } }
}
```

- [ ] **Step 2: Append the `AppChrome` table at the end of `KitCatalog.swift`**

(After the closing `}` of `func kitComponent(_:)`.)

```swift

/// Per-app prism-tab metadata: a one-line blurb + what the app ACTUALLY consumes
/// from sill + its notable themes (grounded in the app-repo survey 2026-06-21).
/// Drives the caption under each per-app tab so the bench shows the CONSUMER
/// reality (apps are theme + effect-painted bespoke chrome — they barely use the
/// ThemeKit widgets, which exist for build-best-then-migrate).
struct AppChrome: Identifiable {
    let tab: KitFamily       // .facet/.wand/.perch/.halo/.glance
    let blurb: String        // what the app's surface is
    let uses: String         // sill modules / widgets / effects it consumes
    let themes: String       // notable themes it ships
    var id: String { tab.rawValue }
}

let appChromes: [AppChrome] = [
    AppChrome(tab: .facet,
        blurb: "window/workspace manager — sidebar tree · grid · rail overlays",
        uses: "Palette · PaletteKit · Effects · ThemedScroller · border/flash/pets",
        themes: "14 themes (terminal · chomp · rainbow · …)"),
    AppChrome(tab: .wand,
        blurb: "gesture daemon — fullscreen trail + non-activating launcher tome",
        uses: "Palette · Effects · CLIKit · line-pets (trail bespoke)",
        themes: "7 themes (chomp · splatoon · neon · vapor · mono · …)"),
    AppChrome(tab: .perch,
        blurb: "keyboard hint overlay — frosted hint pills over clickables",
        uses: "Palette · PaletteKit · Effects · CLIKit · border · particles",
        themes: "8 themes (system · dracula · nord · …)"),
    AppChrome(tab: .halo,
        blurb: "focus ring — thin click-through glow around the focused window",
        uses: "Palette · Effects · border · flash · line-pets (no widgets)",
        themes: "6 themes (neon · cyber · vapor · kawaii · rainbow · chomp)"),
    AppChrome(tab: .glance,
        blurb: "markdown popover — non-activating panel, fixed dark preset",
        uses: "Palette · PaletteKit only (no Effects, no theme switching)",
        themes: "fixed catppuccin-mocha"),
]

/// The metadata for an app tab, or nil for a Kit tab.
func appChrome(_ tab: KitFamily) -> AppChrome? {
    appChromes.first { $0.tab == tab }
}
```

- [ ] **Step 3: Do NOT build yet** — the `KitFamily.allCases` `ForEach` in Gallery and the `.chrome` switch case are now stale. Proceed straight to Task 3; the first green build is Task 3 Step 4. (No commit here — Task 2 + Task 3 commit together in Task 3 Step 5.)

---

### Task 3: Header restructure (#11 toggle relocation + #10 two-group tab row) + per-app card switch

This is the visible change. Three edits in `Gallery.swift`: (a) move `EffectToggle` to the title row and replace the single family-tab `HStack` with two labeled `FlowLayout` rows; (b) replace the `.chrome` case in `ThemeCard.widgetFamily(p:)` with the 5 per-app cases (each = its mock + the `AppChrome` caption).

**Files:**
- Modify: `Sources/prism/Gallery.swift:91-127` (the `header` computed property)
- Modify: `Sources/prism/Gallery.swift:343-354` (the `.chrome` case in `widgetFamily`)
- Add: a `tabGroup(label:families:)` + `appCaption(_:)` helper to `Gallery` (in the same file)

**Interfaces:**
- Consumes: `KitFamily.kitCases/.appCases/.group` (Task 2), `appChrome(_:)` (Task 2), `MockHalo` (Task 1), existing `MockTree/MockPill/MockTome/MockMarkdown` (Specimens.swift), `EffectToggle`/`FamilyTab`/`FlowLayout` (Gallery.swift), `self.name`/`self.showEffects` (ThemeCard properties).
- Produces: the final two-axis header; no new public types other than two private helpers on `Gallery`/`ThemeCard`.

- [ ] **Step 1: Replace the `header` computed property (`Gallery.swift:91-127`)**

```swift
    // MARK: header — title + effect toggle, then the theme-switch row, then tabs

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row. The Effects 演出 master toggle lives HERE now (#11) — it
            // is a THEME-axis control (effects animate themes), not a tab, so it
            // sits with the title, clear of both tab groups below.
            HStack(spacing: 10) {
                Text("prism — \(selected == "all" ? "\(Gallery.switchable.count) themes" : selected)")
                    .font(sysFont(12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer(minLength: 12)
                EffectToggle(on: showEffects) { showEffects.toggle() }
            }
            // A wrapping flow of theme buttons — "All" first, then the catalog in
            // order. Each chip is tinted in its own theme colours, so the switch
            // row doubles as an at-a-glance colour preview.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ThemeChip(name: "all", label: "All",
                          selected: selected == "all") { selected = "all" }
                ForEach(Gallery.switchable, id: \.self) { name in
                    ThemeChip(name: name, label: name,
                              selected: selected == name) { selected = name }
                }
            }
            // A rule separating the two control axes: WHICH theme (the colour
            // chips above) vs WHICH content (the tabs below).
            Divider()
            // Two tab groups (#10): the Kit library showcase, then one tab per
            // app. Each group wraps so a narrow window stacks tabs instead of
            // clipping them.
            tabGroup(label: "Kit",  families: KitFamily.kitCases)
            tabGroup(label: "Apps", families: KitFamily.appCases)
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One labeled, wrapping tab row (Kit or Apps). The leading label aligns the
    /// two rows so the tabs start at the same x.
    @ViewBuilder
    private func tabGroup(label: String, families: [KitFamily]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(sysFont(9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32 * uiScale, alignment: .leading)
                .padding(.top, 6)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(families) { fam in
                    FamilyTab(family: fam, selected: selectedFamily == fam) {
                        selectedFamily = fam
                    }
                }
            }
        }
    }
```

- [ ] **Step 2: Replace the `.chrome` case in `widgetFamily(p:)` (`Gallery.swift:343-354`)**

```swift
        case .facet:
            appCaption(.facet)
            MockTree(p: p)
        case .wand:
            appCaption(.wand)
            MockTome(p: p)
        case .perch:
            appCaption(.perch)
            MockPill(p: p)
        case .halo:
            appCaption(.halo)
            MockHalo(p: p, themeName: name, showEffects: showEffects)
        case .glance:
            appCaption(.glance)
            MockMarkdown(p: p)
```

- [ ] **Step 3: Add the `appCaption(_:)` helper to `ThemeCard`** (just below `widgetFamily(p:)`, before the closing brace of `ThemeCard`)

```swift
    /// The per-app tab caption — what this app's surface is + what it ACTUALLY
    /// consumes from sill + its notable themes (the consumer reality; apps barely
    /// use the ThemeKit widgets the Kit tabs showcase). Grounded data, see
    /// `appChromes` in KitCatalog.swift.
    @ViewBuilder
    private func appCaption(_ tab: KitFamily) -> some View {
        if let a = appChrome(tab) {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.blurb)
                    .font(sysFont(10, weight: .medium))
                    .foregroundColor(Color(nsColor: base.foreground))
                Text("uses: \(a.uses)")
                    .font(sysFont(8.5, design: .monospaced))
                    .foregroundColor(Color(nsColor: base.muted))
                Text(a.themes)
                    .font(sysFont(8.5, design: .monospaced))
                    .foregroundColor(Color(nsColor: base.muted))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
        }
    }
```

NOTE: `appCaption` reads `self.base` — `ThemeCard.body` computes `let base = resolve(spec)` locally, NOT a stored property. Add a stored `base` is unnecessary; instead recompute inside the helper: replace the three `base.*` references with `resolve(paletteFor(name)).*`. To avoid resolving 3×, compute once:

```swift
    private func appCaption(_ tab: KitFamily) -> some View {
        let a = appChrome(tab)
        let cp = resolve(paletteFor(name))
        return Group {
            if let a {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.blurb)
                        .font(sysFont(10, weight: .medium))
                        .foregroundColor(Color(nsColor: cp.foreground))
                    Text("uses: \(a.uses)")
                        .font(sysFont(8.5, design: .monospaced))
                        .foregroundColor(Color(nsColor: cp.muted))
                    Text(a.themes)
                        .font(sysFont(8.5, design: .monospaced))
                        .foregroundColor(Color(nsColor: cp.muted))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
            }
        }
    }
```

(Use this second form — it has no dependency on a stored `base`.)

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` — no errors. The enum (Task 2), the switch, and the header now all agree. If the compiler complains the `widgetFamily` switch is non-exhaustive, a `.chrome` case was left behind or an app case is missing — fix to cover exactly `palette/icon/text/action/feedback/collection/motion/particles/facet/wand/perch/halo/glance`.

- [ ] **Step 5: Commit (Task 2 + Task 3 together)**

```bash
git add Sources/prism/KitCatalog.swift Sources/prism/Gallery.swift
git commit -m ":lipstick: feat(prism): per-app tabs (facet/wand/perch/halo/glance) + effect toggle on the title row (#10/#11)"
```

---

### Task 4: Doc-comment + config sync

Bring the stale comments and the `family` config doc in line with the new tab model. No behavior change — but leaving "fake perch / facet / wand / glance" comments and a "widget-family tab" config doc would mislead the next reader.

**Files:**
- Modify: `Sources/prism/Prism.swift:51-54` (the `family` config doc comment)
- Modify: `Sources/prism/Specimens.swift:1-4` (file header) — optional wording
- Modify: `Sources/prism/Gallery.swift` — the retired comment near the old chrome case, if any text remains

**Interfaces:** none (comments only).

- [ ] **Step 1: Update the `family` config doc in `Prism.swift:51-54`**

```swift
    /// Which tab opens (a `KitFamily` raw value, case-insensitive; a Kit family
    /// like `icons`/`action`, or an app tab like `facet`/`halo`). Lets a
    /// screenshot target a tab deterministically instead of clicking. Default =
    /// `palette` (the foundations).
    var family: String = "palette"
```

- [ ] **Step 2: (Optional) refresh the `Specimens.swift` header** to note halo now has its own mock in `HaloShowcase.swift`. One line; skip if it reads fine.

- [ ] **Step 3: Build + commit**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

```bash
git add Sources/prism/Prism.swift Sources/prism/Specimens.swift
git commit -m ":memo: docs(prism): sync comments to the per-app tab model"
```

---

### Task 5: Live verification + handoff

prism is verified LIVE (no test target). Capture the new tabs across a few representative themes, confirm visually, then record the result.

**Files:** none (verification + ROADMAP handoff happens at the session level — see "Handoff" below).

- [ ] **Step 1: Launch prism on an app tab (deterministic capture)**

Per the prism capture recipe ([[prism-bench]] memory): launch `.build/debug/prism` with a `PRISM_CONFIG` toml that sets `family = "halo"` (then `facet`, `wand`, `perch`, `glance`), get the window id, `screencapture -l<winid> -o out.png` WITHOUT osascript-activating. Use `theme = "all"` to see the app's chrome in every theme, or a single animatable theme (e.g. `synthwave`/`neon`) with `show-effects = true` to confirm the halo ring glows.

```bash
swift build
printf 'family = "halo"\ntheme = "all"\nshow-effects = true\n' > /tmp/prism-halo.toml
PRISM_CONFIG=/tmp/prism-halo.toml .build/debug/prism &
# get winid for "prism", then: screencapture -l<winid> -o /tmp/prism-halo.png
```

- [ ] **Step 2: Confirm visually** (look at the capture):
  - Title row shows `[✨ Effects ON]` toggle at top-right, NOT in the tab row.
  - Two labeled tab rows: `KIT [Palette][Icons][Text][Action][Feedback][Collection][Motion][Particles]` and `APPS [facet][wand][perch][halo][glance]`.
  - The halo tab renders the `MockHalo` ring around the fake window, glowing on an animatable theme; the caption reads halo's blurb/uses/themes.
  - Repeat for `family = "facet"` (MockTree), `wand` (MockTome), `perch` (MockPill), `glance` (MockMarkdown) — each shows its mock + caption, one per theme card.
  - Narrow the window: the Apps/Kit rows WRAP (FlowLayout), nothing clips.

- [ ] **Step 3: Toggle Effects OFF** (click the title-row toggle or `show-effects = false`): the halo ring + animatable card rims rest to a static `primary` stroke. Confirms #11 toggle still drives the whole bench from its new home.

- [ ] **Step 4: Final build gate**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 5: Handoff** — update `docs/ROADMAP.md` (#10/#11 → 完了 pending merge, or 着手中 if stopping mid-execution) and report the live-capture evidence. Squash-merge per [[ci-green-merge-ok]] once CI is green (prism-only ⇒ default no version tag — confirm). Do NOT claim done without the Step 2 capture.

---

## Self-review (against the spec)

- **#11 (toggle relocation):** Task 3 Step 1 moves `EffectToggle` to the title-row `HStack`. ✓
- **#10 (per-app tabs):** Task 2 (enum) + Task 3 (header rows + card switch) + Task 1 (halo mock) split Chrome into facet/wand/perch/halo/glance. ✓
- **Kit tabs preserved (Option A):** `KitFamily.kitCases` keeps palette/icon/text/action/feedback/collection/motion/particles. ✓
- **No library change:** only `Sources/prism/` files touched. ✓
- **Type consistency:** `MockHalo(p:themeName:showEffects:)` defined in Task 1 == call site in Task 3 Step 2. `appChrome(_:)`/`AppChrome` defined in Task 2 == used in Task 3 Step 3. `KitFamily.kitCases/.appCases` defined in Task 2 == used in Task 3 Step 1. `.chrome` removed in Task 2 == switch case removed in Task 3 Step 2 (exhaustiveness checked at Task 3 Step 4). ✓
- **No placeholders:** every code step is complete. ✓
- **Build-green cadence:** Task 1 green (new file), Tasks 2+3 green together (coupled enum/switch — flagged), Tasks 4/5 green. ✓

## Deferred / follow-up (NOT in this plan — flagged so it is not implicit)

- **Richer per-app mocks:** facet currently shows only the sidebar (`MockTree`); its grid + rail surfaces are not mocked. wand shows only the launcher (`MockTome`); its hero gesture-trail is not mocked (a future mock could use the now-shared `Effects.TrailGeometry` + `drawLinePets`). These enrich the tabs but are not required to "split Chrome per app."
- **Per-app tab tint:** app tabs use the neutral `FamilyTab` chrome (correct — a tab spans all themes). A subtle per-app accent dot was considered and dropped for simplicity.
- **Per-app theme filtering (Option B):** not done by design — the full theme grid is preserved.
- **Version tag:** prism-only ⇒ default no tag; revisit only if bundled with a library change.
