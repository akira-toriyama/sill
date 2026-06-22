# sill 汎用化 + SwiftUI 化 + 各アプリ適用 — 設計 (#13〜)

> 状態: **設計合意フェーズ**（ユーザー方向確定済 2026-06-22）。実装は別セッション可。
> 進捗 SSOT は `docs/ROADMAP.md`（このファイルは設計の根拠・決定記録）。
> 調査根拠 = 14-agent workflow（2026-06-22）: sill API/DRY 棚卸し・Radix/Tailwind/MUI マッピング・SwiftUI gap・5アプリ UI 構造（懐疑検証付き・全件 confidence high）。
> 本 spec は **4観点の敵対的レビュー（実現可能性/Swift6/CLT・順序・抜け漏れ・規約整合）で固めた版**（7 must-fix + 主要 should-fix 反映済 2026-06-22）。

## 1. 目的（ユーザー要望）

1. **sill ブラッシュアップ**: Radix UI / Tailwind / MUI の良い部分を取り入れ、汎用化・DRY 化。
2. **各アプリ適用**: facet 等を「sill に寄せる」。当初要望は「脱AppKit して sill の SwiftUI に乗り換え」。

前提（ユーザー 2026-06-22）: 各アプリは個人開発・**破壊的変更すべてOK・長時間リファクタOK**・品質重視・プラン再作成OK・1セッションで全部やらなくてよい・**未達成を暗黙にしない**。

## 2. 調査で判明した決定的事実

- **5アプリ（facet/wand/perch/halo/glance）は全て 100% AppKit・SwiftUI ゼロ・sill ThemeKit ウィジェット利用ゼロ。** sill は `Palette`/`PaletteKit`/`Effects` を「色・アニメ・設定エンジン」としてのみ消費し、画面に出る chrome は**全部自前で手描き**。
- **SwiftUI でウィンドウを作る（`WindowGroup`/`Window`/`Scene`）と必ずアプリがアクティブ化＝フォーカスを奪う。** これは全アプリの存在理由（非アクティブ overlay）を壊す。各アプリの土台（`.nonactivatingPanel`・クリックスルー window・CGEventTap・Carbon hotkey・Accessibility・per-pixel CG 描画）は **SwiftUI が表現できない**領域＝労力に関係なく「脱AppKit」は成立しない。
- **しかし NSHostingView で SwiftUI を“中身として”載せる分には非アクティブ性は保たれる**（フォーカスは奪わない）。**ただし非アクティブ/条件付き key パネル内 SwiftUI の副作用は複数あり、移行前に spike で検証する**:
  1. 標準キーボード入力（`TextField`/`.onKeyPress`）は panel が key にならないと効かない（各アプリは CGEventTap/条件付き key 化で対応中）。
  2. focus-ring: SwiftUI 既定の focus ring は key window 前提で、非 key パネルでは欠落/不自然（既存 AppKit 部品が focus ring を手描きしているのはこの理由）。
  3. NSAppearance 伝播: `NSHostingView` は host パネルの `effectiveAppearance` を自動継承しない（SwiftUI `Color` 解決＝下記④に直結）。hosting view に appearance を設定して橋渡しが要る。
  4. first-responder 連携: panel が条件付き key になる時、AppKit first-responder と SwiftUI `@FocusState` は別系統で手動ブリッジが要る（facet KeyablePanel・glance becomesKeyOnlyIfNeeded）。
