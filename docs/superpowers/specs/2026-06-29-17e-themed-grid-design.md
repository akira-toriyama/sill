# #17e — サムネ Grid 部品（汎用 themed thumbnail Grid）設計

> Phase A（[ROADMAP](../../ROADMAP.md) #17 / furrow `t-99za`）。**ユーザー設計承認済 2026-06-29**（SCOPE・機能範囲・タイミング・4設計セクションを順に確認）。
> 別セッションが本書だけで実装着手できるよう書く（実装は executing-plans で別セッション可＝ユーザー承認）。
> 根拠調査: facet grid/rail consumer プロファイル（Explore 1-agent・`Sources/FacetViewGrid/`・`Sources/FacetViewRail/`・`Controller+Grid.swift` を file:line で精読）＋ sill 現況コード確認（ListCore DnD / Package.swift floor / ThemeKitUI の API 使用状況 / CI / 母艦 Xcode）2026-06-29。

## 1. 目的・位置づけ

**#16/#17a と同じ「sill を本物の SwiftUI 部品ライブラリへ育てる」工程の続き。** deep-dive §0.6 が挙げた未充足部品の一つ「Grid/サムネ格子部品 ← facet grid/rail」を、**汎用 NATIVE SwiftUI 部品**として `ThemeKitUI` に新設する。

- consumer: 当面は facet（grid / rail）。将来 perch grid・wand launcher・任意の picker も同じ部品を pull できる汎用 primitive にする（sill-first 統一感の実体化）。
- **裏方は持ち込まない**: サムネ画像の供給（ScreenCaptureKit 等）は consumer/Controller の責務。本部品は **画像を受け取って themed に並べる UI** だけを持つ（[[kit-component-philosophy]]）。
- AppKit 使用可ポリシー（床2個）順守: 本部品は **100% SwiftUI native**。AppKit 橋は作らない。

## 2. consumer 調査の結論（facet grid/rail = 巨大かつ facet 固有）

facet の grid/rail は単なる「サムネ格子」ではなく **ワークスペース overview UI 全体**（100% AppKit）:

- `Sources/FacetViewGrid/GridView.swift`（~1478行）+ `GridMath`/`GridHeader`/`GridPick`/`GridConfig`/`Tunables`。
- `Sources/FacetViewRail/RailView.swift`（~1000行＋）= carousel + hero の別 surface（grid の mode ではない）。
- セル = 1枚のサムネではなく「**ミニ画面＋その中に複数ウィンドウサムネを位置どり**」＋ header band（名前 / レイアウト mode / grip dots）。
- facet 固有の挙動: ワークスペース swap・lens/unassigned セル・FLIP 並べ替えアニメ・rail の carousel/hero・`onMoveWindow`/`onSwap`/`onReorder`・`OverviewCell`/`MiniWindowHit`/`GridPick`/`Workspace`/`WindowID` 等の facet ドメイン型・`WindowBackend`/ScreenCaptureKit 配線。

→ **これを丸ごと sill に移すのは [[kit-component-philosophy]] 違反**（汎用部品にアプリドメインを入れる）であり、本来は **Phase B #18（facet pilot・facet repo 側）の領分**。よって #17e は「**汎用の themed grid primitive**」を建て、facet 固有の overview は Phase B で本部品を consumer として上に compose する。

## 3. SCOPE 決定（ユーザー確定 2026-06-29）

### 3.1 作るもの = 汎用 content-agnostic themed grid（標準スコープ）

- **核（今 macOS 13 で建てる）**: responsive レイアウト（cols/gap/aspect/角丸）＋テーマ配色＋単一/複数選択（controlled/uncontrolled seam）＋hover＋focus 枠＋activation（Return / ダブルクリック）＋ロード中 skeleton＋content-agnostic セル（`@ViewBuilder`）＋既定 `ThemedThumbnailCell`＋軸切替（縦 grid / 横 rail strip）。
- キーボードは **macOS 13 で動く `onMoveCommand`（矢印）中心**（新 API `onKeyPress` に依存しない）。

### 3.2 やらないもの（明示・暗黙にしない）

