# #15 — ヘッドレス純粋核 + 相互作用/a11y（設計）

> 親 spec: [`2026-06-22-sill-generalization-and-swiftui-design.md`](2026-06-22-sill-generalization-and-swiftui-design.md) の Phase 1 / #15。
> 本 spec はその #15 を実装可能な粒度まで具体化したもの。
> 状態: **設計合意済（ユーザー方向確定 2026-06-23）**。スコープ＝**焦点版**（ユーザー裁定）。
> 調査: 6 並列 agent（List 解剖・ComboBox・Menu・seam・a11y マトリクス・pure module 慣習）+ 統合 1 agent
> = 計 7 agent / 470k tokens で事実を固めた版。

## 0. 一行サマリ

複雑な stateful widget（List → ComboBox/Menu）から **Foundation のみ・Sendable の AppKit-free な
純粋核**を抽出し（新規 module `ListCore`）、**controlled/uncontrolled seam** を契約として明文化し、
**a11y を監査して通知欠落と value 属性を補完**する。すべて**バイト等価リファクタ + additive**
（見た目/挙動の変化なし）。

> **#15 の主目的（実証で訂正・2026-06-23）**: この repo の `swift test` は **CLT-only マシンでは走らない**
> （XCTest.framework が無く `import XCTest` が失敗・`xcrun --find xctest` も失敗。Motion/Gesture の純粋
> テストも実は CI でしか走らない。local gate は従来どおり `swift build`）。よって純粋核の価値は
> 「CLT でテストできる」ことでは**ない**。主目的は ①**#16/#17 の SwiftUI 共有核**（クリティカルパス
> #13→#15→#17＝AppKit/SwiftUI 両実装が同じ純粋ロジックを使う）・②**AppKit-free な隔離テスト**
> （window/@MainActor/GUI を要さない純粋 XCTest を **CI で**・現状 `_moveHighlight` 等の seam は
> ThemeKitTests＝AppKit セットアップ要 → 純粋核なら AppKit-free に）・③ Radix 的 behavior/style 分離。

## 1. スコープ（焦点版・ユーザー裁定 2026-06-23）

### IN
- 新規 pure module **`ListCore`**: 選択 resolver + highlight ナビ（roving）+ ComboBox の
  filter/free-solo/index-reconcile + Menu の keycode→action マップを 1 モジュールに集約。
- ThemedList / ThemedComboBox / ThemedMenu を「核を呼ぶ薄いラッパ」に（公開 API 不変・バイト等価）。
- **controlled/uncontrolled seam** の契約化（明文化 + 不足部品に「発火 setter」追加）。
- **a11y P0/P1**: `NSAccessibility.post` ヘルパ（系統的欠落の解消）+ stateful 部品の value 属性。
- DESIGN.md `### Adding a widget` 節を **a11y / seam / 純粋核**要件で拡張（チェックリスト化）。
- 新規 `ListCoreTests`（AppKit-free な純粋 XCTest・**CI で実行**）+ 既存 full-Xcode-only seam テストの repoint/複製。

### OUT（将来項目・暗黙にしない）
- **`typeAheadMatch`（前方一致ジャンプ）**: focused では consumer ゼロ（ComboBox は contains
  フィルタ＝prefix-jump ではない・Menu は矢印のみ・bare List 配線は繰延）。投機的抽象を避ける
  repo 文化（#14a CornerPath・#14b ToolBar/ButtonGroup container 見送りと同型）に従い **#15 では作らない**。
  consumer が出る #17 SwiftUI / bare-List 配線時に追加。
- **DnD/幾何核の移設**（`resolveDropTarget`/`dragCandidates`/`chunkMemberIDs`/`stickyHeader` 等）:
  既に pure かつ test seam 有り（テストは CI 実行）。ListCore へ移せば AppKit-free に隔離できる（テストは依然 CI）が、
  選択+highlight が load-bearing 80%。**繰延**（包括版送り）。
- **最大 a11y**（P2/P3）: RowAX の checked を label 文字列→真の value 属性化・ComboBox の row-AX
  vending を ON 化・ToolBar ラベル・Tooltip 再 sync。**繰延**。
- **多選択 `.multiple`**: コードに `// no .multiple（YAGNI）` が既に在る。どのアプリも未要求。
  `ListSelection.Mode` は `.none`/`.single` のまま（現状一致）。

## 2. モジュール構成と依存グラフ

