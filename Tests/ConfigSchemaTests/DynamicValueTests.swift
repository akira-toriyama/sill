import XCTest
import Toml
@testable import ConfigSchema

/// Exercises the additive `ObjectShape.dynamicValue` open-map-with-typed-value
/// mechanism (t-5d5a): a dynamic-ordinal table like facet's `[desktop.<N>]`
/// whose KEYS are checked against a pattern and whose VALUES carry a full nested
/// `ObjectShape` (`section[]` / `tab[]` / `tab.section[]`). Emit lowers it to
/// `patternProperties` + `additionalProperties: false`; validate checks the key
/// pattern and recurses each value into the value shape. The bare `permissive`
/// Bool path (a fieldless dynamic table) stays byte-identical — no dynamicValue.
///
/// The value-shape fixture mirrors the settled facet `desktop` grammar
/// (t-0avb 決定): `N -> { section[], tab[] }`, tab carrying its own `section[]`.
final class DynamicValueTests: XCTestCase {

    /// 1-based Mission-Control ordinal: accepts `1`/`01`/`10`, rejects `0`/`foo`
    /// (mirrors facet's runtime `Int >= 1`).
    private let ordinalPattern = "^0*[1-9][0-9]*$"

    // MARK: - Fixtures (mirror facet desktop: N -> { section[], tab[] })

    private func applyShape() -> ObjectShape {
        ObjectShape(fields: [
            SchemaField("workspace", .string, doc: "Target workspace."),
            SchemaField("tags", .stringArray, doc: "Tags to add."),
            SchemaField("floating", .boolean, doc: "Force floating."),
        ], doc: "Adopt vocabulary.")
    }

    private func sectionItemShape() -> ObjectShape {
        ObjectShape(fields: [
            // OPTIONAL (NOT in `required`): unassigned receptacle + tab.section
            // children carry no `type`.
            SchemaField("type", .string, doc: "Section kind.",
                        enumDomain: ["workspace", "lens"]),
            SchemaField("label", .string, doc: "Display name."),
            SchemaField("match", .string, doc: "Filter WHERE."),
            SchemaField("layout", .string, doc: "Layout name."),
            SchemaField("unassigned", .boolean, doc: "Lost-and-found marker."),
        ], objects: [NestedObject(key: "apply", shape: applyShape())],
           doc: "A display section.")
    }

    private func tabShape() -> ObjectShape {
        ObjectShape(fields: [
            SchemaField("type", .string, doc: "Tab kind.",
                        enumDomain: ["workspace", "lens"]),
            SchemaField("label", .string, doc: "Display name."),
        ], nested: [NestedTable(key: "section", item: sectionItemShape())],
           doc: "A named grouping.")
    }

    private func desktopValueShape() -> ObjectShape {
        ObjectShape(fields: [],
                    nested: [NestedTable(key: "section", item: sectionItemShape()),
                             NestedTable(key: "tab", item: tabShape())],
                    doc: "One mac desktop.")
    }

    /// A descriptor with a `desktop` section that is an ordinal-keyed open map.
    private func descriptor(keyPattern: String? = nil) -> SchemaDescriptor {
        let pattern = keyPattern ?? ordinalPattern
        return SchemaDescriptor(title: "facet-like", sections: [
            SchemaSection("desktop",
                .table(ObjectShape(fields: [], doc: "Per-desktop sections.",
                    dynamicValue: DynamicValue(keyPattern: pattern,
                                               shape: desktopValueShape()))),
                doc: "Per-desktop sections."),
        ])
    }

