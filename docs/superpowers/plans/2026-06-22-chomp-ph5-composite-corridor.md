# #12 chomp — Ph5 合成 ChompCorridor 完成（食べ判定＋虹フラッシュ＋「+N」スコア）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ph4 のネオンコリドーに「食べ判定（通過でペレット消滅）・壁の虹フラッシュ・『+N』スコアポップ」を足し、合成 `ChompCorridor` を完成させる（#12 の最終フェーズ）。

**Architecture:** すべて **`now` から純粋導出（f(now)）**。顔（eater）の弧長 `pathPetCursors(...).pet` 一つから「どのペレットが食べられたか／直近に食べた時刻／アクティブな score pop」を決める。`rollFlash` の RNG は使わず `EffectSpec.chomp.flash` を `blendThrough` で時間駆動。これで `PRISM_CHOMP_T` 凍結スクショ・XCTest が決定論（sill 不変条件＝可変アニメ状態ゼロ・clock 注入）を厳守する。実アプリの離散イベント配線用に純粋 `eatCrossed(arc:prev:cur:)` を公開。

**Tech Stack:** Swift / AppKit（`#if canImport(AppKit)` gate）/ 既存 sill モジュール `PixelArt`（pure）・`Motion`（pure）・`Effects`（pure＋AppKit）。テストは XCTest（CLT ローカルは `swift build` のみ・`swift test` は CI）。

## Global Constraints

- **pure / AppKit 分離は依存グラフで強制**: `PixelArt` は AppKit を import しない。描画は `Effects`（`@MainActor`・`#if canImport(AppKit)`）。
- **clock 注入**: 全アニメ（フラッシュ位相・スコア上昇）は `now: Double` を引数で受ける。モジュール内で `CACurrentMediaTime()` を読まない（読むのはアプリ/prism）。
- **additive・既存 API 非破壊**: 既存シグネチャは壊さない。新パラメータは**デフォルト付き**で足す（`drawChompPath` の `showHead` は `= true`）。
- **決定論**: RNG 不使用。テストの境界 `now` は**2 進厳密値**（例 `1.25`）を選ぶ（#6 の float-boundary 教訓）。
- **色は intrinsic アーケード**: 壁/ペレット/pac は `SpriteColor`（`pupilBlue 0x2121FF`・`pacYellow 0xFFEA00`）。フラッシュは `EffectSpec.chomp.flash = [0xFFEA00, 0x2121FF, 0xFF0000, 0x2121FF]`。
- **Tests/ 必須**（[[sweep-include-tests]]）。型/import 漏れ注意（`swift build` だけがローカルゲート・9d の `import Foundation` 漏れ赤の教訓）。
- **push ゲート継続**（[[chomp-push-gate]]）＝ユーザーが sill でライブ確認するまで push しない。⚠ **マージ保留**＝#12 全フェーズ完了まで merge/tag しない（Ph5 完了でようやく一括 squash-merge＋最終タグ1本）。作業は `feat-chomp-12` 単一ディレクトリ。
- **小さめ判断（設計承認済・veto 可）**: ① 壁フラッシュ＋「+N」は **bonus（cherry/icon）食べ時のみ**（普通の dot は静かに消える）。② Ph4 の「追従ヘッド光点」は実ペレットが的になるので**大カードでは外す**。

---

## 0. これまでの足場（Ph1–Ph4・再利用するだけ）

- **PixelArt**（pure）: `PixelSprite`・`pacManCells`・`mouthHalfRad`・`positionHash01(x:y:)`・`ScaleTier`・`chompMouthFrames/Hz`。
- **Motion**（pure）: `ThemedTransition.frameStep(now:hz:frames:)`・`ThemedTransition.Easing.easeOutCubic`（`callAsFunction` で評価・入力 `[0,1]` clamp）・`dampedSine`。
- **Effects / Trail.swift**（pure＋AppKit gate）: `resampleAlongPolyline(_:interval:trimTail:)→[TrailMark(point,tangent)]`・`polylineLength`・`markAtArcLength`・**`pathPetCursors(total:speed:now:faceLag:)→(head,pet)`**（`pet` がコリドー pac の顔＝eater 弧長・負 now は前方 fold）・`roundedCornerPath`・`interiorCorners`・`nsBezierPath`。
- **Effects / Effects.swift**（AppKit）: `drawChompPath(path,now,valid,scale,speed,faceLag,showGuide)`・**`drawChompCorridor(path,now,valid,tier,scale,speed,icon)`**（Ph4・2 ストローク壁＋フィレット＋静的ペレット列＋Ph3 pac）・`blendThrough(_:at:)`・`EffectSpec.chomp`。
- **Effects / Sprite.swift**（AppKit）: `SpriteColor`・`CanonicalSprite.cherry`・`drawPixelSprite`・`drawPacMan`。
- **prism / PixelArtShowcase.swift**: `CorridorNSView`＋`NeonCorridorView`（`orthogonalMazePath` を内蔵 60Hz timer で `drawChompCorridor` 駆動・`PRISM_CHOMP_T` freeze）。

---

## ファイル構成（このフェーズで触る/作る）

