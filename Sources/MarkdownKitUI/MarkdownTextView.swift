import SwiftUI
import AppKit
import PaletteKit

/// The floor-3 `NSTextView` host: a single TextKit 1 text view that renders the whole
/// markdown document (built by `MarkdownRenderer`) so selection is continuous and the
/// `InlineCodePillLayoutManager` can round inline code. Content-sized (no scroll of its
/// own — a consumer that needs clamping wraps it in a `ScrollView`), so it drops into a
/// SwiftUI layout like any view. Re-themes by reassigning `palette` (the rendered
/// attributed string is rebuilt in `updateNSView`).
struct MarkdownTextView: NSViewRepresentable {
    var palette: ResolvedPalette
    var source: String
    var style: MarkdownStyle
    var highlighter: MarkdownHighlighter?

    func makeNSView(context: Context) -> NSTextView {
        // Explicit TextKit 1 stack so InlineCodePillLayoutManager's
        // fillBackgroundRectArray override is in effect (NSTextView(frame:) picks
        // TextKit 2 and bypasses it).
        let textStorage = NSTextStorage()
        let layoutManager = InlineCodePillLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = SelectableTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        apply(to: textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        apply(to: textView)
    }

    /// Lay the text out at the proposed width and report the used height so SwiftUI
    /// sizes the view to its content (the consumer supplies the width).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: ceil(used.height))
    }

    @MainActor
    private func apply(to textView: NSTextView) {
        let renderer = MarkdownRenderer(style: .init(palette: palette, markdown: style),
                                        highlighter: highlighter)
        textView.textStorage?.setAttributedString(renderer.render(source))
        (textView.layoutManager as? InlineCodePillLayoutManager)?.cornerRadius = style.pillCornerRadius
    }
}

/// `NSTextView` that copies the selection on ⌘C even with no host Edit menu in the
/// responder chain — so copy works in a non-activating popover (glance) or a
/// menu-less bench (prism), not only inside a full app menu bar.
final class SelectableTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "c",
           selectedRange().length > 0 {
            copy(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