新規 **`Sources/ListCore/`**（Foundation のみ・全型 `Sendable`/`Equatable`・CG 便宜は
`#if canImport(CoreGraphics)` で gate＝Motion/Gesture と同テンプレ）。**AppKit-free な純粋 XCTest**
（window/@MainActor/GUI 不要）＝ Motion/Gesture と同様 **CI で実行**（`swift test` は CLT 不可・§0 参照・
local gate は `swift build`）。主目的は #16/#17 SwiftUI 共有核 + 隔離テスト + Radix 分離（§0）。

- **命名衝突回避**: module 名は `ListCore` だが**主要型を `ListCore` と名付けない**
  （Palette/ThemeSpec が避ける module==type 衝突を踏襲）。型は `ListSelection`、自由関数
  `resolveSelection` / `nextHighlight`、Combo 用 `comboFilter` 等、Menu 用 keycode マップ。
- **同梱**: combo/menu の純粋ロジックは別モジュールにせず **ListCore 内の別ファイル**
  （`ListSelection.swift` / `Highlight.swift` / `ComboLogic.swift` / `MenuLogic.swift` など）。
  compose 順序は import 関係ではなくファイル同居で満たす（小さい純粋ロジック）。
- **Package.swift 配線**（既存 pure leaf と同形）:
  - `.library(name: "ListCore", targets: ["ListCore"])`
  - `.target(name: "ListCore")` ← 依存ゼロの leaf
  - `.testTarget(name: "ListCoreTests", dependencies: ["ListCore"])`
  - `ThemeKit` の `dependencies` に `"ListCore"` を追加
- **依存グラフ**: `ListCore`（何にも依存しない）← `ThemeKit`。**acyclic 維持**・pure 側は AppKit を
  一切リンクしない。将来 #16/#17 の SwiftUI 層も同じ核を共有可能。

## 3. `ListCore` の API と「薄いラッパ化」

核は**値（index/id + 選択可能性の射影）だけ**を受ける純粋関数群。各 widget は公開 API を保ったまま
内部実装だけを核に委譲＝**バイト等価リファクタ**（#14a/#14b と同じ安全性）。

> **最重要制約（検証済・交渉不可）**: `ListItem.image: NSImage?`（ThemedList.swift 付近）と
> `Badge.symbol: NSImage?` は**非 Sendable**。よって `ListItem` を核に渡せない。核の全シグネチャは
> AppKit 側が reload 毎に 1 回計算する **index/id + selectability の射影**を受ける。将来「便宜のため
> ListItem を核に渡す」と純粋契約が壊れ module が AppKit を transitively リンクする＝禁止。

### (A) 選択モデル — `setSelection` の純粋化
```swift
public struct ListSelection: Sendable, Equatable {
    public enum Mode: Sendable { case none, single }   // .multiple は持たない（YAGNI・現状一致）
}
public func resolveSelection(proposed: String?, current: String?,
                             mode: ListSelection.Mode,
                             selectable: (String) -> Bool) -> (resolved: String?, didChange: Bool)
```
`.none` は常に nil／`.single` は `selectable(id)` の時のみ id 保持。ThemedList の `setSelection` は
「核を呼ぶ→invalidate/scroll/発火」の薄いラッパに。`selectable` は AppKit 側の `isSelectable`
（`!header && !separator && !disabled`）をクロージャで渡す。

### (B) highlight ナビ（roving）— `moveHighlight` の検証済み純粋ボディを移設
```swift
public func nextHighlight(current: Int?, delta: Int,
                          selectableIndices: [Int], wraps: Bool) -> Int?
```
wrap = `((pos+delta)%n+n)%n`、clamp = `min(max(pos+delta,0),n-1)`、空→nil、current なし→delta 符号で
先頭/末尾。入力は**選択可能 index の `[Int]`**（items ではない）。action-row 特例（`isActionRowActive→0`）は
AppKit 側ガードとして残す。**List/ComboBox/Menu の 3 部品が共有**（rule-of-three 達成）。

### (C) ComboBox 純粋ロジック（ListCore 内 `ComboLogic.swift`）
- `comboFilter`（既存 `defaultFilter` の `localizedStandardContains` を昇格・既に nonisolated）
- index↔id マッピング（`effectiveHighlight` 相当）/ options 変化時の選択 index 再 reconcile /
  free-solo commit 判定 — すべて Foundation のみ。
- ComboBox は `NSObject` controller で `private var list: ThemedList!` を所有（list は highlight のみ・
  combo は committed selection を所有）＝**widget 層で既に compose 関係**。核層もこれを鏡写しにする。

### (D) Menu 純粋ロジック（ListCore 内 `MenuLogic.swift`）
- `handleKeyDown` の keyCode→action マップを純粋な「イベント→意図」テーブルに
  （DispatchQueue タイマ・submenu cascade の副作用は AppKit 側に残す）。