- **Create** `Sources/PixelArt/Bonus.swift` — `chompBonusPool` / `bonusValue(x:y:)`（pure データ＋ピッカー）。
- **Modify** `Sources/Effects/Trail.swift` — pure `eatCrossed(arc:prev:cur:)` を arc プリミティブ群に追加。
- **Create** `Sources/Effects/CorridorEat.swift` — pure `ScorePop` / `chompFlashPhase(...)` / `chompScorePops(...)` ＋定数 `chompEatFlashDur`/`chompScorePopDur` ＋ AppKit `drawScorePop(...)`。コリドーの「食べタイムライン」一式の家。
- **Modify** `Sources/Effects/Effects.swift` — `drawChompPath` に `showHead: Bool = true` を追加；`drawChompCorridor` に「ペレット消滅・壁フラッシュ・score pop・ヘッド光点抑制」を統合。
- **Modify** `Sources/prism/PixelArtShowcase.swift` — valid な Neon Corridor カードを Ph5「食べながら周回する大カード」に昇格（キャプション＋寸法）。
- **Tests**: `Tests/EffectsTests/TrailTests.swift`（`eatCrossed`）・`Tests/PixelArtTests/PixelArtTests.swift`（`bonusValue`）・**Create** `Tests/EffectsTests/CorridorTests.swift`（flash/score 純粋関数＋draw スモーク）。
- **Doc**: `docs/ROADMAP.md` #12 を Ph5 着手中→（ライブ確認後）完了に更新。

---

### Task 1: `eatCrossed` — 純粋な食べ判定プリミティブ

**Files:**
- Modify: `Sources/Effects/Trail.swift`（`pathPetCursors` の直後・pure 帯）
- Test: `Tests/EffectsTests/TrailTests.swift`

**Interfaces:**
- Produces: `public func eatCrossed(arc: Double, prev: Double, cur: Double) -> Bool`

- [ ] **Step 1: 失敗するテストを書く**（`Tests/EffectsTests/TrailTests.swift` の `// MARK: - polylineLength + pathPetCursors` セクションの後に追記）

```swift
    // MARK: - eatCrossed (the per-frame eat primitive, #12 Ph5)

    func testEatCrossedForwardInterval() {
        // arc 50 lies in (40, 60] → crossed this frame.
        XCTAssertTrue(eatCrossed(arc: 50, prev: 40, cur: 60))
        // half-open: arc == cur is INCLUDED, arc == prev is EXCLUDED.
        XCTAssertTrue(eatCrossed(arc: 50, prev: 40, cur: 50))
        XCTAssertFalse(eatCrossed(arc: 50, prev: 50, cur: 60))
    }

    func testEatCrossedNotReachedOrAlreadyPast() {
        XCTAssertFalse(eatCrossed(arc: 70, prev: 40, cur: 60))   // ahead of the face
        XCTAssertFalse(eatCrossed(arc: 30, prev: 40, cur: 60))   // already behind
    }

    func testEatCrossedWrapIsNotACrossing() {
        // A loop restart (cur < prev) is NOT a crossing — the caller resets per lap.
        XCTAssertFalse(eatCrossed(arc: 10, prev: 90, cur: 5))
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift build` （`eatCrossed` 未定義で**コンパイル失敗**＝CLT ローカルの代理ゲート。CI が `swift test` を回す）
Expected: `error: cannot find 'eatCrossed' in scope`

- [ ] **Step 3: 最小実装**（`Sources/Effects/Trail.swift`・`pathPetCursors` 関数の閉じ括弧の直後に追記）

```swift
/// True when an eater advancing from face arc-length `prev` to `cur` in one frame
/// CROSSES a token at arc-length `arc` — i.e. `arc ∈ (prev, cur]` (half-open:
/// `cur` included, `prev` excluded, so a token is eaten exactly once as the mouth
/// reaches it). Clock-free + deterministic: the per-frame primitive an app pairs
/// with `resampleAlongPolyline` / `pathPetCursors` to fire a discrete eat event
/// (a sound, a real score). Forward motion only — a wrap (`cur < prev`, the loop
/// restart) is NOT a crossing; the caller resets its per-lap bookkeeping there.
/// The corridor's own showcase derives eating purely from `now` instead (see
/// `chompFlashPhase` / `chompScorePops`), so it needs no frame-to-frame state.
public func eatCrossed(arc: Double, prev: Double, cur: Double) -> Bool {
    prev < arc && arc <= cur
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift build`
Expected: 成功（型解決。実テストの PASS は CI の `swift test`）

- [ ] **Step 5: コミット**

```bash
git add Sources/Effects/Trail.swift Tests/EffectsTests/TrailTests.swift
git commit -m ":construction: feat(Effects): pure eatCrossed(arc:prev:cur:) — half-open crossing primitive for chomp eating (#12 Ph5 WIP)"
```

---

### Task 2: `chompBonusPool` ＋ `bonusValue` — ボーナス得点（純粋データ）

**Files:**
- Create: `Sources/PixelArt/Bonus.swift`
- Test: `Tests/PixelArtTests/PixelArtTests.swift`

**Interfaces:**
- Consumes: `positionHash01(x:y:)`（同 PixelArt）
- Produces: `public let chompBonusPool: [Int]` ／ `public func bonusValue(x: Int, y: Int) -> Int`

- [ ] **Step 1: 失敗するテストを書く**（`Tests/PixelArtTests/PixelArtTests.swift` の末尾メソッド群に追記）

```swift
    // MARK: - Bonus pool (#12 Ph5)

    func testChompBonusPoolIsTheArcadeLadder() {
        XCTAssertEqual(chompBonusPool, [100, 200, 300, 500, 700, 1000, 2000, 5000])
    }

    func testBonusValueIsStableAndInPool() {
        let v = bonusValue(x: 3, y: 7)
        XCTAssertTrue(chompBonusPool.contains(v))
        XCTAssertEqual(v, bonusValue(x: 3, y: 7))                 // deterministic
    }

    func testBonusValueVariesByCell() {
        // Decorrelated from the <0.08 selection band (swapped-coord hash), so
        // neighbouring bonuses are not all 100 — at least two distinct values
        // appear across a small spread of cells.
        let vals = Set((0..<16).map { bonusValue(x: $0 * 13, y: $0 * 7 + 1) })
        XCTAssertGreaterThan(vals.count, 1)
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift build`
Expected: `error: cannot find 'chompBonusPool' / 'bonusValue' in scope`

- [ ] **Step 3: 最小実装**（新規ファイル `Sources/PixelArt/Bonus.swift`）