- **sill には現在 SwiftUI の部品が無い。** SwiftUI は prism の中だけで、しかも AppKit 部品を包む `NSViewRepresentable` ブリッジ（**25 構造体・うちウィジェット橋は ~14、残りは Effects/PixelArt/デモ橋**）の形。
- **sill の汎用化の穴**: 色ロール＋TypeScale は成熟。だが **spacing / radius / elevation スケールが無い**（`radius:4`/`radius:2`/`cornerRadius=6`/`gap:8` が各部品に散乱）。
- **motion トークンは既に存在する（新規ではない）**: `Motion` モジュールに `ThemedTransition.Duration.enter = 0.16` と `Easing.standard = cubicBezier(0.4,0,0.2,1)` がある。問題は **ThemeKit が `Motion` に依存しておらず**（`import Motion` 無し）、`0.16` リテラルが **14 ファイルにコピペ**されていること＝「新規追加」ではなく「**配線**」が本体。
- **DRY 違反が大量**: hover/press/focus 状態（`fxHovered`/`fxPressed`/`fxFocused`）は Button/ButtonGroup/Checkbox/Chip/FAB/ToolBar の **6 ファイル**／mouse trio（enter/exit/down）は **10 ファイル**（ComboBox/List/Menu/TextField/Tooltip/ToolBar 含む）／`layerTxn`×11／`backingScale`×14／role switch×6／focus-ring setup×4／`ink(on:)` は `PaletteKit.bestContrast`(internal) があるのに 6 ウィジェットで再実装。
- **Radix/Tailwind/MUI 採用方針**:
  - 採用: spacing/radius/elevation トークン（Tailwind/MUI）・variant/size/role 統一＋共有 `ThemeRole`＋`palette.color(for:)`（MUI）・controlled/uncontrolled 状態（Radix）・NSAccessibility 契約（Radix の原則を AppKit に・**現状の監査→不足補完**）・複雑部品のヘッドレス純粋核（Radix の behavior/style 分離・CLT テスト可）・既存 `Motion` トークンへの配線（MUI theme.transitions）。
  - 却下（web 専用）: utility-class 文字列（Tailwind `className`）・responsive/`dark:` 接頭辞・`sx` 任意スタイル注入（sill 契約違反）・`asChild` リテラル（AppKit に DOM ラッパ税が無い）・Portal/Presence（`PopupPanel`/`CATransaction` で native 解決済）。

## 3. 確定した方向（ユーザー裁定 2026-06-22）

- **item2 = ハイブリッド（A→B）**: まず A（prism のウィジェット橋を公開 `ThemeKitUI` に昇格して sill を SwiftUI 対応に）→ **部品ごとに順次 B（ネイティブ SwiftUI 再実装）へ昇格**。旧 AppKit 版は「まだ使う部品だけ」一時併存させ、置換完了後に撤去（二重維持を部品単位の短期間に限定）。
- **アプリの姿 = AppKit の薄い殻 + 中身 SwiftUI-on-sill**: 非アクティブ panel・event tap・AX は AppKit のまま、中身（手描き chrome）を `NSHostingView` で新 sill SwiftUI 部品に載せ替える。
- **Effects/装飾（border/particle/pet/pixelart）は当面 AppKit のまま**（A でラップ or 既存描画を hosting）。これらは interactive widget でなく装飾で、SwiftUI Canvas への描画移植は数式以外フルリライトなので、**B のスコープは interactive ウィジェットに限定**し装飾の Canvas 化は別判断（必要時のみ）。
- **順番 = item1（ブラッシュアップ）が先**: トークン（pure・platform 非依存）とヘッドレス純粋核（AppKit/SwiftUI 両方が共有・CLT テスト可）は **B の前工事そのもの**。先に作ると B が安く・安全になる。
- **アプリ適用の順 = glance → perch → wand → facet（facet 最後・ユーザー指示）**。halo は描画のみ（click-through RingView・`ignoresMouseEvents`）で SwiftUI ウィジェット/入力の検証にならないため**先頭から外し**、#13 トークン消費のタッチアップとして随時。glance を先頭にするのは、小さく（~1,966 LOC）既に PaletteKit を消費し、実 NSPanel+NSScrollView chrome があり「NSHostingView in 非アクティブ panel + sill 消費」を小規模で実証できるから。
- **入力 spike（facet/wand 着手前の必須前提）**: 「`becomesKeyOnlyIfNeeded` な NSHostingView パネル内の SwiftUI `TextField`/`.onKeyPress`/focus-ring/`@FocusState` ブリッジ」を prism か glance で先に検証してから、SwiftUI-content 経路を facet/wand に確約する。

## 4. 分解（#13〜）

