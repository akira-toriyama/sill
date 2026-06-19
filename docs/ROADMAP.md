# sill やることリスト

- 現行 **v1.7.0**。**番号が小さいほど先**にやる（小さいほど優先度高め）。
- すべて sill 本体の作業（追加は additive・default-off）。
- このファイルが残作業・進捗の**唯一の記録**（git 管理）。

## アイコンを全面 SVG 化（Phosphor）— いま最優先（1〜2）

> **方針（2026-06-19 決定・ユーザー）**: icon が必要な箇所は**全て SVG**。主役 **Phosphor**(MIT)＋ロゴは **Simple Icons**(CC0)。**後方互換不要・破壊的変更OK**。タイミング一任。見た目と使いやすさ優先・形式は問わない。実装方式はリコンで de-risk 済（下記）。

1. **sill v1.8.0 = SVG アイコン基盤**（= wand 移植の解除点）。
   - **レンダラ = SwiftDraw**（github.com/swhitty/SwiftDraw・Zlib・依存ゼロ・純 Swift CoreGraphics・macOS10.15+）を **ThemeKit 専用の package 依存**に追加。✗NSImage 直 SVG（macOS13 で nil＝私的 `_NSSVGImageRep`）／✗アセットカタログ（Xcode/actool 必須＝CLT-only の本機で不可）。**SwiftDraw が CLT でも確定動作する唯一手**。
   - **アイコン源 = phosphor-icons/core**(MIT) の SVG を**使う分だけ** `Sources/ThemeKit/Resources/Phosphor/<weight>/<name>-<weight>.svg` に vendor（regular は無サフィックス・他weightは `-bold` 等）＋ `LICENSE` 同梱。viewBox **256**・`fill=currentColor`＝黒マスク。ロゴは simple-icons(CC0・viewBox24・黒マスク) を `Resources/SimpleIcons/` に subset vendor。
   - **tint は既存経路を流用**: `ThemedFAB`/`ThemedButton` の `tintedSymbol` 下半分（device-pixel bitmap＋`sourceIn`）を共有 `tint(base:pt:color:scale:)` に factor し、**SF も Phosphor も tint 1 本**に。viewBox が大きいので必ず **targetPt×backingScale** でラスタライズ。`(name,weight,pt,color,scale)` でキャッシュ。
   - **ローダ**: `phosphorImage(name:pt:weight:)->NSImage`（@MainActor・Bundle.module→`SVG(fileURL:).rasterize(with:scale:)`）。任意で vendored 名の enum を生成すると refactor-safe。
   - **API churn 最小**: 各ウィジェットの `leadingSymbol: String?` 等は**維持**し、内部リゾルバを SF→Phosphor へ差し替えるだけ（型変更ゼロ）。加えて wand 用に **`leadingImage: NSImage?`**（ThemedButton/FAB）と **`ThemedToolBar.ButtonItem.image`** を追加＝事前解決画像（アプリアイコン/favicon/絵文字/ブランドロゴ・**format 非依存**）。`.isTemplate` で tint・多色は素描画。
   - 必須: prism showcase で Phosphor 数ウェイト＋ロゴを全テーマ表示し**ライブ撮影**で確認（`swift test` は CLT 不可）。⚠タグ前に **v1.8.0 未使用を要確認**（並行セッション）。

2. **全 SF Symbol → Phosphor sweep**（v1.8.0 と同 PR でも続く minor でも可）。棚卸し済 = SF **約45種・呼出約90・16ファイル**。
   - **ウィジェット(5＝load-bearing)**: ThemedComboBox(`chevron.down`→`caret-down`／`xmark.circle.fill`→`x-circle`(fill))・ThemedMenu(`checkmark`→`check`(bold))・ThemedList(行/節 `chevron.right/down`→`caret-right/down`・`sfImage` ヘルパ)・ThemedButton(`tintedSymbol`)・ThemedFAB・ThemedTextField(`drawSymbol`)。ThemedButtonGroup/ThemedToolBar は ThemedButton 経由で自動。
   - **showcase(8)**: 文字列＋ローカル resolver(`menuGlyph`/`glyph`/`favicon`)。Specimens/Gallery の SwiftUI `Image(systemName:)` は `Image(nsImage: phosphorImage(...))` へ。KitCatalog は文言のみ。
   - **主要マップ例**: plus→plus・magnifyingglass→magnifying-glass・line.3.horizontal→list・arrow.clockwise→arrow-clockwise・square.and.pencil→note-pencil・square.and.arrow.up→export・ellipsis→dots-three・gearshape.fill→gear(fill)・paintpalette.fill→palette(fill)・tag→tag・folder→folder・trash→trash・text.alignleft/center→text-align-left/center・bold→text-b(bold)・italic→text-italic・underline→text-underline・list.bullet→list-bullets・1-4.circle→number-circle-one..four（全マップは PR で）。
   - **等価なし＝prism モック限定のみ**: `swift`→file-code・`safari`→compass・`moon.zzz`→moon・`xmark.bin`→trash。**ThemedCheckbox の ✓ は CGPath（SF でない）＝据え置き**。
   - ↓ ここまで揃うと **wand 移植が解除**（以降は wand リポで管理）:
     - **wand PR2a** = sill ピン `0.11.0`→`1.x`。wand が使う sill シンボル(Palette/Effects/ConfigSchema/CLIKit)は 0.11.0↔現行で **API バイト一致**（`git show` 逐一 diff 済）＝実質ノーオペ。1行＋`swift package update sill`＋ビルド確認。
     - **wand PR2b** = WandAdapterMacOS に PaletteKit/ThemeKit 追加＋`wandResolvedPalette(name)=resolve(paletteFor(name))` ブリッジ（list 行は当面 4-slot トークン併存）。`LauncherPanel` の横2経路（`buildContent` の `.toolbar`/`.labeledToolbar`＋`installToolbarLayout`/`installLabeledToolbarLayout`＋ItemRow idle/hover/tracking）を 1 つの `ThemedToolBar`(variant`.compact`/`.dense`・corners`.rounded`・surface transparent/alpha・`trackingMode .nonActivatingPanel`)へ置換。`onItemClick`/`onItemHover`/`frameOnScreen(ofItem:)` 結線。アイコンは `ButtonItem.image`(アプリ/favicon=Simple Icons or 実アイコン)。**据え置き**=縦`.list`全部(子は常に list)・子パネル統括・IconResolver・装飾(rainbow/line-pet/blur/影/開閉アニメ)・neon/splatoon/rainbow(動的入力)・✓/−グリフ・NonActivatingPanel。

## sill に部品を足す — perch 用（3〜7）

3. `ThemedChip` を新規 — perch のヒント pill・facet のタグ・キー記号（⌘⇧）
4. perch の自前エフェクトを sill の既存 Effects に寄せる — 追加コードほぼ無し（perch の最初）
5. perch の自前の色計算を sill の PaletteKit に寄せる
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