```swift
// PixelArt — the arcade BONUS score ladder for the chomp corridor (#12 Ph5).
// Pure data + a deterministic per-cell picker, AppKit-free like the rest of
// PixelArt; the draw side floats a "+N" from an eaten cherry / app-icon.
//
// `import Foundation` is load-bearing for `positionHash01`'s neighbour (the #9d
// missing-import lesson) — keep it even though this file declares no Date.
import Foundation

/// The arcade bonus values a corridor cherry / app-icon awards when eaten — the
/// classic Pac-Man fruit ladder. Pure `Sendable` data.
public let chompBonusPool: [Int] = [100, 200, 300, 500, 700, 1000, 2000, 5000]

/// The bonus value for a bonus pellet at cell `(x, y)` — a STABLE pick from
/// `chompBonusPool`. Uses `positionHash01` of the SWAPPED coordinate so the value
/// is decorrelated from the `< 0.08` hash band that SELECTED the cell as a bonus
/// (otherwise every bonus would map to the pool's low end). Pure + deterministic:
/// the same pellet always awards the same N (a re-draw / a new lap is identical).
public func bonusValue(x: Int, y: Int) -> Int {
    let g = positionHash01(x: y, y: x)
    return chompBonusPool[Int(g * Double(chompBonusPool.count)) % chompBonusPool.count]
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift build`
Expected: 成功

- [ ] **Step 5: コミット**

```bash
git add Sources/PixelArt/Bonus.swift Tests/PixelArtTests/PixelArtTests.swift
git commit -m ":construction: feat(PixelArt): chompBonusPool + bonusValue(x:y:) — pure arcade bonus ladder (#12 Ph5 WIP)"
```

---

### Task 3: `ScorePop` ＋ `chompFlashPhase` ＋ `chompScorePops` — 食べタイムライン（純粋 f(now)）

**Files:**
- Create: `Sources/Effects/CorridorEat.swift`
- Test: `Tests/EffectsTests/CorridorTests.swift`

**Interfaces:**
- Produces:
  - `public let chompEatFlashDur: Double`（= 0.45）／`public let chompScorePopDur: Double`（= 0.8）
  - `public struct ScorePop: Sendable, Equatable { point:(x:Double,y:Double); value:Int; t:Double }`
  - `public func chompFlashPhase(eventArcs:[Double], total:Double, speed:Double, now:Double, faceLag:Double, dur:Double) -> Double?`
  - `public func chompScorePops(bonuses:[(point:(x:Double,y:Double), arc:Double, value:Int)], total:Double, speed:Double, now:Double, faceLag:Double, dur:Double) -> [ScorePop]`

- [ ] **Step 1: 失敗するテストを書く**（新規 `Tests/EffectsTests/CorridorTests.swift`）

```swift
// Corridor-eat timeline tests — the pure f(now) derivation that lets the chomp
// corridor flash + score WITHOUT frame-to-frame state (so PRISM_CHOMP_T freezes
// and XCTest stays deterministic). Boundaries binary-exact (the #6 lesson).
// swift test runs on CI only (CLT has no XCTest).

import XCTest
import AppKit
@testable import Effects

final class CorridorTests: XCTestCase {

    // total 100, speed 50 → lap period 2s. faceLag 0 ⇒ the face crosses arc `a`
    // at `a/50` seconds into the lap.

    func testFlashPhaseActiveAfterCrossing() {
        // bonus at arc 50 → crossed at lapPhase 1.0. now 1.25 ⇒ since 0.25,
        // dur 0.5 ⇒ phase 0.5.
        let p = chompFlashPhase(eventArcs: [50], total: 100, speed: 50,
                                now: 1.25, faceLag: 0, dur: 0.5)
        XCTAssertEqual(p!, 0.5, accuracy: 1e-9)
    }

    func testFlashPhaseNilBeforeCrossOrAfterWindow() {
        // before the cross (now 0.5 < 1.0) → nil.
        XCTAssertNil(chompFlashPhase(eventArcs: [50], total: 100, speed: 50,
                                     now: 0.5, faceLag: 0, dur: 0.5))
        // after the 0.5s window (now 1.75 ⇒ since 0.75 ≥ dur) → nil.
        XCTAssertNil(chompFlashPhase(eventArcs: [50], total: 100, speed: 50,
                                     now: 1.75, faceLag: 0, dur: 0.5))
    }

    func testFlashPhasePicksMostRecentCrossing() {
        // arcs 25 (cross 0.5) and 50 (cross 1.0). now 1.125 ⇒ most recent is 1.0,
        // since 0.125, dur 0.5 ⇒ phase 0.25.
        let p = chompFlashPhase(eventArcs: [25, 50], total: 100, speed: 50,
                                now: 1.125, faceLag: 0, dur: 0.5)
        XCTAssertEqual(p!, 0.25, accuracy: 1e-9)
    }

    func testFlashPhaseSkipsUnreachableTail() {
        // arc 100 with faceLag 20 ⇒ arc+faceLag 120 > total ⇒ never crossed ⇒ nil.
        XCTAssertNil(chompFlashPhase(eventArcs: [100], total: 100, speed: 50,
                                     now: 1.9, faceLag: 20, dur: 0.5))
    }

    func testScorePopsActiveWindowAndProgress() {
        // bonus at arc 50 (cross 1.0), value 700. now 1.25 ⇒ one pop, t 0.5.
        let pops = chompScorePops(
            bonuses: [(point: (x: 5, y: 6), arc: 50, value: 700)],
            total: 100, speed: 50, now: 1.25, faceLag: 0, dur: 0.5)
        XCTAssertEqual(pops.count, 1)
        XCTAssertEqual(pops[0].value, 700)
        XCTAssertEqual(pops[0].t, 0.5, accuracy: 1e-9)
        XCTAssertEqual(pops[0].point.x, 5, accuracy: 1e-9)
        // before the cross → no pop.
        XCTAssertTrue(chompScorePops(
            bonuses: [(point: (x: 5, y: 6), arc: 50, value: 700)],
            total: 100, speed: 50, now: 0.5, faceLag: 0, dur: 0.5).isEmpty)
    }

    func testCorridorEatDegenerateInputs() {
        XCTAssertNil(chompFlashPhase(eventArcs: [50], total: 0, speed: 50,
                                     now: 1, faceLag: 0, dur: 0.5))
        XCTAssertTrue(chompScorePops(bonuses: [], total: 100, speed: 50,
                                     now: 1, faceLag: 0, dur: 0.5).isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift build`