### Phase 1 — sill ブラッシュアップ（全部 sill 内・additive/リファクタ・B の前工事）

- **#13 トークン基盤**
  - pure `Palette` に `Space`/`Radius`/`Elevation` スケール（`Double`/`Int`・`Sendable`・`TypeRole`/`InkTier` と同じ「固定内部スケール」流儀＝`ThemeSpec`/config には載せない）。**新規なのはここと、`PaletteKit` の `Elevation`→(opacity,blur,dy) 解決表**。
  - motion は新規追加せず**配線**: `ThemeKit` の target deps に `Motion` を追加し、14 ファイルの `0.16` リテラル/`CATransaction` を `ThemedTransition.Duration.enter`/`Easing.standard` に置換。
  - 各 ThemeKit 部品の散乱リテラル（`radius:4` 等）をトークンに置換。
  - 非対象: 制御サイズ別レイアウト（button 高さ 30/36/42・hpad 帯）は各部品 `Metrics` に残す（DESIGN.md §5「正当な control-size layout」）。
  - **halo タッチアップ**（随時・#13 のトークン消費先・SwiftUI 移行ではない）。

- **#14 DRY 集約 + 共有基盤**（#14a はトークン非依存＝#13 と並行/先行可、#14b は #13 後）
  - **#14a（トークン非依存・即着手可）**: 共有 `layerTransaction`／`PaletteKit.bestContrast` を public 化（6コピー削除）／`NSView.themeBackingScale`／`CornerPath`／共有 `ControlRole` + `palette.color(for:)`／重複 `Elevation` struct（Button/FAB 逐語コピー）の統合。
  - **#14b（#13 後）**: 散乱リテラルを #13 トークンへ配線。
  - **本丸 `ThemedControl: NSView` 基底**: hover/press/focus 状態・tracking area・mouse trio・first-responder・Space-activate・flash・focus-ring・`preview*`/`fx*` を一本化。サブクラスは `applyState`/`activate()` のみ。Button の「クリックで first responder を取らない」・Chip の「2ターゲット hover」等は**オーバーライド可能な seam** として露出。
  - **採用範囲の明示**: 完全採用＝Button/FAB/Checkbox/Chip（+ToolBar の fx-state）。ComboBox/List/Menu/TextField/Tooltip は leaf ヘルパ（`layerTransaction`/`backingScale`/`CornerPath`）のみ共有（基底は被せない）。
  - 検証ゲート: prism の `preview*` で hover/pressed/focused/disabled をライブ撮影（before/after）＝**Button/FAB/Checkbox/Chip に加え ToolBar と ComboBox or Menu も**（hover 経路が共有ヘルパを通るため回帰を捕捉）。

- **#15 ヘッドレス純粋核 + 相互作用/a11y**（**内部順序: ThemedList 核を先に**）
  - ComboBox/Menu は ThemedList を**コンポーズ**している（peer ではない）。よって **(a) ThemedList の純粋核（選択モデル・`highlightedIndex`/roving・type-ahead）を先に抽出 → (b) ComboBox/Menu 核は List 核に依存**（filter/free-solo/anchor を薄く重ねる）＝AppKit の合成関係を踏襲。3つ並列に剥がさない。
  - 純粋核は Foundation のみ・`Sendable`・**CLT で XCTest 可能**（AppKit/SwiftUI 両実装が共有）。
  - controlled/uncontrolled 状態 seam（AppKit の `@Binding` 相当）を stateful 部品（Checkbox/ComboBox/TextField/List 選択）に明示。
  - **a11y は「監査→不足補完」**（全 15 ウィジェットは既に NSAccessibility を参照済＝ゼロからではない）。各部品の現状被覆を棚卸し → 正準契約（role/label/value/enabled + 変更時 post）を定義 → 不足だけ追加。「Adding a widget」チェックリスト化（DESIGN.md §5）。

### Phase 2 — sill を SwiftUI 化（item2 の A→B）

