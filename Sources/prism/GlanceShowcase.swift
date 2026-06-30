// prism — glance mock chrome. glance paints a markdown popover (ViewerPanel +
// MarkdownRenderer): a non-activating, borderless rounded HUD panel that floats
// at the cursor and renders the selected text's GFM markdown, scrollable, on a
// fixed dark preset (catppuccin-mocha). This mock rebuilds that scene out of the
// REAL MarkdownKitUI `MarkdownView` (#17f) inside a faux floating HUD panel (the
// MockWindowShell "shell surface" recipe), so it re-themes across every catalog
// theme — a cheap de-risk before glance's real application (prism imports no app
// View; the scene is mirrored by eye). glance pins ONE dark theme in production;
// the bench proves the same chrome composes generically on EVERY theme.
//
// MarkdownKitUI now renders glance's ENTIRE GFM surface with glance's own technique:
// #17f re-architected the renderer onto a selectable NSTextView (AppKit floor-3) — the
// rounded inline-code pill (fillBackgroundRectArray), content-sized NSTextTable tables/
// code-blocks/blockquotes, and native drag-select + ⌘C all match glance. The residual
// glance-side bits are app-essential behaviour (cursor anchoring, cross-app dismiss, the
// Highlightr adapter — prism injects StubSwiftHighlighter to exercise the hook). See
// docs/superpowers/specs/2026-06-30-17f-markdown-nstextview-design.md.

import SwiftUI
import PaletteKit      // ResolvedPalette
import MarkdownKitUI   // MarkdownView, MarkdownStyle, MarkdownHighlighter (the merged glance renderer)
// NOTE: panelStroke, uiScale, sysFont are prism-LOCAL (Specimens.swift / Gallery.swift).

/// A miniature of glance's markdown popover: the REAL `MarkdownView` rendering a
/// representative GFM document inside a faux floating HUD panel, anchored below a
/// faux text "selection" so it reads as a cursor popover (not a flat doc). Stages
/// the full element range MarkdownKitUI covers — h1–h6, bold/italic/strike, inline
/// code, link, image placeholder, raw-HTML passthrough, fenced code (themed mono +
/// the injected-highlighter path), nested blockquote, bullet/ordered/task lists,
/// GFM table with column alignment, and a rule — so the live card proves glance's
/// chrome rebuilds from sill parts on every theme. The card's palette drives `p`,
/// so on an animatable theme the prose re-themes live with the rest of the bench.
struct MockGlancePopover: View {
    let p: ResolvedPalette

