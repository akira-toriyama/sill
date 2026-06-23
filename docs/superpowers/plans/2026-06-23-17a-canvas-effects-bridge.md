# #17a 実装プラン — Canvas/エフェクト橋（build-best 版）

> 設計 spec: [`2026-06-23-17a-canvas-effects-bridge-design.md`](../specs/2026-06-23-17a-canvas-effects-bridge-design.md)。
> ユーザー裁定 2 件（2026-06-23）: ① 粒子＋splatter は **Canvas 再実装でなく NSViewRepresentable バイト等価昇格**（グロー fidelity 優先・spec §3 の Canvas-native から意図的逸脱）。② 「prism デモの逐語コピー」でなく **build-best＝下層ドロー関数の汎用性をそのまま公開する薄い汎用部品**（path/emitter/sprite/icon を入力化・prism は従来のデモデータを渡してバイト等価）。
> 調査が訂正した spec の前提: `Sources/Trail/` は無く trail 幾何は `Effects/{Trail,CorridorEat}.swift`、canonical スプライト/blitter は `Effects/Sprite.swift`。よって **ThemeKitUI に足す依存は `Motion` ＋ `PixelArt` のみ**（Trail は `Effects` 依存でカバー済）。

## 方針（要点）

- **下層のドロー関数は既に汎用**（`drawChompPath(path:…)`・`drawChompCorridor(path:icon:…)`・`drawLinePets(pets:on:rect…)`・`drawPixelSprite(sprite:at:)`・`rollBurst(from: emitters)`・`rollSplatter(at:…)`）。ハードコードは prism のデモビューだけ（zigzag/maze・サンプル行・auto-center）。
- 各公開部品＝**薄い `NSViewRepresentable`**（タイマ＋`frozen` seam＋`scale` を所有 → 既存バイト等価ドロー関数を**汎用入力**で呼ぶ）。背景は塗らず透明（消費者が背景を合成＝prism は SwiftUI `.background` で従来同色の黒を供給）。
- prism は **純 consumer**：`Mock*` が従来のデモデータで公開部品を合成 → **エフェクト描画はバイト等価**。
- **catalog デモは prism ローカル据え置き**（消費アプリ無し）：pac+tier ladder（`PacLadderView` 新規・`pacManCells`/`ScaleTier` 参照）、`MockTrail`(trail 幾何 viz)・`MockMotion`(easing plot)・`LiveEffectStrip`(border 色 strip)。

## ① Package.swift

`ThemeKitUI` ターゲット依存に **`Motion`・`PixelArt`** を追加：
```swift
.target(name: "ThemeKitUI",
        dependencies: ["ThemeKit", "PaletteKit", "Effects", "Motion", "PixelArt"]),
```

## ② 6 公開部品（`Sources/ThemeKitUI/` に新規・全 `public struct … : NSViewRepresentable`）

各ファイル＝裏の `final class …NSView`（プライベート・module 内）＋ public 橋。クロック所有（60Hz Timer・`viewDidMoveToWindow` 起停・`frozen` で停止）。`isFlipped` は元のまま（粒子/splatter/sprite=flipped, line-pets/path/corridor=非 flipped）。背景塗りは**削除**（透明）。`uiScale` 参照は `scale` パラメータへ（既定 1）。env 読み（`PRISM_*_T`）は削除し公開 `frozen: Double?` へ。

