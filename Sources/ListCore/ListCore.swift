import Foundation

// ListCore — Foundation-only, Sendable, AppKit-free pure logic backing the
// stateful ThemeKit widgets (List → ComboBox/Menu). No type is named `ListCore`
// (module==type collision); the surface is top-level free functions, like Motion.
// CG conveniences, if any, go behind `#if canImport(CoreGraphics)`.

/// Internal build marker so a fresh test target has a symbol to import. Replaced
/// by real surface in later tasks; harmless to keep.
public let listCoreLinked = true
