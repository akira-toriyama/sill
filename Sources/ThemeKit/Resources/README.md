# ThemeKit vendored icons — a CURATED SUBSET (not the whole catalog)

These folders hold only the icons sill **actually uses so far**, vendored
as-needed. They are a tiny slice of two much larger open sets — **don't assume
"this is all there is."** When you need a glyph that isn't here, it almost
certainly exists upstream: grab it (one command) and drop it in.

> At dev time you don't even have to remember this: `phosphorImage(…)` /
> `simpleIconImage(…)` print a one-line "not vendored — add it" hint (DEBUG)
> the first time you ask for a name that isn't in these folders.

## The full catalogs

| set | what | full size | vendored here | license | browse / source |
|---|---|---|---|---|---|
| **Phosphor** | UI glyphs | **1,512 icons × 6 weights = 9,072** | see `Phosphor/` | MIT | <https://phosphoricons.com> · <https://github.com/phosphor-icons/core> |
| **Simple Icons** | brand / app logos | **3,445** | see `SimpleIcons/` | CC0 | <https://simpleicons.org> · <https://github.com/simple-icons/simple-icons> |

(We vendor as-used on purpose: the full sets are ~12.5k files / ~6 MB and would
bloat git + every `swift build`'s resource copy. Adding one is trivial.)

## Add a Phosphor glyph

1. Find the exact slug on <https://phosphoricons.com> (e.g. `bookmark-simple`).
2. Fetch the weight(s) you need into `Phosphor/<weight>/`. **`regular` has NO
   suffix; every other weight is suffixed** (`-bold`, `-fill`, `-duotone`,
   `-light`, `-thin`), matching upstream's `assets/<weight>/` layout:

   ```sh
   cd Sources/ThemeKit/Resources/Phosphor
   B=https://raw.githubusercontent.com/phosphor-icons/core/main/assets
   curl -fsSL "$B/regular/bookmark-simple.svg"        -o regular/bookmark-simple.svg
   curl -fsSL "$B/bold/bookmark-simple-bold.svg"      -o bold/bookmark-simple-bold.svg
   ```
3. Use it: `phosphorImage("bookmark-simple", pt: 20)` /
   `phosphorImage("bookmark-simple", pt: 20, weight: .bold)`. No code change —
   the loader resolves it from `Bundle.module` by name. (viewBox-256
   `fill="currentColor"` masks; they tint to the role colour automatically.)

## Add a Simple Icons logo

1. Find the slug on <https://simpleicons.org> (the file name, e.g. `slack`).
2. `curl -fsSL https://raw.githubusercontent.com/simple-icons/simple-icons/master/icons/slack.svg -o SimpleIcons/slack.svg`
3. Use it: `simpleIconImage("slack", pt: 18)`. (Single-path monochrome →
   tinted to the role colour; for a full-colour app icon build an `NSImage`
   from the real `.app` and pass it as `leadingImage` / `ButtonItem.image`.)

## License hygiene

`Phosphor/LICENSE` (MIT) and `SimpleIcons/LICENSE.md` (CC0) ship in the bundle.
MIT requires the notice be kept — leave the LICENSE files in place when you add
icons. No attribution UI is required for either set.
