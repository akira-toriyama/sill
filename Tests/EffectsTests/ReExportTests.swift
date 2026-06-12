// Re-export + bridge guards for 0.6.0. Deliberately `import Effects`
// ONLY (no `import Palette`): compiling at all is the proof that the
// `@_exported import Palette` re-export gives an Effects-only consumer
// (halo) the pure vocabulary without a second dependency.
import XCTest
import Effects

final class ReExportTests: XCTestCase {

    /// Symbols that moved to Palette in 0.6.0 (or always lived there)
    /// stay visible through a bare `import Effects`.
    func testPureVocabularyVisibleThroughEffects() {
        XCTAssertTrue(canonicalEffectNames.contains("neon"))
        XCTAssertEqual(LinePet(rawValue: "ghost"), .ghost)
        XCTAssertEqual(canonicalLinePetNames.count, LinePet.allCases.count)
        XCTAssertEqual(EffectIntensity.parse("bold"), .bold)
        XCTAssertEqual(parseColorToken("#ff0000"), HexColor(0xFF0000))
    }

    /// The effect catalog still answers for every canonical name except
    /// `off` (and `random` resolves to a concrete member).
    func testEffectCatalogCoversCanonicalNames() {
        for name in canonicalEffectNames where name != "off" {
            XCTAssertNotNil(borderEffectFor(name), "no spec for '\(name)'")
        }
        XCTAssertNil(borderEffectFor("off"))
    }

    #if canImport(AppKit)
    /// `NSColor(HexColor)` materializes rgb + alpha in sRGB. The bridge
    /// lives in Effects so an Effects-only consumer can use it.
    @MainActor
    func testHexColorNSColorBridge() {
        let c = NSColor(HexColor(0x336699, 0.5))
        guard let srgb = c.usingColorSpace(.sRGB) else {
            return XCTFail("no sRGB conversion")
        }
        XCTAssertEqual(srgb.redComponent, 0x33 / 255, accuracy: 0.001)
        XCTAssertEqual(srgb.greenComponent, 0x66 / 255, accuracy: 0.001)
        XCTAssertEqual(srgb.blueComponent, 0x99 / 255, accuracy: 0.001)
        XCTAssertEqual(srgb.alphaComponent, 0.5, accuracy: 0.001)
    }

    /// `chaseGap` parameter exists and the guard path (empty pets) makes
    /// the call safe without a graphics context.
    @MainActor
    func testDrawLinePetsChaseGapSignature() {
        drawLinePets([], on: CGRect(x: 0, y: 0, width: 10, height: 10),
                     now: 0, scale: 1, speed: 120, chaseGap: 28)
    }
    #endif
}
