# #12 chomp — Ph4 ネオンコリドー（PLAN）

- **日付**: 2026-06-22
- **ステータス**: 計画確定待ち→実行。設計 spec の **Ph4** ＋ ユーザー裁定「**直交 90° 迷路**」(2026-06-22)。
- **親**: `docs/ROADMAP.md` #12 / 設計 spec [`2026-06-21-chomp-sill-reinterpretation-design.md`](2026-06-21-chomp-sill-reinterpretation-design.md)
- **ブランチ**: `feat-chomp-12`（origin/main から先行・**単一ディレクトリ運用**＝クラッシュ後 worktree `sill-wt-chomp` 廃止）。⚠ **push ゲート継続**（[[chomp-push-gate]]＝ユーザーが sill でライブ確認するまで push しない・後で「push OK」も「sill で確認済?」と再確認）。⚠ **マージ保留**＝#12 全フェーズ完了まで merge/tag しない。Ph4 はライブ PASSED でも `feat-chomp-12` に積むだけ。

---

## 0. これまで（Ph1–Ph3 で確定済みの足場＝Ph4 はこれらを合成するだけ）

- **PixelArt**（pure）: `PixelSprite`・`pacManCells(diameterCells:mouthHalfRad:)`・`positionHash01(x:y:)`・`ScaleTier{.s,.m,.l}=×2/×3/×4.5`。
- **Effects スプライト**（`Sprite.swift`・AppKit gate）: `drawPixelSprite(_:cell:at:color:)`／`drawPacMan(diameterCells:mouthHalfRad:cell:at:)`＝**AA off**・**`isFlipped`(y-down) 前提で row0 が下方向**・`CanonicalSprite.cherry`(12×13)/`ghost`。色は `SpriteColor` intrinsic（`pacYellow 0xFFEA00`・`pupilBlue 0x2121FF`＝**壁の青**・`cherryRed`…）。
- **TrailGeometry**（`Trail.swift`・pure＋AppKit gate）: `resampleAlongPolyline(_:interval:trimTail:)→[TrailMark(point,tangent)]`・`roundedCornerPath(_:radius:)→[PathStep]`・`nsBezierPath(_:lineWidth:)`・`polylineLength`・`markAtArcLength`・`pathPetCursors`。
- **PathPet (Ph3)**（`Effects.swift`）: `drawChompPath(path,now,valid,scale,speed,faceLag,showGuide)`＝頭が弧長先行→顔 `faceLag` 追従。pac は tangent rotate＋口パク(`frameStep` 5Hz)、ghost は**直立**＋`GhostLook.facing`＋`dampedSine`(6/7) パニック。ホストは **NON-flipped (y-up)**・内部でフリップ。

## 1. Ph4 のゴール（spec 表 Ph4 行・確定済み）

**ネオンコリドー（2 ストローク壁＋内角フィレット）＋中央ペレット列＋`positionHash01` で cherry/icon 分け＋`ScaleTier`。道形 = 直交 90° 迷路**（ユーザー裁定・spec「90° スナップ前提・フィレットは 90° 頂点用」と一致）。

- **deliverable** = prism 新規「**Neon Corridor**」ライブカード（`.particles` タブ・PathPet カードの隣）。直角コリドーを pac が周回、中央にペレット列（cherry / app-icon / dot）。
- **Ph3 斜め PathPet カードは残置**＝「任意ジェスチャーを歩く」デモとして共存（2 カードで役割分担）。
- ⚠ **スコープ外＝Ph5**: 食べ判定(`eatCrossed`)・虹フラッシュ・「+N」スコア・**ペレット消滅**。Ph4 のペレットは**静的**（まだ消えない）。

## 2. 実装（Effects・additive）

### 2.1 純粋ジオメトリ（`Trail.swift`／XCTest 可＝CI ガード）

- **`interiorCorners(_ path:) -> [CornerFillet]`**（pure）= ポリラインの各中間頂点 B で、入セグメント単位 `inU`・出セグメント単位 `outU` から **凹コーナー**（道の内側に折れる側）を判定。返り値 = `(vertex, bisector, ...)`。
  - 二等分線 `bisector = normalize(-inU + outU)`（頂点から見て**凹側**を指す向きに符号調整＝turn の外積符号で決定）。
  - フィレット中心 `= vertex + bisector * (wallOffset*√2)`、半径 `= wallThickness*0.5`（spec の式）。
  - 直交前提では turn は ±90°＝`bisector` は軸対角。テスト: L 字 / 直線（角ゼロ）/ U 字 / 直交スネークで **角数・bisector 向き・凹凸判定**。

### 2.2 合成レンダラ `drawChompCorridor(...)`（AppKit gate）

シグネチャ（案）: `drawChompCorridor(_ path:[CGPoint], now:CFTimeInterval, valid:Bool=true, scale:CGFloat=1, tier:ScaleTier = .m, speed:CGFloat=60, faceLag:CGFloat=0, icon:NSImage? = nil)`。描画順（下→上）:

1. **黒道＋2 ストロークネオン壁**（不透明カード適応＝spec「黒道を実塗り」）: `roundedCornerPath(path, radius)→nsBezierPath` を
   - ① **ネオン青**で `lineWidth = roadWidth + 2*wallThickness`（外壁の外縁まで・`NSShadow` で軽くグロー）
   - ② **黒**で `lineWidth = roadWidth`（道を抜く）
   → 差分バンド（両側 `wallThickness`）だけがネオン壁。`round` join で外角丸。**頂点アーティファクト回避**＝spec の肝。