- **DnD（reorder / move / swap ＋ drag-ghost overlay ＋ FLIP 並べ替え）= macOS 26 milestone へ defer**。
  - 理由: SwiftUI-native の interactive DnD/キーボードこそ **#17b が macOS 26 待ちにしている当の hard part**。今やると (a) #17e も macOS 26 ブロック、または (b) 新規 AppKit grid widget = **床2個ポリシー違反（要相談案件・[[appkit-scope-is-the-hard-gate]]）**。
  - parity: tree でさえ SwiftUI-native DnD は macOS 26 待ち（現状の list DnD は AppKit 橋 `ThemedListView`→`ThemedList` 経由のみ）。grid も同じ扱い。
  - 布石: 将来 `GridCore` に `GridDnD.swift`（[`ListCore/ListDnD.swift`](../../../Sources/ListCore/ListDnD.swift) と同型の汎用 DnD 語彙）を足す。汎用 DnD メカニズムは sill / 意味は consumer の callback、という同じ分担で入れる。
- **carousel / hero rail = facet 固有 overview 挙動 → Phase B #18**（汎用でない）。本部品の「横 rail strip」は普通の横スクロール `LazyHGrid` までで、carousel pinning/hero/edge-peek は持たない。

### 3.3 タイミング（ユーザー確定）

- **核を先に今シップ**（macOS 13・SwiftUI native）。核は macOS 13/26 どちらでも動くので無駄にならない。
- macOS 26 bump は **独立に furrow `t-tbar`**（家族横断で最低 macOS を引き上げ＝製品判断）で扱う。bump 後に #17b DnD と grid DnD を一式で解禁。
- **正直な注意**: 名指し consumer の facet/grid・rail 再構築（#18 Phase B）も macOS 26 前提の公算。核を今出すのは Phase A 前進＆汎用 primitive として正しいが、当面ライブ消費者は facet 以外（perch grid / wand launcher 等）を当てない限り speculative。設計は build-best-then-migrate で先行させる（ユーザー方針）。

#### macOS 26 移行の解除点（参考・本 spec の範囲外）

技術的には4箇所: ① sill `Package.swift` の `platforms` を `.macOS(.v13)` → `.macOS(.v26)` ② CI（`.github/workflows/build.yml` + 共有 `akira-toriyama/.github/actions/swift-build` で Xcode 26 選択）③ 各アプリの deployment target ④ ローカルは Xcode 26.6.0（母艦に導入済）を `DEVELOPER_DIR` で利用（`swift test` もローカル化＝`t-zmhn`）。**本丸は「macOS 25 以前をサポート外にする家族横断の製品判断」**（`t-tbar`）。

## 4. アーキテクチャ = 3層（ListCore / ThemedList と同型）

### 4.1 pure `GridCore`（新 SPM target・Foundation / Sendable・AppKit-free）

CI で XCTest 可能な純粋ロジックだけを置く（母艦は CommandLineTools-only ＝ローカル `swift test` 不可。**pure 核だけが CI で守れる**＝#15 ListCore と同じ判断・[[sweep-include-tests]]）。

```swift
// 列数（adaptive）: 利用可能幅・最小セル幅・gap・最大列から実列数を算出
public func gridColumns(availableWidth: CGFloat, minCellWidth: CGFloat,
                        gap: CGFloat, max maxColumns: Int) -> Int

// セルサイズ（aspect-fit）: 列数・gap・aspect から1セルの W×H
public func gridCellSize(availableWidth: CGFloat, columns: Int,
                         gap: CGFloat, aspectRatio: CGFloat?) -> CGSize

// 2D 矢印 nav: 現在 index から (dx,dy) 移動。ragged 最終行スナップ／端の wrap 方針を内包
public func nextGridIndex(from index: Int, dx: Int, dy: Int,
                          count: Int, columns: Int, wrap: Bool) -> Int

// 選択 resolve（単一/複数の共通ヘルパ。消えた id の落とし込み等）
public func resolveGridSelection<ID: Hashable>(...) -> ...
```

- 将来 macOS 26 で `GridDnD.swift` を同 target に追加（`ListDnD` 同型）。
- `CGFloat`/`CGSize`/`CGPoint` は CoreGraphics（`#if canImport(CoreGraphics)` で gate、Foundation 経由で macOS は常に可）。純粋・Sendable を維持。

### 4.2 `ThemeKitUI`（SwiftUI 前面）