Expected: `error: cannot find 'chompFlashPhase' / 'chompScorePops' / 'ScorePop' in scope`

- [ ] **Step 3: 最小実装**（新規 `Sources/Effects/CorridorEat.swift`・pure 帯のみ。AppKit ヘルパは Task 4 で追記）

```swift
// CorridorEat — the chomp corridor's EAT TIMELINE (#12 Ph5), derived PURELY from
// `now`. The pac face sweeps the centreline (its arc-length is `pathPetCursors`'
// `pet`), eating the pellet row; a bonus (cherry / app-icon) crossing fires a
// ~450ms wall RAINBOW FLASH and an ~800ms floating "+N". Because everything is a
// pure function of `now` — no FlashState cell, no eaten-set, no rollFlash RNG —
// the prism card freezes deterministically (PRISM_CHOMP_T) and XCTest is exact.
//
// Why no `rollFlash`/`onEat`: those carry frame-to-frame state, which would break
// the freeze + determinism invariant. The crossing time of a bonus at arc `a` is
// `(a + faceLag) / speed` seconds into the lap, so "time since the last eat" is a
// closed form in `now`. Apps that DO want discrete events compose the pure
// `eatCrossed` primitive (Trail.swift) with their own successive face-arc samples.

import Foundation

/// How long the wall rainbow flash lasts after a bonus is eaten (seconds).
public let chompEatFlashDur: Double = 0.45
/// How long a "+N" score pop rises + fades after a bonus is eaten (seconds).
public let chompScorePopDur: Double = 0.8

/// One floating "+N" in flight at the sampled `now`: the screen `point` of the
/// eaten bonus, its `value`, and `t` (0…1 progress through the rise+fade). The
/// AppKit `drawScorePop` lifts + fades it; pure + `Sendable` so it is testable.
public struct ScorePop: Sendable, Equatable {
    public let point: (x: Double, y: Double)
    public let value: Int
    public let t: Double

    public init(point: (x: Double, y: Double), value: Int, t: Double) {
        self.point = point
        self.value = value
        self.t = t
    }

    public static func == (a: ScorePop, b: ScorePop) -> Bool {
        a.point == b.point && a.value == b.value && a.t == b.t
    }
}

/// Seconds into the CURRENT lap at `now` for a pac looping a corridor of arc
/// length `total` at `speed` — a floored modulo so a negative `now` folds forward
/// (the `pathPetCursors` / `frameStep` convention). `nil`-guarded by the callers.
private func corridorLapPhase(total: Double, speed: Double, now: Double) -> Double {
    let period = total / speed
    let lp = now.truncatingRemainder(dividingBy: period)
    return lp < 0 ? lp + period : lp
}

/// The wall flash phase `0..<1` at `now` if the corridor pac crossed any bonus in
/// `eventArcs` within the last `dur` seconds THIS lap, else `nil`. The crossing
/// time of a bonus at arc `a` is `(a + faceLag)/speed` into the lap; the flash is
/// keyed to the MOST RECENT crossing `≤ lapPhase`. A bonus with `a + faceLag >
/// total` is never reached this lap (the face trails by `faceLag`) and is skipped.
/// Pure f(now). `eventArcs` need not be sorted.
public func chompFlashPhase(eventArcs: [Double], total: Double, speed: Double,
                            now: Double, faceLag: Double, dur: Double) -> Double? {
    guard total > 0, speed > 0, dur > 0 else { return nil }
    let lp = corridorLapPhase(total: total, speed: speed, now: now)
    var best: Double? = nil                       // most recent crossing time ≤ lp
    for a in eventArcs {
        guard a + faceLag <= total else { continue }
        let ct = (a + faceLag) / speed
        if ct <= lp, best == nil || ct > best! { best = ct }
    }
    guard let ct = best else { return nil }
    let since = lp - ct
    return since < dur ? since / dur : nil
}