    private func emittedDesktop(_ d: SchemaDescriptor) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: Data(d.jsonSchema().utf8)) as? [String: Any]
        let props = try XCTUnwrap((obj?["properties"]) as? [String: Any])
        return try XCTUnwrap(props["desktop"] as? [String: Any])
    }

    // MARK: - Emit

    func testDynamicValueEmitsPatternPropertiesAndStrictAdditional() throws {
        let desktop = try emittedDesktop(descriptor())
        XCTAssertEqual(desktop["type"] as? String, "object")
        // The open map: values keyed by the ordinal pattern, everything else strict.
        XCTAssertEqual(desktop["additionalProperties"] as? Bool, false)
        let pp = try XCTUnwrap(desktop["patternProperties"] as? [String: Any])
        let valueSchema = try XCTUnwrap(pp[ordinalPattern] as? [String: Any])
        // The value schema resolves to the nested section[]/tab[] arrays.
        let valueProps = try XCTUnwrap(valueSchema["properties"] as? [String: Any])
        XCTAssertNotNil(valueProps["section"], "value shape exposes section[]")
        XCTAssertNotNil(valueProps["tab"], "value shape exposes tab[]")
    }

    func testDynamicValueValueSchemaNestsTabSection() throws {
        // B3 same-wave: tab.section resolves inside the dynamic value's tab item.
        let desktop = try emittedDesktop(descriptor())
        let pp = try XCTUnwrap(desktop["patternProperties"] as? [String: Any])
        let value = try XCTUnwrap(pp[ordinalPattern] as? [String: Any])
        let tab = try XCTUnwrap((value["properties"] as? [String: Any])?["tab"] as? [String: Any])
        let tabItems = try XCTUnwrap(tab["items"] as? [String: Any])
        XCTAssertNotNil((tabItems["properties"] as? [String: Any])?["section"],
                        "tab.section nests one more level")
    }

    func testDynamicValueNilPatternEmitsSchemaValuedAdditionalProperties() throws {
        // keyPattern == nil → additionalProperties is the value SCHEMA (a dict),
        // not a bool, and no patternProperties.
        let d = SchemaDescriptor(title: "app", sections: [
            SchemaSection("desktop",
                .table(ObjectShape(fields: [], doc: "d",
                    dynamicValue: DynamicValue(keyPattern: nil, shape: desktopValueShape()))),
                doc: "d"),
        ])
        let desktop = try emittedDesktop(d)
        XCTAssertNil(desktop["patternProperties"], "nil keyPattern → no patternProperties")
        let ap = try XCTUnwrap(desktop["additionalProperties"] as? [String: Any])
        XCTAssertEqual(ap["type"] as? String, "object")
        XCTAssertNotNil((ap["properties"] as? [String: Any])?["section"])
    }

    // MARK: - Validate

    private func validate(_ toml: String) throws -> [ValidationError] {
        descriptor().validate(try Toml.parse(toml))
    }

    func testValidOrdinalDocumentValidatesClean() throws {
        let errs = try validate("""
        [[desktop.1.section]]
        type = "workspace"
        label = "code"

        [[desktop.1.tab]]
        type = "lens"
        label = "browsers"

          [[desktop.1.tab.section]]
          label = "safari"

        [[desktop.2.section]]
        type = "lens"
        match = "app=Safari"
        """)
        XCTAssertEqual(errs, [], "valid ordinal desktops validate clean: \(errs.map(\.message))")
    }

    func testRejectsZeroOrdinalKey() throws {
        let errs = try validate("""
        [[desktop.0.section]]
        type = "workspace"
        """)
        XCTAssertTrue(errs.contains { if case .unknownKey(let k) = $0.rule { return k == "0" }; return false },
                      "0 is not a valid 1-based ordinal: \(errs.map(\.message))")
    }

    func testRejectsNonNumericOrdinalKey() throws {
        let errs = try validate("""
        [[desktop.foo.section]]
        type = "workspace"
        """)
        XCTAssertTrue(errs.contains { if case .unknownKey(let k) = $0.rule { return k == "foo" }; return false },
                      "a non-numeric ordinal is rejected: \(errs.map(\.message))")
    }

    func testOrdinalPatternAcceptsLeadingZeroAndMultiDigit() throws {
        // Pins the 1-based ordinal contract `^0*[1-9][0-9]*$`: leading zeros and
        // multi-digit ordinals are valid (facet's runtime `Int("01") == 1 >= 1`).
        let errs = try validate("""
        [[desktop.01.section]]
        type = "workspace"

        [[desktop.10.section]]
        type = "lens"
        match = "app=Safari"
        """)
        XCTAssertEqual(errs, [], "01 and 10 are valid ordinals: \(errs.map(\.message))")
    }

    func testRejectsAllZeroOrdinalKey() throws {
        let errs = try validate("""
        [[desktop.00.section]]
        type = "workspace"
        """)
        XCTAssertTrue(errs.contains { if case .unknownKey(let k) = $0.rule { return k == "00" }; return false },
                      "00 is not a valid 1-based ordinal: \(errs.map(\.message))")
    }

    func testValidatesValueShapeEnum() throws {
        let errs = try validate("""
        [[desktop.1.section]]
        type = "banana"
        """)
        XCTAssertTrue(errs.contains { if case .notInEnum(let k, _, _) = $0.rule { return k == "type" }; return false },
                      "a bad enum inside a dynamic value is caught: \(errs.map(\.message))")
    }

    func testValidatesNestedTabSectionUnknownKey() throws {
        // Descent all the way into desktop.N.tab.section — proves the value
        // shape's nested tables validate (B3 same-wave).
        let errs = try validate("""
        [[desktop.1.tab]]
        type = "workspace"
        label = "grp"

          [[desktop.1.tab.section]]
          labl = "typo"
        """)
        XCTAssertTrue(errs.contains { if case .unknownKey(let k) = $0.rule { return k == "labl" }; return false },
                      "a typo deep in a dynamic value's tab.section is caught: \(errs.map(\.message))")
    }

    func testMalformedKeyPatternFailsClosedRejectingAllKeys() throws {
        // A broken (uncompilable) pattern is a broken schema: the validator must
        // match NOTHING (fail-closed), mirroring the emitted never-matching
        // patternProperties + additionalProperties:false — never silently accept
        // every key (which would disagree with the schema).
        let d = SchemaDescriptor(title: "app", sections: [
            SchemaSection("desktop",
                .table(ObjectShape(fields: [], doc: "d",
                    dynamicValue: DynamicValue(keyPattern: "desktop.[",   // unbalanced = invalid
                                               shape: desktopValueShape()))),
                doc: "d"),
        ])
        let errs = d.validate(try Toml.parse("""
        [[desktop.1.section]]
        type = "workspace"
        """))
        XCTAssertTrue(errs.contains { if case .unknownKey(let k) = $0.rule { return k == "1" }; return false },
                      "a malformed key pattern rejects all keys (fail-closed): \(errs.map(\.message))")
    }

    func testNilKeyPatternAcceptsAnyKeyAndStillValidatesValue() throws {
        // keyPattern == nil = an open map keyed by ANY name; the value is still
        // validated against the value shape. Covers the validator's nil-pattern
        // branch (the emit side of which is tested separately).
        let d = SchemaDescriptor(title: "app", sections: [
            SchemaSection("desktop",
                .table(ObjectShape(fields: [], doc: "d",
                    dynamicValue: DynamicValue(keyPattern: nil, shape: desktopValueShape()))),
                doc: "d"),
        ])
        let clean = d.validate(try Toml.parse("""
        [[desktop.anything.section]]
        type = "workspace"
        """))
        XCTAssertEqual(clean, [], "any key name is accepted with a nil pattern: \(clean.map(\.message))")

        let bad = d.validate(try Toml.parse("""
        [[desktop.anything.section]]
        type = "banana"
        """))
        XCTAssertTrue(bad.contains { if case .notInEnum(let k, _, _) = $0.rule { return k == "type" }; return false },
                      "the value shape still validates under a nil pattern: \(bad.map(\.message))")
    }

    // MARK: - Spec authoring bridge (foldedRoot .dynamicTable reads dynamicValue)

    private struct Dummy {}

    func testSpecDynamicTableWithValueShapeEmitsPatternProperties() throws {
        let spec = ConfigSchema.Spec<Dummy>(title: "app", sections: [
            ConfigSchema.Section("desktop", kind: .dynamicTable, doc: "Per-desktop.",
                dynamicValue: DynamicValue(keyPattern: ordinalPattern, shape: desktopValueShape())),
        ])
        let obj = try JSONSerialization.jsonObject(with: Data(spec.jsonSchema().utf8)) as? [String: Any]
        let desktop = try XCTUnwrap(((obj?["properties"]) as? [String: Any])?["desktop"] as? [String: Any])
        XCTAssertEqual(desktop["additionalProperties"] as? Bool, false)
        XCTAssertNotNil((desktop["patternProperties"] as? [String: Any])?[ordinalPattern],
                        "a Spec .dynamicTable carrying a value shape emits patternProperties")
    }

    func testSpecFieldlessDynamicTableStaysPermissiveByteIdentical() throws {
        // No dynamicValue → the existing bare-permissive behaviour is untouched
        // (overlay.themes / search.synonyms depend on this).
        let spec = ConfigSchema.Spec<Dummy>(title: "app", sections: [
            ConfigSchema.Section("themes", kind: .dynamicTable, doc: "Dynamic names."),
        ])
        let obj = try JSONSerialization.jsonObject(with: Data(spec.jsonSchema().utf8)) as? [String: Any]
        let themes = try XCTUnwrap(((obj?["properties"]) as? [String: Any])?["themes"] as? [String: Any])
        XCTAssertEqual(themes["additionalProperties"] as? Bool, true, "no dynamicValue → unchanged permissive")
        XCTAssertNil(themes["patternProperties"])
        XCTAssertNil(themes["properties"], "an empty permissive object omits properties")
    }

    // MARK: - Leaf values (open map of name → one scalar/array field, t-wnvm)
    //
    // perch's `[search.synonyms]` is word → ARRAY OF STRINGS — the map's values
    // are not sub-tables, so `DynamicValue(keyPattern:shape:)` cannot express
    // it. The `leaf:` spelling lowers the FIELD schema as the value schema and
    // validates each dynamic key's value as that field.

    private func synonymsLeaf() -> SchemaField {
        SchemaField("<word>", .stringArray, doc: "Synonyms for this word.")
    }

    private func leafDescriptor(keyPattern: String? = nil) -> SchemaDescriptor {
        SchemaDescriptor(title: "app", sections: [
            SchemaSection("synonyms",
                .table(ObjectShape(fields: [], doc: "s",
                    dynamicValue: DynamicValue(keyPattern: keyPattern, leaf: synonymsLeaf()))),
                doc: "s"),
        ])
    }

    private func emittedSynonyms(_ d: SchemaDescriptor) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: Data(d.jsonSchema().utf8)) as? [String: Any]
        let props = try XCTUnwrap((obj?["properties"]) as? [String: Any])
        return try XCTUnwrap(props["synonyms"] as? [String: Any])
    }

    func testLeafDynamicValueEmitsFieldSchemaAsAdditionalProperties() throws {
        let syn = try emittedSynonyms(leafDescriptor())
        XCTAssertNil(syn["patternProperties"], "nil keyPattern → no patternProperties")
        let ap = try XCTUnwrap(syn["additionalProperties"] as? [String: Any])
        XCTAssertEqual(ap["type"] as? String, "array")
        XCTAssertEqual((ap["items"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertEqual(ap["description"] as? String, "Synonyms for this word.")
    }

    func testLeafDynamicValueWithKeyPatternEmitsFieldSchemaUnderPattern() throws {
        let pattern = "^[a-z]+$"
        let syn = try emittedSynonyms(leafDescriptor(keyPattern: pattern))
        XCTAssertEqual(syn["additionalProperties"] as? Bool, false)
        let pp = try XCTUnwrap(syn["patternProperties"] as? [String: Any])
        let value = try XCTUnwrap(pp[pattern] as? [String: Any])
        XCTAssertEqual(value["type"] as? String, "array")
    }

    func testLeafDynamicValueValidatesCleanArrays() throws {
        let errs = leafDescriptor().validate(try Toml.parse("""
        [synonyms]
        close = ["shut", "quit"]
        open = ["launch"]
        """))
        XCTAssertEqual(errs, [], "word → [string] entries validate clean: \(errs.map(\.message))")
    }

    func testLeafDynamicValueFlagsScalarValue() throws {
        // perch's silent hole: `close = "shut"` (scalar, not array) loads as
        // nothing today — the leaf shape must flag it as a type mismatch.
        let errs = leafDescriptor().validate(try Toml.parse("""
        [synonyms]
        close = "shut"
        """))
        XCTAssertTrue(errs.contains {
            if case .typeMismatch(let k, _) = $0.rule { return k == "close" }; return false
        }, "a scalar value in a leaf map is a type mismatch: \(errs.map(\.message))")
        XCTAssertTrue(errs.contains { $0.message.contains("synonyms.close") },
                      "the message names the dynamic key's path: \(errs.map(\.message))")
    }

    func testLeafDynamicValueFlagsNonStringElement() throws {
        let errs = leafDescriptor().validate(try Toml.parse("""
        [synonyms]
        close = ["shut", 3]
        """))
        XCTAssertTrue(errs.contains {
            if case .typeMismatch(let k, _) = $0.rule { return k == "close" }; return false
        }, "a non-string element inside a leaf array is caught: \(errs.map(\.message))")
    }

    func testLeafDynamicValueKeyPatternStillRejectsKeys() throws {
        let errs = leafDescriptor(keyPattern: "^[a-z]+$").validate(try Toml.parse("""
        [synonyms]
        BAD = ["x"]
        """))
        XCTAssertTrue(errs.contains {
            if case .unknownKey(let k) = $0.rule { return k == "BAD" }; return false
        }, "a leaf map still enforces its key pattern: \(errs.map(\.message))")
    }

    // MARK: - Quoted-header dynamic tables carry a value shape (t-wnvm)
    //
    // `behavior."<bundle-id>"` folds onto its PARENT node. With a dynamicValue
    // the parent's arbitrary sub-tables get the typed value schema while the
    // parent keeps its own static fields AND its own description (the per-app
    // doc belongs on the value shape's `doc`); without one, the pre-existing
    // bare-permissive fold (parent doc overwritten) is unchanged.

    private func perAppShape() -> ObjectShape {
        ObjectShape(fields: [
            SchemaField("min-size", .number, doc: "Min font size.", minimum: 0),
            SchemaField("roles", .stringArray, doc: "AX roles."),
        ], doc: "Per-app overrides.")
    }

    private func quotedSpec() -> ConfigSchema.Spec<Dummy> {
        ConfigSchema.Spec<Dummy>(title: "app", sections: [
            ConfigSchema.Section("behavior", doc: "Global behavior."),
            ConfigSchema.Section("behavior.\"<bundle-id>\"", kind: .dynamicTable,
                doc: "Per-app (ignored: the value shape's doc is the surfaced one).",
                dynamicValue: DynamicValue(keyPattern: nil, shape: perAppShape())),
        ])
    }

    func testSpecQuotedHeaderDynamicTableCarriesValueShape() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(quotedSpec().jsonSchema().utf8)) as? [String: Any]
        let behavior = try XCTUnwrap(((obj?["properties"]) as? [String: Any])?["behavior"] as? [String: Any])
        let ap = try XCTUnwrap(behavior["additionalProperties"] as? [String: Any],
                               "quoted-header dynamicValue types the parent's open map")
        XCTAssertNotNil((ap["properties"] as? [String: Any])?["min-size"])
        XCTAssertEqual(ap["description"] as? String, "Per-app overrides.")
        XCTAssertEqual(behavior["description"] as? String, "Global behavior.",
                       "the parent keeps its OWN doc — no longer overwritten by the per-app section")
    }

    func testSpecQuotedHeaderDynamicTableValidatesInnerKeys() throws {
        let clean = quotedSpec().validate(try Toml.parse("""
        [behavior."com.foo.Bar"]
        min-size = 3.5
        roles = ["AXButton"]
        """))
        XCTAssertEqual(clean, [], "a well-formed per-app table validates clean: \(clean.map(\.message))")

        let errs = quotedSpec().validate(try Toml.parse("""
        [behavior."com.foo.Bar"]
        min-siez = 3
        """))
        XCTAssertTrue(errs.contains {
            if case .unknownKey(let k) = $0.rule { return k == "min-siez" }; return false
        }, "a typo'd inner key inside a quoted-header dynamic table is caught: \(errs.map(\.message))")
    }

    func testSpecQuotedHeaderWithoutValueShapeStaysPermissive() throws {
        // No dynamicValue → the pre-existing quoted fold is byte-identical:
        // parent permissive + parent description overwritten by the section doc.
        let spec = ConfigSchema.Spec<Dummy>(title: "app", sections: [
            ConfigSchema.Section("behavior", doc: "Global behavior."),
            ConfigSchema.Section("behavior.\"<bundle-id>\"", kind: .dynamicTable, doc: "Per-app."),
        ])
        let obj = try JSONSerialization.jsonObject(with: Data(spec.jsonSchema().utf8)) as? [String: Any]
        let behavior = try XCTUnwrap(((obj?["properties"]) as? [String: Any])?["behavior"] as? [String: Any])
        XCTAssertEqual(behavior["additionalProperties"] as? Bool, true)
        XCTAssertEqual(behavior["description"] as? String, "Per-app.")
    }
}
