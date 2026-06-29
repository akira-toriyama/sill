import Foundation
import Markdown

/// Flatten a block's inline children into one AttributedString carrying
/// semantic intents (no colors). Colors/fonts are applied by MarkdownKitUI.
func inlineAttributed(_ container: Markup) -> AttributedString {
    var out = AttributedString()
    for child in container.children { out.append(inlineRun(child, intents: [], link: nil)) }
    return out
}

private func inlineRun(_ markup: Markup,
                       intents: InlinePresentationIntent,
                       link: URL?) -> AttributedString {
    switch markup {
    case let text as Markdown.Text:
        return styledLeaf(text.string, intents: intents, link: link)
    case is SoftBreak:
        return styledLeaf(" ", intents: intents, link: link)
    case is LineBreak:
        return styledLeaf("\n", intents: intents, link: link)
    case let code as InlineCode:
        return styledLeaf(code.code, intents: intents.union(.code), link: link)
    case let html as InlineHTML:
        return styledLeaf(html.rawHTML, intents: intents, link: link)
    case let img as Markdown.Image:
        // inline image alt as plain text (v1 stub; block images handled in parser)
        return styledLeaf(img.plainText.isEmpty ? "image" : img.plainText, intents: intents, link: link)
    case let strong as Strong:
        return recurse(strong, intents: intents.union(.stronglyEmphasized), link: link)
    case let em as Emphasis:
        return recurse(em, intents: intents.union(.emphasized), link: link)
    case let strike as Strikethrough:
        return recurse(strike, intents: intents.union(.strikethrough), link: link)
    case let a as Markdown.Link:
        return recurse(a, intents: intents, link: URL(string: a.destination ?? "") ?? link)
    default:
        return recurse(markup, intents: intents, link: link)
    }
}

private func recurse(_ markup: Markup,
                     intents: InlinePresentationIntent,
                     link: URL?) -> AttributedString {
    var out = AttributedString()
    for child in markup.children { out.append(inlineRun(child, intents: intents, link: link)) }
    return out
}

private func styledLeaf(_ s: String,
                        intents: InlinePresentationIntent,
                        link: URL?) -> AttributedString {
    var run = AttributedString(s)
    if !intents.isEmpty { run.inlinePresentationIntent = intents }
    if let link { run.link = link }
    return run
}