/// The "+N" pops in flight at `now`: for each `bonus` (its centreline `arc`,
/// screen `point`, `value`), a pop runs for `dur` seconds after the face crosses
/// it (crossing time `(arc + faceLag)/speed` into the lap), with `t` the 0…1
/// progress. Loops per lap; a bonus the face never reaches (`arc + faceLag >
/// total`) emits nothing. Pure f(now). Empty for degenerate `total`/`speed`/`dur`.
public func chompScorePops(
    bonuses: [(point: (x: Double, y: Double), arc: Double, value: Int)],
    total: Double, speed: Double, now: Double, faceLag: Double, dur: Double
) -> [ScorePop] {
    guard total > 0, speed > 0, dur > 0 else { return [] }
    let lp = corridorLapPhase(total: total, speed: speed, now: now)
    var out: [ScorePop] = []
    for b in bonuses {
        guard b.arc + faceLag <= total else { continue }
        let since = lp - (b.arc + faceLag) / speed
        if since >= 0, since < dur {
            out.append(ScorePop(point: b.point, value: b.value, t: since / dur))
        }
    }
    return out
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift build`
Expected: 成功

- [ ] **Step 5: コミット**

```bash
git add Sources/Effects/CorridorEat.swift Tests/EffectsTests/CorridorTests.swift
git commit -m ":construction: feat(Effects): chompFlashPhase + chompScorePops + ScorePop — pure f(now) corridor eat timeline (#12 Ph5 WIP)"
```

---

### Task 4: `drawScorePop` — 「+N」の AppKit 描画（rise+fade）

**Files:**
- Modify: `Sources/Effects/CorridorEat.swift`（末尾に `#if canImport(AppKit)` 帯を追記）
- Test: `Tests/EffectsTests/CorridorTests.swift`（draw スモーク）

**Interfaces:**
- Consumes: `ScorePop`（Task 3）／`ThemedTransition.Easing.easeOutCubic`（Motion）／`SpriteColor.pacYellow`・`HexColor`（同 Effects モジュール／Palette）
- Produces: `@MainActor public func drawScorePop(_ pop: ScorePop, scale: CGFloat)`

- [ ] **Step 1: 失敗するテストを書く**（`Tests/EffectsTests/CorridorTests.swift` に追記）

```swift
    @MainActor
    func testDrawScorePopSmoke() {
        // Render into an offscreen image — proves the text draw path doesn't trap.
        let img = NSImage(size: NSSize(width: 64, height: 32))
        img.lockFocus()
        drawScorePop(ScorePop(point: (x: 30, y: 8), value: 700, t: 0.5), scale: 2)
        img.unlockFocus()
        XCTAssertEqual(img.size.width, 64, accuracy: 1e-9)
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift build`
Expected: `error: cannot find 'drawScorePop' in scope`

- [ ] **Step 3: 最小実装**（`Sources/Effects/CorridorEat.swift` 末尾に追記）

```swift
#if canImport(AppKit)
import AppKit
import Motion   // ThemedTransition.Easing — the rise curve
import Palette  // HexColor

/// Draw one "+N" score pop: arcade-yellow bold monospaced text RISING (eased) and
/// FADING over its `t` (0…1). Host in a NON-flipped (y-up) view (the corridor
/// contract) — `NSAttributedString.draw` orients itself there, so +y lifts the
/// text up; no flip. Centred horizontally on `pop.point`. `scale` matches the
/// corridor's render resolution.
@MainActor
public func drawScorePop(_ pop: ScorePop, scale: CGFloat) {
    let rise = ThemedTransition.Easing.easeOutCubic(pop.t)   // 0…1, snappy then soft
    let dy = CGFloat(rise) * 14 * scale                      // total lift in points
    let alpha = max(0, 1 - pop.t)                            // linear fade to 0
    let font = NSFont.monospacedSystemFont(ofSize: 9 * scale, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(HexColor(SpriteColor.pacYellow))
            .withAlphaComponent(alpha),
    ]
    let str = NSAttributedString(string: "+\(pop.value)", attributes: attrs)
    let size = str.size()
    str.draw(at: CGPoint(x: CGFloat(pop.point.x) - size.width / 2,
                         y: CGFloat(pop.point.y) + dy))
}
#endif
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift build`
Expected: 成功

- [ ] **Step 5: コミット**

```bash
git add Sources/Effects/CorridorEat.swift Tests/EffectsTests/CorridorTests.swift
git commit -m ":construction: feat(Effects): drawScorePop — rise+fade +N blitter (Motion easeOutCubic) (#12 Ph5 WIP)"
```

---

### Task 5: `drawChompPath` に `showHead` を追加（コリドーでヘッド光点を抑制）

**Files:**
- Modify: `Sources/Effects/Effects.swift`（`drawChompPath` シグネチャ＋ヘッド光点ガード）

**Interfaces:**
- Produces（変更）: `drawChompPath(_ path:[CGPoint], now:CFTimeInterval, valid:Bool=true, scale:CGFloat=1, speed:CGFloat=60, faceLag:CGFloat=0, showGuide:Bool=true, showHead:Bool=true)`

**理由:** Ph4 までヘッド光点（追従の的）は「ペレットが無いから」表示していた。Ph5 で実ペレットが的になるので、コリドーからは `showHead:false` で外す（小さめ判断 ②）。PathPet カードは既定 `true` のまま＝挙動不変（additive）。

- [ ] **Step 1: シグネチャ変更**（`Sources/Effects/Effects.swift` の `drawChompPath` 宣言）

```swift
public func drawChompPath(_ path: [CGPoint], now: CFTimeInterval, valid: Bool = true,
                          scale: CGFloat = 1, speed: CGFloat = 60,
                          faceLag: CGFloat = 0, showGuide: Bool = true,
                          showHead: Bool = true) {
```

- [ ] **Step 2: ヘッド光点ガードに `showHead` を足す**（同関数内の該当 `if`）

変更前:
```swift
    if valid, faceLag > 0, let head = markAtArcLength(path, distance: headDist) {
```
変更後:
```swift
    if showHead, valid, faceLag > 0, let head = markAtArcLength(path, distance: headDist) {
```

- [ ] **Step 3: ビルド確認**

Run: `swift build`
Expected: 成功（既存呼び出しはデフォルト `showHead:true` で挙動不変）

- [ ] **Step 4: コミット**

```bash
git add Sources/Effects/Effects.swift
git commit -m ":construction: refactor(Effects): drawChompPath gains showHead (default true) — corridor suppresses the chased dot (#12 Ph5 WIP)"
```

---

### Task 6: `drawChompCorridor` に食べ判定・虹フラッシュ・スコアを統合

**Files:**
- Modify: `Sources/Effects/Effects.swift`（`drawChompCorridor` 本体を再構成）
- Test: `Tests/EffectsTests/CorridorTests.swift`（食べ/フラッシュフレームのスモーク）

**Interfaces:**
- Consumes: `pathPetCursors`・`polylineLength`・`resampleAlongPolyline`・`positionHash01`・`bonusValue`・`chompFlashPhase`・`chompScorePops`・`chompEatFlashDur`・`chompScorePopDur`・`blendThrough`・`EffectSpec.chomp`・`drawScorePop`・`drawChompPath(...,showHead:)`
- Produces: シグネチャ不変の `drawChompCorridor(...)`（挙動が Ph5 化）

**設計（描画順・すべて `valid==true` のときだけ食べ挙動。`valid==false` は Ph4 のまま静的）:**
1. `total = polylineLength(path)`、`faceLag = valid ? roadWidth*1.4 : 0`、`cursors = pathPetCursors(...)`、`faceArc = cursors.pet`。
2. ペレット列を**先に分類**（壁の色がフラッシュ依存のため）: `marks = resampleAlongPolyline(path, interval: pelletGap)`。各 `i>0` で `arc = min(Double(i)*pelletGap, total)`、`h = positionHash01(round x, round y)`、kind（`h<0.04` cherry / `h<0.08 && icon!=nil` icon / else dot）。bonus（cherry/icon）は `arc`・`point`・`value = bonusValue(round x, round y)` を蓄積。
3. **壁**: フラッシュ中（`flash != nil`）は青の代わりに `blendThrough(EffectSpec.chomp.flash, at: flash)` 色＋グロー強め。
4. フィレット（Ph4 のまま）。
5. **ペレット**: `valid && faceArc >= arc` のものは**描かない**（食べられた）。残りを Ph4 同様に描画。
6. **pac**: `drawChompPath(..., showHead: false)`（Ph3 再利用・ヘッド光点なし）。
7. **score pops**: `chompScorePops(...)` の各 `pop` を `drawScorePop(pop, scale: s)`（pac の上）。

- [ ] **Step 1: 失敗するテストを書く**（`Tests/EffectsTests/CorridorTests.swift` に追記。`drawChompCorridor` は Ph4 で存在するが、Ph5 の「食べ/フラッシュ frame」でも no-crash を固定）

```swift
    @MainActor
    func testDrawChompCorridorEatFrameSmoke() {
        // A frozen `now` partway through a lap (pellets eaten + possibly flashing +
        // a pop) must render without trapping. Orthogonal U-maze, y-up host.
        let path = [CGPoint(x: 20, y: 20), CGPoint(x: 180, y: 20),
                    CGPoint(x: 180, y: 80), CGPoint(x: 20, y: 80)]
        let img = NSImage(size: NSSize(width: 200, height: 100))
        img.lockFocus()
        drawChompCorridor(path, now: 1.3, valid: true, tier: .s, scale: 1, speed: 60)
        drawChompCorridor(path, now: 2.7, valid: false, tier: .s, scale: 1, speed: 60)
        img.unlockFocus()
        XCTAssertEqual(img.size.height, 100, accuracy: 1e-9)
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `swift build`（このスモーク自体はシグネチャ既存なので**ビルドは通る**＝赤にならない。代わりに、本タスクは挙動変更が主眼なので「Step 3 で実体を書き替え→ Step 4 でオフスクリーン目視」を実ゲートにする）
Expected: `swift build` 成功（テストの厳密 PASS は CI）

- [ ] **Step 3: `drawChompCorridor` を再構成**（`Sources/Effects/Effects.swift`・`drawChompCorridor` 本体を以下で**置換**。`guard path.count >= 2` と `let s … roadHalf` の寸法計算ブロックは既存のまま残し、その後ろを差し替える）

`guard` と寸法定義（既存・そのまま）:
```swift
    guard path.count >= 2 else { return }
    let s = CGFloat(tier.multiplier) * scale
    let roadWidth = 11 * s
    let wallThick = max(1, 0.9 * s)
    let pelletR   = 0.8 * s
    let pelletGap = 5.2 * s
    let roadHalf  = roadWidth / 2
```

ここから下を**置換**:
```swift
    // #12 Ph5 — eating is a PURE function of `now`: the face (the eater) is the
    // trailing `pathPetCursors` cursor; pellets behind it are eaten, a bonus
    // crossing flashes the walls + floats a "+N". `valid == false` (the panicking
    // ghost) doesn't eat — it keeps Ph4's static pellets.
    let total = Double(polylineLength(path))
    let faceLag = valid ? roadWidth * 1.4 : 0
    let cursors = pathPetCursors(total: total, speed: Double(speed),
                                 now: Double(now), faceLag: Double(faceLag))
    let faceArc = cursors.pet                       // the eating arc-length

    // Classify the pellet row up front (the wall colour depends on bonus eats).
    enum Kind { case dot, cherry, icon }
    struct Pellet { let point: CGPoint; let arc: Double; let kind: Kind; let value: Int }
    let marks = resampleAlongPolyline(path, interval: Double(pelletGap))
    var pellets: [Pellet] = []
    for (i, m) in marks.enumerated() where i > 0 {
        let pt = CGPoint(x: m.point.x, y: m.point.y)
        let arc = min(Double(i) * Double(pelletGap), total)
        let ix = Int(m.point.x.rounded()), iy = Int(m.point.y.rounded())
        let h = positionHash01(x: ix, y: iy)
        let kind: Kind = h < 0.04 ? .cherry : (h < 0.08 && icon != nil ? .icon : .dot)
        pellets.append(Pellet(point: pt, arc: arc, kind: kind,
                              value: bonusValue(x: ix, y: iy)))
    }
    let bonusArcs = valid ? pellets.filter { $0.kind != .dot }.map(\.arc) : []
    let flash = chompFlashPhase(eventArcs: bonusArcs, total: total, speed: Double(speed),
                                now: Double(now), faceLag: Double(faceLag),
                                dur: chompEatFlashDur)

    // 1) Black road + 2-stroke neon walls on ONE rounded centreline. While a bonus
    //    flash is in flight the wall sweeps EffectSpec.chomp.flash (the rainbow
    //    flash) instead of resting blue, with a brighter glow.
    let steps = roundedCornerPath(path, radius: Double(roadHalf))
    let wall  = nsBezierPath(steps, lineWidth: roadWidth + 2 * wallThick)
    let road  = nsBezierPath(steps, lineWidth: roadWidth)
    let wallColor: NSColor
    if let flash {
        let c = blendThrough(EffectSpec.chomp.flash, at: flash)
        wallColor = NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g),
                            blue: CGFloat(c.b), alpha: 1)
    } else {
        wallColor = NSColor(HexColor(SpriteColor.pupilBlue))
    }
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = wallColor.withAlphaComponent(flash != nil ? 1 : 0.85)
    glow.shadowBlurRadius = (flash != nil ? 5 : 3) * s; glow.shadowOffset = .zero; glow.set()
    wallColor.setStroke(); wall.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.black.setStroke(); road.stroke()

    // 2) Interior fillets — a black disc erodes each inner neon notch (Ph4; the
    //    1.15 radius is the user-approved live value, see the Ph4 note).
    NSColor.black.setFill()
    for c in interiorCorners(path) {
        let d  = Double(roadHalf) / cos(abs(c.turn) / 2)
        let fr = Double(wallThick) * 1.15
        let cx = c.vertex.x + c.bisector.x * d, cy = c.vertex.y + c.bisector.y * d
        NSBezierPath(ovalIn: CGRect(x: cx - fr, y: cy - fr,
                                    width: 2 * fr, height: 2 * fr)).fill()
    }

    // 3) Central pellet row — skip the FIRST mark (live cursor) AND any pellet the
    //    face has already eaten this lap (valid only; the ghost keeps them static).
    let yellow    = NSColor(HexColor(SpriteColor.pacYellow))
    let bonusCell = roadWidth * 0.62 / 12        // cherry is 12 cells wide
    let iconBox   = roadWidth * 0.66
    for p in pellets {
        if valid, faceArc >= p.arc { continue }   // eaten — gone until the lap wraps
        switch p.kind {
        case .cherry:
            drawCenteredSprite(CanonicalSprite.cherry, cell: bonusCell, at: p.point)
        case .icon:
            if let icon { drawCorridorIcon(icon, at: p.point, box: iconBox) }
        case .dot:
            yellow.setFill()
            NSBezierPath(ovalIn: CGRect(x: p.point.x - pelletR, y: p.point.y - pelletR,
                                        width: 2 * pelletR, height: 2 * pelletR)).fill()
        }
    }

    // 4) The walking pac / panicking ghost — reuse Ph3 (no guide, no chased dot;
    //    the pellets are the targets now).
    let petScale = roadWidth * 0.78 / chompFaceFootprint
    drawChompPath(path, now: now, valid: valid, scale: petScale,
                  speed: speed, faceLag: faceLag, showGuide: false, showHead: false)

    // 5) Floating "+N" score pops for bonuses eaten in the last ~0.8s (valid only).
    if valid {
        let pops = chompScorePops(
            bonuses: pellets.filter { $0.kind != .dot }
                .map { (point: (x: Double($0.point.x), y: Double($0.point.y)),
                        arc: $0.arc, value: $0.value) },
            total: total, speed: Double(speed), now: Double(now),
            faceLag: Double(faceLag), dur: chompScorePopDur)
        for pop in pops { drawScorePop(pop, scale: s) }
    }
