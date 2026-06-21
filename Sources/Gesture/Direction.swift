/// `L U R D` is single-letter on purpose: grep-friendly in logs and easy to
/// type in TOML. 4-way only — diagonal / scroll-axis directions are not
/// recognised yet (wand parity; 8-way is a later extension).
public enum Direction: Character, Sendable, Hashable, CaseIterable {
    case left  = "L"
    case up    = "U"
    case right = "R"
    case down  = "D"
}

extension Array where Element == Direction {
    /// The coalesced pattern string (`[.down, .left] → "DL"`) — the key a rule
    /// table matches against.
    public var patternString: String {
        String(map { $0.rawValue })
    }
}

extension Direction {
    /// Arrow glyph for the direction — diagnostic / HUD use.
    public var arrow: String {
        switch self {
        case .left:  return "←"
        case .up:    return "↑"
        case .right: return "→"
        case .down:  return "↓"
        }
    }
}
