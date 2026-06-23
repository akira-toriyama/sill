import Foundation

/// One roving-highlight step over the selectable indices, mirroring the core math
/// of `ThemedList.moveHighlight`: from the current position move by `delta`,
/// wrapping (`((p+delta)%n+n)%n`) or clamping (`min(max(p+delta,0),n-1)`); an empty
/// list → nil; no current → first (delta>0) or last (delta<0). Pure / Foundation-only.
public func nextHighlight(current: Int?, delta: Int,
                          selectableIndices: [Int], wraps: Bool) -> Int? {
    guard !selectableIndices.isEmpty else { return nil }
    if let cur = current, let pos = selectableIndices.firstIndex(of: cur) {
        let n = selectableIndices.count
        let np = wraps ? ((pos + delta) % n + n) % n
                       : min(max(pos + delta, 0), n - 1)
        return selectableIndices[np]
    } else {
        return delta > 0 ? selectableIndices.first! : selectableIndices.last!
    }
}
