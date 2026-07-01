import Foundation

/// The pure intent a menu derives from a key code. AppKit-side conditionals
/// (does the highlighted row have a submenu? is there a parent level?) and the
/// side effects (open/close/dismiss/activate) stay in `ThemedMenu.handleKeyDown`.
public enum MenuKeyIntent: Sendable, Equatable {
    case moveDown, moveUp, openSubmenu, closeLevel, activate, escapeLevel, dismissTab, passThrough
}

/// How the menu LEVEL being keyed is laid out. A `.vertical` level (a drop-down /
/// submenu list) navigates ↑↓ and opens a child with → (beside it); a `.horizontal`
/// level (a toolbar / menu-bar root) navigates ←→ along the row and opens a child
/// with ↓ (below it). Orientation is per-LEVEL — a horizontal root's vertical child
/// still keys vertically — so the caller passes the active leaf's own orientation.
public enum MenuOrientation: Sendable, Equatable { case vertical, horizontal }

/// Map a macOS virtual key code to a menu intent (mirrors the switch in
/// `ThemedMenu.handleKeyDown`). Pure / Foundation-only. Orientation defaults to
/// `.vertical` (the historical behavior — an unchanged caller keeps its meaning).
///
/// The intent VOCABULARY is orientation-neutral (`moveDown` = "the next item",
/// `openSubmenu` = "open the child in the presentation's natural direction"); only
/// the key→intent MAPPING flips, so `handleKeyDown` needs no per-axis branching
/// beyond calling the leaf's own move/open helpers. `closeLevel` (←) is vertical-only
/// — on a horizontal bar ← is "previous item", and the top-level bar has no parent
/// level to close up to.
public func menuKeyIntent(keyCode: UInt16, orientation: MenuOrientation = .vertical) -> MenuKeyIntent {
    switch orientation {
    case .vertical:
        switch keyCode {
        case 125: return .moveDown      // ↓ next
        case 126: return .moveUp        // ↑ prev
        case 124: return .openSubmenu   // → open child (beside the row)
        case 123: return .closeLevel    // ← close one level
        case 36, 76, 49: return .activate   // ⏎ / keypad ⏎ / Space
        case 53: return .escapeLevel    // Esc
        case 48: return .dismissTab     // Tab
        default: return .passThrough
        }
    case .horizontal:
        switch keyCode {
        case 124: return .moveDown      // → next (along the bar)
        case 123: return .moveUp        // ← prev (along the bar)
        case 125: return .openSubmenu   // ↓ open child (below the item)
        case 36, 76, 49: return .activate   // ⏎ / keypad ⏎ / Space
        case 53: return .escapeLevel    // Esc
        case 48: return .dismissTab     // Tab
        default: return .passThrough    // ↑ (126) has no meaning on a top bar → host/IME safe
        }
    }
}
