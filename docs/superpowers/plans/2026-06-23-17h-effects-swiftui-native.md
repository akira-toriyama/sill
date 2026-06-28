# #17h — Effects bridges → SwiftUI-native Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the 6 `ThemeKitUI` effect bridges (`ParticleBurstView` / `InkSplatterView` / `PixelSpriteView` / `LinePetsView` / `PathPetView` / `ChompCorridorView`) from `NSViewRepresentable`-over-AppKit-draw to NATIVE SwiftUI, eliminating their AppKit policy violations.

**Architecture:** Each view becomes a SwiftUI `View` (a `Canvas` + `TimelineView(.animation)` for vector/glow scenes; a nearest-neighbor `Image(.interpolation(.none))` for pixel sprites) that consumes the EXISTING pure `f(now)` layer in `Effects`/`PixelArt`/`Trail`/`Motion`. The AppKit draw layer stays in `Effects` (reference/tests); only ThemeKitUI stops calling it. Pet placement logic now-private in `Effects.swift` is promoted to public pure selectors.

**Tech Stack:** Swift, SwiftUI (`Canvas`/`GraphicsContext`/`TimelineView`/`Image.interpolation(.none)`), CoreGraphics (`CGImage` rasterization for pixel sprites). No new package dependencies.

**Design spec:** [`docs/superpowers/specs/2026-06-23-17h-effects-swiftui-native-design.md`](../specs/2026-06-23-17h-effects-swiftui-native-design.md).

## Global Constraints

