// Particle-burst tests — the one-shot celebratory atom (紙吹雪 / 花火).
//
// The closed-form resolve is asserted against HAND-BUILT bursts (no
// `rollBurst` randomness) so the math is exact; `rollBurst` itself is tested
// for counts/caps/colors/gravity. All boundary values are binary-exact
// fractions (0.5 / 0.25 / powers of two) — the #6 lesson: a `swift test`
// float boundary is caught only by CI, so never sit one on a value like
// `0.1 + 0.2`.

import XCTest
import AppKit
@testable import Palette
@testable import Effects

@MainActor
final class ParticlesTests: XCTestCase {

    // MARK: - Closed-form resolve (deterministic, hand-built)

    func testClosedFormBallistic() {
        // vy negative = up; gravity arcs it back down. All values binary-exact.
        let p = Particle(x0: 10, y0: 20, vx: 100, vy: -50, radius: 2, color: 0xFF0000)
        let b = ParticleBurst(particles: [p], startedAt: 100, duration: 1,
                              gravity: 800, emission: .fireworks)
        // t = 0 → at the emitter, full alpha, no rotation.
        let r0 = resolveParticles(b, now: 100)
        XCTAssertEqual(r0.count, 1)
        XCTAssertEqual(r0[0].x, 10, accuracy: 1e-9)
        XCTAssertEqual(r0[0].y, 20, accuracy: 1e-9)
        XCTAssertEqual(r0[0].alpha, 1, accuracy: 1e-9)
        XCTAssertEqual(r0[0].rotation, 0, accuracy: 1e-9)
        // t = 0.5 → x = 10 + 100·0.5 = 60; y = 20 − 50·0.5 + ½·800·0.25 = 95.
        let r = resolveParticles(b, now: 100.5)
        XCTAssertEqual(r[0].x, 60, accuracy: 1e-9)
        XCTAssertEqual(r[0].y, 95, accuracy: 1e-9)
        XCTAssertEqual(r[0].alpha, 0.5, accuracy: 1e-9)   // life = 1 → localP = 0.5
    }

    func testSpinAndSwayAreClosedForm() {
        // phase 0, swayFreq π → at t = 0.5 the sway term is sin(π/2) = 1.
        let p = Particle(x0: 0, y0: 0, vx: 40, vy: 0, radius: 2, color: 0x00FF00,
                         spin: 4, sway: 10, swayFreq: .pi, phase: 0, life: 1, shape: .paper)
        let b = ParticleBurst(particles: [p], startedAt: 0, duration: 2,
                              gravity: 0, emission: .confetti)
        // t = 0 → sway term is sin(0) = 0, rotation 0.
        XCTAssertEqual(resolveParticles(b, now: 0)[0].x, 0, accuracy: 1e-9)
        // t = 0.5 → x = 40·0.5 + 10·sin(π/2) = 20 + 10 = 30; rotation = 4·0.5 = 2.
        let r = resolveParticles(b, now: 0.5)[0]
        XCTAssertEqual(r.x, 30, accuracy: 1e-6)
        XCTAssertEqual(r.rotation, 2, accuracy: 1e-9)
    }

    func testPerParticleLifeDropsDeadOnes() {
        let short = Particle(x0: 0, y0: 0, vx: 0, vy: 0, radius: 1, color: 1, life: 0.5)
        let long  = Particle(x0: 0, y0: 0, vx: 0, vy: 0, radius: 1, color: 2, life: 1.0)
        let b = ParticleBurst(particles: [short, long], startedAt: 0, duration: 1,
                              gravity: 0, emission: .fireworks)
        // Before either dies: both alive.
        XCTAssertEqual(resolveParticles(b, now: 0.25).count, 2)
        // At t = 0.75: short (lifeSpan 0.5) is past its end → dropped; long alive.
        let mid = resolveParticles(b, now: 0.75)
        XCTAssertEqual(mid.count, 1)
        XCTAssertEqual(mid[0].color, 2)
        XCTAssertEqual(mid[0].alpha, 0.25, accuracy: 1e-9)   // long: 1 − 0.75
    }

    func testEmptyBeforeRollAndAfterSettle() {
        let p = Particle(x0: 0, y0: 0, vx: 0, vy: 0, radius: 1, color: 1)
        let b = ParticleBurst(particles: [p], startedAt: 10, duration: 2,
                              gravity: 0, emission: .fireworks)
        XCTAssertTrue(resolveParticles(b, now: 9.5).isEmpty)    // before the roll
        XCTAssertTrue(resolveParticles(b, now: 12).isEmpty)     // exactly settled
        XCTAssertTrue(resolveParticles(b, now: 99).isEmpty)     // long after
        XCTAssertFalse(resolveParticles(b, now: 10).isEmpty)    // at the roll
    }