### 1. `ParticleBurstView.swift` ← ParticleFieldView/ParticleBurstNSView（perch particle・wand burst）
```swift
public struct ParticleBurstView: NSViewRepresentable {
    public var emission: ParticleEmission
    public var colors: [UInt32]
    public var intensity: EffectIntensity        // 旧: ハードコード .bold
    public var duration: TimeInterval            // 旧: emission で分岐
    public var radiusSpeed: Double               // 旧: emission で分岐
    public var loopPeriod: Double?               // nil=一発, 非nil=周期で再ロール（旧: duration+0.4）
    public var emitters: (CGRect) -> [CGPoint]   // bounds→emitter点（旧: emission で 0.46h/0.94h）
    public var scale: CGFloat
    public var frozen: Double?                   // 0…1 of duration; nil=live
    public init(emission: ParticleEmission = .fireworks, colors: [UInt32],
                intensity: EffectIntensity = .bold, duration: TimeInterval = 1.1,
                radiusSpeed: Double = 0, loopPeriod: Double? = nil, scale: CGFloat = 1,
                frozen: Double? = nil,
                emitters: @escaping (CGRect) -> [CGPoint] = { [CGPoint(x: $0.midX, y: $0.midY)] })
}
```
draw: freeze 時 `rollBurst(emission:from: emitters(bounds):colors:intensity:now:0:duration:radiusSpeed:)` を保持して `drawParticles(b, now: clamp(frozen)*duration, scale: scale)`。live 時は `loopPeriod` で再ロール → `drawParticles(b, now:, scale: scale)`。**ロール入力 `now:0` の固定・clamp 等は元コードと一致**。

### 2. `InkSplatterView.swift` ← SplatterFieldView/SplatterNSView（wand decal）
```swift
public struct InkSplatterView: NSViewRepresentable {
    public var colors: [UInt32]
    public var center: (CGRect) -> CGPoint   // 旧: midX,midY
    public var size: (CGRect) -> Double      // 旧: min(w,h)*0.78
    public var seed: UInt64?                 // live: nil=毎回ランダム
    public var duration: TimeInterval        // 旧: 1.4
    public var loopPeriod: Double?           // 旧: 1.4+0.4
    public var frozen: Double?               // 0…1 of duration
    public init(colors:, seed: UInt64? = nil, duration: TimeInterval = 1.4,
                loopPeriod: Double? = nil, frozen: Double? = nil,
                center: @escaping (CGRect)->CGPoint = { CGPoint(x:$0.midX,y:$0.midY) },
                size:   @escaping (CGRect)->Double  = { Double(min($0.width,$0.height))*0.78 })
}
```
freeze 時の決定論シード既定 `static let frozenSeedDefault: UInt64 = 0xC0FFEE`（`frozen != nil && seed == nil` のとき使用）＝旧 freeze の 0xC0FFEE と一致。`drawInkSplatter` に scale 引数は無い（size が解像度ノブ）。

### 3. `PixelSpriteView.swift` ← 新規（facet pet＝共有 antialias-off blitter）
```swift
public struct PixelSpriteView: NSViewRepresentable {
    public var frames: [PixelSprite]   // 1要素=静止
    public var hz: Double              // frames.count>1 のとき frameStep
    public var cell: CGFloat           // 1ピクセルの pt
    public var color: UInt32?          // tint 上書き（nil=sprite 固有色）
    public var frozen: Double?         // 絶対秒
    public init(frames:, hz: Double = CanonicalSprite.waddleHz, cell:, color: UInt32? = nil, frozen: Double? = nil)
    public init(sprite: PixelSprite, cell: CGFloat, color: UInt32? = nil)  // 静止 convenience
}
```
draw: `isFlipped`（row0=top）・透明背景・`drawPixelSprite(frameStep(now,hz,frames), cell:, at: .zero, color:)`。`sizeThatFits` = 先頭 frame の `pixelSize(cell:)`。**消費者 = facet pet**（§0.6 の「小さな NSViewRepresentable blitter」を sill が供給）。prism showcase = cherry 静止 + ghost waddle + 4方向 ghost を本部品で（旧 4-dir strip を置換）。