```swift
@MainActor
public struct ThemedGridView<Data, ID, Cell>: View
where Data: RandomAccessCollection, ID: Hashable, Cell: View {
    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<Set<ID>>? = nil,    // nil ⇒ uncontrolled（内部 @State）
        layout: GridLayout = .adaptive(minCellWidth: 160),
        axis: Axis = .vertical,                 // .vertical=LazyVGrid / .horizontal=LazyHGrid（ともに ScrollView）
        aspectRatio: CGFloat? = nil,
        palette: ResolvedPalette,
        onActivate: ((ID) -> Void)? = nil,      // Return / ダブルクリック
        @ViewBuilder cell: @escaping (Data.Element, GridCellState) -> Cell
    )
}

public enum GridLayout: Sendable {
    case fixed(columns: Int)
    case adaptive(minCellWidth: CGFloat)
}

public struct GridCellState: Sendable {        // セルが任意で参照（自前強調用）
    public let isSelected: Bool
    public let isHovered: Bool
    public let isFocused: Bool
}
```

決定:

1. **content-agnostic** — `data` + `id` + `@ViewBuilder cell`。中身は consumer（facet=ミニ画面+窓群／perch・picker=1枚サムネ）。
2. **chrome は `ThemedGridView` が所有** — 選択リング/hover veil/focus 枠/角丸/elevation は本部品が各セルを包んで描く（テーマ統一が無料）。`cell` は**コンテンツのみ**描き、必要なら `GridCellState` で自前強調可。
3. **selection seam** — `Binding<Set<ID>>?`（複数）。`nil` で uncontrolled（内部 `@State`）。単一選択は `Binding<ID?>` を受ける **convenience init** を別途用意し、内部で `Set<ID>` にブリッジ。SwiftUI `List`/`Table` ＋ [ListCore](../../../Sources/ListCore/) の controlled/uncontrolled 流儀に一致。
4. **layout/axis** — `.fixed(columns:)` か `.adaptive(minCellWidth:)`、`axis` で縦/横。列数は `GridCore.gridColumns` が算出（キーボード nav が列数を要る）。`aspectRatio` 任意。
5. **キーボード** — `.focusable()` + `onMoveCommand`（矢印・macOS 12+）で 2D 移動（`GridCore.nextGridIndex`）、Return / ダブルクリックで `onActivate`。
6. **convenience 部品**:
   - `ThemedThumbnailCell` — 既定セル中身（下記 §5）。
   - `ThemedThumbnailGridView` — 既定セルを使う薄ラッパ。`[{id, image: NSImage?, label: String?}]` 相当を受け、`image == nil` で skeleton。

### 4.3 prism（consumer・必須 showcase）

`Sources/prism/GridShowcase.swift` 新設 → `Gallery.widgetFamily` に配線（§6）。prism は `import ThemeKitUI` の consumer のまま（ドリフト無し）。

## 5. セルの見た目と状態（canonical ロール ＋ #13 トークン）

**chrome は `ThemedGridView` 所有。** 配色は canonical ロールのみ使用（`selection`/`hover` 専用ロールあり）。正確な alpha/トークン値は **prism でライブ調整＝maintainer ゲート**（agent は画面収録不可・[[prism-bench]]）。

| 状態 | 表現（ロール / トークン） |
|---|---|
| **rest** | 角丸クリップ `Radius`（≈ md/lg）＋ `border` 1pt hairline。画像背後の letterbox/ロード地は `muted` 低 alpha |
| **hover**（非選択） | `hover` veil を上掛け＋ border を `foreground` 低 alpha に強調 |
| **selected** | `selection` wash 塗り ＋ `primary` 2pt リング（ThemedList の wash を grid 用にリング化） |
| **focused**（キーボード cursor） | `primary` の concentric focus ring・outset = `focusRingOutset`（`Space.xxs` = 2、ThemedControl の idiom 流用） |
| **disabled**（任意） | `tertiary` で減色 |

- 3状態は合成可（selected＋focused＋hover 同時）。
- cursor ≠ selection を使いたい consumer 向けに、focus を `secondary` outline に切替える option を用意（facet tree 流儀＝`ThemedList` の `.outline` highlight と同思想）。
- **elevation** は任意で hover/selected 時に `palette.shadow(.dp2)` の軽い lift（控えめ・off 可）。

`ThemedThumbnailCell`（既定セル中身）:

