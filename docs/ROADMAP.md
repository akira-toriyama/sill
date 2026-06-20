# sill やることリスト

- 現行 **v1.10.0**（#4 完了 = perch PR #132 merged・**sill 変更なし**で perch を寄せた／#3 = PR #54 tagged 2026-06-20）。**番号が小さいほど先**にやる。
- すべて sill 本体の作業（追加は additive・default-off）。
- このファイルが残作業・進捗の**唯一の記録**（git 管理）。

## 🧭 現在地（引き継ぎ — 最新セッション 2026-06-20）

**新セッションはまずここを読む。** 進捗の単一ソースはこのファイル。

- **#1（SVG アイコン基盤）= ✅ 完了（PR #52 merged + `v1.8.0` tagged 2026-06-19）。** 内容: SwiftDraw（`<0.25` ピン）・Phosphor/Simple Icons を使う分だけ vendor・`phosphorImage`/`simpleIconImage` ローダ・共有 `tintedBitmap`（SF は byte-identical）・新画像API（`ThemedButton/FAB.leadingImage`・`ThemedToolBar.ButtonItem.image`）・prism「Icons」タブ＋`family` 設定キー。敵対的レビュー反映済。詳細は下の #1 と Package.swift / `Sources/ThemeKit/Resources/README.md`。
- **アイコン vendor 方針 = A「使う分だけ」で確定**（全カタログ ~12.5k/~6MB は入れない。発見可能性は README＋DEBUG ログ＋CLAUDE.md で担保済。#2 の sweep で実使用分が自然に増える）。
- **#2（全 SF→Phosphor sweep）= ✅ 完了（PR #53 merged + `v1.9.0` tagged 2026-06-19）。** SF Symbol を Sources/ **と Tests/** から全廃（`*Symbol: String?` は型維持で Phosphor スラッグを受ける／内部リゾルバを `phosphorImage` に差し替え）・メニュー✓は `check`(bold)・prism 全 showcase の文字列＋`Image(systemName:)`→`phosphorIcon` ヘルパ・Phosphor regular SVG を 31 個 vendor。`swift build`＋prism ライブ撮影（text/action/collection/chrome 両 tint 経路）＋敵対的レビュー（指摘8件反映）＋CI `swift test`（full Xcode・385 tests）緑。**→ これで wand 移植が解除**（以降は wand リポで管理）。⚠教訓: sweep は **Tests/ も含める**（`swift test` は CLT ローカル不可＝CI だけが守るゲート。Button/FAB は icon 解決依存で nil slug→赤、TextField/ToolBar は文字列有無で確保）。メモリ [[sweep-include-tests]]。
- **#3（`ThemedChip` 新規）= ✅ 完了（PR #54 merged + `v1.10.0` tagged 2026-06-20）。** MUI `<Chip>`＋HTML `<kbd>` を1部品に。`public final class ThemedChip: NSControl`・`variant{filled,outlined,keycap}`・`size{small24,medium32}`・`role{neutral,primary,secondary,error}`・`title`/`leadingSymbol`/`leadingImage`/`isSelected`/`onTap?`(クリック可)/`onDelete?`(末尾×=`x-circle`)/`preview*`。perch のヒント**オーバーレイは設計上スコープ外**（`OverlayCanvas.PillLayout` を CG ループで N 個 bespoke アニメ描画＝NSView 部品で代替不可）。実装＋prism showcase＋29 XCTest＋`swift build` 緑＋3テーマ ライブ撮影＋敵対的レビュー（5観点×2票・確定1件=`onTap` の動的 a11y role 再同期を修正）＋CI `swift test`（full Xcode）緑。⚠教訓: **テストは CI だけが守る**＝初回 CI で `laidOut` の trailing-closure 引数順 compile error を捕捉（`swift test` は CLT ローカル不可）。メモリ [[sweep-include-tests]]。
- **#4（perch の自前エフェクトを sill の既存 Effects に寄せる）= ✅ 完了（perch PR #132 merged 2026-06-20・sill 変更なし）。** perch のネオン枠を自前 hue テーブル（`BorderEffect.baseHex`＋`rotateHue`＋`borderHueOffset`）から sill `Effects` に収束＝`borderEffectFor`→`resolveBorder`/`blendThrough` 委譲。perch は redraw クロック所有＋NSColor 化＋glow 合成を維持（sill の app 側 border 契約どおり）。決定（ユーザー Q1/Q2 2026-06-20）= **sill をそのまま採用**（neon/cyber/vapor/kawaii は facet と同じ list-blend に・rainbow 実質同じ／animatedPalette 結線は後回し）。実装: sill ピン 0.11.0→1.10.0（Palette/ConfigSchema/CLIKit はバイト一致＝ノーオペ）・`Effects` を PerchAdapterMacOS にリンク・`.random` を1回解決（draw 毎フリッカも解消）・`BorderEffectMappingTests`（perch↔sill 名前ドリフトを CI で検出）。CI 緑（swift build＋full Xcode swift test）。⚠ perch は headless＝視覚自動テスト無し（見た目は `./run.sh` 手動）。⚠教訓: **#4 は sill 無改変＝アプリ移植のみで完結**（build-best-then-migrate＝sill は既に best、適用は app repo の follow-up。wand 移植と同型で、以降の perch 作業も perch リポで管理）。
- **#5（perch の自前の色計算を sill の PaletteKit に寄せる）= 着手中: perch PR #133。** #4 と同型＝**sill 無改変**（build-best-then-migrate）。`HintPainter.resolvePalette` を `PaletteKit.resolve(spec)` 経由に＝role 色（accent/text/miss/font）＋ system-primary sentinel（0→`controlAccentColor`）を sill が materialize。**要設計だった 3 perch-ism の裁定**（ユーザー Q 2026-06-20 = ③は perch 側に残す）: ① sentinel→**PaletteKit が吸収済**（perch の手書き削除）・② translucency（pillBgAlpha・frosted +0.45）→**フィールドは spec に既存・描画は perch 据置**・③ per-app `[overlay].accent` override→**perch 側に残す**（resolve 後に重ねる・sill は per-app accent を設計上持たない）。重複 `color(hex:)`（HintPainter＋ParticleDriver）を PaletteKit の `NSColor(hex:)` に寄せて全廃。**全テーマで byte-identical**（perch が渡す spec は常に `.fixed`＝"system" は perchSystemSpec で intercept・組み込み/custom は背景あり・`parseHexValue` が alpha を捨て全 role opaque）。`swift build` 緑＋敵対的レビュー（色保存・網羅性を独立確認）＋CI 用 `PaletteResolveMappingTests` 追加（perch headless＝`swift test` は CI だけ）。**merge で 完了 に。**