```

- [ ] **Step 4: ビルド＋オフスクリーン目視レンダ**（向き・食べ・フラッシュ・+N を実証＝Ph1–4 と同手法。agent は画面収録不可なので prism 撮影はユーザー）

Run: `swift build`
Expected: 成功

そのうえで一時スクリプトでオフスクリーン PNG を出して目視（複数 `now` で「ペレットが顔の手前で消える／bonus 直後に壁が色変わり／+N が浮く／全部正立」を確認）:
```bash
cat > /tmp/ph5_render.swift <<'SWIFT'
import AppKit
import Effects
import PixelArt
func frame(_ now: Double, _ name: String) {
    let path = [CGPoint(x: 30, y: 30), CGPoint(x: 270, y: 30),
                CGPoint(x: 270, y: 95), CGPoint(x: 30, y: 95),
                CGPoint(x: 30, y: 160), CGPoint(x: 270, y: 160)]
    let img = NSImage(size: NSSize(width: 300, height: 190))
    img.lockFocus()
    NSColor(white: 0.04, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 300, height: 190).fill()
    drawChompCorridor(path, now: now, valid: true, tier: .m, scale: 1, speed: 60)
    img.unlockFocus()
    let tiff = img.tiffRepresentation!
    let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
}
for (i, t) in [0.2, 1.0, 1.1, 2.4, 3.8].enumerated() { frame(t, "ph5_\(i)") }
print("wrote /tmp/ph5_*.png")
SWIFT
swift -I .build/debug/Modules -L .build/debug \
  -lEffects -lPixelArt -lMotion -lPalette /tmp/ph5_render.swift 2>/dev/null \
  || echo "（直接 swift 実行が不可なら、prism のライブカードで確認＝ユーザー側）"
