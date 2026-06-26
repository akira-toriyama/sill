// ThemeKitUI — the SwiftUI-native materialization of a pure Trail `[PathStep]`
// (#17h). The SwiftUI analog of the Effects AppKit path builder: turn the pure
// move/line/quadCurve description (`roundedCornerPath` etc.) into a SwiftUI
// `Path` to stroke or fill in a `Canvas`. Reused by the PathPet guide trail
// (PathPetView) and the corridor walls (ChompCorridorView).
import SwiftUI
import Effects   // PathStep

/// Build a SwiftUI `Path` from the pure Trail `[PathStep]` (move/line/quadCurve).
/// Coords are in the caller's space (already canvas-space when the caller flips
/// the polyline up-front). `.quadCurve` maps to `addQuadCurve` (one control
/// point), the same quadratic the pure description carries.
func swiftUIPath(from steps: [PathStep]) -> Path {
    var p = Path()
    for s in steps {
        switch s {
        case let .move(x, y): p.move(to: CGPoint(x: x, y: y))
        case let .line(x, y): p.addLine(to: CGPoint(x: x, y: y))
        case let .quadCurve(x, y, cx, cy):
            p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
        }
    }
    return p
}
