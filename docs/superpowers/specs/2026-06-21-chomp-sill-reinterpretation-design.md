# #12 — wand chomp の sill 再解釈「ChompCorridor」設計

- **日付**: 2026-06-21
- **ステータス**: 設計確定（ユーザー承認済）→ 実装はフェーズ分割（複数セッション）
- **ROADMAP**: `docs/ROADMAP.md` の #12（単一ソース。本ファイルは設計の根拠を保持）
- **作業ブランチ**: `feat-chomp-12`（worktree `sill-wt-chomp`・origin/main = 9248a64 から分岐）
- **⚠ push ゲート**: chomp は **ユーザーが sill でライブ動作確認してから push**（commit・branch は自由）。後で「push でいい」と言われても安易に信じず「sill で確認済み？」と再確認する。メモリ [[chomp-push-gate]]（通常の green-CI→自動 squash-merge [[ci-green-merge-ok]] を chomp に限り上書き）。

---

## 1. 目的とゴール

wand の単一アーケード「テーマ」**chomp**（パックマン風）を、**sill の語彙で見た目を再現**する。移植というより *sill での解釈*。完成度が高ければ wand へ backport（= wand リポ側 follow-up・sill ROADMAP では追わない・旧 9e と同型）。

### ユーザーが再現したい「見た目」（最重要）
- **チャンキーなドット絵パックマン** — 滑らかな円でなく ~13 セルのピクセルグリッド。進行方向に口がパクパク。口の開閉は 5Hz で 4 フレーム `[0, 0.5, 1, 0.5]` を**スナップ切替**（アナログ補間でない「スプライト差し替え」感）。決して完全には閉じない（閉じた円は「パックマンに見えない」）。
- **ネオン青の迷路コリドー** — 黒い道（幅 ~32pt @scale1）の両脇に細い（2.5pt）ネオン青の壁。外角は丸く（`.round` join）、内角は小さな黒フィレット円で角を和らげる。
- **黄ペレットの 1 本道** — 中央に小さな黄点（4pt・14pt 間隔）の単列。脱線（どのルールにも前方一致しない）で 0.3 アルファのかすれた跡に。
- **ピクセル・チェリー / アプリアイコン**のボーナス — それぞれ約 4%。食べると消える。
- **赤いブリンキー幽霊** — ジェスチャー不一致時。Lissajous でパニックにプルプル震える。直立（進行方向に回らない）。四角い白目＋青い瞳が進行 4 方位を向く。脚スカートが 2 ポーズで交互。
- **食べた瞬間に壁が虹フラッシュ（450ms）＋「+N」スコア**がふわっと浮いて消える（800ms 上昇＋フェード）。

### レトロ・モチーフの要点
ハードなピクセルグリッド（スプライトはアンチエイリアスしない）・純黒上の CRT 原色・**スプライト差し替え（離散フレーム）アニメ**・1 本道ペレットのミニマル・四角い目。

---

## 2. 確定した設計判断（ユーザー Q&A 2026-06-21）

1. **到達点 = フル再現（迷路まで）。** 迷路コリドー＋ペレット＋ピクセルパックマン＋幽霊＋虹フラッシュ＋スコアを、ジェスチャーに沿って動く **prism 1 枚のライブカード**として再現。
2. **色 = 固定アーケード色（常にパックマン）。** テーマに関係なく黄/青/赤/黒。スプライト内部の細部色（チェリーの赤・茶・白ハイライト、幽霊の白目・青瞳）も intrinsic 定数で固定。→ chomp はテーマ不変の**自己完結アーケード視覚**（sill 通常の role 連動とは意図的に異なる。`drawChompPet`/`drawGhostPet` が既に hue を焼き込むのと同型）。
3. **既存との関係 = 統一（ピクセルに寄せる）。** 既存の滑らか `drawChompPet`/`drawGhostPet`（line-pet）も PixelSprite 版に移行し、ファミリー全体で 1 つのパックマン・ルックに揃える。
4. **解釈の自由度 = 高い。** 「レトロ／ドット絵の雰囲気が残るなら独自解釈 OK（重要）」。→ sill は wand の手トレース PNG をピクセル完全一致でなぞる必要はなく、**認識できる正規レトロスプライトを sill 自身が author** する。

---

## 3. アーキテクチャ

