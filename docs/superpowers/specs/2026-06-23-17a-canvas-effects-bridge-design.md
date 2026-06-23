# #17a — Canvas 粒子/スプライト/line-pets 系（SwiftUI エフェクト橋）設計

> Phase A 最優先（[ROADMAP](../../ROADMAP.md) 参照）。**ユーザー設計承認済 2026-06-23。** 別セッションが本書だけで実装着手できるよう書く。
> 根拠調査: 2-agent コードサーベイ（sill エフェクト面の純粋/AppKit 切り分け＋prism の現行ホスティング＋Canvas 可否）2026-06-23。

## 1. 目的・位置づけ

**#16 と同じ動きを「アニメ層」に対して行う**: 現状 prism に in-tree で散在する「エフェクト描画」を **公開 `ThemeKitUI` ビューに昇格**し、prism を最初の consumer にする（ドリフトゼロ）。対象＝粒子(spark/paper)・ink splatter・trail・border・pixel sprite・line-pets(pac/ghost)・chomp corridor。
将来 Phase B で wand(trail/arcade)・perch(particle)・halo(ring)・facet(pet/line-pets) が同じ公開ビューを consumer にする（5アプリ横断＝最頻出ゆえ最優先）。

## 2. 既存コードの状態（調査結論・実装者はここを足場に）

- **純粋 `f(now)` 層は ~95% 完成**（Sendable・AppKit-free）。再利用する純粋関数:
  - `Effects`: `blendThrough`/`rollFlash`/`resolveBorder`/`BorderFrame`（border）, `rollBurst`/`resolveParticles`/`ResolvedParticle`（粒子）, `linePetPosition`（pet 周回）, `rollSplatter`/`tendrilBlob`/`SplatterShape.alpha`（splatter）, `chompFlashPhase`/`chompScorePops`/`corridorLapPhase`（corridor）。
  - `Trail`: `resampleAlongPolyline`/`roundedCornerPath`/`markAtArcLength`/`polylineLength`/`pathPetCursors`/`eatCrossed`/`PathStep`/`interiorCorners`。
  - `PixelArt`: `PixelSprite.cells()`/`pacManCells`/`mouthHalfRad`/`positionHash01`/`CanonicalSprite`/`SpriteColor`/`bonusValue`。
  - `Motion`: `Tween`/`frameStep`/`Easing`/`lerp`/`spring`/`dampedSine`。
- **AppKit draw 層**（`#if canImport(AppKit)`・`@MainActor`）が薄く乗っている: `drawParticles`/`drawSpark`/`drawPaper`・`drawInkSplatter`(+`catmullRomPath`)・`drawLinePets`/`drawChompPath`/`drawChompCorridor`・`drawPixelSprite`/`drawPacMan`・`drawScorePop`。
- **prism の現行ホスティング（2パターン・実績）**:
  - ネイティブ **`Canvas` + `TimelineView(.animation 1/60)`**: `TrailShowcase`・`MotionShowcase`・`EffectShowcase`（border）。`GraphicsContext` で `fill`/`stroke`/`addFilter(.shadow)` 実証済。
  - **`NSViewRepresentable` + `NSView` + 60Hz `Timer` + `CACurrentMediaTime()`**: `ParticleShowcase`(`ParticleFieldView`)・`SplatterShowcase`(`SplatterFieldView`)・`PixelArtShowcase`(`PixelArtFieldView`/`LinePetWalkView`/`DirectionalGhostView`/`PathPetView`/`NeonCorridorView`)。
  - 決定論: env `PRISM_PARTICLE_T`(0…1)・`PRISM_CHOMP_T`(秒) で frozen `now` を注入。
- **ThemeKitUI 橋 idiom**（踏襲する）: `public struct X: NSViewRepresentable`／public プロパティ／`apply()` ヘルパ／必要時のみ `Coordinator`／`preview*` seam／`sizeThatFits`。

## 3. アーキテクチャ決定 = ハイブリッド