- **AppKit policy (hard gate):** end-state of every task — these 6 views have ZERO `NSViewRepresentable`, `NSShadow`, `shouldAntialias`, and ZERO calls to `Effects`/`PixelArt` AppKit draw fns (`drawParticles`/`drawInkSplatter`/`drawPixelSprite`/`drawPacMan`/`drawLinePets`/`drawChompPath`/`drawChompCorridor`/`drawScorePop`/`drawSpark`/`drawPaper`). If a fidelity point (glow, rotated-pixel crispness) can't be matched in SwiftUI, STOP and consult the user — never fall back to keeping AppKit, never widen AppKit scope on your own.
- **Public API preserved:** prism is the only consumer and imports the 6 views by their public `struct` API (property names, `init` params, `frozen`/`loopPeriod`/`scale`/`emitters`/`emission`/`colors`/`intensity`/`duration`/`radiusSpeed`/`seed`/`center`/`size`/`pets`/`inset`/`speed`/`path`/`valid`/`tier`/`icon`/`showBonuses`/`faceLag`/`showGuide`/`frames`/`hz`/`cell`/`color`/`sprite`). Keep them identical so prism needs ZERO changes.
- **`frozen` semantics (preserve exactly):** `ParticleBurstView`/`InkSplatterView` `frozen` = fraction `0…1` of `duration`; `PixelSpriteView`/`LinePetsView`/`PathPetView`/`ChompCorridorView` `frozen` = ABSOLUTE clock seconds. Non-nil ⇒ render ONE static frame (no `TimelineView`).
- **Test reality:** `swift test` (XCTest) runs ONLY in CI (full Xcode); the maintainer's machine is CommandLineTools-only. LOCAL gate = `swift build`. Pure-logic tasks WRITE XCTest (CI runs it) — do not claim a local test pass. View fidelity is the maintainer's prism live gate (agents can't screen-record).
- **Coordinate conventions (from the AppKit draws — replicate in Canvas):** ParticleBurst/InkSplatter are FLIPPED (+y DOWN, gravity falls on-screen). LinePets/PathPet/ChompCorridor + the upright sprites are NON-flipped (+y UP). Pixel sprites' row 0 is the TOP.
- **Commits:** gitmoji + Conventional Commits, English subject. Library change overall ⇒ minor bump + `v`-tag at the END (`v1.25.0` target) — individual task commits are `feat(ThemeKitUI)` / `refactor(Effects)`, no per-task tag. End commit messages with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Worktree:** work happens in the worktree on branch `worktree-17h-effects-swiftui-native` (already created off origin/main).

## File Structure

- **Create** `Sources/Effects/PetSprites.swift` — pure pet-placement selectors (`chompPacSprite`, `chompGhostSprite`) + promoted publics. (Or add to `Sprite.swift`; a new file keeps it focused.)
- **Modify** `Sources/Effects/Effects.swift` — make `linePetPosition` + the 4 pet constants public; refactor `drawChompPet`/`drawGhostPet` to call the new selectors (single source, no behavior change).
- **Create** `Sources/ThemeKitUI/PixelImage.swift` — internal CGImage rasterizer + SwiftUI `Image`/`Canvas` helpers for pixel sprites (shared by Tasks 4/6/7/8).
- **Rewrite** the 6 view files in `Sources/ThemeKitUI/`: `InkSplatterView.swift`, `PixelSpriteView.swift`, `ParticleBurstView.swift`, `LinePetsView.swift`, `PathPetView.swift`, `ChompCorridorView.swift`.
- **Delete** `Sources/ThemeKitUI/EffectClock.swift` (the 60 Hz `Timer`; replaced by `TimelineView`).
- **Create/extend** tests: `Tests/EffectsTests/PetSpritesTests.swift` (Task 1, CI). Optional `Tests/ThemeKitUITests/…` only if a ThemeKitUI test target exists — it does NOT today (#16 added none), so DO NOT create one; keep pixel-image coverage as a pure `Effects`/`PixelArt` test where possible.

---

### Task 1: Pure pet selectors + visibility promotion

**Files:**
- Create: `Sources/Effects/PetSprites.swift`
- Modify: `Sources/Effects/Effects.swift` (promote `linePetPosition` line ~768, `chompFaceCells`/`chompFaceFootprint`/`ghostFootprint` lines ~785-787, `pathPetPanicHz` line ~588 to `public`; refactor `drawChompPet`/`drawGhostPet` to use the selectors)
- Test: `Tests/EffectsTests/PetSpritesTests.swift`

**Interfaces:**
- Consumes (existing publics): `pacManCells(diameterCells:mouthHalfRad:)`, `mouthHalfRad`, `chompMouthFrames`, `chompMouthHz`, `PixelSprite`, `SpriteColor`, `CanonicalSprite.ghostFrames(look:)`, `CanonicalSprite.waddleHz`, `GhostLook`, `ThemedTransition.frameStep(now:hz:frames:)`.
- Produces:
  - `public func chompPacSprite(now: Double) -> PixelSprite` — a `chompFaceCells`×`chompFaceCells` sprite of pac-yellow cells (others transparent) at the current mouth phase.
  - `public func chompGhostSprite(now: Double, look: GhostLook) -> PixelSprite` — the waddling Blinky frame for `look` at `now`.
  - `public func linePetPosition(on r: CGRect, distance t: CGFloat) -> (x: CGFloat, y: CGFloat, rot: CGFloat)` (now public)
  - `public let chompFaceCells: Int`, `public let chompFaceFootprint: CGFloat`, `public let ghostFootprint: CGFloat`, `public let pathPetPanicHz: Double` (now public)

- [ ] **Step 1: Write the failing test** (`Tests/EffectsTests/PetSpritesTests.swift`)

```swift
import XCTest
@testable import Effects
import PixelArt

final class PetSpritesTests: XCTestCase {
    // Pac mouth SNAPS through chompMouthFrames at chompMouthHz via frameStep, so
    // two `now` values landing in different frame buckets give different sprites.
    func testPacMouthSnapsBetweenPhases() {
        let closed = chompPacSprite(now: 0)                    // frame 0 (mouth 0)
        let open   = chompPacSprite(now: 2.0 / chompMouthHz / 4) // a later bucket
        XCTAssertEqual(closed.width, chompFaceCells)
        XCTAssertEqual(closed.height, chompFaceCells)
        XCTAssertNotEqual(closed.cells().count, open.cells().count,
                          "mouth wedge changes the filled-cell count across frames")
    }
    // Ghost waddle swaps poses at waddleHz; the look picks the gaze grid.
    func testGhostWaddleSwapsAndLookMatters() {
        let a = chompGhostSprite(now: 0, look: .right)
        let b = chompGhostSprite(now: 1.0 / CanonicalSprite.waddleHz / 2 + 1e-6, look: .right)
        XCTAssertNotEqual(a, b, "feet pose swaps across the waddle half-cycle")
        XCTAssertNotEqual(chompGhostSprite(now: 0, look: .left),
                          chompGhostSprite(now: 0, look: .right),
                          "gaze direction changes the sprite")
    }
    // Negative now folds forward (frameStep convention) — no crash, deterministic.
    func testNegativeNowIsStable() {
        XCTAssertEqual(chompPacSprite(now: -3.21), chompPacSprite(now: -3.21))
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Run (CI-only locally cannot): `swift build` first. Expected after impl absent: `chompPacSprite` undefined ⇒ build/test fail. Note: locally only `swift build` runs; the assertion-level pass is verified by CI.

- [ ] **Step 3: Implement `PetSprites.swift`**

```swift
// Pure pet-placement selectors (#17h): "now → the sprite to draw" for the
// pac / ghost line-pets, so the SwiftUI-native ThemeKitUI views and the AppKit
// `drawChompPet`/`drawGhostPet` share ONE frame-selection source of truth.
#if canImport(CoreGraphics)
import Foundation
import PixelArt
import Motion

/// The pac line-pet at `now`: a `chompFaceCells`-wide PixelSprite whose mouth
/// wedge SNAPS through `chompMouthFrames` at `chompMouthHz` (the retro swap).
/// Pac-yellow filled cells; every other cell transparent. The wedge opens
/// toward +x (travel) — the caller rotates by the lap tangent.
public func chompPacSprite(now: Double) -> PixelSprite {
    let phase = ThemedTransition.frameStep(now: now, hz: chompMouthHz, frames: chompMouthFrames)
    let cells = pacManCells(diameterCells: chompFaceCells, mouthHalfRad: mouthHalfRad(phase))
    let filled = Set(cells.map { Point(col: $0.col, row: $0.row) })
    var rows: [String] = []
    let yellowChar: Character = "Y"
    for r in 0..<chompFaceCells {
        var line = ""
        for c in 0..<chompFaceCells {
            line.append(filled.contains(Point(col: c, row: r)) ? yellowChar : " ")
        }
        rows.append(line)
    }
    return PixelSprite(rows: rows, palette: [yellowChar: SpriteColor.pacYellow])
}

/// The waddling Blinky frame for `look` at `now` (poses swap at `waddleHz`).
public func chompGhostSprite(now: Double, look: GhostLook) -> PixelSprite {
    ThemedTransition.frameStep(now: now, hz: CanonicalSprite.waddleHz,
                              frames: CanonicalSprite.ghostFrames(look: look))
}

private struct Point: Hashable { let col: Int; let row: Int }
#endif
```

> **Implementer note:** verify `PixelSprite`'s real initializer signature (it is built from a `rows: [String]` grid + a char→`UInt32` palette — confirm exact label names in `Sources/PixelArt/PixelSprite.swift` and adapt; the space char must map to "transparent/empty"). If `PixelSprite` uses a different empty convention, mirror what `CanonicalSprite.cherry` does. Confirm `mouthHalfRad` is the phase→radians mapping the old `drawChompPet` used (it called `mouthHalfRad(phase)`).

- [ ] **Step 4: Promote visibility + refactor draws in `Effects.swift`**

Change `private func linePetPosition` → `public func linePetPosition`. Change `private let chompFaceCells`/`chompFaceFootprint`/`ghostFootprint`/`pathPetPanicHz` → `public let …`. In `drawChompPet`, replace the inline `frameStep`+`pacManCells` blit with: build via `chompPacSprite(now:)` then `drawPixelSprite(_, cell:, at:)` centered — OR keep the existing blit but route the mouth phase through the same `chompMouthFrames`/`chompMouthHz` (behavior must stay byte-identical; the goal is shared constants, not a redraw). Likewise `drawGhostPet` → `chompGhostSprite(now:look:)`. Keep `drawChompPetSmooth`/`drawGhostPetSmooth` untouched.

> **Implementer note:** the refactor of `drawChompPet`/`drawGhostPet` is OPTIONAL DRY — if it risks changing pixels, SKIP it and only promote the constants/`linePetPosition` to public (the selectors are then the new public path ThemeKitUI uses; the AppKit draws keep their existing private logic). Do not break the existing `Effects` tests.

- [ ] **Step 5: `swift build`** — Run: `swift build`. Expected: PASS (compiles on CLT).

- [ ] **Step 6: Commit**

```bash
git add Sources/Effects/PetSprites.swift Sources/Effects/Effects.swift Tests/EffectsTests/PetSpritesTests.swift
git commit -m ":sparkles: feat(Effects): #17h — pure pet-sprite selectors + public pet-placement geometry"
```

---

### Task 2: ThemeKitUI pixel-image helpers (CGImage rasterizer)

**Files:**
- Create: `Sources/ThemeKitUI/PixelImage.swift`

**Interfaces:**
- Consumes: `PixelSprite.cells() -> [(col,row,color)]`, `PixelSprite.width`, `PixelSprite.height`, `HexColor` (for channel extraction — or decode `0xRRGGBB` directly).
- Produces:
  - `func pixelCGImage(_ sprite: PixelSprite, color: UInt32?) -> CGImage?` — a `width × height`-PIXEL image (1 px/cell), cell color = `color ?? cell.color`, empty cells transparent. (nonisolated; pure CoreGraphics.)
  - `func pixelImage(_ sprite: PixelSprite, color: UInt32? = nil) -> Image` — `Image(decorative: cg, scale: 1).interpolation(.none)` (nil cg ⇒ empty `Image`).
  - `func drawPixelSprite(in ctx: inout GraphicsContext, _ sprite: PixelSprite, cell: CGFloat, at origin: CGPoint, rotation: CGFloat, color: UInt32?)` — resolves `pixelImage(...).resizable()` and draws it `width*cell × height*cell` at `origin` under a `rotation` (radians) CTM, preserving nearest-neighbor.

- [ ] **Step 1: Implement `PixelImage.swift`**

```swift
// ThemeKitUI — pixel-sprite rasterization for the SwiftUI-native effect views
// (#17h). A PixelSprite becomes a 1px/cell CGImage shown with
// `.interpolation(.none)` (nearest-neighbor) so cells stay crisp at any scale
// AND under rotation — the SwiftUI replacement for the AppKit `shouldAntialias
// = false` blitter (which is now gone from this layer).
import SwiftUI
import CoreGraphics
import PixelArt

/// Rasterize `sprite` to a `width × height`-PIXEL image (one device pixel per
/// cell). `color` overrides every filled cell; nil honours each cell's own
/// `0xRRGGBB`. Empty cells are transparent.
func pixelCGImage(_ sprite: PixelSprite, color: UInt32?) -> CGImage? {
    let w = sprite.width, h = sprite.height
    guard w > 0, h > 0 else { return nil }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setShouldAntialias(false)
    for c in sprite.cells() {
        let rgb = color ?? c.color
        let r = CGFloat((rgb >> 16) & 0xFF) / 255, g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        // CGContext origin is bottom-left; sprite row 0 is the TOP → flip row.
        ctx.fill(CGRect(x: c.col, y: h - 1 - c.row, width: 1, height: 1))
    }
    return ctx.makeImage()
}

func pixelImage(_ sprite: PixelSprite, color: UInt32? = nil) -> Image {
    guard let cg = pixelCGImage(sprite, color: color) else { return Image(size: .zero) { _ in } }
    return Image(decorative: cg, scale: 1).interpolation(.none)
}

func drawPixelSprite(in ctx: inout GraphicsContext, _ sprite: PixelSprite,
                     cell: CGFloat, at origin: CGPoint, rotation: CGFloat, color: UInt32?) {
    let w = CGFloat(sprite.width) * cell, h = CGFloat(sprite.height) * cell
    guard w > 0, h > 0 else { return }
    let resolved = ctx.resolve(pixelImage(sprite, color: color).resizable())
    ctx.drawLayer { layer in
        layer.translateBy(x: origin.x, y: origin.y)
        layer.rotate(by: .radians(Double(rotation)))
        layer.draw(resolved, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }
}
```

> **Implementer notes:** (1) `Image(size:renderer:)` empty fallback API exists on macOS 13+; if unavailable, return `Image(nsImage: NSImage(size: .zero))`. (2) Decide the sprite's draw anchor — `drawPixelSprite` centers (`-w/2,-h/2`) to match the rotated pet transforms; the standalone `PixelSpriteView` (Task 4) places top-left at origin like the old `drawPixelSprite(at:)` — so it uses `pixelImage(...).resizable().frame(...)` directly, NOT this centered Canvas helper. (3) Verify nearest-neighbor survives `layer.rotate` + `draw(resolved,in:)` during the FIRST rotated-pet task (Task 6) via the maintainer's prism gate; if it softens, switch the pet rendering to a ZStack of `pixelImage(...).rotationEffect(...)` overlays (still SwiftUI — do not revert to AppKit).

- [ ] **Step 2: `swift build`** — Run: `swift build`. Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ThemeKitUI/PixelImage.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17h — nearest-neighbor pixel-sprite CGImage helpers"
```

---

### Task 3: InkSplatterView → SwiftUI Canvas

**Files:**
- Rewrite: `Sources/ThemeKitUI/InkSplatterView.swift`

**Interfaces:**
- Consumes: `SplatterShape` (`.units` → `Unit.rim/.body/.droplets: [(x,y)]`, `.color`), `SplatterShape.alpha(now:)`, `rollSplatter(at:size:colors:seed:now:duration:)`, `SplatterShape.startedAt`.
- Produces: `public struct InkSplatterView: View` (same public stored props + inits as today: `colors`, `seed`, `duration`, `loopPeriod`, `frozen`, `center`, `size`, `static frozenSeedDefault`).

- [ ] **Step 1: Rewrite as native SwiftUI.** Replace the `NSViewRepresentable`/`InkSplatterNSView` with a `View` whose `body` is a `Canvas` (live = wrapped in `TimelineView(.animation)`; `frozen != nil` = static). Keep the public API verbatim. Render each `unit`: build a closed Catmull-Rom `SwiftUI.Path` (same 1/6-tension formula as the AppKit `catmullRomPath`) for `rim` (color = unit ink blended 45% toward black, α `0.78·a`), `body` (ink α `0.96·a`), each `droplets` blob (ink α `0.88·a`), filling with `ctx.fill(path, with: .color(...))`. FLIPPED frame (+y down): the splat math is in the view's local space; honor `center(bounds)`/`size(bounds)`.

Key clock logic (mirror the old `draw`): re-stamp once or every `loopPeriod`; `frozen` ⇒ stable seed (`seed ?? frozenSeedDefault`) at fraction `f·duration`. Catmull-Rom helper:

```swift
private func catmullRom(_ v: [(x: Double, y: Double)]) -> Path {
    var p = Path(); let n = v.count; guard n > 1 else { return p }
    func cg(_ q: (x: Double, y: Double)) -> CGPoint { CGPoint(x: q.x, y: q.y) }
    p.move(to: cg(v[0]))
    for i in 0..<n {
        let p0 = v[(i-1+n)%n], p1 = v[i], p2 = v[(i+1)%n], p3 = v[(i+2)%n]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x)/6, y: p1.y + (p2.y - p0.y)/6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x)/6, y: p2.y - (p3.y - p1.y)/6)
        p.addCurve(to: cg(p2), control1: c1, control2: c2)
    }
    p.closeSubpath(); return p
}
```

> **Color blend note:** the AppKit rim used `NSColor.black.blended(withFraction:0.45, of: ink)`. Replicate as a manual lerp of `unit.color` channels toward 0 by 0.45 (don't import AppKit). Body/droplet colors are `unit.color` at the listed alphas.

- [ ] **Step 2: `swift build`** — Run: `swift build`. Expected: PASS.
- [ ] **Step 3: No-AppKit gate** — Run: `grep -nE "NSViewRepresentable|NSShadow|shouldAntialias|drawInkSplatter|import AppKit" Sources/ThemeKitUI/InkSplatterView.swift`. Expected: NO matches.
- [ ] **Step 4: Commit** — `git commit -am ":recycle: refactor(ThemeKitUI): #17h — InkSplatterView SwiftUI-native (Canvas + Catmull-Rom Path)"`

---

### Task 4: PixelSpriteView → Image(.interpolation(.none))

**Files:**
- Rewrite: `Sources/ThemeKitUI/PixelSpriteView.swift`

**Interfaces:**
- Consumes: `pixelImage(_:color:)` (Task 2), `ThemedTransition.frameStep(now:hz:frames:)`, `PixelSprite.pixelSize(cell:)`, `CanonicalSprite.waddleHz`.
- Produces: `public struct PixelSpriteView: View` (same props/inits: `frames`, `hz`, `cell`, `color`, `frozen`; plus `init(sprite:cell:color:)`).

- [ ] **Step 1: Rewrite.** `body`: choose the current `PixelSprite` (single frame ⇒ `frames[0]`; else `frameStep(now:hz:frames:)`), render `pixelImage(sprite, color: color).resizable().frame(width: w, height: h)` where `w = CGFloat(sprite.width)*cell`, `h = CGFloat(sprite.height)*cell`. Live (`frozen == nil`, `frames.count > 1`) ⇒ wrap in `TimelineView(.animation)` with a birth-relative clock (`now = context.date.timeIntervalSince(start)` where `start` is a `@State` set once). `frozen != nil` ⇒ static at that absolute `now`. Single-frame ⇒ no `TimelineView` (no clock). Preserve the intrinsic size (`pixelSize(cell:)`) so prism's layout is unchanged.

> **Clock note:** capture the birth `Date` in a `@State private var start = Date()` initialized in `init`? `Date()` in a `@State` default is fine. Use `TimelineView(.animation)`'s `context.date` minus `start` for `now`. Match the old "clock from view birth" contract.

- [ ] **Step 2: `swift build`** — Expected: PASS.
- [ ] **Step 3: No-AppKit gate** — `grep -nE "NSViewRepresentable|shouldAntialias|drawPixelSprite\(|import AppKit" Sources/ThemeKitUI/PixelSpriteView.swift` ⇒ NO matches (note: the Canvas helper `drawPixelSprite(in:…)` is NOT used here; the standalone view uses `pixelImage` directly).
- [ ] **Step 4: Commit** — `git commit -am ":recycle: refactor(ThemeKitUI): #17h — PixelSpriteView SwiftUI-native (Image interpolation .none)"`

---

### Task 5: ParticleBurstView → SwiftUI Canvas (glow watch-point)

**Files:**
- Rewrite: `Sources/ThemeKitUI/ParticleBurstView.swift`

**Interfaces:**
- Consumes: `resolveParticles(_:now:) -> [ResolvedParticle]` (`x`/`y`/`radius`/`alpha`/`color`/`rotation`/`shape`), `ParticleShape{.spark,.paper}`, `rollBurst(emission:from:colors:intensity:now:duration:radiusSpeed:)`, `ParticleBurst.startedAt`.
- Produces: `public struct ParticleBurstView: View` (same props/inits: `emission`, `colors`, `intensity`, `duration`, `radiusSpeed`, `loopPeriod`, `emitters`, `scale`, `frozen`).

- [ ] **Step 1: Rewrite.** `body` = a FLIPPED-coordinate `Canvas` (+y down) wrapped in `TimelineView(.animation)` (live) or static (`frozen`). Re-roll logic identical to the old `draw`: one-shot (`loopPeriod == nil`) re-rolls once; else every `loopPeriod`; clock = `context.date.timeIntervalSinceReferenceDate` (absolute/monotonic for `startedAt` math). For each `rp` in `resolveParticles(burst, now)`:
  - `.spark`: `ctx.addFilter(.shadow(color: Color(particle, opacity: a*0.85), radius: rp.radius*2.6*scale))`, fill an oval `Ø 2r` at (x,y); then a hot-white core oval `Ø r` (white, α `a*0.85`, NO shadow — apply core in a separate `ctx.drawLayer` or after resetting the filter).
  - `.paper`: in a `ctx.drawLayer { l in … }`, `l.translateBy(x,y)`, `l.rotate(by:.radians(rotation*0.4))`, `l.scaleBy(x: flip, y: 1)` (`flip = max(0.18, abs(cos(rotation)))`), fill a rounded rect `w=radius*2.4*scale, h=radius*1.4*scale, corner=1*scale` with the back-face-darkened color.

> **GLOW WATCH-POINT (Global Constraint):** `GraphicsContext.addFilter(.shadow(radius:))` blur scale ≠ `NSShadow.shadowBlurRadius`. Start with `radius = rp.radius*2.6*scale` (the old value) and let the maintainer compare in prism's Particles tab. If the glow reads materially weaker/stronger, tune the multiplier — and if it cannot be matched, STOP and consult (do not revert to AppKit). The `.shadow` filter applies to subsequent draws in the context; isolate spark glow from the white core (separate layers) so the core stays sharp.

- [ ] **Step 2: `swift build`** — Expected: PASS.
- [ ] **Step 3: No-AppKit gate** — `grep -nE "NSViewRepresentable|NSShadow|drawParticles|drawSpark|drawPaper|import AppKit" Sources/ThemeKitUI/ParticleBurstView.swift` ⇒ NO matches.
- [ ] **Step 4: Commit** — `git commit -am ":recycle: refactor(ThemeKitUI): #17h — ParticleBurstView SwiftUI-native (Canvas + shadow filter)"`

---

### Task 6: LinePetsView → SwiftUI Canvas + rotated pixel sprites (rotation watch-point)

**Files:**
- Rewrite: `Sources/ThemeKitUI/LinePetsView.swift`

**Interfaces:**
- Consumes: `linePetPosition(on:distance:)` (public, Task 1), `chompPacSprite(now:)`, `chompGhostSprite(now:look:)`, `GhostLook.facing(dx:dy:)`, `chompFaceFootprint`/`chompFaceCells`/`ghostFootprint`, `LinePet{.chomp,.ghost}`, `drawPixelSprite(in:_:cell:at:rotation:color:)` (Task 2).
- Produces: `public struct LinePetsView: View` (same props/inits: `pets`, `inset`, `scale`, `speed`, `frozen`).

- [ ] **Step 1: Rewrite.** `body` = NON-flipped (+y up) `Canvas` (live `TimelineView`/static `frozen`, birth-relative clock). Replicate `drawLinePets`' lap math: `track = bounds.insetBy(inset)`; `perim = 2*(w+h)`; `leader = now.truncatingRemainder(perim/speed)*speed`; per pet `i`: `pos = (leader - i*chaseGap)` folded into `[0,perim)`, `chaseGap = 24*scale`; `(px,py,rot) = linePetPosition(on: track, distance: pos)`.
  - `.chomp`: `cell = scale*chompFaceFootprint/CGFloat(chompFaceCells)`; `drawPixelSprite(in:&ctx, chompPacSprite(now:), cell: cell, at: CGPoint(px,py), rotation: rot, color: SpriteColor.pacYellow)`.
  - `.ghost`: `look = GhostLook.facing(dx: Double(cos(rot)), dy: Double(sin(rot)))`; ghost stays UPRIGHT (`rotation: 0`); `cell = scale*ghostFootprint/14`; `drawPixelSprite(in:&ctx, chompGhostSprite(now:look:), cell: cell, at: CGPoint(px,py), rotation: 0, color: nil)`.

> **Canvas +y-up note:** SwiftUI Canvas is +y DOWN by default. The old draws were NON-flipped (+y up). Either flip the Canvas CTM once (`ctx.scaleBy(x:1,y:-1)` + translate by height) so `linePetPosition`/`GhostLook` math matches verbatim, OR convert y at the call sites consistently. Pick ONE and document it; the upright sprites must not end up upside-down (prism gate).
> **ROTATION WATCH-POINT (Global Constraint):** this is the first rotated-pixel task. The maintainer verifies in prism's PixelArt tab that the pac's rotated pixels stay crisp (not blurred) and the ghost reads upright with correct gaze. If rotation softens the pixels, switch the pet draw to the ZStack `rotationEffect` fallback noted in Task 2 (still SwiftUI). Do NOT revert to AppKit.

- [ ] **Step 2: `swift build`** — Expected: PASS.
- [ ] **Step 3: No-AppKit gate** — `grep -nE "NSViewRepresentable|drawLinePets|drawChompPet|drawGhostPet|drawPacMan|shouldAntialias|import AppKit" Sources/ThemeKitUI/LinePetsView.swift` ⇒ NO matches.
- [ ] **Step 4: Commit** — `git commit -am ":recycle: refactor(ThemeKitUI): #17h — LinePetsView SwiftUI-native (Canvas + nearest-neighbor pets)"`

---

### Task 7: PathPetView → SwiftUI Canvas (glow + rotation)

**Files:**
- Rewrite: `Sources/ThemeKitUI/PathPetView.swift`

**Interfaces:**
- Consumes: `polylineLength([CGPoint])`, `roundedCornerPath([CGPoint], radius:)` (→ `[PathStep]`), `pathPetCursors(total:speed:now:faceLag:)`, `markAtArcLength([CGPoint], distance:)` (`.point`/`.tangent`), `chompPacSprite`/`chompGhostSprite`, `GhostLook.facing`, `ThemedTransition.dampedSine(_:frequency:decay:)`, `pathPetPanicHz` (public), `SpriteColor.pupilBlue`/`.pacYellow`, `drawPixelSprite(in:…)`, `chompFaceFootprint`/`chompFaceCells`/`ghostFootprint`.
- Produces: `public struct PathPetView: View` (same props/inits: `path`, `valid`, `scale`, `speed`, `faceLag`, `showGuide`, `frozen`).

- [ ] **Step 1: Rewrite.** NON-flipped Canvas (same y-up handling as Task 6). Replicate `drawChompPath` (with `showHead: true` default — the standalone PathPetView showed the head; the corridor calls its own logic in Task 8): pts = `path(bounds)`; guard `count>=2, speed>0`; `total = polylineLength(pts)`.
  - `showGuide`: stroke `roundedCornerPath(pts, radius: 6*scale)` as a SwiftUI `Path` (build from `[PathStep]` — see helper note) with `pupilBlue` α 0.22, line width `1.5*scale`.
  - `(headDist, petDist) = pathPetCursors(total:, speed:Double(speed), now:, faceLag:Double(faceLag))`.
  - head dot (`valid && faceLag>0`): `addFilter(.shadow(color: pacYellow, radius: 4*scale))` then fill `Ø 2*(2.5*scale)` oval at `markAtArcLength(pts, headDist).point` (isolate in a layer so it doesn't bleed onto the pet).
  - pet at `markAtArcLength(pts, petDist)`: `valid` ⇒ pac rotated by `atan2(tangent.y, tangent.x)`, `cell = scale*chompFaceFootprint/chompFaceCells`, `drawPixelSprite(in:…, chompPacSprite(now:), …, rotation: angle, color: pacYellow)`. Else ⇒ ghost upright at `(px+jx, py+jy)` where `pp = frac(now*pathPetPanicHz)` folded ≥0, `jx = dampedSine(pp,freq:6,decay:0)*1.6*scale`, `jy = dampedSine(pp,freq:7,decay:0)*1.6*scale`; `look = GhostLook.facing(tangent.x, tangent.y)`; rotation 0.

> **PathStep → SwiftUI Path helper:** add (in `PixelImage.swift` or a small `Sources/ThemeKitUI/TrailPath.swift`) `func path(from steps: [PathStep]) -> Path` translating each `PathStep` case (line/curve/move — confirm the enum's cases in `Sources/Effects/Trail.swift`) into `Path` ops. This is REUSED by Task 8 (corridor walls). Define it here, consume it in both.

- [ ] **Step 2: `swift build`** — Expected: PASS.
- [ ] **Step 3: No-AppKit gate** — `grep -nE "NSViewRepresentable|NSShadow|drawChompPath|nsBezierPath|import AppKit" Sources/ThemeKitUI/PathPetView.swift` ⇒ NO matches.
- [ ] **Step 4: Commit** — `git commit -am ":recycle: refactor(ThemeKitUI): #17h — PathPetView SwiftUI-native (Canvas guide + glow + nearest-neighbor pet)"`

---

### Task 8: ChompCorridorView → SwiftUI Canvas (composite; glow + rotation + text)

**Files:**
- Rewrite: `Sources/ThemeKitUI/ChompCorridorView.swift`

**Interfaces:**
- Consumes: everything Task 7 consumes, plus `ScaleTier` (`.multiplier`), `resampleAlongPolyline([CGPoint], interval:)`, `interiorCorners([CGPoint])` (`.vertex`/`.bisector`/`.turn`), `positionHash01(x:y:)`, `bonusValue(x:y:)`, `chompFlashPhase(eventArcs:total:speed:now:faceLag:dur:)`, `chompScorePops(bonuses:total:speed:now:faceLag:dur:)` (`ScorePop.point`/`.t`/`.value`), `chompEatFlashDur`, `chompScorePopDur`, `blendThrough([UInt32], at:)`, `EffectSpec.chomp.flash`, `CanonicalSprite.cherry`, `ThemedTransition.Easing.easeOutCubic`, the `path(from:[PathStep])` helper (Task 7), `pixelImage`/`drawPixelSprite`, `NSImage` (the `icon` param type only — drawn via `ctx.draw(Image(nsImage:))`, NOT AppKit drawing).
- Produces: `public struct ChompCorridorView: View` (same props/inits: `path`, `valid`, `tier`, `icon`, `showBonuses`, `scale`, `speed`, `frozen`).

- [ ] **Step 1: Rewrite** as a NON-flipped Canvas replicating `drawChompCorridor` step-for-step (see spec §4.6 and the AppKit source `Effects.swift:640-762`):
  1. sizing: `s = tier.multiplier*scale`, `roadWidth=11*s`, `wallThick=max(1,0.9*s)`, `pelletR=0.8*s`, `pelletGap=5.2*s`, `roadHalf=roadWidth/2`.
  2. cursors/eat: `total=polylineLength(pts)`, `faceLag = valid ? roadWidth*1.4 : 0`, `faceArc = pathPetCursors(...).pet`.
  3. classify pellets from `resampleAlongPolyline(pts, interval: pelletGap)` (skip i==0; `arc=min(i*pelletGap,total)`; kind via `positionHash01` band: cherry `<0.04`, icon `<0.08 && icon != nil`, else dot; `!showBonuses` ⇒ all dot; `value=bonusValue`).
  4. walls: `steps = roundedCornerPath(pts, radius: roadHalf)`; build `wallPath = path(from: steps)`; stroke WIDE (`lineWidth: roadWidth+2*wallThick`) in `wallColor` under `addFilter(.shadow(color: wallColor·(flash != nil ? 1 : 0.85), radius:(flash != nil ?5:3)*s))`, then stroke `roadWidth` in BLACK (no shadow). `wallColor = flash != nil ? blendThrough(EffectSpec.chomp.flash, at: flash) : pupilBlue` (decode `(r,g,b)` → `Color`). `flash = chompFlashPhase(eventArcs: bonusArcs, total:, speed:, now:, faceLag:, dur: chompEatFlashDur)` where `bonusArcs = valid ? non-dot pellet arcs : []`.
  5. fillets: for each `interiorCorners(pts)` corner, fill a BLACK disc `r = wallThick*1.15` at `vertex + bisector*(roadHalf/cos(|turn|/2))`.
  6. pellets: skip eaten (`valid && faceArc >= arc`); cherry ⇒ `drawPixelSprite(in:…, CanonicalSprite.cherry, cell: roadWidth*0.62/12, at: point, rotation: 0, color: nil)`; icon ⇒ `ctx.draw(ctx.resolve(Image(nsImage: icon)), in: square box roadWidth*0.66 centered)`; dot ⇒ yellow oval `Ø 2*pelletR`.
  7. pet: inline the Task-7 pet draw (no guide, no head) at `petScale = roadWidth*0.78/chompFaceFootprint` (do NOT call the old `drawChompPath`).
  8. score pops (`valid`): `chompScorePops(...)` → for each, `ctx.draw(Text("+\(pop.value)").font(.system(size: 9*s, weight: .bold, design: .monospaced)).foregroundColor(Color(pacYellow, opacity: max(0,1-pop.t))), at: CGPoint(x: pop.point.x, y: pop.point.y + easeOutCubic(pop.t)*14*s))` — match the AppKit rise/fade.

> **Risk note:** this is the largest composite (glow + rotated pixels + text + icon image). Build incrementally and rely on the maintainer's prism gate on the "ChompCorridor (#12 Ph5)" card (valid + mismatch). The icon is drawn as a SwiftUI image (`Image(nsImage:)`), which is allowed — `NSImage` here is just the pre-resolved image payload, not AppKit drawing.

- [ ] **Step 2: `swift build`** — Expected: PASS.
- [ ] **Step 3: No-AppKit gate** — `grep -nE "NSViewRepresentable|NSShadow|drawChompCorridor|drawCenteredSprite|drawCorridorIcon|drawScorePop|nsBezierPath|shouldAntialias" Sources/ThemeKitUI/ChompCorridorView.swift` ⇒ NO matches. (`import AppKit` is allowed ONLY for the `NSImage` type in the public `icon` prop — confirm it's used solely as the image payload, never for drawing. Prefer keeping the `NSImage` type via `import AppKit` minimal.)
- [ ] **Step 4: Commit** — `git commit -am ":recycle: refactor(ThemeKitUI): #17h — ChompCorridorView SwiftUI-native (composite Canvas)"`

---

### Task 9: Delete EffectClock + final no-AppKit sweep + prism build

**Files:**
- Delete: `Sources/ThemeKitUI/EffectClock.swift`

**Interfaces:** none produced; this finalizes the migration.

- [ ] **Step 1: Confirm `startEffectTick` is unused**, then delete the file — Run: `grep -rn "startEffectTick\|EffectClock" Sources/`. Expected after Task 3-8: matches ONLY in `EffectClock.swift`. Then `git rm Sources/ThemeKitUI/EffectClock.swift`.
- [ ] **Step 2: `swift build`** — Run: `swift build`. Expected: PASS (prism + all targets compile).
- [ ] **Step 3: Final whole-module no-AppKit gate** — Run: `grep -rnE "NSViewRepresentable|NSShadow|shouldAntialias|drawParticles|drawInkSplatter|drawPixelSprite\(|drawPacMan|drawLinePets|drawChompPath|drawChompCorridor|drawScorePop|drawSpark|drawPaper" Sources/ThemeKitUI/{ParticleBurstView,InkSplatterView,PixelSpriteView,LinePetsView,PathPetView,ChompCorridorView}.swift`. Expected: ZERO matches (the end-state guarantee).
- [ ] **Step 4: Confirm prism untouched** — Run: `git status Sources/prism/` ⇒ no changes (prism consumed the views by their preserved public API).
- [ ] **Step 5: Commit** — `git commit -am ":fire: refactor(ThemeKitUI): #17h — drop EffectClock 60Hz timer (TimelineView replaces it)"`

---

## Self-Review

**1. Spec coverage:** §1 goal → all tasks; §2.1 pure layer reuse → consumed in Tasks 3-8; §2.2 promotions → Task 1; §2.3 AppKit draws stay → enforced (no deletion of Effects draws); §3 architecture (Canvas/Image-none/TimelineView) → Tasks 2-8; §3.1 pixel technique → Task 2 + 4/6/7/8; §3.2 selectors → Task 1; §3.3 clock → per-view clock notes; §4 per-part → Tasks 3-8; §5 order (low→high risk) → Task order 3(splatter)→4(pixel)→5(particle)→6(linepets)→7(pathpet)→8(corridor); EffectClock delete → Task 9; §6 verification → build + grep gates + (CI test in Task 1) + maintainer prism gate noted; §7 end-state → Task 9 Step 3. No gaps.

**2. Placeholder scan:** No TBD/TODO. "Implementer notes" carry concrete fallbacks (verify exact `PixelSprite` init; ZStack rotation fallback; PathStep enum cases) — these are real API-confirmation steps, not deferred work.

**3. Type consistency:** `chompPacSprite(now:)`/`chompGhostSprite(now:look:)` (Task 1) consumed verbatim in 6/7/8. `pixelCGImage`/`pixelImage`/`drawPixelSprite(in:…)` (Task 2) consumed in 4/6/7/8. `path(from:[PathStep])` defined in Task 7, reused in Task 8. `linePetPosition`/`chompFaceCells`/`chompFaceFootprint`/`ghostFootprint`/`pathPetPanicHz` promoted in Task 1, consumed in 6/7. Public view APIs unchanged ⇒ prism (consumer) untouched (Task 9 Step 4).

**Known confirm-at-implementation points (not placeholders):** exact `PixelSprite` initializer label/empty-cell convention; `PathStep` enum case names; `SwiftUI.Image(size:renderer:)` availability on the OS floor; whether `GraphicsContext` rotation preserves `.interpolation(.none)` (Task 6 maintainer gate decides fallback).
