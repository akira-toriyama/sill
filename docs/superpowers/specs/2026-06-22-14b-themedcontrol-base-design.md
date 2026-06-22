# #14b — `ThemedControl` 基底クラス + リテラル→#13 トークン配線 設計

> 状態: **設計合意済**（ユーザー承認 2026-06-22・ブレインストーミング3セクション全 OK）。実装は別セッション可。
> 進捗 SSOT = [`docs/ROADMAP.md`](../../ROADMAP.md)（この doc は設計の根拠・決定記録）。
> 親 spec = [`2026-06-22-sill-generalization-and-swiftui-design.md`](2026-06-22-sill-generalization-and-swiftui-design.md) §4「#14」。
> 前工程 = [`2026-06-22-14a-dry-consolidation.md`](../plans/2026-06-22-14a-dry-consolidation.md)（✅ 完了・PR #67 + `v1.20.0`）。
> 根拠 = 8-agent 調査 workflow（2026-06-22）: Button/FAB/Checkbox/Chip/ToolBar の状態管理面を構造化マップ化 + leaf 消費者 +
> リテラル→トークン棚卸し → 共通面/seam/スコープ境界を統合（懐疑的シンセサイザ付き）。

## 0. この doc が確定すること

`ThemedControl: NSControl` 基底クラスを新設し、**Button/FAB/Checkbox/Chip の4部品**が継承する。hover/press/focus 状態・
tracking area・mouse trio・first-responder・Space 起動・activation flash・focus-ring・`preview*`/`fx*` を一本化し、各部品の逸脱は
**override 可能な seam** として露出する。加えて #14b パート2 = focus-ring outset の4重複を基底トークン `focusRingOutset = Space.xxs` に集約。

これは **値保存リファクタ**（基底抽出であって再設計ではない）。hover/press/focus/flash/ring の挙動は**バイト等価**を維持し、
意図的な値変更は **ゼロ**（focus-ring outset も 2pt 据え置き）。

## 1. スコープ確定（ユーザー判断 + 調査による spec 訂正）

### ユーザー判断（2026-06-22）

1. **#14b = 単一コントロール基底（4部品のみ）に絞る。** ToolBar/ButtonGroup のコンテナ共通化は将来の別 ROADMAP 項目
   「**ThemedContainer 基底**」へ切り出し（2つ目の実消費者が出たら着手）。
2. **ThemedList の密度不変 gap（lineGap=2/badgeGap=4/badgeHPad=6/clusterGap=6/budgetMargin=8）は `Metrics` に据え置き**
   （#13 ドキュメントの「control-size レイアウトは Metrics」規約を尊重・List は基底対象外の leaf 部品）。

### 調査が overturn した親 spec の前提（満場一致・実コード根拠・ユーザー設計承認に織込み済）

| 親 spec の記述 | 実コードの事実 | #14b での確定 |
|---|---|---|
| `ThemedControl: **NSView**` | 4部品とも**セルレス NSControl**で `_enabled/_target/_action` + `sendAction` + `performKeyEquivalent` + 無効化後始末を逐語コピー | `ThemedControl: **NSControl**`（NSView だと各サブクラスが基底の存在理由を再追加する羽目に） |
| 完全採用に「**+ ToolBar の fx-state**」 | ToolBar は**コンテナ**（`NSView`）で自前 control 状態ゼロ。per-item hover は `.nonActivatingPanel` 時に子 `ThemedButton` へ `previewHovered` を押し下げて描かせるのみ | ToolBar は**継承しない**。子 Button 経由で恩恵を受け、prism 回帰ゲートには残す |
| `CornerPath` を #14b で抽出（基底/ButtonGroup が2つ目の消費者） | 選択的角丸パス（`closedCornerPath`/`borderPath`）の消費者は**今も ThemedButton 1つだけ**。ButtonGroup は子へ `roundedCorners`/`drawnBorderEdges` を steer するだけで自前パスを作らない。基底は focus-ring layer のみ所有し、リングの**形はサブクラス override** | `CornerPath` 抽出は**据え置き継続**（rule-of-three 未達）。`closedCornerPath`/`borderPath` は ThemedButton にインライン継続 |

## 2. セクション A — 基底クラスの形

