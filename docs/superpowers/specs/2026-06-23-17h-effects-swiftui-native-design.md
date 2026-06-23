# #17h — #17a の AppKit 残骸を SwiftUI native へ是正（設計）

> ROADMAP **#17h**（Phase A）。**ユーザー設計承認済 2026-06-23（「提案の方法でOK GO」）。** 別セッションが本書だけで着手できるよう書く。
> 根拠調査: #17a でシップした6エフェクト橋（`ParticleBurstView`/`InkSplatterView`/`PixelSpriteView`/`LinePetsView`/`PathPetView`/`ChompCorridorView`）＋`EffectClock` の現行コード読み込み＋`Effects`/`PixelArt`/`Trail`/`Motion` の純粋層 public 可視性確認（2026-06-23・code-level）。

## 1. 目的・位置づけ

#17a は「prism のエフェクト描画を公開 `ThemeKitUI` ビューへ昇格」を**`NSViewRepresentable` バイト等価昇格**で実現した（glow fidelity 優先のユーザー裁定）。だが **2026-06-23 確定の AppKit 使用可ポリシー**（CLAUDE.md／ROADMAP #16.5/#17）により、これら6ビューの `NSViewRepresentable`（粒子+splatter の `NSShadow` glow／pixel-sprite・line-pets・path-pet・chomp の `shouldAntialias=false`）は **ポリシー違反＝是正対象**。

**#17h = この6ビューを NATIVE SwiftUI に書き換える**。完了時、`ThemeKitUI` のこれら6ビューは **`NSViewRepresentable` ゼロ・`NSShadow`/`shouldAntialias`/AppKit draw 呼び出しゼロ**。`v1.24.0`（#17a）のシップは史実として保持。

**ガバナンス（ユーザー確定 2026-06-23）**: 作業順序は実装者に一任。ただし **end-state で AppKit 使用範囲ルール（床2個＝IME 編集コア＋窓の殻）を担保する**ことが条件。SwiftUI でどうしても出せない fidelity 点（glow 等）が判明したら、**黙って AppKit に戻さず必ず要相談**（事前の AppKit 維持承認はしない）。**AppKit の使用範囲を広げたい時も必ず要相談。**

> ※ #16 の14ウィジェット橋（Button/List/…）は本項目のスコープ外＝#17b〜で順次 native 化。#17h は **#17a の6エフェクト橋のみ**を是正する。

## 2. 既存コードの状態（実装者の足場）

### 2.1 純粋 `f(now)` 層 — そのまま消費（変更しない）
すべて Sendable・AppKit-free。native 描画はこれを読むだけ。
- **Particles**（`Sources/Effects/Particles.swift`）: `public func resolveParticles(_:now:) -> [ResolvedParticle]`、`public struct ResolvedParticle`（`shape`/`x`/`y`/`radius`/`alpha`/`color`/`rotation`）、`public enum ParticleShape{.spark,.paper}`、`rollBurst`、`ParticleBurst`。
- **Splatter**（`Sources/Effects/Splatter.swift`）: `public struct SplatterShape`（`.units` の各 `Unit.rim/.body/.droplets: [(x,y)]` + `color`、`func alpha(now:) -> Double`）、`rollSplatter`。
- **PixelArt**（`Sources/PixelArt/`）: `PixelSprite.cells() -> [(col,row,color)]`、`pacManCells(diameterCells:mouthHalfRad:)`、`mouthHalfRad`、`positionHash01`、`bonusValue`、`chompMouthFrames`/`chompMouthHz`。
- **Sprite/canonical**（`Sources/Effects/Sprite.swift`）: `SpriteColor`、`GhostLook`/`.facing(dx:dy:)`、`CanonicalSprite`（`cherry`/`waddleFrames`/`waddleHz`/`ghostFrames(look:)`/`ghostSprite(feet:look:)`）。
- **Trail**（`Sources/Effects/Trail.swift`・CGPoint オーバーロードあり）: `polylineLength`、`resampleAlongPolyline`、`markAtArcLength`、`pathPetCursors`、`eatCrossed`、`roundedCornerPath`、`interiorCorners`、`PathStep`、`TrailMark`、`InteriorCorner`。
- **Corridor**（`Sources/Effects/CorridorEat.swift`）: `chompFlashPhase`、`chompScorePops`、`ScorePop`、`chompEatFlashDur`、`chompScorePopDur`。
- **色**（`Sources/Effects/Effects.swift`）: `blendThrough(_:at:)`、`EffectSpec.chomp.flash`。
- **Motion**（`Sources/Motion/`）: `ThemedTransition.frameStep(now:hz:frames:)`、`Easing.easeOutCubic`、`dampedSine`、`lerp`、`spring`。

