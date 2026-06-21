// Gesture — the family's shared pure GESTURE-RECOGNITION atom (wand's mouse-
// stroke recogniser, generalised). MECHANISM ONLY — the same D4 line as
// CLIKit: this module turns a stream of timestamped points into a coalesced
// direction string (`[.down, .left] → "DL"`); the APP owns the action table
// (which pattern fires what verb), the CLOCK (`CACurrentMediaTime`), and the
// input plumbing (CGEventTap / Dispatch). `Gesture` owns NO vocabulary and NO
// timing — only the geometry of "which way did the cursor go".
//
// 4-WAY ONLY (`L U R D`) — wand parity; diagonal / scroll-axis (8-way) is a
// later extension. Pure, Sendable, AppKit-free — a pure atom alongside
// Palette / CLIKit / Motion, shipped under the one sill tag. Coordinates are
// plain `Double` so the core links ZERO CoreGraphics; a
// `#if canImport(CoreGraphics)` convenience layer on `Sample` adds `CGPoint` /
// `TimeInterval` overloads for apps already working in CG (the Trail.swift /
// Splatter.swift gated-overload idiom).

import Foundation

public enum Recognition {

    /// Dominant-axis quantisation: walk `samples`; when `|dx|` or `|dy|` since
    /// the last anchor exceeds `minStrokePx`, emit a `Direction` on the
    /// dominant axis and reset the anchor. Consecutive duplicates are coalesced
    /// so a long single stroke is ONE direction, not many — keeps the mental
    /// model "draw a path of arrow keys" instead of something fancier.
    ///
    /// `Y grows UP`: callers sign-flip the platform's Y-down event coordinate
    /// at sample creation, so a larger `y` means the cursor moved up
    /// (`dy >= 0 ⇒ .up`). The anchor resets on every threshold-exceeding
    /// sample — including a coalesced duplicate — so spacing is measured from
    /// the last turn, not the stroke start. Returns `[]` for fewer than two
    /// samples or `minStrokePx <= 0`.
    public static func recognize(samples: [Sample], minStrokePx: Int) -> [Direction] {
        guard samples.count >= 2, minStrokePx > 0 else { return [] }
        var out: [Direction] = []
        var anchorX = samples[0].x
        var anchorY = samples[0].y
        let threshold = Double(minStrokePx)
        for s in samples.dropFirst() {
            let dx = s.x - anchorX
            let dy = s.y - anchorY
            let absX = abs(dx), absY = abs(dy)
            guard max(absX, absY) >= threshold else { continue }
            let dir: Direction
            if absX >= absY {
                dir = dx >= 0 ? .right : .left
            } else {
                dir = dy >= 0 ? .up : .down
            }
            if out.last != dir { out.append(dir) }
            anchorX = s.x
            anchorY = s.y
        }
        return out
    }

    /// Number of 180° direction reversals (`L↔R`, `U↔D`) in a coalesced
    /// pattern string. Counts adjacent `LURD` pairs whose axes match and signs
    /// oppose. Drives the scribble-to-cancel detector; pure so it unit-tests
    /// without an input stack.
    public static func reversals(_ pattern: String) -> Int {
        let c = Array(pattern)
        guard c.count > 1 else { return 0 }
        var n = 0
        for i in 1..<c.count where isOpposite(c[i - 1], c[i]) { n += 1 }
        return n
    }

    /// Whether two `LURD` characters denote opposite directions.
    public static func isOpposite(_ a: Character, _ b: Character) -> Bool {
        (a == "L" && b == "R") || (a == "R" && b == "L")
            || (a == "U" && b == "D") || (a == "D" && b == "U")
    }

    /// A human-readable issue string if `pattern` is something the recogniser
    /// can NEVER produce — otherwise `nil`. Two failure modes: a character
    /// outside the `L U R D` alphabet, and consecutive duplicate directions
    /// (the recogniser coalesces same-direction segments, so `DRR` would always
    /// read as `DR` and the rule could never fire). Apps call this at
    /// config-load to drop a bad rule loudly instead of letting it load and
    /// silently no-op at runtime.
    public static func patternIssue(_ pattern: String) -> String? {
        let chars = Array(pattern)
        guard !chars.isEmpty else { return "empty pattern" }
        let valid: Set<Character> = ["L", "U", "R", "D"]
        for (i, c) in chars.enumerated() {
            if !valid.contains(c) {
                return "invalid character '\(c)' — alphabet is L U R D"
            }
            if i > 0 && chars[i] == chars[i - 1] {
                return "consecutive duplicate direction '\(c)\(c)' — "
                     + "the recogniser coalesces same-direction segments, "
                     + "so this pattern can never be drawn"
            }
        }
        return nil
    }
}