### 4. `LinePetsView.swift` ← LinePetWalkView/LinePetWalkNSView（halo ring・facet）
```swift
public struct LinePetsView: NSViewRepresentable {
    public var pets: [LinePet]      // 旧: [.chomp, .ghost] 固定
    public var inset: CGFloat       // 旧: 18*uiScale
    public var scale: CGFloat       // pet 倍率
    public var speed: CGFloat       // 旧: 70*uiScale
    public var frozen: Double?      // 絶対秒
    public init(pets: [LinePet] = [.chomp, .ghost], inset: CGFloat = 18, scale: CGFloat = 1,
                speed: CGFloat = 70, frozen: Double? = nil)
}
```
draw: 非 flipped・透明・`drawLinePets(pets, on: bounds.insetBy(dx:inset*scale,dy:inset*scale), now:, scale: scale, speed: speed*scale)`。**prism との等価**: prism は `pets=[.chomp,.ghost], inset=18, scale=1.6*uiScale 相当, speed=70*uiScale` を渡す（旧 `petScale*uiScale` と `70*uiScale` を再現するよう scale/inset/speed を合成）。⚠ 旧は `inset=18*uiScale`(uiScale で固定 18) かつ `scale=petScale*uiScale`・`speed=70*uiScale`。等価には prism 側で `scale: 1.6*uiScale, speed: 70*uiScale, inset: 18*uiScale/(1.6*uiScale)=…` の調整が必要 → **inset を「絶対 pt」入力**にして prism が `18*uiScale` を直接渡す方が安全（下記実装で inset を scale 乗算しない素の pt にする）。実装時にバイト等価を offscreen で確認。

### 5. `PathPetView.swift` ← PathPetView/PathPetNSView（wand trail）
```swift
public struct PathPetView: NSViewRepresentable {
    public var path: (CGRect) -> [CGPoint]   // 旧: zigzagPath(in: inset)
    public var valid: Bool
    public var scale: CGFloat
    public var speed: CGFloat                 // 旧: 60*uiScale
    public var faceLag: CGFloat               // 旧: valid ? scale*15*uiScale : 0
    public var showGuide: Bool
    public var frozen: Double?
    public init(path:, valid: Bool = true, scale: CGFloat = 1, speed: CGFloat = 60,
                faceLag: CGFloat = 0, showGuide: Bool = true, frozen: Double? = nil)
}
```
draw: 非 flipped・透明・`drawChompPath(path(bounds), now:, valid:, scale:, speed:, faceLag:, showGuide:)`。prism は zigzag 生成クロージャ＋`inset 26/22*uiScale`＋`scale 2.4/1.9*uiScale`＋`speed 60*uiScale`＋`faceLag` を渡しバイト等価。

### 6. `ChompCorridorView.swift` ← NeonCorridorView/CorridorNSView（wand arcade）
```swift
public struct ChompCorridorView: NSViewRepresentable {
    public var path: (CGRect) -> [CGPoint]   // 旧: orthogonalMazePath
    public var valid: Bool
    public var tier: ScaleTier
    public var icon: NSImage?                 // 旧: corridorBonusIcon（prism star）
    public var showBonuses: Bool
    public var scale: CGFloat                 // 旧: uiScale
    public var speed: CGFloat                 // 旧: 64*uiScale
    public var frozen: Double?
    public init(path:, valid: Bool = true, tier: ScaleTier = .m, icon: NSImage? = nil,
                showBonuses: Bool = true, scale: CGFloat = 1, speed: CGFloat = 64, frozen: Double? = nil)
}
```
draw: 非 flipped・透明・`drawChompCorridor(path(bounds), now:, valid:, tier:, scale:, speed:, icon:, showBonuses:)`。prism は maze 生成＋`inset 34/30*uiScale`＋star icon＋`scale uiScale`＋`speed 64*uiScale` を渡す。

## ③ prism = 純 consumer

