// Icons.swift — ThemeKit's SVG icon foundation (sill v1.8.0, docs/ROADMAP.md #1).
//
// Every icon in the family is now an SVG: Phosphor (MIT) is the workhorse set,
// Simple Icons (CC0) supplies brand / app logos. Both are vendored AS-USED under
// `Resources/` (viewBox-256 `currentColor` masks for Phosphor, viewBox-24 black
// masks for Simple Icons) — see each folder's LICENSE.
//
// WHY SwiftDraw (not NSImage's own SVG / an asset catalog): on macOS 13 the
// built-in SVG path is the PRIVATE `_NSSVGImageRep` and returns nil; asset
// catalogs need Xcode/actool, which the maintainer's CommandLineTools-only box
// lacks. SwiftDraw is pure-Swift CoreGraphics — the one renderer that both
// resolves AND compiles here. It is a ThemeKit-ONLY dependency.
//
// RENDERING CONTRACT — one tint path for SF *and* SVG. `tintedBitmap` is the
// lower half of the old per-widget `tintedSymbol`, factored out: it rasterizes a
// vector base (an SF symbol OR a SwiftDraw `NSImage`) into a DEVICE-PIXEL bitmap
// and template-tints it with `sourceIn`. Setting a layer's `contentsScale` alone
// leaves a vector's 1× CGImage blurry on Retina — the bitmap must be sized in
// device pixels (`pt × backingScale`). A loaded SVG carries no fixed resolution,
// so we draw the WHOLE image (`from: .zero`) into the target-point rect and the
// bitmap's scale decides the crispness.

#if canImport(AppKit)
import AppKit
import SwiftDraw

// MARK: - Phosphor weights

/// The six Phosphor weights. The `regular` file has no suffix
/// (`heart.svg`); every other weight is suffixed (`heart-bold.svg`), matching
/// phosphor-icons/core's `assets/<weight>/` layout that we vendor verbatim.
public enum PhosphorWeight: String, Sendable, CaseIterable {
    case thin, light, regular, bold, fill, duotone

    /// The filename suffix for this weight (`""` for `regular`, `"-bold"` …).
    public var fileSuffix: String { self == .regular ? "" : "-\(rawValue)" }
}

// MARK: - Loaders (Bundle.module → SwiftDraw)

/// A Phosphor icon as a TEMPLATE `NSImage` (a black `currentColor` mask) sized to
/// `pt × pt`. Template = the widget tints it to the role colour via the shared
/// `tintedBitmap` path; the image stays vector, so it rasterizes crisply at any
/// backing scale. Returns nil if the name/weight isn't vendored. @MainActor
/// because `NSImage` / the cache are main-isolated.
///
/// `pt` sets only the returned image's INTRINSIC size; a host widget
/// (`leadingImage` / `ButtonItem.image`) always re-fits to its own icon metric,
/// so the final render size is the widget's, not `pt`. Pass any convenient value
/// (e.g. the target widget's icon point size).
@MainActor
public func phosphorImage(_ name: String, pt: CGFloat,
                          weight: PhosphorWeight = .regular) -> NSImage? {
    let file = name + weight.fileSuffix
    return IconStore.templateImage(key: "ph:\(weight.rawValue)/\(file)", pt: pt) {
        Bundle.module.url(forResource: file, withExtension: "svg",
                          subdirectory: "Phosphor/\(weight.rawValue)")
    }
}

/// A Simple Icons brand/app logo as a TEMPLATE `NSImage` sized to `pt × pt`.
/// Simple Icons are single-path monochrome glyphs, so the template tint adopts
/// the role colour (a toolbar's foreground). For a FULL-COLOUR app icon, build an
/// `NSImage` from the real `.app` and pass it as `leadingImage` / `ButtonItem.image`
/// with `isTemplate == false` — it's then drawn raw. @MainActor.
@MainActor
public func simpleIconImage(_ name: String, pt: CGFloat) -> NSImage? {
    IconStore.templateImage(key: "si:\(name)", pt: pt) {
        Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "SimpleIcons")
    }
}

// MARK: - Device-pixel template tint (shared by ThemedButton / ThemedFAB / …)

/// Rasterize a vector `base` into a `size`-point rect inside a `size × scale`
/// DEVICE-PIXEL bitmap and, when `color` is non-nil, fill its opaque pixels with
/// it (`sourceIn` template tint). `color == nil` keeps the source colours (a
/// multi-colour app icon / favicon drawn raw). The whole image is drawn
/// (`from: .zero`) so a 256-viewBox SVG and a point-sized SF symbol both scale to
/// fill `size`. Returns the device image + its POINT size (for layout). Lives
/// here so SF and SVG share ONE tint recipe.
@MainActor
func tintedBitmap(base: NSImage, size: CGSize, color: NSColor?,
                  scale: CGFloat) -> (CGImage, CGSize)? {
    let pxW = max(1, Int((size.width  * scale).rounded()))
    let pxH = max(1, Int((size.height * scale).rounded()))
    guard size.width > 0, size.height > 0,
          let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Crisp for vectors regardless; sharper when `base` is a RASTER app icon /
    // favicon downscaled into a small slot (the `leadingImage` path accepts those).
    NSGraphicsContext.current?.imageInterpolation = .high
    let r = NSRect(origin: .zero, size: size)
    base.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
    if let color {
        color.set()
        r.fill(using: .sourceIn)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let cg = rep.cgImage else { return nil }
    return (cg, size)
}

/// Render an arbitrary pre-resolved `image` (a Phosphor/Simple-Icons template, an
/// app icon, a favicon, an emoji bitmap, …) into the icon slot: fit it to a
/// `pt × pt` box preserving aspect, template-tint to `tint` when `isTemplate`,
/// else draw raw. Shared by the widgets' `leadingImage` / `ButtonItem.image` paths.
@MainActor
func renderedIcon(_ image: NSImage, pt: CGFloat, tint: NSColor,
                  scale: CGFloat) -> (CGImage, CGSize)? {
    let nat = image.size
    guard nat.width > 0, nat.height > 0 else { return nil }
    let f = pt / max(nat.width, nat.height)
    let size = CGSize(width: nat.width * f, height: nat.height * f)
    return tintedBitmap(base: image, size: size,
                        color: image.isTemplate ? tint : nil, scale: scale)
}

// MARK: - Cache

/// Caches the parsed `SVG` (Sendable DOM) per resource so a repaint never
/// re-reads/re-parses the file; each call wraps it in a fresh vector `NSImage`
/// (cheap) sized to `pt`, so callers never alias one image's `size`. A FAILED
/// lookup (missing / unparseable resource) is cached too (the value is `SVG?`),
/// so a typo'd or unsupported name is attempted at most once per process — never
/// re-hit on every repaint.
@MainActor
private enum IconStore {
    static var svgs: [String: SVG?] = [:]

    static func templateImage(key: String, pt: CGFloat,
                              url: () -> URL?) -> NSImage? {
        let svg: SVG
        if let cached = svgs[key] {          // present (success OR cached failure)
            guard let hit = cached else { return nil }
            svg = hit
        } else {
            let parsed = url().flatMap { SVG(fileURL: $0) }
            svgs[key] = parsed               // cache the SVG, or nil on failure
            guard let hit = parsed else { return nil }
            svg = hit
        }
        let image = NSImage(svg)            // vector, resolution-independent
        image.size = CGSize(width: pt, height: pt)
        image.isTemplate = true
        return image
    }
}
#endif