```
Expected: `/tmp/ph5_*.png` が複数出力され、目視で食べ/フラッシュ/+N/正立が確認できる（直接実行が環境で不可なら prism ライブで確認）。

- [ ] **Step 5: コミット**

```bash
git add Sources/Effects/Effects.swift Tests/EffectsTests/CorridorTests.swift
git commit -m ":sparkles: feat(Effects): drawChompCorridor eats pellets + rainbow wall flash + +N score (pure f(now)) — composite ChompCorridor (#12 Ph5)"
```

---

### Task 7: prism — Neon Corridor を「食べながら周回する大カード」に昇格

**Files:**
- Modify: `Sources/prism/PixelArtShowcase.swift`（valid な `NeonCorridorView` のキャプション＋寸法）

**理由:** `drawChompCorridor` が Ph5 化したので、既存 valid カードに食べ/フラッシュ/+N が**自動で出る**。キャプションを Ph5 の内容に更新し、大カードとして少し背を高くする（ライブで詰める前提）。mismatch カードは据え置き。

- [ ] **Step 1: valid corridor カードのキャプション差し替え**（`Sources/prism/PixelArtShowcase.swift`・"Neon Corridor (#12 Ph4) —" で始まる `Text(...)`）

変更前（先頭一致で特定）:
```swift
            Text("Neon Corridor (#12 Ph4) — the maze: 2-stroke neon walls (one rounded centreline stroked WIDE-blue then NARROW-black) + interior fillets on the inner corners + a central pellet row (positionHash01 bands cherry / icon / dot) + the Ph3 pac walking it. Orthogonal 90° path = a real Pac-Man maze:")
