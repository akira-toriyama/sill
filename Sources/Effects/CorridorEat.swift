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
/// (the `pathPetCursors` / `frameStep` convention). Callers guard `total`/`speed`.
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
