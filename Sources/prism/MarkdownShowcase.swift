// prism — MarkdownView showcase: renders the real MarkdownKitUI renderer across
// every theme so the maintainer can verify colour/spacing/element coverage live.

import SwiftUI
import PaletteKit
import MarkdownKitUI

struct MockMarkdown: View {
    let p: ResolvedPalette

    private static let fixture = """
    # Heading 1
    ## Heading 2

    Body with **bold**, _italic_, ~~struck~~, `inline code`, and a [link](https://example.com).

    > A blockquote
    > > nested deeper

    - bullet one
    - [ ] todo
    - [x] done
        - nested item

    1. first
    2. second

    ```swift
    let greeting = "hello"
    print(greeting)
    ```

    | Left | Center | Right |
    |:-----|:------:|------:|
    | a    | b      | c     |

    ---

    Trailing paragraph.
    """

    var body: some View {
        MarkdownView(palette: p, source: Self.fixture)
            .frame(maxWidth: 360, alignment: .leading)
    }
}