純粋 `f(now)` 層の上に薄い SwiftUI 層を2系統で載せる:

| 系統 | 対象 | 理由 |
|---|---|---|
| **ネイティブ `Canvas`+`TimelineView`**（新規 `View` 構造体） | 粒子(spark/paper)・ink splatter・trail・border | `GraphicsContext` が fill/stroke/shadow/blend を出せる。prism Trail/Motion/Effect で実証済。AppKit 不要＝純 SwiftUI。 |
| **`NSViewRepresentable`**（prism NSView+timer を昇格） | **pixel sprite・line-pets(pac/ghost)・chomp corridor のスプライト部** | **唯一の hard wall = `shouldAntialias=false` の per-pixel** が `GraphicsContext` に無い（deep-dive の「facet pet」と同根）。既存 AppKit blitter をそのまま内包。 |

- splatter の Catmull-Rom は Swift 側で `Path` を組めば Canvas で stroke/fill 可（NSBezierPath 不要）。
- score-pop の**テキスト**は Canvas 非対応 → SwiftUI `Text` overlay か `GraphicsContext.draw(Text)`。
- 粒子の glow は `GraphicsContext.addFilter(.shadow)`（`NSShadow` と微差の可能性＝実機目視で許容判断）。

## 4. 決定論 seam（必須）

各ビューに **`frozen: Double?`（or `previewT`）** プロパティを公開（prism の `PRISM_*_T` env を公開プロパティ化＝ThemeKitUI の `preview*` idiom と同型）。
- 非 nil = その `now`/phase で 1 フレーム固定（静止スクショ＝maintainer ゲート用）。
- nil = ライブ（Canvas 系＝`TimelineView(.animation 1/60)`、NSView 系＝60Hz timer）。
- clock 契約は f(now)＝replayable を維持（既存どおり）。

## 5. 置き場所・依存

- 新規ビューは **`ThemeKitUI`** に追加（SwiftUI 橋モジュール）。
- `Package.swift`: ThemeKitUI の deps に **PixelArt・Trail・Motion を追加**（現状 ThemeKit/PaletteKit/Effects）。`Effects` は既に依存。
- **prism を consumer に**: in-tree の `ParticleFieldView`/`SplatterFieldView`/`PixelArt*View`/`LinePetWalkView`/`DirectionalGhostView`/`PathPetView`/`NeonCorridorView` を削除し `import ThemeKitUI`（#16 と同じドリフトゼロ）。`TrailShowcase`/`MotionShowcase`/`EffectShowcase` の Canvas ロジックも公開ビューへ抽出して prism は薄く。

## 6. 実装手順（subagent-driven 推奨・#16/#15 と同型）

1. ThemeKitUI に Canvas 系ビュー（Particle/Splatter/Trail/Border）を新規（純粋関数を `GraphicsContext` で描画＋`frozen` seam）。
2. ThemeKitUI に NSViewRepresentable 系ビュー（PixelSprite/LinePets/Corridor）を prism から昇格（既存 NSView+timer を移植＋`frozen` seam）。
3. `Package.swift` deps 追加。
4. prism を consumer 化（in-tree 橋削除→import・ドリフトゼロ確認）。
5. 検証: `swift build` 緑＋**prism ライブ目視（maintainer ゲート・[[prism-bench]]・各 showcase が同一に動く）**＋敵対レビュー（finding 毎に独立検証）＋CI（`swift test`・full Xcode）。

## 7. 注意・リスク

- **antialias-off pixel sprite は Canvas で不可**＝NSViewRepresentable 維持（設計の前提・覆さない）。
- 粒子 glow / score-pop テキストは SwiftUI 側で微差が出うる＝**実機目視で許容判断**（agent は画面収録不可）。
- 公開 API churn 最小: prism が唯一の consumer なので命名は自由に best へ（[[build-best-then-migrate]]）。
- library 変更＝**minor bump + `v`-tag**（`v1.24.0` 目安）。push 前に未使用版確認（[[parallel-work-hazard]]）。