### 2.2 現在 private で **public 化（または純粋セレクタへ吸収）が要る** pet 配置ロジック
`Sources/Effects/Effects.swift`:
- `private func linePetPosition(on:distance:) -> (x,y,rot)`（周回・行768）
- `private let chompFaceCells = 13` / `chompFaceFootprint: CGFloat = 14` / `ghostFootprint: CGFloat = 14`（行785–787）
- `private let pathPetPanicHz: Double = 1.5`（行588）
- `private func drawChompPet`/`drawGhostPet`（@MainActor AppKit draw）— **「now→今描くスプライト」の純粋部だけ抜き出す**（mouth=`frameStep(now,hz:chompMouthHz,frames:chompMouthFrames)`→`pacManCells(d:chompFaceCells,mouthHalfRad:)`、ghost=`frameStep(now,hz:waddleHz,frames:ghostFrames(look:))`）。

### 2.3 AppKit draw 層 — **Effects に残置**（呼ばなくなるだけ）
`drawParticles`/`drawSpark`/`drawPaper`・`drawInkSplatter`/`catmullRomPath`・`drawPixelSprite`/`drawPacMan`・`drawLinePets`/`drawChompPath`/`drawChompCorridor`/`drawCenteredSprite`/`drawCorridorIcon`・`drawScorePop`・`drawChompPet(Smooth)`/`drawGhostPet(Smooth)`。
`Effects` は CLAUDE.md 公認の **AppKit draw 層**＝これら自体はポリシー違反ではない（違反は ThemeKitUI が `NSViewRepresentable` で包んでいたこと）。**残置**＝史実/リファレンス/既存 XCTest 維持。policy が問うのは ThemeKitUI 残骸だけ。
> ※ これらが #17h 後に「ThemeKitUI から未使用」になる点は build-best 観点で将来の削除候補だが、**本項目では削除しない**（AppKit reference renderer + 既存テストを保全。削除は blast-radius が別物＝別途判断）。

### 2.4 consumer と依存
- **prism が唯一の consumer**（`ParticleShowcase`/`SplatterShowcase`/`PixelArtShowcase` が6ビューを公開 API で消費）。→ **公開 struct の API（プロパティ名・`init`・`frozen`/`loopPeriod`/`scale`/`emitters` 等）を完全保持すれば prism 無改修。**
- `Package.swift`: ThemeKitUI deps = `["ThemeKit","PaletteKit","Effects","Motion","PixelArt"]`。Trail 関数は Effects 内。**Package.swift 変更不要。**

## 3. アーキテクチャ決定

**原則 = 1シーン1 `Canvas` + `TimelineView(.animation)`／ピクセル絵だけ `Image(.interpolation(.none))`。**

| 技法 | 使う所 | 根拠 |
|---|---|---|
| SwiftUI `Canvas`（`GraphicsContext`） | ベクター（splatter blob・trail/壁 stroke・fillet・ペレット円・glow） | fill/stroke/`addFilter(.shadow)`/`draw(Text)` を出せる（#17a §2 で prism 実証済） |
| `GraphicsContext.addFilter(.shadow(color:radius:))` | spark glow・追従ドット・コリドー壁の発光 | `NSShadow` の native 代替。**blur 半径スケールが異なる watch-point**（§6） |
| `Image(.interpolation(.none))`（nearest-neighbor） | pixel sprite（PixelSprite/pac/ghost/cherry） | Canvas は AA off 不可（#17a の hard wall）。nearest 拡大で crisp pixel＝AA-off rect より忠実 |
| `TimelineView(.animation)` | 全ライブ描画のクロック | 60Hz timer の native 代替（ProMotion 追従・off-window 自動停止） |