```
変更後:
```swift
            Text("ChompCorridor (#12 Ph5) — the FULL loop: the pac walks the maze EATING the pellet row (each vanishes as the mouth reaches it, all respawn on the lap wrap); a cherry / app-icon eat flashes the walls (EffectSpec.chomp.flash, ~450ms) and floats a +N score (bonus ladder, rise+fade). All derived PURELY from now — PRISM_CHOMP_T freezes it:")
```

- [ ] **Step 2: valid corridor カードの高さを上げる**（直後の `NeonCorridorView(valid: true, tier: .s)` の `.frame(height: 178 * uiScale)`）

変更前:
```swift
            NeonCorridorView(valid: true, tier: .s)
                .frame(height: 178 * uiScale)
```
変更後:
```swift
            NeonCorridorView(valid: true, tier: .s)
                .frame(height: 200 * uiScale)
```

- [ ] **Step 3: ビルド確認**

Run: `swift build`
Expected: 成功

- [ ] **Step 4: コミット**

```bash
git add Sources/prism/PixelArtShowcase.swift
git commit -m ":lipstick: feat(prism): ChompCorridor Ph5 live card — eat + flash + +N (relabel + taller) (#12 Ph5)"
```

---

### Task 8: ROADMAP 反映（Ph5 着手中→検証ゲート）＋ 最終ビルド

**Files:**
- Modify: `docs/ROADMAP.md`（#12 の Ph5 行を「着手中（実装済・ユーザーのライブ確認待ち）」に）

- [ ] **Step 1: ROADMAP #12 を更新**（Ph5 行＋引き継ぎ節を「着手中: feat-chomp-12 に Ph5 実装済・`swift build` 緑・オフスクリーン確認済・**ユーザー prism ライブ確認待ち（push ゲート）**」に。マージ保留・最終タグは全フェーズ完了後＝Ph5 ライブ PASSED で一括、を明記）

- [ ] **Step 2: 最終ビルド＋全コミット確認**

Run: `swift build && git log --oneline -8`
Expected: 成功・Ph5 の commit 群が `feat-chomp-12` に積まれている（**push しない**）

- [ ] **Step 3: コミット**

```bash
git add docs/ROADMAP.md
git commit -m ":memo: docs(ROADMAP): #12 Ph5 着手中（実装済・ライブ確認待ち・push/merge ゲート継続）"
```

---

## 検証ゲート（順）

1. `swift build`（ローカル緑＝唯一のローカルゲート）。
2. **オフスクリーン PNG レンダ**（Task 6 Step 4）で「食べで消える／bonus でフラッシュ／+N が浮く／全部正立・道に乗る」を実証（直接実行不可なら prism ライブで）。
3. **prism ライブ確認（ユーザー）＝push ゲート**（[[chomp-push-gate]]・[[prism-bench]]）。agent は画面収録不可。
4. **敵対的レビュー workflow**（Ph3/Ph4 同型・4 観点: ① 決定論クロック純粋性〔freeze/負 now/lap 境界〕② 食べ/フラッシュ/score の忠実度〔spec §3.3〕③ ジオメトリ座標系〔y-up・score pop 正立・arc=i*gap の妥当性〕④ テスト/sill 規約〔Tests/ 含む・型/import〕）= 各指摘を独立スケプティックで検証 → must-fix 反映。
5. ユーザー sill ライブ最終確認 → **#12 全フェーズ完了** → **ここで初めて一括 squash-merge＋最終タグ1本**（未使用版を再確認＝[[parallel-work-hazard]]）→ ROADMAP 完了反映。

## スコープ外 / 非ゴール

- 実プレイ可能なゲーム（スコア永続化・敵 AI・難易度）は作らない（spec §7）。アーケード「風」演出のみ。
- `onEat:` コールバック（フレーム状態が必要＝freeze/決定論不変条件と衝突）は**足さない**。実アプリの離散イベントは公開済の純粋 `eatCrossed` を各自の prev/cur 顔弧長と合成して配線（設計判断：ユーザー承認の「完全 f(now) 派生」に従う）。
- 既存 line-pet / PathPet カードへの食べ拡張（Ph5 はコリドー合成に限定＝YAGNI）。
- 非直交コリドーの一般化（chomp は 90° スナップ前提）。
- wand backport（Ph6・wand リポ側・sill ROADMAP では追わない）。

## ラップ境界の既知の小事（実装ノート・敵対的レビューで確認）

- **末尾デッドゾーン**: 顔は `faceLag` 分だけ遅れるので、`arc + faceLag > total` のペレット（道の終端 ~1.4 road 幅分）はそのラップで食べられない＝常時可視。`faceLag` は total に対し小さいので 1–2 個。許容（ライブで違和感あれば調整）。
- **フラッシュのラップ跨ぎ**: フラッシュ/score は per-lap 導出なので、ラップ末尾で始まった演出は wrap で打ち切られる。bonus は道中に分布し `dur`（0.45/0.8s）は周期より十分短いので通常は問題なし。気になればレビューで対処。