    /// A representative GFM document covering every block + inline element glance
    /// renders (broadened past the old bare specimen: now exercises h3–h6, an
    /// image placeholder, raw-HTML passthrough, and both a highlighted swift fence
    /// and a plain themed-mono fence).
    private static let doc = """
    # glance
    ## a markdown popover

    Selected text, rendered: **bold**, _italic_, ~~struck~~, `inline code`, \
    and a [link](https://example.com).

    ```swift
    import Foundation
    // greet the world
    func greet(_ name: String) {
        let msg = "hello, " + name
        print(msg)
    }
    ```

    | Left | Center | Right |
    |:-----|:------:|------:|
    | a    | bb     | ccc   |
    | long left cell | x | 1 |

    ### Heading 3
    #### Heading 4
    ##### Heading 5
    ###### Heading 6

    ![architecture diagram](diagram.png)

    <div class="callout">raw HTML block — passed through as source</div>

    Inline <kbd>⌘C</kbd> HTML stays verbatim too.

    > A blockquote, GitHub left-bar styled.
    > > nested one level deeper

    - bullet one
    - [ ] an open task
    - [x] a done task
        - a nested item

    1. first
    2. second

    ```
    plain fence — no language, plain themed monospaced
    ```

    ---

    Trailing paragraph.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            selectionSource   // the faux selected text the popover explains
            popoverPanel      // the REAL MarkdownView in a floating HUD panel
        }
    }

    /// A couple of faint faux text lines with one `selection`-tinted run — so the
    /// panel below reads as a popover anchored to a cursor selection (glance's UX),
    /// not a free-floating document.
    private var selectionSource: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar(width: 220, opacity: 0.10)
            HStack(spacing: 6) {
                bar(width: 54, opacity: 0.10)
                RoundedRectangle(cornerRadius: 3)              // the "selection"
                    .fill(Color(nsColor: p.selection))
                    .frame(width: 96, height: 10)
                bar(width: 30, opacity: 0.10)
            }
        }
        .padding(.leading, 4)
    }

    private func bar(width: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: p.foreground).opacity(opacity))
            .frame(width: width, height: 10)
    }

    /// The floating HUD panel — the MockWindowShell "shell surface" recipe (theme
    /// `background` fill, rounded 10, a drop shadow, a `panelStroke` outline) so the
    /// card reads as a floating notification panel. It hosts the real `MarkdownView`
    /// at glance's bigger-for-quick-read 16 pt base, padded to echo the body inset.
    /// The panel SIZES TO CONTENT (mirrors glance's auto-size-to-content; glance
    /// scrolls only past its 80..600 clamp — the consumer supplies that `ScrollView`,
    /// here the bench stages the whole doc so every element is verifiable at a
    /// glance). Anchored with a small leading offset so it sits under the selection.
    private var popoverPanel: some View {
        MarkdownView(palette: p,
                     source: Self.doc,
                     style: MarkdownStyle(baseFontSize: 16),
                     highlighter: StubSwiftHighlighter(
                        keyword: Color(nsColor: p.primary),
                        string: Color(nsColor: p.secondary),
                        comment: Color(nsColor: p.muted),
                        base: Color(nsColor: p.foreground)))
            .padding(14)
            .frame(width: 380, alignment: .topLeading)
            .background(Color(nsColor: p.background ?? .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.30), radius: 10, y: 5)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: panelStroke(p)), lineWidth: 1))
            .padding(.leading, 28)
    }
}

/// A tiny bench-only syntax highlighter so prism exercises `MarkdownView`'s
/// `highlighter` HOOK live: glance ships the real Highlightr adapter (app-essential,
/// stays in glance), but without ANY highlighter injected the bench never showed
/// that an injected, themed `AttributedString` flows through `CodeBlockView` and
/// re-themes per card. This proves the SILL side of that seam. It is a naive
/// token recolor keyed off the palette (keyword=primary, string=secondary,
/// comment=muted) — NOT a real language parser, and only for the `swift` fence;
/// every other fence returns nil → plain themed monospaced (also staged).
struct StubSwiftHighlighter: MarkdownHighlighter {
    let keyword: Color
    let string: Color
    let comment: Color
    let base: Color

    private static let keywords: Set<String> = [
        "let", "var", "func", "return", "import", "print", "struct", "enum",
        "if", "else", "for", "in", "while", "guard", "self", "true", "false",
        "nil", "public", "private",
    ]

    func highlight(_ code: String, language: String?) -> AttributedString? {
        guard language == "swift" else { return nil }   // other fences → plain themed mono
        var out = AttributedString()
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, line) in lines.enumerated() {
            if i > 0 { out += AttributedString("\n") }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                var seg = AttributedString(String(line))
                seg.foregroundColor = comment
                out += seg
                continue
            }
            let tokens = line.components(separatedBy: " ")
            for (j, tok) in tokens.enumerated() {
                if j > 0 { out += AttributedString(" ") }
                var seg = AttributedString(tok)
                let bare = tok.trimmingCharacters(in: CharacterSet(charactersIn: "(){}[]:.,;"))
                if Self.keywords.contains(bare) {
                    seg.foregroundColor = keyword
                } else if tok.contains("\"") {
                    seg.foregroundColor = string
                } else {
                    seg.foregroundColor = base
                }
                out += seg
            }
        }
        return out
    }
}