- 画像 = `Image(nsImage:).resizable().interpolation(.high)` を `scaledToFill` + クリップ。`image == nil` で [`ThemedSkeletonView`](../../../Sources/ThemeKitUI/ThemedSkeletonView.swift)。
- ラベル（任意）= 下帯に `foreground` テキスト＋薄 scrim。型は TypeScale トークン。
- コーナー badge 等の盛り付けは**既定セルに入れない**。必要なら generic な `ThemedGridView` の `cell` ビルダで consumer が compose（[[kit-component-philosophy]]）。

レイアウト・トークン: セル間 gap = `Space`（≈ sm/md）・外周 padding = `Space`・角丸 = `Radius`。具体値は prism で詰める。

## 6. prism showcase

- `Sources/prism/GridShowcase.swift` に `MockThumbnailGrid(p: ResolvedPalette)`:
  - **決定論的ダミーサムネ**（ScreenCaptureKit は裏方ゆえ不使用）= 色スウォッチ／phosphor アイコンを `NSImage` 生成して並べる。
  - 状態一望: rest / hover（固定 preview）/ selected / focused / skeleton（image=nil）/ adaptive・fixed 両レイアウト / 縦 grid・横 rail strip。
- [`Gallery.swift`](../../../Sources/prism/Gallery.swift) の `widgetFamily` に `WidgetSection(kitComponent("ThemedGrid"), p: p) { MockThumbnailGrid(p: p) }` を追加＝全テーマで live。

## 7. テスト方針

- **`Tests/GridCoreTests`（CI のみ・CLT ローカル不可）** — pure 核を網羅:
  - `gridColumns`（adaptive 列数・端数・最大列クランプ）
  - `gridCellSize`（aspect-fit）
  - `nextGridIndex`（2D 矢印・ragged 最終行・端 wrap）
  - 選択 resolve（単一/複数・消えた id 落とし込み）
- `ThemedGridView`/`ThemedThumbnailCell` は純 `@MainActor` SwiftUI ＝**テストせず prism ライブで maintainer 確認**（[[prism-bench]]）。
- ローカルゲート = `swift build` 緑。CI = `swift test`＋lint。⚠ `swift test` は CLT ローカル不可＝CI だけが守る（[[sweep-include-tests]]）。

## 8. バージョニング / リリース

- ライブラリ変更（additive）⇒ **minor bump + `v`-prefixed tag**。現行 `v1.32.0`（#17d）→ **次は `v1.33.0`**。
- commit: gitmoji + Conventional Commits（例 `:sparkles: feat(ThemeKitUI): #17e themed thumbnail Grid …`）。
- furrow `t-99za` を着手時 in-progress、完了で done に（projects は live/concurrent＝`git pull --rebase`→write→push ff-only）。

## 9. 受け入れ基準

1. `swift build` 緑（ローカルゲート）。
2. 新 `GridCoreTests` を含む `swift test` が CI 緑（+ lint）。
3. prism「ThemedGrid」showcase が全テーマで描画され、rest/hover/selected/focused/skeleton と adaptive/fixed・縦/横を一望できる。
4. `ThemeKitUI` に残る AppKit は床2個（IME 編集コア＋窓の殻）のまま不変（本部品は AppKit ゼロ）。
5. **ライブ目視（prism）= maintainer ゲート**で配色・状態・レイアウトを確認（agent は画面収録不可）。

## 10. 未決・チューニング（実装/プラン段階で詰める）

- gap/padding/corner/selection・hover の **具体トークン/alpha 値**は prism で確定（本 spec はロール/トークン種別まで規定）。
- `GridCore` を新 SPM target にするか、既存 pure target に同居させるか（推奨 = 新 target で ListCore parity・将来 GridDnD の置き場）。
- 単一選択 convenience init の正確なシグネチャ（`Binding<ID?>`）と uncontrolled 既定の挙動詳細。
- `aspectRatio == nil`（content-driven）時の高さ決定（セルが自前で高さを持つケース）。

## 11. 非目標（再掲・暗黙にしない）

- DnD（reorder/move/swap/ghost/FLIP）= macOS 26 milestone（#17b と一式・`GridDnD` で）。
- carousel/hero rail = facet 固有 → Phase B #18。
- facet ドメイン型/挙動（Workspace/WindowID/OverviewCell/GridPick/swap/lens）の sill 取り込み = しない。