## アイコンを全面 SVG 化（Phosphor）— いま最優先（1〜2）

> **方針（2026-06-19 決定・ユーザー）**: icon が必要な箇所は**全て SVG**。主役 **Phosphor**(MIT)＋ロゴは **Simple Icons**(CC0)。**後方互換不要・破壊的変更OK**。タイミング一任。見た目と使いやすさ優先・形式は問わない。実装方式はリコンで de-risk 済（下記）。

1. **sill v1.8.0 = SVG アイコン基盤**（= wand 移植の解除点）。 **✅ 完了（PR #52 merged + `v1.8.0` tagged・2026-06-19）**（実装・全要素ライブ撮影確認済・敵対的レビュー反映済。次は #2 の sweep）。
   - ⚠**実装メモ（PR #52）**: SwiftDraw は最新 0.27.0 ではなく **`< 0.25.0`（=0.24.0）にピン** — 0.25.0 が追加した `SVGView.swift` の `#Preview` マクロ（`PreviewsMacros` プラグイン）が **CLT でビルド不可**。0.24.0 は同一 API（`SVG(fileURL:)`/`rasterize`/`NSImage(_:)`）で CLT クリーン。tint 共有関数は `tintedBitmap(base:size:color:scale:)` 名で実装（`pt` は CGSize＝SF を byte-identical に保つため）。`leadingSymbol` の SF→Phosphor リゾルバ差し替えは #2 に分離（基盤では SF 維持＝回帰ゼロ、SVG 入口は `leadingImage`）。prism に `family` 設定キー追加（タブ決定論撮影）。`Package.resolved` は `.gitignore`（lib 慣習）。
   - **レンダラ = SwiftDraw**（github.com/swhitty/SwiftDraw・Zlib・依存ゼロ・純 Swift CoreGraphics・macOS10.15+）を **ThemeKit 専用の package 依存**に追加。✗NSImage 直 SVG（macOS13 で nil＝私的 `_NSSVGImageRep`）／✗アセットカタログ（Xcode/actool 必須＝CLT-only の本機で不可）。**SwiftDraw が CLT でも確定動作する唯一手**。
   - **アイコン源 = phosphor-icons/core**(MIT) の SVG を**使う分だけ** `Sources/ThemeKit/Resources/Phosphor/<weight>/<name>-<weight>.svg` に vendor（regular は無サフィックス・他weightは `-bold` 等）＋ `LICENSE` 同梱。viewBox **256**・`fill=currentColor`＝黒マスク。ロゴは simple-icons(CC0・viewBox24・黒マスク) を `Resources/SimpleIcons/` に subset vendor。
   - **tint は既存経路を流用**: `ThemedFAB`/`ThemedButton` の `tintedSymbol` 下半分（device-pixel bitmap＋`sourceIn`）を共有 `tint(base:pt:color:scale:)` に factor し、**SF も Phosphor も tint 1 本**に。viewBox が大きいので必ず **targetPt×backingScale** でラスタライズ。`(name,weight,pt,color,scale)` でキャッシュ。
   - **ローダ**: `phosphorImage(name:pt:weight:)->NSImage`（@MainActor・Bundle.module→`SVG(fileURL:).rasterize(with:scale:)`）。任意で vendored 名の enum を生成すると refactor-safe。
   - **API churn 最小**: 各ウィジェットの `leadingSymbol: String?` 等は**維持**し、内部リゾルバを SF→Phosphor へ差し替えるだけ（型変更ゼロ）。加えて wand 用に **`leadingImage: NSImage?`**（ThemedButton/FAB）と **`ThemedToolBar.ButtonItem.image`** を追加＝事前解決画像（アプリアイコン/favicon/絵文字/ブランドロゴ・**format 非依存**）。`.isTemplate` で tint・多色は素描画。
   - 必須: prism showcase で Phosphor 数ウェイト＋ロゴを全テーマ表示し**ライブ撮影**で確認（`swift test` は CLT 不可）。⚠タグ前に **v1.8.0 未使用を要確認**（並行セッション）。

