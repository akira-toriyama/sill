# #12 chomp — directional-eye upright ghost (PLAN, separate/Ph3-aligned session)

- **日付**: 2026-06-21
- **ステータス**: 計画確定待ち→**別セッションで実行**（ユーザー裁定: 品質重視・計画と実行を分ける・別セッションOK）。Ph3（spec の「不一致幽霊＝直立・目は cardinal」）と統合。
- **親**: `docs/ROADMAP.md` #12 / 設計 spec `2026-06-21-chomp-sill-reinterpretation-design.md`
- **ブランチ**: `feat-chomp-12`（worktree `sill-wt-chomp`）に続けて積む。⚠ **push ゲート継続**（[[chomp-push-gate]]）— ユーザーが sill でライブ確認するまで push しない。

---

## 0. これまで（Ph2 で確定済み）

Ph2 で **canonical 大きい目の Blinky（右向き）** に差し替え済み（`CanonicalSprite.ghost`/`ghostAlt`、commit `b42748b`）。現状の line-pet は**スプライト全体を周回接線で回す**（＝下辺で上下逆さ）。本プランはそれを **直立＋目だけ進行方向（4 cardinal）を向く** 版に進化させる（=ユーザー素材 目.gif/全身2.gif の意図）。

## 1. 参照素材（ユーザー提供 GIF を ASCII 化して保存＝再抽出不要）

> 元 GIF は `~/Desktop/a/`（全身.gif=右・全身2.gif=左・色違い・目.gif=4方向）。**transient なので下にグリッドを焼き込む**。`r`=ghostRed `w`=eyeWhite `b`=pupilBlue `.`=透明。全 14×14。

### 1.1 canonical body（右向き・Ph2 で採用済み）= rows 0–11、feet 2 ポーズ
```
.....rrrr.....
...rrrrrrrr...
..rrrrrrrrrr..
.rrrwwrrrrwwr.
.rrwwwwrrwwww.
.rrwwbbrrwwbb.
rrrwwbbrrwwbbr
rrrrwwrrrrwwrr
rrrrrrrrrrrrrr
rrrrrrrrrrrrrr
rrrrrrrrrrrrrr
rrrrrrrrrrrrrr
```
feetA = `rr.rrr..rrr.rr` / `r...rr..rr...r`　feetB = `rrrr.rrrr.rrrr` / `.rr...rr...rr.`

目領域 = rows 3–7。白目は 4 セル幅（左 cols3–6 / 右 cols9–12）、瞳 2×2。**右向き = 瞳が白目の右側（cols5–6 / 11–12）**。

### 1.2 目.gif の 4 方向（瞳配置の source-of-truth・目クロップなので body は別スケール／瞳の「向き」のみ参照）
right(me_0): 瞳=白目の**右**　up(me_1): 瞳=**上** 白目が下　left(me_2): 瞳=**左**　down(me_3): 瞳=**下** 白目が上
```
right          up             left           down
..rr..         bbrrbb         ..rr..         ..rr..
rrrrrr         rbbrrbbr       rrrrrr         rrrrrr
rrwrrrwr       rrwwrrww       rwrrrwr        rwwrrwwr
rwwbrwwb       (白下)         bwwrbwwr       rrbbrrbb
rrrwrrrwrr                    rrwrrrwrr      rrbbrrbb
```
（↑は目.gif の生抽出の要約。実装時は **canonical の 4×5 白目を固定し、2×2 瞳を R/L/U/D に動かす**だけ。下に実装ドラフト。）

### 1.3 実装ドラフト＝canonical 目領域（rows 3–7）の 4 変種（執筆時に目.gif とライブ突合で微調整）
- **right**（=現状）: r5 `.rrwwbbrrwwbb.` r6 `rrrwwbbrrwwbbr`（瞳 cols5–6/11–12）
- **left**: r5 `.rrbbwwrrbbww.` r6 `rrrbbwwrrbbwwr`（瞳 cols3–4/9–10）
- **up**: r3 `.rrrbbrrrrbbr.` r4 `.rrwbbwrrwbbw.` r5 `.rrwwwwrrwwww.` r6 `rrrwwwwrrwwwwr` r7 `rrrrwwrrrrwwrr`（瞳上）
- **down**: r3 `.rrrwwrrrrwwr.` r4 `.rrwwwwrrwwww.` r5 `.rrwwwwrrwwww.` r6 `rrrbbwwrrbbwwr`→要調整 r7 `rrrrbbrrrrbbrr`（瞳下）

