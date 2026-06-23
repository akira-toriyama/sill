# #16.5 — アプリ別 SwiftUI/sill 深掘りメモ（working）

> **working memo**。進め方 = 0ベースで全アプリ・全パーツを code-level 監査 → ここに記録 → `docs/ROADMAP.md`（SSOT）へ distill。
> 母体: handoff doc [`2026-06-23-roadmap-regrounding-phase2-3.md`](2026-06-23-roadmap-regrounding-phase2-3.md) ＋ 本セッションの focus 実証(VM) ＋ **0ベース再調査(34-agent workflow, 2026-06-23)**。
> ⚠ 最初の「各アプリ SwiftUI 不可/value-negative」結論は**誤り**だったとして本書で上書き。

## 0. 土台（確定・実証済み）

1. 全5アプリ = sill の pure エンジンのみ利用（Palette/PaletteKit/Effects/ConfigSchema/CLIKit）。widget kit・SwiftUI は import ゼロ（=現状）。wand のみ PaletteKit 未使用＝自前 NSColorParse。
2. **focus 実証(クリーン VM)**: `.nonactivatingPanel`+`NSHostingView` の ThemeKitUI TextField は、ユーザーの前面アプリ/メニューバーを奪わず(frontmost/menuBar=TextEdit のまま)key+first responder になれる。＝召喚型の検索/ランチャー面で SwiftUI-on-sill は focus 成立。
3. **IME**: ThemeKitUI.TextField は実 NSTextField を包む橋 → ネイティブ IME OK。
4. sill 構成: **widget 実体は AppKit(ThemeKit)、その上に SwiftUI 橋 ThemeKitUI**。「SwiftUI にしたい」は ThemeKitUI 経由で達成でき、AppKit widget の IME/DnD/AX 成熟も得られる。
5. 検証資産: `focusprobe`(scratchpad, sill path 依存, CLT 可) / VM `sill-focusprobe`(facet-test-26 clone, macOS26.4, Swift6.3.1, **Xcode無**)。

## 0.5 0ベース再調査の結論（全17パーツ）

**全パーツ、UI 層は SwiftUI/sill で組める。真の UI hard wall は実質ゼロ。** ネイティブは UI ではなく裏方(画像/入力/窓位置/データ)に限局。
判定内訳: `all-swiftui-sill` 4 ・ `swiftui-sill-with-thin-native-backend` 13 ・ `partial-hard-wall` 0。

| app/part | verdict | effort | UI wall |
|---|---|---|---|
| facet/tree | swiftui+thin native | M | なし |
| facet/grid | swiftui+thin native | M | なし |
| facet/rail | swiftui+thin native | M | なし |
| facet/search-bar | swiftui+thin native | **S** | なし |
| facet/panel-chrome+icons | swiftui+thin native | **L** | なし |
| facet/pet | swiftui+thin native | S | ⚠ ピクセルスプライト(下記) |
| wand/launcher-tome | swiftui+thin native | M | なし |
| wand/trail-HUD | swiftui+thin native | M | なし |
| wand/arcade-effects | swiftui+thin native | M | なし |
| wand/border+pets+blur | **all-swiftui-sill** | M | なし |
| wand/color-parse | **all-swiftui-sill** | M | なし(pure収束) |
| perch/hint-overlay | swiftui+thin native | M | なし |
| perch/search-pill | swiftui+thin native | M | なし |
| perch/particle-sim | **all-swiftui-sill** | S | なし |
| glance/markdown | **all-swiftui-sill** | M | なし(表は要部品) |
| glance/chrome+findbar | swiftui+thin native | M | ⚠ GFM表(下記) |
| halo/ring | swiftui+thin native | M | なし |