- Menu も `NSObject` controller で `private let list: ThemedList` を所有＝同じ compose 関係。
- ⚠ `MenuItem→ListItem` 変換は NSImage を載せた `ListItem` を生むので **AppKit 側に残す**。

### テスト
- 新規 **`ListCoreTests`**（A〜D を AppKit-free な純粋 XCTest で・**CI 実行**）。
- ⚠ 現在 `_moveHighlight`/`_stickyHeader`/`_resolveDropTarget` 等の seam テストは **full-Xcode CI でしか
  走らない `ThemeKitTests`** にある。核へ移すロジック分（A/B/C/D）は **ListCoreTests に repoint/複製**
  して orphan させない（[[sweep-include-tests]]）。DnD/sticky の seam は移設対象外（OUT）なので据置。
- ⚠ 整数 wrap/clamp は安全だが、もし将来 DnD 幾何（y-offset Double）が核に入る時はテストを
  **2 進で厳密な Double（0.25/0.5/0.75）**で書く（Motion #6 の Tween.isComplete CI-only 赤の教訓）。

## 4. controlled/uncontrolled seam の契約化

**新しい型は作らない。**既にコードに在る一貫パターンを*命名・明文化*し、不足部品に「発火 setter」を足す。

**既存契約**（4 部品で一貫）: 値は widget が所有。**プロパティ代入 = silent（callback 発火しない）**。
**ユーザー操作のみ callback が新値を発火**。host が callback 内で値を再代入 = controlled 相当。
List が既に持つ「2 ドア」`selectedID=`(silent) / `selectRow(_:)`(発火) がテンプレ。

| 部品 | 現状 | #15 で足す発火ドア |
|---|---|---|
| **List** | `selectedID=`(silent) / `selectRow`(発火) | ✅ 既に 2 ドア（テンプレ） |
| **Checkbox** | `isChecked=`(silent) / `toggle(fromUser:)`(発火・トグルのみ) | `setChecked(_:notifying:)` |
| **ComboBox** | `selectedIndex=`(silent) / user commit のみ `onSelect` | `commitSelection(_:)` |
| **TextField** | `stringValue=`(silent) / `clearText()`(発火) / keystroke `onChange` | `setText(_:notifying:)`（`clearText` を一般化） |

**やらないこと**: `@Binding<T>` / protocol 注入 get/set は**導入しない**（`isChecked = true` /
`stringValue = x` の既存 caller を全て壊す＝却下）。seam は「callback が唯一の統合点」のステートレス設計
のままが正しい。#15 の仕事は silent vs 発火の非対称を **call site で明示的**にすること。

## 5. a11y P0/P1 補完（監査→不足補完）

**正準契約**: 非装飾 widget は `{ role, label, value(stateful時), enabled }` を出し、**値/選択の変更時に
AX 通知を post**する。装飾系（Border/Divider/Skeleton/Scroller）は設計上 exempt。

**唯一の系統的欠落（grep 実証済み）**: `NSAccessibility.post` が **ThemeKit 全体でゼロ件**＝VoiceOver に
変更を一切通知していない。`setAccessibilityValue` も Checkbox 1 ファイルのみ。

- **P0（横断・1 ヘルパを全所に）**: 値/選択の変更点に `postAXValueChanged()`/`postAXSelectionChanged()`
  を入れる共有ヘルパ（`Shared.swift` に追加）。Checkbox/Chip/ComboBox/Menu/List/ButtonGroup/TextField の
  critical gap を一括で閉じる。
- **P1（stateful 部品の value 属性）**:
  - Checkbox: value は既に有り（tri-state -1/0/1）→ **post 追加のみ**
  - Chip(`isSelected`) / ComboBox(`selectedItem`) / List(`.single` 選択行) / ButtonGroup(`selectedIndex`) /
    TextField(`stringValue`): **value 属性 + post**
- **発火ルール（重要・flood 対策）**: post は**確定変更（ユーザー操作 callback の地点）でのみ**。
  毎キーストローク/毎 highlight 移動では出さない。§4 の seam「発火ドア」と同じ地点に乗る。
- **繰延**（OUT）: RowAX checked の value 化・ComboBox row-AX vending・ToolBar ラベル。

## 6. 「Adding a widget」チェックリスト（DESIGN.md `### Adding a widget` を拡張）

既存節（rule-of-three + prism mandate）に以下を追記し、新規 widget の gap 再発を防ぐ:
- a11y: role / label / value(stateful) / enabled / **変更時 post**（§5 契約）
- controlled/uncontrolled の **2 ドア**（silent 代入 + 発火 setter＝§4）
- 決定論プレビュー seam（`preview*`）— 既存記述を維持
- 複雑 stateful なら**純粋核（ListCore 流儀）にロジックを置き AppKit-free な XCTest**（CI 実行）