### 3.1 ピクセルスプライトの native 描画
`PixelSprite`（または `pacManCells`）を **`sprite.width × sprite.height` ピクセルの `CGImage`（1px/cell・`shouldAntialias` 無関係＝1:1）** に焼き、SwiftUI `Image(decorative: cgImage, scale: 1).interpolation(.none).resizable()` で `cell×` 拡大。
- 静止/アニメ単体（`PixelSpriteView`）= SwiftUI `Image` を直接配置（Canvas 不要）。
- 回転/合成が要る pet（line-pets/path-pet/corridor）= **同一 `Canvas` 内で** `ctx.draw(ctx.resolve(Image(...).interpolation(.none)), in:)` を回転 CTM 下で描画（ベクターと同座標系で合成）。`GraphicsContext` は resolved image の interpolation を尊重＝回転下でも nearest（チャンキーな retro 回転）。
  - ⚠ **watch-point**: 回転 CTM 下で nearest が保たれるか／cherry 等の極小スプライトの可読性は **prism ライブで maintainer 確認**（§6）。万一ソフトになる場合の代替＝ZStack に `Image(.interpolation(.none)).rotationEffect()` を重ねる（SwiftUI image レンダは確実に nearest）。代替も SwiftUI 内＝AppKit に戻さない。

### 3.2 純粋セレクタの新設（additive・single-source）
`Effects`（または PixelArt）に「now→今のスプライト」を返す純粋関数を足し、ThemeKitUI と既存 AppKit draw の**両方が同じ選定を共有**:
- `chompPacSprite(now:) -> PixelSprite`（口パク phase→`pacManCells`→`PixelSprite`）
- `chompGhostSprite(now:look:) -> PixelSprite`（waddle phase→`ghostFrames(look:)` 選択）
- `linePetPosition` と定数（`chompFaceCells`/`chompFaceFootprint`/`ghostFootprint`/`pathPetPanicHz`）を **public 化**。
これで ThemeKitUI は「どこに・どの向きで・どのスプライト」を純粋層から受け取り、§3.1 で描くだけ。既存 `drawChompPet`/`drawGhostPet` もこのセレクタ経由に寄せて drift を防ぐ（任意・無理なら定数 public 化のみでも可）。

### 3.3 クロック契約（f(now) 維持）
- ライブ = `TimelineView(.animation) { ctx in let now = ... }`。
  - birth 相対（PixelSprite/LinePets/PathPet/Corridor の現行 `CACurrentMediaTime()-clockStart`）= ビュー生成時に基準 `Date` を保持し `now = context.date.timeIntervalSince(start)`。
  - 絶対/ループ（Particle/Splatter の `now - startedAt >= period`）= `now = context.date.timeIntervalSinceReferenceDate`（単調・replayable）。
- `frozen != nil` = `TimelineView` を使わず固定 `now`/fraction で1フレーム静止描画（静止スクショ＝maintainer ゲート）。**公開 `frozen` の意味（Particle/Splatter=0…1 of duration・他=絶対秒）を現行どおり保持。**

## 4. 部品別の設計

各ビューは現行の **公開 struct API を完全保持**し、内部 `makeNSView`/`updateNSView`/NSView を **SwiftUI `body`（Canvas/Image + TimelineView）** に置換。

