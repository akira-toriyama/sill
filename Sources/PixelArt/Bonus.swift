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
