// ThemeKitUI — pixel-sprite rasterization for the SwiftUI-native effect views
// (#17h). A PixelSprite becomes a 1px/cell CGImage shown with
// `.interpolation(.none)` (nearest-neighbor) so cells stay crisp at any scale
// AND under rotation — the SwiftUI replacement for the AppKit `shouldAntialias
// = false` blitter (which is now gone from this layer).
import SwiftUI
import CoreGraphics
import PixelArt

/// Rasterize `sprite` to a `width × height`-PIXEL image (one device pixel per
/// cell). `color` overrides every filled cell; nil honours each cell's own
/// `0xRRGGBB`. Empty cells are transparent.
func pixelCGImage(_ sprite: PixelSprite, color: UInt32?) -> CGImage? {
    let w = sprite.width, h = sprite.height
    guard w > 0, h > 0 else { return nil }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setShouldAntialias(false)
    for c in sprite.cells() {
        let rgb = color ?? c.color
        let r = CGFloat((rgb >> 16) & 0xFF) / 255, g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        // CGContext origin is bottom-left; sprite row 0 is the TOP → flip row.
        ctx.fill(CGRect(x: c.col, y: h - 1 - c.row, width: 1, height: 1))
    }
    return ctx.makeImage()
}

func pixelImage(_ sprite: PixelSprite, color: UInt32? = nil) -> Image {
    guard let cg = pixelCGImage(sprite, color: color) else { return Image(size: .zero) { _ in } }
    return Image(decorative: cg, scale: 1).interpolation(.none)
}

func drawPixelSprite(in ctx: inout GraphicsContext, _ sprite: PixelSprite,
                     cell: CGFloat, at origin: CGPoint, rotation: CGFloat, color: UInt32?) {
    let w = CGFloat(sprite.width) * cell, h = CGFloat(sprite.height) * cell
    guard w > 0, h > 0 else { return }
    let resolved = ctx.resolve(pixelImage(sprite, color: color).resizable())
    ctx.drawLayer { layer in
        layer.translateBy(x: origin.x, y: origin.y)
        layer.rotate(by: .radians(Double(rotation)))
        layer.draw(resolved, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }
}
