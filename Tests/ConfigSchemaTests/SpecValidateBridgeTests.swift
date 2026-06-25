import XCTest
import Toml
@testable import ConfigSchema

/// Exercises the `ConfigSchema.Spec` → validate bridge (`makeDescriptor()` /
/// `validate(_:)`): the single `Spec` a consumer already uses for decode +
/// `--emit-schema` now ALSO drives runtime structural validation, so "editor
/// green" (taplo vs the emitted schema) and "loader accepts it" (this
/// validator) read ONE source and cannot diverge.
///
/// The fixture mirrors the real consumer shape (perch / wand): nested dotted
/// tables (`[grid.sub]`), an array-of-tables (`[[grid.rule]]`), and a dynamic
/// permissive table (`[palette.<name>]`) — and NO top-level bare field, so the
/// whole document is reachable by the named-section walk.
final class SpecValidateBridgeTests: XCTestCase {

    private struct Cfg: Equatable {}   // validate never decodes; apply is a no-op

    private nonisolated(unsafe) static let spec = ConfigSchema.Spec<Cfg>(
        title: "bridge fixture",
        sections: [
            ConfigSchema.Section("grid", fields: [
                ConfigSchema.Field(key: "mode", kind: .scalar(.string),
                                   apply: { _, _ in },
                                   domain: ["compact", "wide"], doc: "layout mode"),
                ConfigSchema.Field(key: "cols", kind: .scalar(.integer),
                                   apply: { _, _ in }, min: 1, max: 12,
                                   doc: "column count"),
            ]),
            // nested single-object child: `[grid.sub]`
            ConfigSchema.Section("grid.sub", fields: [
                ConfigSchema.Field(key: "flag", kind: .scalar(.boolean),
                                   apply: { _, _ in }, doc: "a flag"),
            ]),
            // array-of-tables child: `[[grid.rule]]`
            ConfigSchema.Section("grid.rule", kind: .arrayOfTables, fields: [
                ConfigSchema.Field(key: "app", kind: .scalar(.string),
                                   apply: { _, _ in }, doc: "bundle id"),
            ]),
            // dynamic, permissive table: `[palette.<name>]`
            ConfigSchema.Section("palette", kind: .dynamicTable,
                                 doc: "custom palettes (arbitrary names)"),
        ]
    )

    // MARK: - makeDescriptor shape

    func testDescriptorSectionsMirrorTopLevelHeaders() throws {
        let d = Self.spec.makeDescriptor()
        XCTAssertEqual(d.title, "bridge fixture")
        // Only top-level headers become sections; `grid.sub` / `grid.rule` ride
        // INSIDE the `grid` section's ObjectShape.
        XCTAssertEqual(Set(d.sections.map(\.name)), ["grid", "palette"])

        let grid = try? XCTUnwrap(d.sections.first { $0.name == "grid" })
        guard case .table(let shape)? = grid?.kind else {
            return XCTFail("grid should be a .table section")
        }
        XCTAssertEqual(Set(shape.fields.map(\.key)), ["mode", "cols"])
        XCTAssertEqual(shape.objects.map(\.key), ["sub"])   // nested [grid.sub]
        XCTAssertEqual(shape.nested.map(\.key), ["rule"])   // nested [[grid.rule]]

        // The dynamic table folds to a permissive object (accepts any keys).
        let palette = d.sections.first { $0.name == "palette" }
        guard case .table(let pShape)? = palette?.kind else {
            return XCTFail("palette should be a .table section")
        }
        XCTAssertTrue(pShape.permissive)
    }

    // MARK: - validate (the convenience on Spec)

    func testValidDocumentHasNoErrors() throws {
        let root = try Toml.parse("""
        [grid]
        mode = "wide"
        cols = 8
        [grid.sub]
        flag = true
        [[grid.rule]]
        app = "com.apple.Safari"
        [palette.midnight]
        anything = "is accepted here"
        count = 3
        """)
        XCTAssertEqual(Self.spec.validate(root), [])
    }

    func testStructuralViolationsAreReported() throws {
        let root = try Toml.parse("""
        [grid]
        mode = "neon"
        cols = 99
        bogus = 1
        [grid.sub]
        flag = "nope"
        """)
        let errors = Self.spec.validate(root)
        let rules = errors.map(\.rule)

        XCTAssertTrue(rules.contains(.notInEnum(key: "mode", value: "neon",
                                                allowed: ["compact", "wide"])),
                      "enum violation expected; got \(rules)")
        XCTAssertTrue(rules.contains { if case .outOfRange(let k, _) = $0 { return k == "cols" }; return false },
                      "out-of-range expected; got \(rules)")
        XCTAssertTrue(rules.contains(.unknownKey(key: "bogus")),
                      "unknown-key expected; got \(rules)")
        XCTAssertTrue(rules.contains { if case .typeMismatch(let k, _) = $0 { return k == "flag" }; return false },
                      "nested type-mismatch expected; got \(rules)")
    }

    func testNestedArrayOfTablesElementIsValidated() throws {
        let root = try Toml.parse("""
        [grid]
        mode = "compact"
        [[grid.rule]]
        app = 7
        """)
        let errors = Self.spec.validate(root)
        // The wrong-typed `app` inside the array-of-tables row is caught, and
        // the path threads through the `[0]` index.
        XCTAssertTrue(errors.contains {
            if case .typeMismatch(let k, _) = $0.rule { return k == "app" }
            return false
        }, "array-of-tables element type-mismatch expected; got \(errors.map(\.rule))")
    }

    func testPermissiveTableAcceptsArbitraryKeys() throws {
        let root = try Toml.parse("""
        [palette.whatever]
        foo = 1
        bar = "baz"
        [palette.another]
        x = true
        """)
        XCTAssertEqual(Self.spec.validate(root), [],
                       "dynamic permissive table must not flag arbitrary keys")
    }

    /// The bridge and the JSON emitter read the SAME fold — a key/enum the
    /// validator enforces must also appear in the emitted schema. Cheap
    /// single-source smoke check (full byte-identity is SpecEmitLoweringTests).
    func testValidateAndEmitShareOneSource() throws {
        let schema = Self.spec.jsonSchema()
        XCTAssertTrue(schema.contains("\"compact\"") && schema.contains("\"wide\""),
                      "emitted schema should carry the same `mode` enum the validator enforces")
        // And the validator independently rejects a value outside that enum.
        let root = try Toml.parse("[grid]\nmode = \"neon\"\n")
        XCTAssertFalse(Self.spec.validate(root).isEmpty)
    }
}
