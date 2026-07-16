// TestSupport — shared XCTest helpers for the sill test targets. A plain
// (non-test) target so testTargets can depend on it (SwiftPM forbids
// test→test deps; same layout as swift-collections' _CollectionsTestSupport).
// canImport-guarded: on a CLT-only toolchain XCTest doesn't exist, and
// `swift build` must stay green there.
#if canImport(XCTest)
import AppKit
import XCTest

/// Asserts a layer colour equals its palette role per-component in sRGB.
/// Widgets that snap colours through a coarser path (e.g. Divider/Skeleton
/// hairlines) pass a tighter explicit `accuracy` at the call site.
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