> ⚠ up/down は白目の縦が足りずタイトなので、目領域を rows 3–8 に 1 行広げる調整が要るかも。ライブ撮影（下記オフスクリーン PNG 手法）で確定。

### 1.4 全身2.gif（左向き・色違い＝色以外参照）= mirror 確認用
```
.....rrrr.....   (cyan→r)
...rrrrrrr....
..rwrrrrwwrr..
..wwwrrwwwrr..
..bwwrrbbwrr..
.rbwwrrbbwrrr.
.rrwrrrrwwrrr.
.rrrrrrrrrrrr.  ...（feet 略）
```
左向きの瞳が左に寄っているのを確認（1.3 の left ドラフトの裏取り）。

## 2. 設計判断

1. **幽霊は直立**（line-pet の周回接線で回さない）。**目だけ**進行方向の cardinal（上/右/下/左）を向く。pac はこれまで通り回す（口=進行方向）。
2. **方向 enum は `Gesture.Direction`（#9d・4-way）を再利用**できるか確認（pure・Sendable）。できなければ Effects ローカルに小さな `enum GhostLook { up,right,down,left }`。
3. **目領域だけ差し替えるビルダー** `ghostSprite(feet: A|B, look:) -> PixelSprite`（body 固定・rows 3–7 を look 別に差し替え）。静的 4×2=8 スプライトを持つより DRY。`CanonicalSprite.waddleFrames` は据え置き or look 込みに一般化。
4. **drawLinePets の per-pet 分岐**: 現状は全 pet を `translate+rotate(tangent)`。ghost は **rotate せず translate のみ**＋`look = cardinal(tangent)` を選ぶ。tangent→cardinal 写像（周回: 上辺=右/右辺=下/下辺=左/左辺=上）。pac は従来通り rotate。
   - 実装案 A: `drawLinePets` 内で pet 別に transform を変える（ghost は rot を渡さない）。
   - 実装案 B: drawGhostPet 内で逆回転して直立に戻す（呼び側を変えない）。A の方が明快。

## 3. 実装ステップ（additive・検証ゲート付き）

1. `GhostLook`（or Gesture.Direction 再利用）＋ `ghostSprite(feet:look:)` ビルダー（Effects/Sprite.swift）。1.3 の 4 目領域を確定（ライブ突合）。
2. drawLinePets を per-pet transform に（ghost=直立＋look・pac=rotate 据え置き）。tangent→cardinal ヘルパ（純粋・テスト可）。
3. prism: 周回カードは自動で 4 方向を一巡（各辺で目が変わる）。静止確認用に `PRISM_CHOMP_T` で各辺の look を凍結できるよう、周回位相も freeze に含める。directional の単体カード（4 look 並べ）も追加すると分かりやすい。
4. Tests: `ghostSprite` の dims/非ragged/白青赤セル（look 別）・tangent→cardinal の境界（45°境界の丸め）・waddle×look の組合せ smoke。MotionTests は不要（frameStep 既存）。
5. 検証: `swift build`（ローカルゲート）＋ **オフスクリーン PNG レンダ**（temp executable で drawLinePets を周回各辺で描き Read＝向き確定。Ph2 で実証済みの手法）＋ **ユーザーの prism ライブ確認（必須ゲート）** ＋ CI `swift test`。
6. 完了で ROADMAP #12 Ph3（一部）反映・push はユーザー確認後。

## 4. 確認したいこと（実行セッション冒頭で）

- **line-pet の幽霊を直立にしてよいか**（現状は周回で回る→直立は見た目が変わる。canonical/spec 的には直立が正だが、ユーザー承認を取る）。
- directional eyes を **Ph2 ブランチに続けて積む**か、**Ph3 として明確に分ける**か（どちらも `feat-chomp-12`）。

## 5. スコープ外
- pac 側の挙動変更（口は据え置き）。コリドー/ペレット/食べ（Ph4–5）。wand backport（Ph6）。
