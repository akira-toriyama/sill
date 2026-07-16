// TestSupport — shared assertion helpers for the widget test targets (R9).
// A PLAIN target (not a test target: SwiftPM test targets can't depend on each
// other) that only test targets depend on — the swift-collections
// `_CollectionsTestSupport` precedent. Everything is gated on
// `canImport(XCTest)` so a CommandLineTools-only `swift build` (no XCTest in
// the CLT toolchain — the repo's quick compile bar) still builds this target,
// as an empty module.

#if canImport(XCTest)
import XCTest
import AppKit

/// CGColor identity is fragile across resolve()/colour-space conversions —
/// compare resolved sRGB components (incl. alpha) within tolerance. The ONE
/// comparator behind every ThemeKit / ThemeKitUI widget-colour assertion
/// (12 verbatim copies collapsed here; hairline-precision suites pass
/// `accuracy: 0.002` explicitly).
public func sameColor(_ a: CGColor?, _ b: NSColor, accuracy: CGFloat = 0.01,
                      _ msg: String = "", file: StaticString = #filePath,
                      line: UInt = #line) {
    guard let a, let an = NSColor(cgColor: a)?.usingColorSpace(.sRGB),
          let bn = b.usingColorSpace(.sRGB) else {
        return XCTFail("colour unconvertible: \(msg)", file: file, line: line)
    }
    XCTAssertEqual(an.redComponent,   bn.redComponent,   accuracy: accuracy, msg, file: file, line: line)
    XCTAssertEqual(an.greenComponent, bn.greenComponent, accuracy: accuracy, msg, file: file, line: line)
    XCTAssertEqual(an.blueComponent,  bn.blueComponent,  accuracy: accuracy, msg, file: file, line: line)
    XCTAssertEqual(an.alphaComponent, bn.alphaComponent, accuracy: accuracy, msg, file: file, line: line)
}
#endif