2. **全 SF Symbol → Phosphor sweep** — **✅ 完了（PR #53 merged + `v1.9.0` tagged・2026-06-19）**（Sources/ + Tests/ から SF 全廃・prism 全 showcase + `phosphorIcon` ヘルパ・Phosphor regular 31個 vendor・CI `swift test` 緑。→ wand 移植解除）。棚卸し済だった = SF **約45種・呼出約90・16ファイル**。
   - **ウィジェット(5＝load-bearing)**: ThemedComboBox(`chevron.down`→`caret-down`／`xmark.circle.fill`→`x-circle`(fill))・ThemedMenu(`checkmark`→`check`(bold))・ThemedList(行/節 `chevron.right/down`→`caret-right/down`・`sfImage` ヘルパ)・ThemedButton(`tintedSymbol`)・ThemedFAB・ThemedTextField(`drawSymbol`)。ThemedButtonGroup/ThemedToolBar は ThemedButton 経由で自動。
   - **showcase(8)**: 文字列＋ローカル resolver(`menuGlyph`/`glyph`/`favicon`)。Specimens/Gallery の SwiftUI `Image(systemName:)` は `Image(nsImage: phosphorImage(...))` へ。KitCatalog は文言のみ。
   - **主要マップ例**: plus→plus・magnifyingglass→magnifying-glass・line.3.horizontal→list・arrow.clockwise→arrow-clockwise・square.and.pencil→note-pencil・square.and.arrow.up→export・ellipsis→dots-three・gearshape.fill→gear(fill)・paintpalette.fill→palette(fill)・tag→tag・folder→folder・trash→trash・text.alignleft/center→text-align-left/center・bold→text-b(bold)・italic→text-italic・underline→text-underline・list.bullet→list-bullets・1-4.circle→number-circle-one..four（全マップは PR で）。
   - **等価なし＝prism モック限定のみ**: `swift`→file-code・`safari`→compass・`moon.zzz`→moon・`xmark.bin`→trash。**ThemedCheckbox の ✓ は CGPath（SF でない）＝据え置き**。
   - ↓ ここまで揃うと **wand 移植が解除**（以降は wand リポで管理）:
     - **wand PR2a** = sill ピン `0.11.0`→`1.x`。wand が使う sill シンボル(Palette/Effects/ConfigSchema/CLIKit)は 0.11.0↔現行で **API バイト一致**（`git show` 逐一 diff 済）＝実質ノーオペ。1行＋`swift package update sill`＋ビルド確認。
     - **wand PR2b** = WandAdapterMacOS に PaletteKit/ThemeKit 追加＋`wandResolvedPalette(name)=resolve(paletteFor(name))` ブリッジ（list 行は当面 4-slot トークン併存）。`LauncherPanel` の横2経路（`buildContent` の `.toolbar`/`.labeledToolbar`＋`installToolbarLayout`/`installLabeledToolbarLayout`＋ItemRow idle/hover/tracking）を 1 つの `ThemedToolBar`(variant`.compact`/`.dense`・corners`.rounded`・surface transparent/alpha・`trackingMode .nonActivatingPanel`)へ置換。`onItemClick`/`onItemHover`/`frameOnScreen(ofItem:)` 結線。アイコンは `ButtonItem.image`(アプリ/favicon=Simple Icons or 実アイコン)。**据え置き**=縦`.list`全部(子は常に list)・子パネル統括・IconResolver・装飾(rainbow/line-pet/blur/影/開閉アニメ)・neon/splatoon/rainbow(動的入力)・✓/−グリフ・NonActivatingPanel。

