/// Knobs that tune how raw stroke samples turn into a direction string —
/// wand's `[cast.recognition]` block, lifted as a plain value. Independent of
/// any visual output: purely a recognition-quality axis.
///
/// MECHANISM ONLY — `recognize` consumes `minStrokePx`; the time-based knobs
/// (`maxSegmentMs` / `cancelWindowMs`) are applied by the APP's adapter against
/// ITS clock (this module owns no clock), and `cancelReversals` pairs with
/// `Recognition.reversals`. Range-clamping is the app's job too (sill owns the
/// value, the app's config loader clamps it).
public struct GestureRecognitionSpec: Sendable, Equatable {
    /// Minimum displacement (px) before a new direction is emitted. Smaller =
    /// catches small flicks; bigger = tolerant of jitter.
    public let minStrokePx: Int
    /// Maximum time (ms) a single segment may take. The clock resets on every
    /// turn, so each leg gets the full budget; only a stalled single direction
    /// (an ordinary slow drag) runs past it and the gesture is abandoned.
    /// `0` = no limit.
    public let maxSegmentMs: Int
    /// Scribble-to-cancel: number of 180° direction reversals that abandons the
    /// in-progress stroke. `0` = off.
    public let cancelReversals: Int
    /// Speed gate for the scribble — reversals must land within this window
    /// (ms). `0` = any speed.
    public let cancelWindowMs: Int

    public init(minStrokePx: Int = 16,
                maxSegmentMs: Int = 0,
                cancelReversals: Int = 2,
                cancelWindowMs: Int = 500) {
        self.minStrokePx = minStrokePx
        self.maxSegmentMs = maxSegmentMs
        self.cancelReversals = cancelReversals
        self.cancelWindowMs = cancelWindowMs
    }

    public static let `default` = GestureRecognitionSpec()
}
