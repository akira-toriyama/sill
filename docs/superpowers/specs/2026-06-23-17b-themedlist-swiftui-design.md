# sill ROADMAP #17b — Design Spec: 0-based SwiftUI-native `ThemedList`

**Date:** 2026-06-23  **Status:** approved-for-planning (brainstorm complete; this doc → `writing-plans`)
**Roadmap item:** #17b `ThemedList` 強化 (Phase A, after #17a, prerequisite for #18 facet pilot)

---

## 0. 決定事項（このセッションで確定）/ Locked decisions

ブレストで合意した骨子（覆さない前提）:

1. **0ベース SwiftUI 正本化.** 新しい **SwiftUI ネイティブ `ThemedListView`** を `ThemeKitUI` に建て、これを *canonical* な list/tree にする。pure `ListCore` を共有頭脳に使う。現在の configure-once ブリッジ (`ThemeKitUI/ThemedListView.swift`, 37行) を **置換**する。
2. **AppKit `ThemedList` を完全 retire.** `Sources/ThemeKit/ThemedList.swift` (2523行) と `Tests/ThemeKitTests/ThemedListTests.swift` (1037行) を **削除**する。`ThemedComboBox` / `ThemedMenu` は AppKit の popup を **内部で `ThemedList` をホストして**行を描いている（[ThemedComboBox.swift:546](../../../Sources/ThemeKit/ThemedComboBox.swift#L546)・[ThemedMenu.swift:203](../../../Sources/ThemeKit/ThemedMenu.swift#L203)）ので、**この2つも巻き取って** 新基盤に載せ替える。
3. **機能は「全部盛り」.** 既存パリティ（Combo/Menu/prism が依存する全機能）＋新規: multi-select（`Set<ID>` binding・shift/cmd range）・折りたたみ section header の**アニメ**・drag/reorder＋drag-ghost overlay・sticky header・キーボード nav（`.onKeyPress`: ↑↓/Space/Return/Esc）。
4. **最低OS = macOS 26.** パッケージ floor を **macOS 26** へ（家族全体 facet/wand/perch/halo/glance も道連れ）。availability gate / fallback は不要。
   - ⚠ **前提条件（PRECONDITION）**: ローカルは CLT-only・SDK **15.5**（`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`）。deployment target は SDK を超えられず、現 toolchain の SwiftPM は `.macOS(.v15)` が上限。**実装フェーズの `swift build`（ローカルゲート）が動く前に、Xcode/CLT 26（macOS 26 SDK）へのローカル更新が必要**。CI（`.github/workflows/build.yml`）も **macOS 26 ランナー + Xcode 26** が必要。spec 執筆自体はビルド不要なので先行可。実装着手はこの更新待ち。
5. **House 規約踏襲.** ThemeKitUI ブリッジは `public struct` + 明示 `public init`・CLT 安全（`#Preview` 不使用）・決定論 preview seam（`frozen`/`preview*` idiom）。prism を最初の consumer＋**ライブ目視 maintainer ゲート**に。テーマは `ResolvedPalette` の role フィールド。pre-1.0 なので breaking OK。

### de-risk の結論（並列リサーチ5 + 敵対検証2 + 統合1 のワークフロー）

2大前提とも **`holds-with-caveats`**（refute されず＝実現可能・要設計の caveat あり）:

- **テーマ忠実度 HOLDS.** AppKit の描画パイプライン全体が solid `NSColor.fill()` + `NSBezierPath` + 固定 CGFloat メトリクス（`Metrics` は定数のみ・Auto Layout 無し）。唯一の非自明な合成は template 画像 tint の `.sourceAtop`（[ThemedList.swift:1599](../../../Sources/ThemeKit/ThemedList.swift#L1599)）＝ SwiftUI の `Image.renderingMode(.template).foregroundColor(...)` と 1:1。CIFilter/NSShadow/blendMode/CALayer エフェクト無し。「テーマ付きスクロールバー」「sticky hand-off」の2 high-risk は **maintainer ゲートが settled-state の目視（pixel-diff ではない）** なので gate を塞がない。
- **非キー popup HOLDS.** 既存設計が既にこの swap 向き（panel は `canBecomeKey=false` [PopupPanel.swift:33]・キーは host の NSEvent monitor 駆動で `.onKeyPress` は元々不使用・mouse は non-key でもルーティングされる）。**要設計の caveat 4点**（§6 で詳述）: ①combo 同期コミットは SwiftUI tap でなく **AppKit mouseUp 駆動**（#1 リスク・retire 前に prism ライブ必須）／②hover は `.onHover` でなく **NSEvent tracking**／③サイズ・サブメニュー位置は **pure 同期計測**（`NSHostingView.fittingSize` は非同期）／④`acceptsFirstMouse` を hosting view に設定。

---

## 1. アーキテクチャ概要 / Architecture overview

**3層・1頭脳。**

- **`ListCore`（pure・Foundation のみ・Sendable）= 共有頭脳.** 現状は5本の free-function ファイル（`resolveSelection`/`nextHighlight`/`menuKeyIntent`/`comboFilter`/`reconcileSelection`）で AppKit widget がこれを呼ぶ（[ThemedList.swift:791](../../../Sources/ThemeKit/ThemedList.swift#L791)）。#17b で **pure row model (`ListRow`)・multi-select resolver・DnD 幾何核（#15 が繰延した移設）・collapse/flatten ヘルパ・pure 計測関数（`fittingWidth`/`contentHeight`）** を増設。CoreGraphics 型は既存 house 慣習どおり `#if canImport(CoreGraphics)` の後ろ（[ListCore.swift:6](../../../Sources/ListCore/ListCore.swift#L6)・Motion idiom）。**NSImage や AppKit 型は一切持たない。**

- **`ThemeKitUI`（SwiftUI・`@MainActor`）= 新 canonical.** `ThemedListView`（`public struct`・明示 `public init`・CLT 安全）。`ScrollView { LazyVStack(pinnedViews:.sectionHeaders) }` で手組みの themed row を `ResolvedPalette` role 色から描く。**image を持つ row 型 `ListItem`** はここが所有（`image: NSImage?`/badge/trailing/tint — NSImage は非 Sendable なので ListCore に置けない）。`ListItem` は `var asRow: ListRow` で pure shadow に **projection** し、各 core は `ListRow` だけ見る。現 configure-once ブリッジを置換。

- **`ThemeKit`（AppKit・`@MainActor`）= 縮小.** AppKit `ThemedList.swift` を **削除**。`ThemedComboBox.swift` / `ThemedMenu.swift` は **存続**＝native popup chrome（`PopupPanel`/`placePopup`/`PopupFade`/`PopupGlue`/outside-click & key monitor/submenu cascade）を 100% 保持し、**行 content だけ** 載せ替え: 今日の `container.addSubview(list /*ThemedList*/)` → 明日の `container.addSubview(NSHostingView(rootView: ThemedListView(...)))`（controller が mutate する `ListController` で駆動）。**`ThemedScroller.swift` は無傷で存置**（facet が直接消費する独立公開 widget・[KitCatalog.swift:512](../../../Sources/prism/KitCatalog.swift#L512)。ThemedList 内の2つの install site だけがファイルと共に消える）。

- **`prism`（exe）= 最初の consumer ＋ ライブ目視ゲート.** 12 の `ThemedListView` 呼び出し（11 in `ListShowcase.swift`, 1 in `MenuShowcase.swift`）+ 1 `ThemedMenuTriggerView` を新 API へ再表現。

**依存グラフ宣言（pure/AppKit 分離はグラフで強制・フラグでない）:** `ListCore` は Foundation（+CG は `#if`）のみ import・Sendable 維持（row/selection/DnD/collapse ロジックを増やすが NSImage/AppKit は決して持たない）。`ThemeKitUI` は `ListCore`+`PaletteKit`+SwiftUI/AppKit に依存し image 持ち `ListItem` を所有。`ThemeKit`（Combo/Menu/Scroller）は **`ThemeKitUI` に依存（新 edge）**＋`PaletteKit`+`ListCore`。アプリは従来どおり pure エンジン（Palette/PaletteKit/Effects/ConfigSchema/CLIKit）**だけ** を消費し、widget kit は prism 向きのまま。

---

## 2. 新 `ThemedListView` の公開 API

reactive・controlled な SwiftUI 面 ＋ 非キー popup ホスト用の命令的 coordinator（**dual contract**＝Combo/Menu は AppKit monitor から highlight を駆動する）。

```swift
public struct ThemedListView<ID: Hashable & Sendable>: View {
    // DATA
    let items: [ListItem<ID>]                  // render-bearing rows (NSImage etc.)

    // CONTROLLED STATE (bindings — host owns the shape, React 契約)
    @Binding var selection: Set<ID>            // multi-select; .single は 1-set ラップ
    @Binding var expanded:  Set<ID>            // collapsed-section / tree disclosure
    @Binding var highlight: ID?                // controlled keyboard/hover cursor

    // CONFIG (value types, defaulted)
    let style:   ListStyle                     // density, hoverStyle(.wash/.solidAccent),
                                               // roundedSelection, showsDividers, zebra,
                                               // reservesLeadingImageColumn, selectionMode,
                                               // wrapsHighlight, highlightFollowsHover,
                                               // horizontalContentScroll, surfaceColor?, backgroundAlpha
    let palette: ResolvedPalette

    // CALLBACKS (behavior は host が注入)
    var onActivate:      (ID) -> Void = { _ in }
    var onMove:          (_ source: ID, _ target: DropTarget<ID>) -> Void = { _,_ in }
    var onToggleSection: (ID) -> Void = { _ in }   // host が items を再導出（既存契約）
    var onEmptyAction:   () -> Void  = {}

    // DETERMINISTIC PREVIEW SEAM (CLT 安全・frozen idiom・ThemeKitUI effect view と同型)
    var preview: ListPreview<ID>? = nil        // frozen selection/highlight/scrollX/scrollY/
                                               // dragSource/dropTarget/dragChunk（prism 静止shot 用）

    public init(/* 上記・デフォルト付き */) { ... }
}
```

- **standalone init（facet インライン list・focusable・キーを自分で持つ）**: 上記をそのまま SwiftUI 内で使用。キーは `.onKeyPress`（macOS 26 floor なので無条件で利用可）。
- **popup-hosted init（Combo/Menu）**: 同じ View を、controller が持つ `@Observable` な **`ListController`** の各フィールドを binding として渡し、命令的に駆動:

```swift
@Observable @MainActor public final class ListController<ID: Hashable & Sendable> {
    public var items:     [ListItem<ID>]
    public var highlight: ID?
    public var selection: Set<ID> = []
    // AppKit key-monitor / field-forwarder が呼ぶ命令 API（旧 widget と 1:1）
    public func moveHighlight(_ delta: Int)        // → ListCore.nextHighlight
    public func activateHighlight()                // → onActivate(highlight)
    public func clearHighlight()                   // highlight = nil
    public var  highlightedID: ID? { highlight }   // 読み戻し（combo が読む）
    // 同期 panel sizing 用（pure・§5）
    public func fittingWidth(max: CGFloat) -> CGFloat
    public func contentHeight() -> CGFloat
    public func rowRectOnScreen(_ id: ID) -> CGRect?   // model が出す rect map から
}
```

これは controller が今日呼んでいる契約をそのまま再 vend する: `moveHighlight`/`activateHighlight`/`highlightedID`/`clearHighlight`（[ThemedList.swift:1007,1028,1034,371]）と `fittingWidth`/`contentHeight`/`rowRectOnScreen`（[ThemedList.swift:839,378,830]）。命令的呼び出し箇所は「概念の書き換え」でなく「model の mutation」に翻訳されるだけ。`@Observable` は macOS 26 floor で無条件に使える。

---

## 3. 描画 & テーマ / Rendering & theming

**機構:** `ScrollView { LazyVStack(pinnedViews: .sectionHeaders) { Section(header:) { rows } } }`。各 row は `.background` / `.overlay(alignment:)` / `Canvas` で手組みし、既に具象の `ResolvedPalette` から `Color(nsColor:)`・`Font(nsFont:)` で描く。

忠実に 1:1 再現する要素（全て solid fill / bezier / 固定メトリクス）:
- **surface / vibrancy / alpha** — opaque 時 `.background(Color(nsColor: surfaceColor ?? palette.background))`、`palette.background == nil`（system/vibrancy preset）時 `.background(.clear)`（host の `NSVisualEffectView` が透ける＝[ThemedList.swift:644](../../../Sources/ThemeKit/ThemedList.swift#L644) の `drawsBackground=false` に対応）。**`backgroundAlpha`** は ThemedToolBar の idiom（[ThemedToolBar.swift:282]）を採用＝**parity-PLUS（決定⑤・現 AppKit list は適用していない・意図的改善）**。
- **zebra**（`hover@0.4α`・opaque-surface 限定・section 毎にリセット）・**leading tint bar**（x=0 full-bleed 3pt）・**selection wash + 3pt `primary` bar**・**rounded pill**（`RoundedRectangle(cornerRadius: Radius.md).inset(dx:3)`）・**outline ring**（inset 1.5 / lineWidth 1.5 / radius md）・**hover veil**・**dividers**（次 item の kind から決まる per-pair inset）・**separators**・**badges**（Capsule・role→fill/ink）・**shortcut lozenge**（Radius.sm・1pt stroke）・**chevron/accessory**・**reorder grip**（Canvas 2×3 dots）・**density**（固定 `.frame(height:)`）・**indent**（内側 HStack を pad・container は full-bleed＝MUI tree モデル）。template vs colour-favicon は `image.isTemplate` で分岐（[ThemedList.swift:1227-1231]）。
- **section header** — opaque "punch"（vibrancy gate を [ThemedList.swift:1358] どおり mirror）・uppercase `.tracking(0.5)`・1pt underline。disclosure caret は **1枚の caret を回転**（`.rotationEffect` + `withAnimation`）＝旧 AppKit の2グリフ swap（[ThemedList.swift:1386-1392]）からの**意図的改善**。

**NSViewRepresentable フォールバック（最小集合）:**
1. **themed scroller（ゲートには不要・bounded 退避路として用意）= 決定③.** SwiftUI `ScrollView` に scroller 装飾 API は無いが、`ThemedScroller` は `.overlay`+`autohidesScrollers=true`（[ThemedList.swift:580-581]）で FILL のみ所有・native fade は維持（[ThemedScroller.swift:14-16]）。prism の各 cell は `previewScrollY/X` で **settled** 位置を撮るので、themed knob は **静止ゲートで不可視**（AppKit/SwiftUI 共通）。→ 純 SwiftUI `ScrollView` + `.scrollIndicators(.hidden)`（+任意で `primary`/`muted` の overlay knob）で出荷。ライブで in-list themed scrolling が load-bearing と判れば `NSViewRepresentable(NSScrollView + ThemedScroller)` で **その部分だけ** 包む。`ThemedScroller.swift` は **削除しない**（facet が直接消費）。
2. **`horizontalContentScroll`（facet 限定・NSViewRepresentable 待機）.** 全 row で1つの水平 offset を共有・clip-not-truncate（`.byClipping`→`.fixedSize(horizontal:true)`）・selection wash を natural 幅まで延長（[ThemedList.swift:695-702] で doc view を広げ [:1314] で clip）。水平 `ScrollView` + per-row 幅 = `max(clip, naturalWidth)`（pure `fittingWidth` 由来）で達成。nested-ScrollView が不安定ならこの mode だけ `NSViewRepresentable` 退避。

sub-pixel のテキスト baseline ズレ（AppKit は ascender−descender 中央・SwiftUI Text は ~0.5–1px 差）は知覚目視ゲート以下で許容。

---

## 4. 相互作用 / Interaction

**キーボード — 2経路（中心の設計分岐）:**
- **popup-hosted（Combo/Menu）= macOS 無依存・SwiftUI focus 不使用.** `PopupPanel.canBecomeKey==false`（[PopupPanel.swift:33]）で hosted view は responder chain に **絶対入らない**。キーは外から来る: combo は field の `onMoveDown/onMoveUp/onReturn/onEscape`（[ThemedComboBox.swift:237-238,410-420]）を転送・menu は1本の `NSEvent.addLocalMonitorForEvents(.keyDown)` で `ListCore.menuKeyIntent` ルーティング（[ThemedMenu.swift:543-580]）。これらが `controller.moveHighlight/activateHighlight/clearHighlight` を呼び `highlight`（`@Observable` の field）を mutate、list は controlled `highlight` の **受動 renderer**。
- **standalone focused list（facet インライン）.** `.focusable()` + `@FocusState` の view に `.onKeyPress(.upArrow/.downArrow/.space/.return/.escape)` を付け、`ListCore.nextHighlight`/`resolveSelection`/multi-select へマップ。macOS 26 floor なので無条件。今日これを使うのは prism の dense cell（[ListShowcase.swift:206]）のみ。

**折りたたみアニメ:** host が `expanded: Set<ID>` を所有（既存 `onToggleSection` 契約・[ThemedList.swift:414]）。toggle で `ListCore.flattenVisible` が新しい可視 row 列を作り、view は swap を `withAnimation(.easeInOut)` + 条件付き `LazyVStack` 子の `.transition(.opacity.combined(with:.move(edge:.top)))` で包む。caret 回転。**`OutlineGroup`/`DisclosureGroup` は使わない**（独自 chrome/indent を強制し row painter・badge・sticky・host-owns-shape 契約と衝突）。flat な indented row が MUI tree モデルに一致。

**multi-select（新規・`.multiple` は [ThemedList.swift:211] で YAGNI 済）:** per-row tap が修飾キーを読み（NSEvent/`EventModifiers`）→ pure `SelectMods` OptionSet → `ListCore.resolveClick` が `Binding<Set<ID>>` を mutate。shift+arrow → `ListCore.extendByKey`。range/anchor 数学は全て pure（§5）で、**selectable のみの順序 id 列** 上で計算（shift-range が header/separator/disabled を巻き込まない）。anchor は sticky（Finder/MUI）。Combo/Menu は `.single`/`.none` 据え置き＝multi-select は純粋に additive。

**drag/reorder + ghost + chunk:** **手動 `DragGesture` + overlay の ghost View**（`.draggable`/`.dropDestination` は pasteboard/NSItemProvider ベース＝非同期・型符号化で、onto-vs-between の pointer-fraction zone・chunk 単位・`dropTargetValidator` ドメイン veto・keyboard lift を表現できない。`onMove` は List/ForEach 限定で custom LazyVStack には使えない）。pure resolver を再利用（`resolveDropTarget`/`dragCandidates`/`chunkMemberIDs`/`KeyboardDragController`・§5）。ghost は top-level `.overlay` View が drag translation を追従＝prism で screencapture 可能になり、現状の非キャプチャ child-window `DragGhost`（[ThemedList.swift:2203]）の制約を解消。drop affordance（ring/insertion-line/section-bar/dim・[ThemedList.swift:2042-2081]）は solid fill/stroke で 1:1。

---

## 5. `ListCore` 追加 / additions

全て Foundation のみ + Sendable・CGFloat/CGRect は `#if canImport(CoreGraphics)`。`ID: Hashable & Sendable` でジェネリックにし、`String` typealias を置いて retire 移行中も AppKit widget が無変更でコンパイルできるようにする。

**pure row model（新規・ListItem 分割＝決定④）:**
```swift
public struct ListRow<ID>: Hashable, Sendable {
    public let id: ID
    public let kind: RowKind          // .row / .sectionHeader(subtitle:collapsed:) / .separator
    public let isDisabled: Bool
    public let indentLevel: Int
    public var isHeader/isSeparator/isSelectable/isCollapsibleHeader: Bool  // 導出
}
```
image 持ち `ListItem`（ThemeKitUI）が `var asRow: ListRow` を出す。core は `[ListRow]` のみ受ける。

**multi-select（新規・`ListCore/MultiSelection.swift`）:**
```swift
func resolveClick<ID>(id: ID, current: Set<ID>, anchor: ID?, mods: SelectMods, selectable: [ID]) -> (selection: Set<ID>, anchor: ID?)
func extendByKey<ID>(current: Set<ID>, anchor: ID?, focus: ID?, delta: Int, selectable: [ID], shiftHeld: Bool, wraps: Bool) -> (selection: Set<ID>, anchor: ID?, focus: ID?)  // focus step は nextHighlight 再利用
func selectAll<ID>(selectable: [ID]) -> Set<ID>
func rangeIDs<ID>(from: ID, to: ID, in: [ID]) -> [ID]
```
`SelectMods` は pure OptionSet `{ command, shift }`（NSEvent.ModifierFlags でない・host がマップ）。

**DnD 幾何（AppKit から移設・#15 繰延分・`ListCore/ListDnD.swift`）:**
```swift
func resolveDropTarget<ID>(atDocY: CGFloat, source: ID, rows: [ListRow<ID>], geom: [RowGeom], mode: DragMode, chunkIDs: [ID], validate: (DragContext<ID>, DropTarget<ID>) -> Bool) -> DropTarget<ID>?
func dragCandidates<ID>(source: ID, rows: [ListRow<ID>], mode: DragMode, chunkIDs: [ID], validate: …) -> [DropTarget<ID>]
func chunkMemberIDs<ID>(forHeader: ID, rows: [ListRow<ID>]) -> [ID]
func stickyHeader(atVisibleTop: CGFloat, headerIndices: [Int], yOffsets: [CGFloat], heights: [CGFloat]) -> (index: Int, drawY: CGFloat)?
```
`RowGeom = (yOffset, height)`（resolver が読む唯一のフィールド・[ThemedList.swift:1797-1798]）。本体は [ThemedList.swift:1783-1922,1083-1092] から逐語移設。DnD 語彙（`DragMode/DropPlacement/DropTarget/DragContext`・[:155,160,177,193]）は既に Sendable + AppKit-free なので丸ごと移し、String→generic ID に拡張、ThemeKit/ThemeKitUI で typealias 再定義。

**collapse（新規・`ListCore/SectionCollapse.swift`）:**
```swift
func toggleSection<ID>(_ id: ID, in collapsed: Set<ID>) -> Set<ID>
func flattenVisible<ID>(rows: [ListRow<ID>], collapsed: Set<ID>) -> [ListRow<ID>]  // renderer と DnD/chunk core 共通の「可視」唯一源
```

**pure 計測（移設・Combo/Menu の reframe を同期に保つ）:**
```swift
func contentHeight<ID>(rows: [ListRow<ID>], metrics: Metrics) -> CGFloat
func fittingWidth<ID>(rows: [ListRow<ID>], maxWidth: CGFloat, metrics: Metrics) -> CGFloat  // NSString.size ループ移植・[ThemedList.swift:839-869]
```

**テスト面（XCTest・CI）:** `ListCoreTests` に `MultiSelectionTests`/`ListDnDTests`/`SectionCollapseTests`/`MeasurementTests` を追加。frozen oracle は既存 [ThemedListTests.swift:484-762]（DnD 50+ assertion）+ [:137-149,896-934]（sticky）+ [:662-682]（chunk）。**AppKit widget を消す前に** 各 assertion を pure 関数に対して写経。移行中は AppKit の `_resolveDropTarget`/`_dragCandidates`/`_chunkMemberIDs`/`_stickyHeader` seam（[:2460-2471,2423]）を thin forwarder にして旧テストを通し続ける（[[sweep-include-tests]]）。

---

## 6. popup 移行 & retire / Popup migration & retire

**Combo/Menu の SwiftUI list ホスト方法（敵対検証: holds-with-caveats）:** panel chrome は byte-for-byte 維持・`container.addSubview(list)` → `container.addSubview(NSHostingView(rootView: ThemedListView(...)))`（controller が mutate する `ListController` で駆動）。**naive な drop-in は2点で退行する**ので以下を必ず設計する:

1. **非キー panel での mouse hit-testing — HOLDS.** `.nonactivatingPanel` + `ignoresMouseEvents=false`（[PopupPanel.swift:48,54]）。`NSHostingView` も同一ルーティング。**caveat:** hosting view に `acceptsFirstMouse=true`（[ThemedList.swift:2255] を mirror）。さもないと focus 取得後の最初のクリックが食われ、combo の「打ってから行クリック」が退行。
2. **同期 row-click コミット — 最高リスク.** combo の `commitItem`（[ThemedComboBox.swift:429-438]）は mouseUp と **同じ runloop tick** で `onActivate` を撃ち、field editor の非同期 blur 照合より先に setSelection+dismiss+focus を済ませる必要（`isCommitting`/`pointerInPopup` ガード・[:378]）。SwiftUI `Button`/`.onTapGesture` は tick を遅延し得て、`clearOnBlur`（[:383]）が選択を潰す。**緩和:** activation は **NSHostingView 上の AppKit mouseUp** から `controller.onActivate` を撃つ（SwiftUI は純 renderer のまま）・ガードはそのまま。**retire 前に prism ライブで証明する #1 項目。**
3. **hover — NSEvent tracking 駆動（`.onHover` でない）.** SwiftUI `.onHover` は非キー window で死に得る。tracking area（`.activeInActiveApp`・[:2275] mirror）で row id を算出し `controller.highlight` を書く（`highlightFollowsHover` + combo の `pointerInPopup` ガード + menu の hover-to-open-submenu 意図を保存）。
4. **submenu cascade + sizing — 構造は HOLDS・新 seam 必要.** cascade は不変（各 level が自分の panel を持ち root が `activeLeaf()` にキー routing・[ThemedMenu.swift:535,559]）。だが `rowRectOnScreen`（子を親 row の横に置く・[:471,518]）と `fittingWidth`/`contentHeight`（placement 前に panel を sizing・[:375-377]）は **同期** 読み。`NSHostingView.fittingSize` は非同期確定。**緩和:** sizing は pure `ListCore.fittingWidth/contentHeight` を headless 呼び・per-row screen rect は GeometryReader+PreferenceKey の map を `ListController` に reduce し hosting window で変換。加えて `scrollRowVisible`（[:1016]）→ `ScrollViewReader.scrollTo(id)`・reload 時の stale-highlight 照合を items setter で再実装。

**combo filter:** `syncList`（[ThemedComboBox.swift:334-342]）は `controller.items = filtered` に＝reactive（SwiftUI の得意分野）。**dismissal**（outside-click monitor・PopupGlue・Esc・fade）は全て chrome-level で swap に透明。

**削除セット:** `Sources/ThemeKit/ThemedList.swift` + `Tests/ThemeKitTests/ThemedListTests.swift`。**存置:** `ThemedScroller.swift` + `ThemedScrollerTests.swift`。**更新（削除しない）:** `ThemedComboBoxTests.swift` + `ThemedMenuTests.swift`（`listProbe`/`_axChildren()`/`emptyActionID` で assert＝新 model 上に同等 probe を再現）。

**prism 移行セット:** `ListShowcase` 11 cell（[:169,183,202,218,238,262,279,300,320,336,348]）+ `MenuShowcase` mock（[:87]）+ live-trigger（[:105]）を新 API へ再表現・cell 毎に決定論 `preview` seam を再提供・caption を書き直し（coverage を黙って落とさない）。

**AX（決定⑥）:** 現状パリティ — standalone list は per-row AX opt-in（旧 `vendsRowAXElements` 相当）を再現・combo は field-level `.comboBox` パリティ（[ThemedComboBox.swift:570-573]）据え置き（スコープを締める。SwiftUI で per-row AX は near-free なので将来 consumer 要求時に拡張可）。

---

## 7. 段取り / Staging（1本の spec・実装は複数 milestone・各 milestone は ship 可能＝build+CI+prism 緑）

> ⚠ milestone 0（前提）: **ローカル toolchain を Xcode/CLT 26 へ更新** + Package.swift floor を macOS 26 へ + CI ランナーを 26 に。これが済むまで `swift build` ローカルゲートは動かない。

1. **ListCore 基盤.** `ListRow` + multi-select/collapse/measurement 追加・DnD 語彙+幾何核を **移設**（String typealias で AppKit `ThemedList` を無変更維持）・frozen oracle assertion を `ListCoreTests` に写経。AppKit `_resolveDropTarget` 等は forwarder 化。*視覚は不変・CI がパリティ証明。*
2. **SwiftUI `ThemedListView` — 描画 + standalone.** 新 `ThemeKitUI/ThemedListView.swift`（ブリッジ置換）＝全テーマ描画（§3）+ 折りたたみアニメ + multi-select + drag/ghost + standalone キーボード。`ListShowcase` 11 cell を貼り替え。*prism ゲート: テーマ毎の忠実度 + collapse/drag アニメ。*
3. **`ListController` + popup ホスト配線.** combo を NSHostingView でホスト・key-monitor→binding・**AppKit mouseUp 同期コミット**・NSEvent hover・pure 計測 sizing。*prism ゲート: combo「打って行クリック→確定」（#1 リスク）・filter・dismiss。*
4. **Menu ホスト + submenu cascade.** ThemedMenu 同様 + `rowRectOnScreen` model map + submenu anchoring・MenuShowcase mock/live-trigger 貼り替え・存続テスト用に `listProbe`/AX 再現。*prism ゲート: menu の見た目・cascade・キーボード。*
5. **RETIRE.** `ThemedList.swift` + `ThemedListTests.swift` 削除・AppKit forwarder seam と ThemedScroller install site 2箇所を除去・不要なら String typealias を落とす。*full CI + full prism sweep 緑 = 完了 → tag `v<x.y.0>`・ROADMAP 完了 flip。*

ROADMAP では #17b 配下に「着手中: PR #N」を記録（[[ci-green-merge-ok]] の自律 merge は milestone 毎に適用可。ただし **AppKit 削除（milestone 5）と combo 同期コミット（milestone 3）は prism ライブ目視ゲートを跨ぐ irreversible 変更**なので、[[chomp-push-gate]] の流儀に従い「sill で確認済み？」を一度確認してから）。

---

## 8. 検証 / Verification

- **XCTest・CI（full Xcode 26）:** pure `ListCore` ロジック全部 — `MultiSelectionTests`（anchor/shift/cmd/range・selectable-only・interleaved-header fixture）・`ListDnDTests`（移設した 50+ oracle）・`SectionCollapseTests`・`MeasurementTests`、加えて存続 `ThemedComboBoxTests`/`ThemedMenuTests`（再現 probe）。新挙動は prism-only でなく CI gate（house「sweep includes Tests」）。
- **prism ライブ目視 maintainer ゲート（知覚的・テーマ毎「見た目正しい」・golden pixel-diff でない）:** 全 catalog テーマのテーマ忠実度（zebra/tint/selection/outline/badge/lozenge/divider/header）・アニメ品質（collapse ease・caret 回転・drag-ghost 追従・reflow＝house「animation is a differentiator」基準）・load-bearing なライブ確認 — **combo 同期コミット（打って行クリック→確定・field focus 維持・revert 無し）**・非キー panel hover・submenu cascade anchoring・vibrancy（`system` テーマ: scroll 時に pinned header 越しに行が透ける）・colour-favicon の no-knockout（wand specimen）。capture は prism recipe（winid + `screencapture -l`・preview seam で決定論状態）。

---

## 9. リスク & 解決済み決定 / Risks & resolved decisions

**carried-forward HIGH リスク:**
- **combo 同期コミット race.** AppKit mouseUp activation で緩和・**AppKit 削除（milestone 5）前に prism ライブ証明必須（milestone 3）。**
- **themed scroller が純 SwiftUI で機能再現不可.** settled 静止ゲートで不可視（検証確認済）・bounded `NSViewRepresentable` 退避路あり・`ThemedScroller.swift` は不削除。
- **toolchain 前提.** macOS 26 floor は Xcode/CLT 26 更新と CI 26 ランナーが前提（§0/§7 milestone 0）。

**carried-forward MEDIUM / caveat:** sticky-header の push-up hand-off が `pinnedViews` の挙動と差異し得る（現 prism frozen offset では未行使だが facet の signature＝prism ライブで確認し、差異あれば pure `stickyHeader` 数学を `.onScrollGeometryChange` 駆動の手動 overlay に移植して true parity・**決定②**）／`horizontalContentScroll` の fiddliness（facet 限定 mode・NSViewRepresentable 待機）／lazy layout が menu sizing 用 `RowLayout` cache を失う（pure 計測で緩和）／hover は NSEvent 駆動必須／submenu rect map・`scrollRowVisible`・stale-highlight 照合の再実装／collapse は `flattenVisible` 1配列を renderer と core で共有。

**LOW / 許容:** sub-pixel テキスト baseline ズレ（知覚ゲート以下）・colour-favicon no-knockout（`isTemplate` 分岐）。

**解決済み（このセッション）:** ①最低OS=macOS 26（toolchain 更新前提）／②sticky=native 試行→ズレたら pure-math overlay 移植／③scroller=純 SwiftUI + NSViewRepresentable 待機・ThemedScroller 存置／④ListItem 分割=ListRow(ListCore)+ListItem(ThemeKitUI)／⑤backgroundAlpha=ThemedToolBar idiom 採用（parity-PLUS）／⑥AX=現状パリティ（standalone per-row opt-in / combo field-level）。

---

## 作成/変更ファイル / Files

**新規:** `Sources/ListCore/{ListRow,MultiSelection,ListDnD,SectionCollapse,Measurement}.swift`（+ 移設 DnD 語彙）・新 `Sources/ThemeKitUI/ThemedListView.swift` + `ListController`・`Tests/ListCoreTests/{MultiSelection,ListDnD,SectionCollapse,Measurement}Tests.swift`。
**変更:** `Sources/ThemeKit/{ThemedComboBox,ThemedMenu}.swift`・`Sources/prism/{ListShowcase,MenuShowcase}.swift`・`Tests/ThemeKitTests/{ThemedComboBox,ThemedMenu}Tests.swift`・`Package.swift`（ThemeKit→ThemeKitUI dep edge・platform floor → macOS 26）。
**削除:** `Sources/ThemeKit/ThemedList.swift`・`Tests/ThemeKitTests/ThemedListTests.swift`。
**無変更:** `Sources/ThemeKit/ThemedScroller.swift`・`Tests/ThemeKitTests/ThemedScrollerTests.swift`。