## sill に部品を足す — perch 用（3〜7）

3. **`ThemedChip` を新規 — ✅ 完了（PR #54 merged + `v1.10.0` tagged 2026-06-20）。** facet のタグ・ステータス pill・キー記号（⌘⇧）を **1部品**で。perch のヒント pill は当初想定に挙がったが、調査で **オーバーレイは CG ループ描画（`OverlayCanvas.PillLayout`／N個を bespoke アニメ）＝ NSView 1チップでは代替不可**と判明し**スコープ外**に確定（必要なら将来 Spec＋描画ヘルパで別途）。
   - **設計（グリル Q1〜Q9 確定）**: 形＝普通の NSView 部品（ThemeKit 全部品と同骨格・`palette{didSet→applyTheme}`）。タイブレーカー＝**「MUI Chip のセマンティクス＋既存 ThemeKit 部品の慣習」**。
   - **enum**: `Variant{filled, outlined, keycap}`／`Size{small(24h), medium(32h)}`（MUI Chip に large 無し）／`Role{neutral, primary, secondary, error}`（既定 neutral＝MUI `color="default"`。ThemedButton には無い `neutral` を MUI 根拠で追加）。
   - **API**: `title`（uppercase しない）・`leadingSymbol`/`leadingImage`(image優先・trailing 汎用アイコンは無し)・`isSelected`・`onTap?`(非nil⇒クリック可＝hover/press/focus ring/Space)・`onDelete?`(非nil⇒末尾 `x-circle`・Backspace/Delete でも発火)・`preview{Hovered,Pressed,Focused}`。`keyEquivalent`/group seam 系は省略。`isInteractive`(clickable∨deletable)でフォーカス可否を判定（delete-only でも × にキーが届く）。
   - **テーマ契約（正準ロールのみ）**: filled→ role不透明＋`onPrimary`/`onSecondary`/`bestContrast(error)`、neutral=`ink(.wash,of:.muted)`＋`foreground`。outlined→ clear＋role@0.5→hover full（neutral=`border`）。keycap→`ink(.faint,of:.foreground)`＋`foreground`＋`border`＋**mono**（role 無視）。state は ThemedButton 同型（クリック可時のみ）。`isSelected`→`selection`(neutral)/role wash。focus ring=`primary`。
   - **寸法**: 高さ 24/32・font 13・**chip=pill(高さ/2)・keycap=5pt 角＋minWidth=高さ(単グリフ正方)**・chip minWidth 0(中身密着)・leading/×=14/16・gap 5。
   - **prism**: `ChipShowcase.swift`（`ThemedChipView` 橋＋`MockChip`：LIVE/強制状態/role/size/variant＋**keycap 実グリフ `⌘ ⇧ ⌥ ⌘N ⇧⌘N Esc`**）＋Gallery `.action` 結線＋KitCatalog エントリ。
   - **検証**: `swift build` 緑・3テーマ（terminal/github-light/blacklight）ライブ撮影で filled/outlined/keycap/×/isSelected/role(黒白コントラスト ink)/全 state 確認・`Tests/ThemeKitTests/ThemedChipTests.swift`(29 ケース・CI で実行)。