1. **InkSplatterView** — `Canvas`。`SplatterShape.units` を `alpha(now)` で fade、各 unit の `rim`(暗blend 0.78a)→`body`(0.96a)→`droplets`(0.88a) を **Catmull-Rom→SwiftUI `Path`**（`addCurve`・現行 `catmullRomPath` と同式 1/6 tension）で fill。glow 無＝**低リスク**。
2. **PixelSpriteView** — SwiftUI `Image(.interpolation(.none))`（§3.1）。`frames.count>1` は `frameStep(now,hz,frames)` でフレーム選択→その `PixelSprite` を Image 化。`sizeThatFits` は `frames.first?.pixelSize(cell:)` 相当を維持。`color` override 対応。**低リスク**。
3. **ParticleBurstView** — `Canvas`。`resolveParticles(burst,now)` を回し、`.spark`=`ctx.addFilter(.shadow(color: base·0.85a, radius: r·2.6))`→塗り円→hot white core 円、`.paper`=translate+rotate(`rot·0.4`)+scaleX(`flip`) の CTM で角丸 rect（裏面 blend）。flipped(+y down) は Canvas 座標で表現。`loopPeriod`/`emitters`/`radiusSpeed` ロジック保持。**glow watch-point**。
4. **LinePetsView** — `Canvas`。`linePetPosition(on:track,distance:)` で各 pet の位置/回転、pac=回転スプライト・ghost=直立＋`GhostLook.facing`、§3.1 で pixel sprite 描画。NON-flipped(y-up) 契約維持。**回転ピクセル watch-point**。
5. **PathPetView** — `Canvas`。`showGuide`=`roundedCornerPath` を `Path` stroke（pupilBlue 0.22）、追従ドット=`addFilter(.shadow)`（valid+faceLag>0）、pet=`pathPetCursors`/`markAtArcLength` で位置・tangent→pac 回転 or ghost 直立+`dampedSine`(6/7) panic。**glow+回転 watch-point**。
6. **ChompCorridorView** — `Canvas`（最大の合成）。`roundedCornerPath` を太(`road+2·wall`)→細(`road`)→黒で2本 stroke、flash 中は `blendThrough(EffectSpec.chomp.flash)` 色＋強め `addFilter(.shadow)`、`interiorCorners` に黒 fillet 円、`resampleAlongPolyline` のペレット列（cherry=スプライト・icon=`ctx.draw(Image(nsImage:))`・dot=円、`faceArc>=arc` で食べ消去）、pet（#5 相当）、`chompScorePops`→`ctx.draw(Text("+N").font(.system(.monospaced,.bold)))` を `easeOutCubic` rise+fade。**glow+回転+合成＝最高リスク**。

`EffectClock.swift`（`startEffectTick` 60Hz timer）= 全ビューが `TimelineView` 化するので **削除**。

## 5. 実装手順（subagent-driven・低リスク→高リスク）

1. **純粋セレクタ/可視性**（§3.2）: `linePetPosition`+定数 public 化、`chompPacSprite`/`chompGhostSprite` 追加、`PixelSprite→CGImage` ヘルパ（ThemeKitUI 内部 util・nearest 焼き）。CI 用 XCTest（セレクタの frame 選択がフレーム境界で正しいか）。
2. **InkSplatterView** native 化（Canvas/Path）。
3. **PixelSpriteView** native 化（Image-none）。
4. **ParticleBurstView** native 化（Canvas+shadow）。
5. **LinePetsView** native 化（Canvas+回転スプライト）。
6. **PathPetView** native 化（Canvas+glow+pet）。
7. **ChompCorridorView** native 化（合成）。
8. `EffectClock.swift` 削除＋prism ビルド確認（無改修で通るはず）。
各ステップ後に `swift build` 緑を確認。タスク毎に spec 整合＋品質レビュー。

## 6. 検証・リスク

- **検証**: `swift build` 緑（local gate）＋**敵対的レビュー**（finding 毎に独立検証＝#15/#16/#17a 同型）＋**CI 緑**（full Xcode `swift test`＋lint）＋**prism ライブ目視（maintainer ゲート・[[prism-bench]]・agent は画面収録不可）**。
- **glow watch-point**: `NSShadow.shadowBlurRadius` と `GraphicsContext` `.shadow(radius:)` は blur スケールが一致しない。実装時に radius を合わせ込む（必要なら係数調整）。ライブ目視で許容外なら **要相談**（§1 ガバナンス）。
- **回転ピクセル watch-point**: §3.1 の代替（ZStack rotationEffect）も SwiftUI 内。AppKit に戻すのは禁止＝広げたい時は要相談。
- **API churn**: prism が唯一の consumer ＝公開 API 保持で無改修（命名 best は #17a で確定済）。
- **版**: library 変更＝**minor bump + `v`-tag（`v1.25.0` 目安）**。push 前に未使用版確認（[[parallel-work-hazard]]）。`EffectClock` 削除と AppKit draw 残置でも公開面は不変。

## 7. 完了の定義（end-state 担保）

- 6エフェクトビューに `NSViewRepresentable`・`NSShadow`・`shouldAntialias`・`drawParticles`/…/`drawChompCorridor` 等 AppKit draw 呼び出しが **一切無い**（`grep` で 0 を確認）。
- `EffectClock.swift` 削除。
- prism 無改修で全 showcase が同等に動く（ライブ目視）。
- `swift build`／CI 緑、敵対的レビュー confirmed-defect 0、ROADMAP #17h を完了に更新。
- SwiftUI で出せない点が出たら AppKit に戻さず要相談で解決（[[appkit-scope-is-the-hard-gate]]）。