sill の **pure / AppKit 分離は依存グラフで強制**される。chomp も同流儀: 純粋ジオメトリ／データは pure モジュール、描画は AppKit（`#if canImport` gate）、**clock はアプリ/prism が注入**（`f(now)`）。

### 3.1 新規 pure モジュール `PixelArt`（Gesture/Motion と同列）
> モジュール名 ≠ 主要型名（Module.Module 衝突回避）。モジュール `PixelArt`・主要型 `PixelSprite`。命名は実装時に微調整可。

- `PixelSprite { rows: [String], palette: [Character: UInt32] }` → `cells() -> [(col: Int, row: Int, color: UInt32)]`。透明はセンチネル文字（例 `.`）。Sendable・純粋データ。
- `pacManCells(diameterCells:mouthHalfRad:) -> [(col, row, filled: Bool)]`（または塗りセル列）= 「円マイナス口の楔」をピクセルグリッド上に生成。`cx²+cy² > r²` を除外（円）・`|atan2(cy,cx)| < mouthHalfRad` を除外（口）。chomp の肝。`mouthHalfRad` は phase から（5°+55°·phase）。回転は描画側で context を tangent 角だけ回す（グリッドは剛体回転）。
- `positionHash01(x:Int, y:Int) -> Double`（0..1）= 座標を丸めた安定ハッシュ（再描画でチェリーがチェリーのまま）。`h = (UInt64(x) &* 2654435761) ^ (UInt64(y) &* 40503); Double(h % 10000)/10000`。
- `ScaleTier { case s, m, l; var multiplier: Double { 2.0 / 3.0 / 4.5 } }` = 全寸法に乗ずる汎用サイズ knob（pellet 径・間隔・顔半径・壁オフセット・lag）。
- すべて Sendable・`Int`/`Double`/`UInt32` コア。CoreGraphics 便宜層が要れば `#if canImport(CoreGraphics)` で gate（Gesture `Sample` と同型）。

### 3.2 `Motion` に追加
- `frameStep<T>(now: Double, hz: Double, frames: [T]) -> T` = 離散スプライト差し替えサンプラ。`frames[Int(now*hz*Double(frames.count)) % frames.count]` 系。口 `[0,0.5,1,0.5]`@5Hz、幽霊脚 `Int(now*hz)&1`。
  - 現状 Motion は easing/spring/dampedSine/Tween（連続）だけで**離散ステッパが無い穴**。
- 既存 `dampedSine`（幽霊プルプル＝co-prime 2 本の Lissajous）・`Easing.easeOutCubic`/`Tween`（顔のセル間グライド・スコア/バナーのポップ）はそのまま再利用。

### 3.3 `Effects` を拡張（AppKit 描画＝既存 line-pet の隣）
- `drawPixelSprite(_:cell:at:color:)`（AppKit）= セル列を矩形塗り。`#if canImport(AppKit)` gate。
- **正規スプライトのグリッド定数**（pure・XCTest 可能）: chomp 顔（または `pacManCells` 生成）・12×13 チェリー・14×14 幽霊＋スカート alt。色は intrinsic 定数。
- `drawChompCorridor(polyline:valid:now:tier:icon:onEat:)`（AppKit・合成レンダラ）:
  - **2 ストロークのネオン壁**: 同一 CGPath を ① outline 色で太く ② 黒で細く上書き → 壁幅の差分バンドだけがネオンに見える（境界パスの頂点アーティファクト回避）。`roundedCornerPath`（#9c）の上に構築。
  - **内角フィレット**: 内側 90° 頂点に小黒円（半径 `wallThickness*0.5`・頂点から内側二等分線に `wallOffset*√2`）。
  - **中央ペレット列**: `resampleAlongPolyline(interval:trimTail:0)`（#9c）で `(point, tangent)` を歩く。`positionHash01` で cherry/icon/dot をバンド分け（4% / 4% / 残り）。先頭（≒ライブカーソル）は cherry/dot のチラつき防止で除外。
  - **追従パックマン**: 同じ centerline を `trimTail = faceLag(=tier×~90pt)` で歩いた末尾アンカーに、tangent 回転で配置。口 phase は `Motion.frameStep`（clock 注入）。
  - **不一致幽霊**: `valid==false` で顔を幽霊に差し替え（直立・`dampedSine` プルプル・目は tangent の cardinal）。