- **#16 SwiftUI 提供層（A）**（Phase 1 完了を待たず #14a と並行可＝橋は既存・現行ウィジェットの上で成立）
  - prism の**ウィジェット橋 ~14個**（Field/Button/ButtonGroup/Checkbox/Chip/FAB/Divider/Border/Skeleton/Tooltip/List/Menu/ComboBox/ToolBar）を**公開モジュール `ThemeKitUI`**（deps=`ThemeKit`/`PaletteKit`）に昇格。**Effects/PixelArt/デモ橋（NeonCorridor/Particle/Splatter/LinePet/PixelArt/HeavyRule/IconBar 等）は除外**（widget 製品に Effects/PixelArt 依存を引き込まない＝必要なら別製品 `EffectsUI` で別判断）。
  - **prism を ThemeKitUI の最初の consumer に**: 昇格後 prism は `import ThemeKitUI` し、**自分の重複橋を削除**、`Package.swift` の prism deps に `ThemeKitUI` 追加（in-tree 橋ゼロ＝ドリフト禁止を満たす）。
  - palette は `Color(nsColor:)` ラッパ（`ResolvedPalette` 上）で **動的 appearance 追従を維持**。**resolver は @MainActor のまま**（system 動的色 `.controlAccentColor` 等の解決は current NSAppearance 下の main-actor 操作）。`Color`/`Font` の値だけが Sendable。RGBA への eager flatten は静的スナップショットが必要な時のみ。
  - 制約: **CLT でビルド可能を維持**（Xcode 専用 `#Preview` マクロ等は禁止＝SwiftDraw `<0.25` ピンと同じ理由）。`NSHostingView`/`NSViewRepresentable` は CLT で動く（prism が実証）。
  - 1実装（AppKit 部品をそのまま）・忠実度 100%・最低リスク。

- **#17 ネイティブ SwiftUI 部品（B・部品ごと）**（#13+#15 後＝トークンと純粋核が要る）
  - #13 トークン + #15 純粋核を土台に、interactive ウィジェットを順次ネイティブ SwiftUI `View` へ（`NSColor`→`Color`・`CAAnimation`→`withAnimation`/`TimelineView`）。
  - 着手順: 簡単（Divider/Chip/Skeleton/Badge）→ 複雑（TextField の IME/ComboBox/ToolBar）は当面 A のラップ維持。公開 API を安定させ、A→B の差し替えを consumer に不可視に。
  - **決定論プレビュー機構（必須・新規）**: AppKit の `preview*` 相当を SwiftUI にも用意（注入式 interaction-state enum / 固定-`now` `TimelineView` seam）＝prism 静止スクショを決定論に保つ。
  - **検証ゲート**: `swift build` は型検査のみで SwiftUI レンダ/アニメを動かさない・CI に prism 起動/スクショ無し・agent は画面収録不可 → **SwiftUI アニメ/見た目の確認は maintainer の実機ライブが前提**（agent の「動いた」主張は maintainer ライブ確認でゲート＝[[chomp-push-gate]] と同型）。prism に SwiftUI showcase（AppKit 版と並置でドリフト検出）。
  - Effects/装飾の Canvas 化は**スコープ外**（§3 のとおり当面 AppKit ラップ）。やるなら数式（pure `f(now)`）は再利用できるが描画層（NSBezierPath/Catmull-Rom/y-flip/antialias-off）は**フルリライト**＝別判断・別見積り。

### Phase 3 — 各アプリへ適用（item2 の 2B・各アプリ repo の follow-up・殻は AppKit のまま・**#16 依存／#17 非依存**）

> 各アプリは安定公開 API（#16 の A ラッパ）を消費すればよく、A/B の別は consumer に不可視。よって早期アプリは #16 が出れば着手でき、#17（B 化）は裏で並行。

