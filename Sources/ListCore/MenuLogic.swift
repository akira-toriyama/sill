import Foundation

/// The pure intent a menu derives from a key code. AppKit-side conditionals
/// (does the highlighted row have a submenu? is there a parent level?) and the
/// side effects (open/close/dismiss/activate) stay in `ThemedMenu.handleKeyDown`.
public enum MenuKeyIntent: Sendable, Equatable {
    case moveDown, moveUp, openSubmenu, closeLevel, activate, escapeLevel, dismissTab, passThrough
}

/// Map a macOS virtual key code to a menu intent (mirrors the switch in
/// `ThemedMenu.handleKeyDown`). Pure / Foundation-only.
public func menuKeyIntent(keyCode: UInt16) -> MenuKeyIntent {
    switch keyCode {
    case 125: return .moveDown      // ↓
    case 126: return .moveUp        // ↑
    case 124: return .openSubmenu   // →
    case 123: return .closeLevel    // ←
    case 36, 76, 49: return .activate   // ⏎ / keypad ⏎ / Space
    case 53: return .escapeLevel    // Esc
    case 48: return .dismissTab     // Tab
    default: return .passThrough
    }
}
