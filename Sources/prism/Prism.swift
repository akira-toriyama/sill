// prism — the sill theme PREVIEW app.
//
// The one executable in sill, and the one place with a `config.toml`.
// It renders every catalog theme: all resolved roles as swatches, a font
// specimen, the effect flash palette, the real ThemeKit widgets, and one
// per-app MOCK chrome tab (a fake facet tree / wand tome / perch pill /
// halo ring / glance markdown) drawn ENTIRELY inside prism — it never imports
// an app's View layer, so the preview can't drift from the apps and the apps
// never depend on prism.
//
// Run it:  swift run prism      (reads ./prism.toml if present)
//
// An AppKit bootstrap (not the SwiftUI `App` lifecycle) so a terminal
// `swift run` reliably shows + activates a window without an .app bundle.

import AppKit
import SwiftUI

@main
enum Prism {
    static func main() {
        let config = PrismConfig.load()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        // Window size — default 1120×820 (×uiScale); `PRISM_WINDOW_W` / `PRISM_WINDOW_H`
        // override it (a screenshot seam so a tall capture can frame every card at once,
        // matching prism's other PRISM_* env knobs).
        let env = ProcessInfo.processInfo.environment
        let winW = env["PRISM_WINDOW_W"].flatMap(Double.init).map { CGFloat($0) } ?? 1120 * uiScale
        let winH = env["PRISM_WINDOW_H"].flatMap(Double.init).map { CGFloat($0) } ?? 820 * uiScale
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "prism — sill theme preview"
        window.center()
        window.contentView = NSHostingView(rootView: Gallery(config: config))
        window.makeKeyAndOrderFront(nil)

        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

// MARK: - Config (prism-local minimal TOML reader)

/// prism's tiny config. NOT a general TOML parser — just `key = value`
/// lines (so the library modules stay parser-free). Looks for
/// `$PRISM_CONFIG` then `./prism.toml`; missing file ⇒ defaults.
struct PrismConfig {
    /// `"all"` = the full gallery, or a single canonical theme name.
    var theme: String = "all"
    /// Specimen text scale.
    var fontScale: CGFloat = 1.0
    /// Show the effect flash palette strip for animatable themes.
    var showEffects: Bool = true
    /// Which tab opens (a `KitFamily` raw value, case-insensitive; a Kit family
    /// like `icons`/`action`, or an app tab like `facet`/`halo`). Lets a
    /// screenshot target a tab deterministically instead of clicking. Default =
    /// `palette` (the foundations).
    var family: String = "palette"

    static func load() -> PrismConfig {
        var c = PrismConfig()
        let path = ProcessInfo.processInfo.environment["PRISM_CONFIG"]
            ?? FileManager.default.currentDirectoryPath + "/prism.toml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return c }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = Substring(rawLine)
            if let hash = line.firstIndex(of: "#") { line = line[..<hash] }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            switch key {
            case "theme":        if !val.isEmpty { c.theme = val.lowercased() }
            case "font-scale":   if let d = Double(val) { c.fontScale = CGFloat(d) }
            case "show-effects": c.showEffects = (val.lowercased() == "true")
            case "family":       if !val.isEmpty { c.family = val.lowercased() }
            default: break
            }
        }
        return c
    }
}