- **ParticleShowcase.swift**: `ParticleBurstNSView`/`ParticleFieldView` 削除。`import ThemeKitUI`。`MockParticles.stage(...)` が `ParticleBurstView(emission:..., colors: burstColors, intensity:.bold, duration: emission==.fireworks ?1.05:1.6, radiusSpeed: emission==.fireworks ? -2.0:0, loopPeriod: dur+0.4, scale: uiScale, frozen: PRISM_PARTICLE_T, emitters: { emission==.fireworks ? [CGPoint(x:$0.midX,y:$0.height*0.46)] : [CGPoint(x:$0.midX,y:$0.height*0.94)] })`。`hexU32`/`festiveHues`/env 読みは prism に残す。
- **SplatterShowcase.swift**: `SplatterNSView`/`SplatterFieldView` 削除。`MockSplatter` が `InkSplatterView(colors: inkColors, duration:1.4, loopPeriod:1.4+0.4, frozen: PRISM_PARTICLE_T)`（center/size 既定が旧と一致）。
- **PixelArtShowcase.swift**:
  - 削除→公開部品化: `LinePetWalkView`→`LinePetsView`、`PathPetView`(prism)→`ThemeKitUI.PathPetView`、`NeonCorridorView`→`ChompCorridorView`。`zigzagPath`/`orthogonalMazePath`/`corridorBonusIcon` は prism に残し path クロージャ/icon として注入。
  - `PixelArtFieldView` の **cherry/ghost/4方向 ghost 部分**→ `PixelSpriteView` 合成specimenに置換（promoted atom の showcase）。**pac + tier ladder** は prism ローカル新規 `PacLadderView`(NSView) に分離（`pacManCells`+`ScaleTier` 参照デモ）。
  - env `PRISM_CHOMP_T` 読みは prism に残し `frozen:` で注入。`startRedrawTick` は各公開部品が自前で持つので prism から削除（`PacLadderView` 用に小さく残すか流用）。
- **Gallery.swift / KitCatalog.swift**: 変更なし（`kitComponent("ParticleBurst"/"SplatterShape"/"TrailGeometry"/"PixelSprite")` 名は据え置き、`Mock*` 名も据え置き）。

## ④ 据え置き（設計判断・繰延でなく）

`MockTrail`(trail 幾何 chevron viz)・`MockMotion`(easing カーブ plot)・`LiveEffectStrip`(border 色 strip) は**開発者向け可視化**で消費アプリ無し → prism のまま（border 本体は公開済 `ThemedBorderView`）。`PacLadderView`(pac+tier ladder)・catalog 参照も prism ローカル。

## ⑤ 検証

1. `swift build` 緑（CLT ローカル＝唯一のローカルゲート）。
2. **offscreen PNG レンダ**で各公開部品が旧と同絵か（向き・グロー・レイアウト）を agent 側で確認（[[chomp-push-gate]]＝agent は画面収録不可だが offscreen レンダは可）。
3. **敵対的レビュー**（部品毎: ①旧 NSView とのバイト等価〔ロール入力・clamp・isFlipped・metrics〕②`frozen` seam ③`scale` 合成 ④API 汎用性 — finding 毎に独立検証）。
4. **CI**（full Xcode `swift test`＝既存テストが回帰ネット・ThemeKitUI テストターゲットは #16 同様無し＝純 @MainActor view コード）。
5. **prism ライブ目視 = maintainer ゲート**（[[prism-bench]]・`particles`/`motion` タブ・各エフェクトが前後同一に動く・特に line-pets の inset/scale 合成と sprite section の再レイアウト）。
6. squash-merge ＋ **`v1.24.0`**（push 前に未使用版確認＝[[parallel-work-hazard]]）。

## 進捗

- [ ] ① Package.swift deps（Motion+PixelArt）
- [ ] ② 6 公開部品（ParticleBurst/InkSplatter/PixelSprite/LinePets/PathPet/ChompCorridor）
- [ ] ③ prism consumer 化（3 showcase + PacLadderView）
- [ ] ④ swift build 緑 + offscreen 確認
- [ ] ⑤ 敵対的レビュー + CI
- [ ] ⑥ maintainer ライブゲート → merge + v1.24.0