### ① 型と可視性
- **`public class ThemedControl: NSControl`**（`@MainActor`）。`open` ではなく `public`（全サブクラスが同一モジュール
  `Sources/ThemeKit/` 内＝アプリは合成のみで継承しない）→ open-class の API 安定性負担を回避。
- セルレス NSControl の慣習を踏襲: `isEnabled`/`target`/`action` を `_enabled`/`_target`/`_action` の手動ストレージで override
  （cell-backed アクセサに依存しない）。

### ② 基底が所有するもの（共通面）
- **tracking area ライフサイクル**: remove→再 add・`NSTrackingArea(rect: .zero, options: [...], owner: self)`・`.inVisibleRect`・
  re-add 後の **stale-hover 復元**（live ポインタが bounds 外なら `isHovered` クリア + `applyState(animated:false)`）。`trackingOptions` は open。
- **状態ストレージ（固定コア）** `isHovered` / `isKeyFocused` / `isFlashing`。**`isPressed` は固定コアに入れず**、§3 の open
  press seam として既定 `Bool isPressed` を提供する（Button/FAB/Checkbox は無改変で継承・Chip は seam ごと差し替え）。
- **mouse trio**（entered/exited/down/dragged/up）+ `acceptsFirstMouse` を open テンプレ + 共有 **drag-cancel ヘルパ**。
- **first-responder** 配線（`acceptsFirstResponder`/`becomeFirstResponder`/`resignFirstResponder`）+ open `focusGate`。
- **keyDown** Space(keyCode 49) ディスパッチ + オートリピート握り潰し（消費して beep させない）/ **performKeyEquivalent**（空キー時は無害）。
- **flash**: `flashThenActivate()` 0.12s ヘルパ + `isFlashing` 原子性（0.12s 窓内の2度押しを落とす + async 無効化で起動キャンセル）。
- **focus-ring** `CAShapeLayer`（fill clear・lineWidth 2・strokeColor = `palette.primary`・`focusRingType = .none` で AppKit 標準を抑制・
  opacity ゲート）+ `focusRingOutset = Space.xxs(2)` が **inset(-2) と角丸 +2 の同心円計算**を駆動（リングの**形**はサブクラス override）。
- **preview トリオ** `previewHovered/Pressed/Focused`（didSet → `applyState(animated:false)`）+ **fx 合成スケルトン**
  `fxHovered/fxPressed/fxFocused`（実状態 ‖ preview フラグ、ゲートで AND）+ open `showFocusRing`。
- **セルレス `_enabled/_target/_action`** + 無効化クリア（hover/press クリア + FR 放棄 = stuck-hover gotcha 修正）+ `sendAction`。
  無効化後始末は **`final` 挙動 + open `didDisable()` フック**（isEnabled setter を overridable にしない＝super 呼び忘れ事故を防ぐ）。
- **二層テンプレ** `applyTheme(snap)`（安定ビジュアルを `layerTxn(animated:false)` で）/ `applyState(animated:)`（相互作用駆動プロップを
  `layerTxn(animated:)` で）。両方 #14a の共有 `layerTxn` 経由。
- `viewDidChangeBackingProperties` の contentsScale 配布フック・`isFlipped = false` 既定・`init(palette:)` /
  `@available(*, unavailable) required init?(coder:)`。

### ③ サブクラスに残るもの（基底は触らない）
各部品の layer ツリー / `layoutContent` / `intrinsicContentSize` / 色計算（baseFill・overlay・border・elevation）/
Checkbox の値モデル（tri-state・glyph CGPath・`previewChecked/Indeterminate`・eff フラグ・a11y value）/
Button の選択的角丸 `closedCornerPath`/`borderPath`（CornerPath インライン据え置き）/ focus-ring の形（Button=選択角・FAB=円・
Checkbox/Chip=全角 pill）/ 各 `activate()` 本体。

## 3. セクション B — seam（基底の柔軟性設計）

各部品の逸脱は基底に特例を埋め込まず、すべて override 可能な口（open メソッド/述語）として露出する。