- **#18 glance（先頭・~1,966 LOC）**: NSPanel 殻は維持、Markdown/TextKit は AppKit 据え置き、chrome の sill 化＋`NSHostingView` 検証台。既に PaletteKit 消費。
- **#19 perch（~3,000 LOC 描画）**: overlay panel/eventtap/AX 殻は維持、ヒント pill 描画の sill 化。
- **#20 wand（~7,000 LOC）**: overlay/launcher 殻は維持、中身を sill 化＋`NSColorParse`→`PaletteKit` 収束。
- **#21 facet（最大・~9,000 LOC・最後）**: KeyablePanel/overlay/AX 殻は維持、sidebar/grid/rail の手描きを SwiftUI-on-sill で再構築。自前 `ThemedScroller` 等の重複を sill へ収束。**着手前に §3 の入力 spike を済ませる。**

> 注: 各アプリ作業は**その app の repo の follow-up**（過去 #4/#5/#9e と同型）。sill ROADMAP では「適用フェーズ」として番号で追うが、実装と PR は各 repo 側。

## 5. 依存・順序（並列化を反映）

- **クリティカルパス**: #13 → #15 → #17。
- **並行可**: #14a はトークン非依存＝#13 と並行/先行。#16(A) は Phase 1 完了を待たず #14a と並行可（橋は現行ウィジェットの上で成立）。
- **#14b**（リテラル→トークン）は #13 後。**#17(B)** は #13+#15 後（トークン+純粋核が要る）。
- **Phase 3 は #16 依存・#17 非依存**: 早期アプリ（glance/perch）は #16 が出れば着手、#17 は裏で並行。
- **#15 内部**: ThemedList 核 → ComboBox/Menu 核（順序固定）。
- **facet（#21）前に入力 spike 必須**。

## 6. 検証方針（house ルール）

- **`swift build` = ローカル唯一のゲート**（CommandLineTools のみ・Xcode 無し）。`swift test`（XCTest）は **CI でのみ**走る → ロジック（特に #15 純粋核）は XCTest を書き、UI 挙動は **prism でライブ実証**。
- **CLT 制約**: SwiftUI 追加は Xcode 専用マクロ（`#Preview` 等）禁止。`NSHostingView`/`NSViewRepresentable` は可。
- **Swift 6 並行性**: `ResolvedPalette`/Color resolver は `@MainActor` のまま（appearance 依存の system NSColor を読む）。値（`Color`/`Font`）のみ Sendable。純粋核は Foundation のみで Sendable。
- **SwiftUI native の検証穴**: `swift build` はレンダを動かさない・CI スクショ無し・agent 画面収録不可 → native 部品は**決定論プレビュー seam を実装**し、**アニメ/見た目は maintainer 実機確認をゲート**（chomp-push-gate 同型）。
- 各部品は prism showcase 必須（AppKit/SwiftUI 両方・並置でドリフト検出）。敵対的レビュー（多視点）を各 PR で。

## 7. 制約・リスク

- **並行作業ハザード**: 本 repo は maintainer + 別 Claude セッションが同時作業中（[[parallel-work-hazard]]）。各作業は clean origin/main から隔離（worktree）、相手の未コミット WIP/ブランチに触れない、タグ前に版が未使用か確認。`docs/ROADMAP.md` 編集も衝突注意。
- **二重維持**: B 移行中は AppKit 版 + SwiftUI 版が部品単位で一時併存。公開 API を安定させ、置換完了部品から AppKit 版を撤去してドリフト窓を最小化。
- **アプリ移行の本質**: SwiftUI 化しても各アプリの AppKit 殻（panel/tap/AX）は残る＝「脱AppKit」は達成しない（中身のみ SwiftUI）。これは技術的必然でユーザー合意済。
- **入力 spike 未消化のまま facet/wand に入らない**（非 key パネル内 SwiftUI 入力の検証）。

## 8. 引き継ぎ（未達成を暗黙にしない）

- 進捗 SSOT = `docs/ROADMAP.md`。着手中の項目は「着手中: PR #N」、完了で 完了 にフリップ。
- 各フェーズはセッション分割可。新セッションは `git fetch` → `docs/ROADMAP.md`（origin/main 版）→ 本 spec を読む。
- フェーズ毎に「実装済/ライブ確認済/レビュー済/未達」を ROADMAP の該当行で明示（暗黙にしない）。