## 7. 検証方針

- **`swift build` 緑 = ローカル唯一のゲート**（CLT・Xcode 無し）。
- **`ListCoreTests`（新規・AppKit-free 純粋 XCTest・CI 実行）** = 核ロジックの隔離検証（local gate は `swift build`）。
- **`ThemeKitTests`（CI・full Xcode）** = バイト等価リファクタの回帰ネット。核移設分の seam テストは
  repoint/複製（[[sweep-include-tests]]）。
- **敵対的レビュー**（#14a/#14b 同様・複数観点 × 独立検証 → confirmed defect 0 を目標）。
- **prism**: 焦点版は**見た目/挙動の変化なし**（核委譲・a11y 通知・seam 明文化）→ ライブ目視の負担最小。
  a11y の VoiceOver 検証は maintainer に委譲（agent 不可・[[chomp-push-gate]] 同型）。
- **実装は origin/main 起点の隔離 worktree**で（[[parallel-work-hazard]]＝maintainer + 別 Claude セッションが
  同 repo を並行作業中）。version は claim 前に未使用確認。library 変更なので **minor bump + `v`-tag**。

## 8. 決定ログ（解決済みオープン質問）

| 質問 | 決定 | 理由 |
|---|---|---|
| モジュール分割 | **単一 `ListCore`**（combo/menu も同梱） | combo/menu の純粋面は小（filter 1 個・keycode マップ）・compose 順序はファイル同居で満たす |
| type-ahead | **#15 では作らない（OUT）** | focused では consumer ゼロ＝投機的抽象（repo 文化に反） |
| 多選択 | **`.single` のまま** | `// YAGNI` がコードに既存・未要求 |
| a11y 深度 | **P0/P1 のみ** | 高価値・低リスク・P2/P3 は繰延 |
| controlled setter | **発火ドアを足す + 明文化**（@Binding なし） | call site で明示化・全 caller 非破壊 |
| DnD/幾何核 | **繰延（OUT）** | 選択+highlight が load-bearing 80%・DnD は行数大/リスク低 |
| PR 形 | writing-plans で確定（焦点版は additive 主体なので 1 PR が既定線） | — |

## 9. リスク

1. **NSImage が load-bearing 制約**: `ListItem.image`/`Badge.symbol` 非 Sendable → 核は ListItem を取れない。
   全シグネチャは index/id + selectability 射影。違反すると module が AppKit を transitively リンク。
2. **非-Foundation を核に入れない**: `fittingWidth`（NSString.size/NSFont 呼び）は **Foundation 純粋でない**
   ＝核に入れない（ThemeKit 側に残す）。テストは全て CI 実行（`swift test` は CLT 不可）なので、`_moveHighlight`
   等の既存 seam テストは核移設分を **ListCoreTests へ repoint/複製**し orphan させない（[[sweep-include-tests]]）。
3. **seam 後方互換**: @Binding/protocol 注入は全 caller 破壊＝却下。レビューで「正式 Binding」を押されても拒否。
4. **a11y 通知 noise**: 毎キーストローク/毎 highlight で post すると VoiceOver flood。**確定変更のみ** post。
5. **combo/menu の list 設定は init で 1 回**（後続プロパティ変更を forward しない）。核抽出はこれを変えないが、
   新 knob を足す時は wire 漏れに注意。
6. **行番号はスナップショット**: 本 spec の file:line は調査時点。**実装は隔離 worktree（origin/main 起点）で
   行番号を再確認**してから着手（local main は stale になり得る・並行セッション hazard）。
7. **prism live-proof ゲート**: 焦点版は視覚変化なしだが、もし可視挙動が混入したら prism showcase +
   maintainer 実機確認が必要（[[chomp-push-gate]] 同型）。

## 10. 内部順序（実装の前後関係）

1. `ListCore` モジュール新設（空 + Package.swift 配線・`swift build` 緑）
2. (A) 選択 resolver + (B) highlight ナビ → ThemedList 委譲 + ListCoreTests（**最も additive・低リスク・最初**）
3. (C) ComboBox 純粋ロジック → ThemedComboBox 委譲
4. (D) Menu 純粋ロジック → ThemedMenu 委譲
5. §4 seam の発火ドア追加（Checkbox/ComboBox/TextField）
6. §5 a11y P0 ヘルパ + P1 value 属性（横断）
7. §6 DESIGN.md チェックリスト拡張
8. 検証（swift build / ListCoreTests / 敵対的レビュー / CI）

詳細ステップは writing-plans で実装プランに展開する。