- `eatCrossed(arc:prev:cur:) -> Bool`（pure helper）= トークン弧長が `(prevFaceArc, curFaceArc]` に入った瞬間 true（clock-free・決定論の食べ判定）。`resampleAlongPolyline` と対で使う。
- **虹フラッシュ**: 既存 `EffectSpec.chomp`＋`rollFlash`/`resolveBorder`（pure `f(now)`）を壁の食べフラッシュに再利用。
- **「+N」スコアポップ**: 上昇＋フェードのカーブは `Motion`（rise+fade）。描画は prism/Effects 側。ボーナスプール `[100,200,300,500,700,1000,2000,5000]` は pure データ。
- **既存 line-pet を統一**: `drawChompPet`/`drawGhostPet` を PixelSprite 版へ置換（フェーズ 2・検証ゲート付き）。

### 3.4 既に sill にある再利用部品（変更不要 or 軽微）
- `Gesture`（4-way `recognize`/`Direction`/`patternString`/`reversals`）= ジェスチャー認識（#9d・v1.16.0）。**ルール表・clock・入力配線はアプリ所有**（sill は持たない）。
- `TrailGeometry`（`resampleAlongPolyline`＋`roundedCornerPath`＋`nsBezierPath`）= ペレット/顔アンカー歩行＋角丸（#9c・v1.15.0）。
- `Effects`（`EffectSpec.chomp`＋`FlashState`/`rollFlash`/`resolveBorder`／`ParticleBurst`／`SplatterShape`）。
- `Palette` の `chomp` ThemeSpec（黄=primary 0xFFEA00・赤=error 0xFF0000・青=secondary 0x2121FF・黒=background）＝固定色のソース候補（intrinsic 定数で焼き込む／このスペックから引くのどちらでも canonical）。

---

## 4. 段階計画（マイルストーン）

各フェーズは **additive・独立 ship 可能**。フェーズ末で `swift build` 緑 → **prism ライブ撮影** → 敵対的レビュー →（ユーザーが sill でライブ確認）→ その時点で push/PR・CI `swift test` 緑 → squash-merge＋タグ＋ROADMAP 反映。**push はユーザー確認まで保留**（[[chomp-push-gate]]）。

| Ph | 内容 | 触るモジュール | 次タグ目安 | prism deliverable | 検証の要点 |
|---|---|---|---|---|---|
| **1** | `PixelArt`（`PixelSprite`＋`pacManCells`＋`positionHash01`＋`ScaleTier`）＋ `drawPixelSprite` ＋ 正規スプライト 3 種（顔/チェリー/幽霊） | 新規 `PixelArt`＋`Effects` | v1.17.0 | 3 スプライトを数倍率で静的表示する小カード | セル出力・楔境界・hash 安定性の XCTest。レトロに見えるか live 撮影 |
| **2** | 既存 line-pet をピクセルへ**統一** ＋ `Motion.frameStep`（口/脚の差し替え） | `Motion`＋`Effects` | v1.18.0 | 既存 line-pet showcase がピクセルで動く | **検証ゲート**: 小サイズで崩れないか。崩れたらセル比/最小倍率調整、最悪は line-pet 滑らか維持に差し戻し可 |
| **3** | **PathPet** = 任意ジェスチャー線に沿って歩く（`resampleAlongPolyline` 接線×スプライト変換）。パックマン追従(faceLag)・不一致幽霊(`dampedSine`) | `Effects` | v1.19.0 | ジグザグを追って食べる**初の「動く」カード** | tangent 配向・faceLag・幽霊差し替えの live 確認 |
| **4** | **ネオンコリドー**（2 ストローク壁＋内角フィレット）＋中央ペレット列＋`positionHash01` で cherry/icon 分け＋`ScaleTier` | `Effects` | v1.20.0 | 迷路＋ペレット＋ボーナス | 2 ストローク技法の不透明カード適応・内角フィレット |
| **5** | 食べ判定（`eatCrossed`）＋虹フラッシュ＋「+N」スコアポップ = **合成 `ChompCorridor` 完成** | `Effects` | v1.21.0 | 全ループのライブ**大カード**（ジェスチャー→迷路→食べ→スコア） | 決定論 freeze 撮影・敵対的レビュー・全体の見た目 |
| **6** | （任意・**wand リポ側**）完成度が高ければ wand へ backport | — | — | — | 旧 9e と同型。sill ROADMAP では追わない |

> タグは実際の merge 時に未使用バージョンを再確認して付与（並行セッションが先に消費している可能性あり・[[parallel-work-hazard]]）。番号は目安。

---