    func testIsActiveAndProgressBoundaries() {
        let b = ParticleBurst(particles: [], startedAt: 0, duration: 2,
                              gravity: 0, emission: .confetti)
        XCTAssertFalse(b.isActive(now: -1))   // t < 0
        XCTAssertTrue(b.isActive(now: 0))     // t = 0
        XCTAssertTrue(b.isActive(now: 1))
        XCTAssertFalse(b.isActive(now: 2))    // t = duration → settled
        XCTAssertEqual(b.progress(now: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(b.progress(now: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(b.progress(now: 2), 1, accuracy: 1e-9)
        XCTAssertEqual(b.progress(now: 3), 1, accuracy: 1e-9)   // clamped
        XCTAssertEqual(b.progress(now: -5), 0, accuracy: 1e-9)  // clamped
    }

    // MARK: - rollBurst (counts, caps, colors, gravity, shape)

    func testRollBurstCountScalesWithIntensityAndCaps() {
        let two = [(x: 0.0, y: 0.0), (x: 0.0, y: 0.0)]
        // fireworks base 18: normal 1.0× → 18/emitter.
        XCTAssertEqual(rollBurst(emission: .fireworks, from: two, colors: [1],
                                 intensity: .normal, now: 0).particles.count, 36)
        // wild 2.5× → 18·2.5 = 45 → capped at 40.
        XCTAssertEqual(rollBurst(emission: .fireworks, from: [(x: 0.0, y: 0.0)],
                                 colors: [1], intensity: .wild, now: 0).particles.count, 40)
        // subtle 0.6× → 18·0.6 = 10 → above the floor of 6.
        XCTAssertEqual(rollBurst(emission: .fireworks, from: [(x: 0.0, y: 0.0)],
                                 colors: [1], intensity: .subtle, now: 0).particles.count, 10)
        // explicit count overrides the intensity math (and the floor).
        XCTAssertEqual(rollBurst(emission: .confetti, from: [(x: 0.0, y: 0.0)],
                                 colors: [1], now: 0, count: 3).particles.count, 3)
    }

    func testRollBurstEmissionGravityAndShape() {
        let fw = rollBurst(emission: .fireworks, from: [(x: 0.0, y: 0.0)],
                           colors: [1], now: 0)
        XCTAssertEqual(fw.gravity, 360, accuracy: 1e-9)
        XCTAssertTrue(fw.particles.allSatisfy { $0.shape == .spark })
        let cf = rollBurst(emission: .confetti, from: [(x: 0.0, y: 0.0)],
                           colors: [1], now: 0)
        XCTAssertEqual(cf.gravity, 900, accuracy: 1e-9)
        XCTAssertTrue(cf.particles.allSatisfy { $0.shape == .paper })
        // confetti pops UP-and-out → initial vy is negative (the popper cone).
        XCTAssertTrue(cf.particles.allSatisfy { $0.vy < 0 })
    }

    func testIntensityScalesLaunchSpeed() {
        // Intensity scales velocity (reach), not just count. Every .wild spark
        // launches at 120…260 × 2.5 = 300…650 pt/s, so ALL of them clear the
        // .normal ceiling of 260 — deterministic (no flake) and only possible
        // if `intensity` multiplies the velocity (guards the `* scale` factor).
        let wild = rollBurst(emission: .fireworks, from: [(x: 0.0, y: 0.0)],
                             colors: [1], intensity: .wild, now: 0, count: 30)
        XCTAssertTrue(wild.particles.allSatisfy {
            ($0.vx * $0.vx + $0.vy * $0.vy).squareRoot() > 260
        })
    }

    func testRollBurstColorsAndEmptyFallback() {
        // Every particle picks from the supplied palette.
        let b = rollBurst(emission: .fireworks, from: [(x: 0.0, y: 0.0)],
                          colors: [0xAB, 0xCD], now: 0)
        XCTAssertTrue(b.particles.allSatisfy { $0.color == 0xAB || $0.color == 0xCD })
        // Empty colors → white fallback (never an out-of-range pick).
        let w = rollBurst(emission: .confetti, from: [(x: 0.0, y: 0.0)],
                          colors: [], now: 0)
        XCTAssertTrue(w.particles.allSatisfy { $0.color == 0xFFFFFF })
        // Empty emitters → an inert (no-particle) burst that resolves to [].
        let empty = rollBurst(emission: .fireworks, from: [], colors: [1], now: 0)
        XCTAssertTrue(empty.particles.isEmpty)
        XCTAssertTrue(resolveParticles(empty, now: 0.5).isEmpty)
    }

    func testRollBurstSpawnsAtEmitter() {
        let b = rollBurst(emission: .fireworks, from: [(x: 7.0, y: 9.0)],
                          colors: [1], now: 0, count: 5)
        XCTAssertTrue(b.particles.allSatisfy { $0.x0 == 7 && $0.y0 == 9 })
        // CGPoint overload routes to the same core.
        let c = rollBurst(emission: .confetti, from: [CGPoint(x: 3, y: 4)],
                          colors: [1], now: 0, count: 2)
        XCTAssertTrue(c.particles.allSatisfy { $0.x0 == 3 && $0.y0 == 4 })
    }

    // MARK: - AppKit draw (smoke — real visual proof is the prism live capture)

    func testDrawParticlesRunsIntoAContext() {
        let img = NSImage(size: NSSize(width: 60, height: 60))
        img.lockFocus()
        let fw = rollBurst(emission: .fireworks, from: [(x: 30.0, y: 30.0)],
                           colors: [0xFF0000], now: 0, duration: 1)
        let cf = rollBurst(emission: .confetti, from: [(x: 30.0, y: 55.0)],
                           colors: [0x00FF00], now: 0, duration: 1)
        drawParticles(fw, now: 0.3)
        drawParticles(cf, now: 0.3)
        drawParticles(fw, now: 5)   // settled → draws nothing, must not crash
        img.unlockFocus()
    }
}