2. **内角フィレット**: `interiorCorners` の凹コーナー各中心に **黒円**（`wallThickness*0.5`）を fill＝内側ネオン角を削る。
   - ⚠ ①が `round` join で既に角を丸めるため、**フィレットが視覚的に効くかはオフスクリーン PNG ＋ライブで確認**（効かなければ簡略化/省略を敵対的レビューで判断＝spec を盲信せず実物で検証）。
3. **中央ペレット列**: `resampleAlongPolyline(path, interval: pelletSpacing, trimTail:0)`。各 `mark` で `h = positionHash01(round(x),round(y))` → **`h<0.04`: cherry**(`drawPixelSprite(.cherry)`)・**`h<0.08`: icon**(`icon` 非 nil ならピクセル風に描画、nil なら dot)・**else: 黄 dot**(径 `pelletR`)。**先頭 mark は除外**（ライブカーソル近傍のチラ防止＝spec）。
4. **追従 pac / 不一致 ghost**: **Ph3 を再利用**＝壁/フィレット/ペレットを敷いた上に `drawChompPath(path, now, valid, scale, speed, faceLag, showGuide:false)` を呼ぶ（**コード重複ゼロ**・pac/ghost のクロック・配向・口パク・パニックは Ph3 のまま）。`showGuide:false` で Ph3 の薄トレイルは出さない（壁が道を示すため）。

### 2.3 `ScaleTier` 適用

`tier.multiplier`(2/3/4.5) に比例: `roadWidth`・`wallThickness`・`pelletR`・`pelletSpacing`・`filletR`・`faceLag(=tier×~90pt)`。既存 `scale`（prism の `uiScale`＝カード解像度）とは**別軸**で両立（`tier`=アーケードの絶対寸法感、`scale`=描画倍率）。基準値は実装時に prism ライブで詰める。

## 3. 座標系（spec リスク #6 ＝混在注意・最重要）

- 全レイヤを **y-up（NON-flipped ホスト）に統一**＝Ph3 PathPet と同じホストに乗せる。
- `resampleAlongPolyline`/`roundedCornerPath` は**座標非依存**＝そのまま。
- スプライト（cherry/pac/ghost）は内部 y-down 前提だが、`drawChompPath`/`drawPixelSprite` の**呼び出し側フリップ**（Ph2/Ph3 で確立）を踏襲。
- **オフスクリーン PNG レンダで「壁・フィレット・ペレット・pac が全部正立・道の上に乗る・下辺で逆さにならない」を実証**（Ph1–3 と同手法＝向き確定の証拠。agent は画面収録不可なので prism ウィンドウ撮影はユーザー）。

## 4. prism カード（`PixelArtShowcase.swift` に追加）

- 新規 `CorridorNSView`＋`NeonCorridorView: NSViewRepresentable`: `orthogonalMazePath(in:tier:)`（直角スネークの 90° ポリライン＝prism 側 helper）を **内蔵 60Hz timer**で `drawChompCorridor` 駆動・`PRISM_CHOMP_T` freeze 対応（Ph2/Ph3 のライブ NSView パターン）。
- **icon サンプル** = Simple Icons の 1 つ（例 `swift`）をピクセル風に（暫定・ライブで調整）。
- `valid:false` の不一致ゴースト版も小さく併置（Ph3 と対）。
- `ScaleTier` ladder（s/m/l）を見せる静的小カードも検討（spec deliverable「ボーナス」可視化）。
- Ph3 斜め PathPet カードは**残置**。

## 5. テスト（`Tests/` 必須＝CLT ローカルは `swift build` のみ・CI が `swift test` を守る・[[sweep-include-tests]]）

- **`TrailTests`**: `interiorCorners`（L 字 / 直線=角ゼロ / U 字 / 直交スネークで角数・bisector 向き・凹判定）。
- **`EffectsTests`**: `drawChompCorridor` スモーク（空 path / 1 点 / 2 点で no-op・クラッシュなし）。
- **`PixelArtTests`**: `positionHash01` 安定性は Ph1 済（バンド閾値 0.04/0.08 は自明＝軽く分布確認）。
- maze path helper を純粋化したら直交性テスト（各セグメント軸平行）。
- ⚠ 型/import 漏れ注意（`swift build` のみがローカルゲート・9d の `import Foundation` 漏れ赤の教訓）。

## 6. 検証ゲート（順）

`swift build`（ローカル緑）→ **オフスクリーン PNG レンダ**（壁/フィレット/ペレット/pac 正立を実証）→ prism ライブ（**ユーザー**＝push ゲート）→ **敵対的レビュー workflow**（4観点: ① ジオメトリ座標系 ② 2 ストローク&フィレット忠実度 ③ 決定論クロック ④ テスト/sill 規約）= must-fix 反映 → ユーザー sill ライブ最終確認。**マージ・タグはしない**（Ph5 完了まで `feat-chomp-12` に積む）。

## 7. スコープ外（= Ph5 で実装）

`eatCrossed(arc:prev:cur:)` 食べ判定・虹フラッシュ（`EffectSpec.chomp`＋`rollFlash`/`resolveBorder` 再利用）・「+N」スコアポップ（`Motion` rise+fade・ボーナスプール `[100,200,…,5000]`）・ペレット消滅 → **合成 `ChompCorridor` 完成**。