4. **perch の自前エフェクトを sill の既存 Effects に寄せる — ✅ 完了（perch PR #132 merged 2026-06-20・sill 変更なし）。** ネオン枠を perch 自前 hue テーブル→sill `Effects`（`borderEffectFor`/`resolveBorder`/`blendThrough`）に収束。決定 = sill をそのまま採用（facet と同じ list-blend・破壊的変更 OK）。詳細は上の 🧭現在地 #4。
5. **perch の自前の色計算を sill の PaletteKit に寄せる — 着手中: perch PR #133**（#4 同型・sill 無改変・byte-identical・3 perch-ism の裁定は上の🧭参照）。
6. アニメ用の計算 `ThemedTransition` を新規 — perch・facet・wand 共通
7. 紙吹雪 / 花火を Effects に足す

## sill のその他（8〜11）

8. **文字を MUI 規約に照合して調整** — 原典 grounding で精密比較（急がない）。
   読みづらい確定 = ThemedList の 2 行目（11pt regular muted）と TextField 補助文 → 12pt か medium。
   要再確認 = badge 9pt・shortcut 10pt（MUI 11px 下限未満）。全体は概ね基準内（13pt は macOS 慣習で適正）。
9. **wand のエフェクト一式を sill に移植** — 大きいので別途じっくり（gesture / trail / line-pet）
10. prism のタブを app 別に分割（facet / wand / perch / glance）— いつでも
11. prism のエフェクト切り替えトグルの配置直し — いつでも

## 完了

- **v1.7.0** 横ツールバー `ThemedToolBar` 新規（MUI `<AppBar>`+`<Toolbar>` 融合）— surface(surface/primary/secondary/transparent)・variant(regular64/dense48/compact40)・flex セクション・型付き items（本物の ThemedButton を COMPOSE／icon-only 角ボタン・label・custom・divider・spaces）・非アクティブパネル hover・子パネルアンカー frameOnScreen。prism showcase＋KitCatalog＋決定論テスト。overflow は follow-up。（PR #50・旧 #1）
- **v1.6.0** ThemedList のチャンク並べ替え — ヘッダ＋配下の行を1かたまりで並べ替え（複数行 dim・節境界フル幅 insertion bar・header grip・chunk ghost）＋キーボード DnD を節境界 aim に共通化（KeyboardDragController）（旧 #1）
- **v1.5.0** ThemedList の横スクロール＋キーボードカーソル（.outline で選択と見分け）＋ゼブラ縞（旧 #4/#5/#6）
- **v1.4.0** ThemedList の階層インデント＋折りたたみ（旧 #2）
- **v1.3.0** ThemedList ドラッグ層（行の drop-onto／並べ替え＋キーボード lift）（旧 #1）
- **v1.2.0** スクロールバーの themed 化 + アイコン上下逆の修正 + prism の文字拡大
- **v1.1.0** メニューのサブメニュー（1 段）