**唯一の注意（true hard wall とまでは言えない2点）:**
- **facet/pet**: アンチエイリアス OFF のピクセルスプライト描画(SwiftUI Canvas は vector-only)→ 小さな `NSViewRepresentable` blitter を残すだけ。装飾なので影響軽微。
- **glance/GFM表組み**: NSTextTable 相当が SwiftUI/TextKit2 に無い → (a)薄い `NSTextView` backend を SwiftUI 内ホスト、or (b)新規 sill「MarkdownKit(LazyVGrid 表)」を作る。どちらでも UI は SwiftUI ホスト可。

→ **0ベースなら全アプリ SwiftUI/sill 化が現実的。** 最初の「不可」は誤り。

## 0.6 ここから生まれる「sill SwiftUI 部品 roadmap」（apps が pull する）

全パーツの `sillAdditionsNeeded` を集約すると、ThemeKitUI を本物の SwiftUI 部品ライブラリへ育てる項目が浮かぶ:
- **ThemedList 強化**: キーボード nav(onKeyPress)・折りたたみ section(アニメ)・multi-select・drag-ghost overlay・sticky header 強化。
- **Canvas 粒子/スプライト/line-pets システム**(Effects→SwiftUI Canvas 橋) ← 最頻出(wand trail/arcade・perch particle・halo ring・facet pet/line-pets)。
- **BlurBackdropView**(NSVisualEffectView 橋) ← wand/perch/glance。
- **AnimatedBorderView**(虹/グラデ animated border) ← wand/facet。
- **Grid/サムネ格子部品** ← facet grid/rail。
- **MarkdownKit**(AttributedText・GFM 表 LazyVGrid・角丸 code block・Highlightr 橋) ← glance。
- 小物: ThemedPill・cascade/radial menu・search-pill badge・DisplayLink→Combine。

= **apps が sill の最初の本格 consumer になり、sill の SwiftUI 層を牽引**（sill-first 統一感の実体化）。

## 1. facet
全パーツ SwiftUI/sill。裏方=ScreenCaptureKit(サムネ画像)/AX/SkyLight/CGWindowList。icon は SF Symbols→sill phosphor 収束。chrome は effort L(窓殻 NSPanel+blur+grip+overview)。tree=ThemedList+TextField の本命(ListCore は tree モデルに設計済)。

## 2. wand
全パーツ SwiftUI/sill。border/pets/blur と particle は all-swiftui-sill(要 sill: AnimatedBorderView・Canvas粒子・BlurBackdrop)。裏方=CGEventTap(入力)/AX。color-parse は PaletteKit へ収束(pure)。

## 3. perch
全パーツ SwiftUI/sill。particle は all-swiftui-sill。裏方=CGEventTap/AX/OverlayCoords(座標)/NSPanel(never-key 属性)。要 sill: ThemedPill・BlurBackdrop・Canvas粒子。never-key は窓属性(裏方)で両立。

## 4. glance
SwiftUI/sill。表組みだけ (a)薄 NSTextView backend or (b)新規 MarkdownKit。裏方=Highlightr/NSPanel。chrome の key≠active は実証済。

## 5. halo
SwiftUI/sill。リング+glow+line-pets を SwiftUI Canvas/Effects で。裏方=SkyLight(窓位置)/CGWindowList/AX。

## 6. ROADMAP 反映方針（distill）

- 旧 Phase2/3「SwiftUI 不可・pure 収束のみ」を**破棄**。
- 新 Phase 3 = **各アプリ UI を 0ベースで SwiftUI/sill 再構築**。これが sill の SwiftUI 部品(ThemeKitUI)を牽引（§0.6 = sill 側 roadmap）。
- 優先順 素案: ①sill 側の不足部品を建てる(Canvas粒子・List の Kbd/collapse/multiselect・BlurBackdrop・AnimatedBorder・MarkdownKit) → ②アプリを1つずつ移植(**pilot=facet の search-bar〔effort S〕→ tree**、次いで halo〔単純〕、wand/perch、glance〔MarkdownKit 依存で最後〕)。
- pure 収束(wand color→PaletteKit 等)は並行。