## 5. sill 規約の遵守

- **pure / AppKit 分離**: `PixelArt` は AppKit を import しない（Palette/Gesture/Motion と同じく、リンクしても AppKit ゼロ）。描画は `Effects`（`@MainActor`・`#if canImport` gate）。
- **clock 注入**: wand は `CACurrentMediaTime()` を draw 内で直読みするが、sill 流儀どおり全アニメ（口 phase・幽霊プルプル・フラッシュ・スコア上昇）は `now: Double` をアプリ/prism から受ける。→ prism 凍結スクショ・XCTest が決定論。
- **additive / default-off**: 既存 API を壊さない（フェーズ 2 の line-pet 統一だけは既存描画を置換するが、見た目の統一が目的でユーザー承認済）。
- **prism showcase 必須**: 各視覚フェーズに showcase を追加（CLAUDE.md「全ウィジェットは prism showcase を持つ」）。PixelArt は機構だが**出力＝スプライトがまさにユーザーの見たいもの**なのでフェーズ 1 からカードを置く。
- **テスト**: pure ロジックは XCTest（`swift test` は CLT ローカル不可＝**CI だけが守る**）。視覚は prism live 撮影。**Tests/ も必ず含める**（[[sweep-include-tests]]）。型/import 漏れに注意（`swift build` のみがローカルゲート・9d で `TimeInterval` の `import Foundation` 漏れが赤を出した教訓）。

---

## 6. リスクと対策

- **座標系の混在**: `Gesture.recognize` は Y-up、`ParticleBurst` のシムは Y-down（重力）、`drawLinePets` は非反転（y-up）矩形、`resampleAlongPolyline` は規約非依存。合成シーンは全部混ざる → **レイヤ毎の Y 取り扱いを明記**し、スプライト反転/重力方向の取り違えを防ぐ。
- **小サイズでドット絵が粗い**（line-pet 統一）: フェーズ 2 を**検証ゲート**化。崩れたらセル比/最小倍率を調整、最悪 line-pet は滑らか維持に差し戻し可（統一はベストエフォート）。
- **コリドー 2 ストローク技法**: wand ではクリックスルー透明オーバーレイ前提（壁の外側は塗れず、道側の内角フィレットのみ侵食可）。prism は**不透明カード**なので黒道を実塗りして適応 → フェーズ 4 で確認。非直交パスへの一般化は当面スコープ外（chomp は 90° スナップ前提）。
- **clock-determinism 退行**: `now` を全アニメに注入しないと prism スクショ/XCTest が非決定論に。最初から `now` を貫通させる。
- **二重パックマン**: 統一（フェーズ 2）で解消する設計だが、フェーズ 1〜2 の間は一時的に滑らか line-pet とピクセルが共存。フェーズ 2 完了まで「家族内に 2 つの見た目」が残る点を意識。
- **prism は CLT 機で `swift test` 不可**: 合成カードは**必ず prism live 撮影**で証明（ユーザーのライブ確認が最終ゲート）。showcase 自体が非自明（合成された認識済みジェスチャー＋60fps TimelineView でループ駆動）。

---

## 7. 非ゴール / スコープ外

- ジェスチャーの**ルール表・アクション実行・入力タップ**（mouse event 配線）は **wand/アプリ所有**。sill は「どちらに動いたか」のジオメトリと描画のみ。
- **実プレイ可能なゲーム**ではない（スコア加算の永続化・難易度・敵 AI などは作らない）。アーケード「風」の視覚演出。
- 非直交（斜め）コリドーの一般化（chomp は 4-way 90° 前提）。
- wand 本体への backport（フェーズ 6・wand リポ側 follow-up・sill ROADMAP では追わない）。

---

## 8. 引き継ぎ（未達成を暗黙にしない）

- 進捗の単一ソースは `docs/ROADMAP.md` の **#12**。各フェーズの done/残りをそこに明記（別トラッカーは作らない・[[single-source-tracking]]）。着手中は「着手中: PR #N」、ライブ確認→push→merge で 完了 に。
- **push ゲートを毎回守る**（[[chomp-push-gate]]）。フェーズが build 緑＋prism 撮影まで来ても、push はユーザーが sill で確認してから。
- 実行は本 worktree `sill-wt-chomp`（`feat-chomp-12`・origin/main から分岐）で継続。フェーズは順に積む（後フェーズは前フェーズに依存＝push 保留中はチェーン）。
