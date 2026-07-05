// ThemeKitUI — the list row-model vocabulary (`Badge` / `BadgeRole` / `ListTint` /
// `TrailingAccessory`), shared by `ListItem<ID>`, `ThemedListView`, `ThemedMenu`
// and `ThemedComboBox`. Rescued byte-identical from the retired AppKit
// `ThemeKit.ThemedList` (#17b M5) — the SwiftUI list is now the only consumer, so
// the vocabulary lives beside it. Role-based colour intent only (resolved to an
// `NSColor` at DRAW time so it re-themes on a `palette` change); glyphs are
// PRE-RESOLVED `NSImage`s the host passes (the kit parses no icon spec).

import AppKit
import Palette

/// The role a `Badge` paints in — resolved to a palette colour at draw time.
public enum BadgeRole: Equatable, Sendable { case neutral, primary, secondary, error }

/// A leading accent intent for a whole row — a 3pt bar in the resolved colour.
/// Role-based (re-themes on a palette switch); `.custom` carries a pure
/// `HexColor` (Sendable) for an app-specific tint the roles can't express.
public enum ListTint: Equatable, Sendable {
    case none, primary, secondary, error
    case custom(HexColor)
}

/// The single trailing affordance on a row (right of any badges). One-of — a row
/// has at most one. All glyphs are PRE-RESOLVED by the host (`.custom`) or drawn
/// from a fixed Phosphor slug the kit owns (`.chevron`).
public enum TrailingAccessory: Equatable {
    case none
    case chevron               // a disclosure `caret-right` (Phosphor), `tertiary`
    case shortcut(String)      // a bordered key-hint lozenge ("⌘1"), `muted`
    case custom(NSImage)       // a pre-resolved trailing glyph
}

/// A small role-typed pill in a row's trailing area. A plain (non-Sendable)
/// value — it may carry a pre-resolved `NSImage` symbol (NSImage isn't Sendable);
/// it lives main-actor-side only. The kit parses no SF name — the host passes the
/// image.
public struct Badge: Equatable {
    public var text: String
    public var symbol: NSImage?
    public var role: BadgeRole
    public init(_ text: String, symbol: NSImage? = nil, role: BadgeRole = .neutral) {
        self.text = text; self.symbol = symbol; self.role = role
    }
}