| seam | 機構 | 既定（boilerplate ゼロ） | 逸脱する部品 |
|---|---|---|---|
| **press 状態** | open mouse trio + 共有 drag-cancel ヘルパ + open `fxPressed` | Bool `isPressed`（単一ターゲット） | **Chip**: `PressTarget` enum（本体 vs 削除ボタンの2ターゲット）で trio と `fxPressed` を override（基底 Bool は不使用） |
| **keyboard 起動 / flash** | open `keyboardActivate()` + 基底提供 `flashThenActivate()` | `flashThenActivate { activate() }`（flash→送出）= Button/FAB | **Checkbox**: flash 後が「送出」でなく「トグル」= `keyboardActivate` override（flash ヘルパ自体は流用） |
| **相互作用ゲート** | 2つの open 述語 `appearanceGate`（hover/press/focus 描画）/ `focusGate`（FR + focus-ring） | 両方 `isEnabled` | **Chip**: 本体不活性でも削除ボタンは focus 可 = `appearanceGate=isClickable` / `focusGate=isInteractive` |
| **click で FR を取るか** | open `mouseDown` | 取らない（push-button 慣習） | 4部品とも既定（将来 click-to-focus 用の override の口だけ用意。cf. TextField=leaf は取るが対象外） |
| **無効化の後始末** | `final` 挙動 + open `didDisable()` フック | hover/press クリア + FR 放棄 | サブクラスは isEnabled setter を上書きせず `didDisable()` に追記 |
| **layer 配置** | 基底が `layerTxn` を開き、その中で open `positionLayers()` を呼ぶ（CATransaction 二重 begin 防止） | 基底は focus-ring のみ配置 | 各部品が自分の layer を `positionLayers()` で配置 |
| **focus-ring の形** | open（path shape を返す） | — | Button=選択角 / FAB=円 / Checkbox/Chip=全角 pill |

注:
- **Checkbox は「scaffold consumer」** = 相互作用の骨組みだけ基底から受け取り、値セマンティクスは100%サブクラス（基底は値を一切持たない）。
  flash 後がトグルになる差は open `keyboardActivate()` の seam で吸収。
- **fx computed は副作用なし（純粋）を維持** = `applyState` 中に基底へ再入しない（Swift6 + retain-cycle 安全）。

## 4. セクション C — トークン配線（パート2）

#13 が radius/gap リテラルの大半を既に配線済（Button/Chip-keycap=`Radius.sm`・Checkbox=`Radius.xs`・TextField/ToolBar/ComboBox=
`Radius.lg`・Menu/List=`Radius.md`・Tooltip/Skeleton=`Radius.sm`・Border=`Radius.xl`／gap も Button/FAB/ToolBar/Tooltip=`Space.md`・
Checkbox/ComboBox/Menu=`Space.xs`・TextField padX=`Space.lg`・Divider middleInset=`Space.xl`）。**これらは再配線しない。**

残る唯一のクリーンな勝ち筋 = **focus-ring outset の集約**:
- 今は4つの 2pt リテラルが重複 — Button(`-2`)・Chip(`-2`)・Checkbox(`focusInset:-2`)・FAB(`ringInset:+2`)。
- → 基底 `focusRingOutset = Space.xxs(2)` 1本に。**inset(-2) と角丸 +2 の両方**を駆動し同心円を保つ（ペアを崩すとリング剥離）。
- **符号トラップ**: Checkbox/FAB は `+2` を保持し使用時に反転、Button/Chip は `-2` 直書き → 基底で符号を1箇所に正規化。

**据え置き**: List Metrics gap（ユーザー判断・§1）／その他 #13 配線済リテラル。
**exempt（トークン化しない）**: 制御サイズ/variant の Metrics 帯（Button hpad/heights/minWidth・Chip hpad・FAB 直径・ToolBar gutter）・
Chip gap=5（off-grid）・Chip outerAdj=-2（icon-tuck = ring outset と意味が逆・同 seam に通さない）・1〜2px hairline/stroke・
alpha（0.06/0.08/0.12/0.16/0.5）・0.12 flash duration（Motion の関心事）・サイズ派生丸み（pill h/2・circle min(w,h)/2）。
**同値別意味トラップ**: `2` は ring outset(Space.xxs) でもあり Checkbox box radius(Radius.xs) でもあり List lineGap でもあり grip dot サイズでもあり
stroke 幅でもある — Space.xxs 候補は outset と lineGap だけ（lineGap は据え置き）。

## 5. スコープ外 / 将来 follow-up（暗黙にしない）

