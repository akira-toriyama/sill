// Phosphor glyph-vendor tests — the F1-seam glyphs vendored for facet's SwiftUI
// tree (facet spec 2026-07-06-facet-swiftui-tree-seam-design §4.5 / §5 sill-B)
// must actually resolve. `phosphorImage` returns non-nil ONLY when the SVG is
// bundled AND SwiftDraw parses it, so a non-nil result is the real end-to-end
// proof: resource present + parseable + rasterizable. Runs in CI (no Xcode
// locally → these first compile + run there).

import XCTest
import AppKit
@testable import ThemeKit

@MainActor
final class PhosphorGlyphVendorTests: XCTestCase {

    /// GAP-A + spiral — vendored verbatim from upstream Phosphor (MIT).
    private let upstream = [
        "spiral", "archive", "push-pin", "push-pin-slash", "tray",
        "arrows-left-right",
    ]

    /// Custom tiling-layout badges authored in Phosphor's viewBox-256 /
    /// currentColor style (no upstream source — see Resources/README.md).
    private let customTiling = [
        "bsp", "master-left", "master-right", "master-top",
        "master-bottom", "master-center",
    ]

    func testVendoredGlyphsResolve() {
        for slug in upstream + customTiling {
            let img = phosphorImage(slug, pt: 20)
            XCTAssertNotNil(
                img,
                "glyph '\(slug)' did not resolve — missing from bundle or unparseable by SwiftDraw")
            XCTAssertGreaterThan(
                img?.size.width ?? 0, 0, "glyph '\(slug)' rasterized to zero width")
        }
    }

    /// Control (true-positive): a long-vendored glyph resolves — guards against a
    /// false-green harness where the bundle path is wrong and everything is nil.
    func testControlGlyphResolves() {
        XCTAssertNotNil(phosphorImage("stack", pt: 20))
    }

    /// Control (true-negative): an absent slug is nil — guards against a
    /// false-green where `phosphorImage` never returns nil.
    func testAbsentGlyphIsNil() {
        XCTAssertNil(phosphorImage("facet-no-such-vendored-slug", pt: 20))
    }
}
