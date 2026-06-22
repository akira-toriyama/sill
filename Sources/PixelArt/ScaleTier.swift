/// A generic size knob for the arcade decals: small / medium / large → a
/// uniform multiplier the draw side applies to every dimension (cell size,
/// pellet radius, face diameter, wall offset, follow-lag). Pure + `Sendable`.
///
/// The chomp look reads at a few discrete sizes rather than a continuous scale,
/// so this is an enum, not a free `Double` (the spec's `2 / 3 / 4.5` ladder).
public enum ScaleTier: Sendable, Hashable, CaseIterable {
    case s, m, l

    /// `2× / 3× / 4.5×` — the canonical sprite size steps.
    public var multiplier: Double {
        switch self {
        case .s: return 2
        case .m: return 3
        case .l: return 4.5
        }
    }
}