- **ToolBar + ButtonGroup** → 将来「**ThemedContainer 基底**」（per-item/segment 枠・color=inherit palette remap・flex layout・
  roving focus・per-item hover）。今は #14a leaf ヘルパのみ共有・子 ThemedControl を内包する形を維持。**別 ROADMAP 項目**として登録。
- **CornerPath 抽出** → 据え置き（rule-of-three 未達・消費者 = ThemedButton 1つ）。`closedCornerPath`/`borderPath` インライン継続。
- **ToolBar 独自 elevation 曲線**（`palette.shadow(.dpN)` 非経由）→ 別件（Elevation 整合）であって #14b ではない。
- **leaf 5部品**（ComboBox/Menu/Tooltip コントローラ・TextField・List）→ leaf のまま無改変。構造的理由 = interactive control 表面でなく
  controller/popup/text view であり、基底の単一コントロール契約に乗らない。

## 6. 検証ゲート

- `swift build` 緑（ローカル CLT バー）。
- **値保存**: hover/press/focus/flash/ring の挙動バイト等価。意図的な値変更ゼロ → prism before/after は一致するはず。
- **prism before/after ライブ撮影**（hover/pressed/focused/disabled）= Button/FAB/Checkbox/Chip + ToolBar + ComboBox or Menu
  （共有ヘルパ経路の回帰捕捉）。**ライブ目視は maintainer 委譲**（agent は画面収録不可）・`preview*` で決定論撮影。
- **XCTest（CI のみ）** = fx 合成ロジック・`focusRingOutset` 同心円計算・無効化クリア契約。`swift test` は CLT ローカル不可＝
  **CI だけが守るゲート**（sweep-include-tests 教訓・Tests/ も忘れず点検）。
- **敵対的レビュー**（#14a 同様 multi-agent: 正しさ / Swift6・CLT / 忠実度 / 規約整合）。

## 7. リスク（Swift6 / @MainActor / 継承）

- swift-tools 6.0 = フル Swift 6 言語モード。基底は一貫して `@MainActor`（全 adopter + Shared.swift も @MainActor）。open メンバは暗黙
  MainActor 隔離・サブクラス override も全モジュール @MainActor なので nonisolated 事故なし。
- `public class`（not `open`）で in-module 継承＝API 安定性負担回避。アプリは合成のみ（leaf 監査で継承ゼロを確認済）。
- セルレス NSControl: 無効化後始末は `final` + `didDisable()` フックにし、isEnabled setter override を避ける（super 呼び忘れで
  stuck-hover 復活を防ぐ）。
- `flashThenActivate` の `DispatchQueue.main.asyncAfter` [weak self] は @MainActor 再入 — flash を完全に @MainActor 基底内に置き、
  `activate()` を nonisolated にしない。
- `init?(coder:)` は全部品で `@available(*, unavailable)` + nil。基底に designated `init(palette:)` + unavailable `required init?(coder:)`。
- layer 所有の継承境界: base が focus-ring layer 所有・サブクラスが残り。base の `layout()`/`viewDidChangeBackingProperties` は super →
  サブクラスが配置。**CATransaction 二重 begin 回避** = base がトランザクションを開き、その中で open `positionLayers()` を呼ぶテンプレ。

## 8. 実装順（writing-plans へのシード・PR 形）

1. `Sources/ThemeKit/ThemedControl.swift` 新設（基底 + seam の口 + focus-ring + flash ヘルパ + `focusRingOutset`）。
2. **ThemedButton** を最初の adopter に（最も full な control = 基底契約のリファレンス）。before/after 撮影で基準を取る。
3. **FAB → Checkbox → Chip** の順で adopt（Chip が最多 seam = press 2-target / 二重ゲート / no-flash を最後に踏ませて seam を実証）。
4. focus-ring outset 4重複を基底トークンへ集約（符号正規化）。
5. XCTest（CI）+ 敵対的レビュー + maintainer ライブ撮影。
6. green CI → squash-merge + `v<x.y.0>` タグ + ROADMAP #14b 完了（library 変更ありなのでタグ付与）。

> 単一ディレクトリ運用・ブランチ `feat-14b-themedcontrol`（origin/main 先行）。[[parallel-work-hazard]]: clean origin/main から隔離・
> タグ前に版未使用を確認。[[ci-green-merge-ok]]: green + clean → squash-merge + タグ + ROADMAP 完了を再質問なしで。
