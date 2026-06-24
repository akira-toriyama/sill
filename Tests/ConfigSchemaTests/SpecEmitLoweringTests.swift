import XCTest
import Toml
@testable import ConfigSchema

// S3 byte-snapshot guard: `ConfigSchema.Spec.jsonSchema()` now folds its
// dotted-header section tree into the shared `SchemaEmit` lowering (the same
// one `SchemaDescriptor` uses). These tests pin the BYTE-LEVEL properties the
// existing structural tests (testJSONSchemaIsValidAndStable /
// testDottedHeadersFoldIntoNestedTree) don't cover — number-precision
// formatting, inclusive-bound rendering, array-of-tables doc PLACEMENT, the
// permissive-empty-table shape, item enums, the top-level-field / dotted-fold /
// quoted-permissive structure, AND the edge cases an adversarial review
// surfaced (documented root, the empty-string-doc normalization, and
// scalar-only metadata dropped from arrays) — so a regression in the unified
// lowering surfaces here, in sill, not only in a consumer's drift guard.
//
// The `facetLike` fixture faithfully replicates the shapes facet's production
// `configSpec` uses (the real consumer); `nested` covers the perch/wand
// dotted-header / dynamic-table surface. `Sink` is a throwaway decode target —
// emission ignores `apply`.
private struct Sink {}

private enum SpecFixture {
    // Placeholder enum domains: the emitter passes values through verbatim.
    static let themes = ["terminal", "matrix", "synth", "random", ""]
    static let pets = ["chomp", "ghost", "nyan"]

    static func field(_ key: String, _ kind: ConfigSchema.Kind,
                      domain: [String]? = nil, enumDocs: [String?]? = nil,
                      def: ConfigSchema.DefaultValue? = nil,
                      min: Double? = nil, max: Double? = nil, doc: String? = nil)
        -> ConfigSchema.Field<Sink> {
        ConfigSchema.Field(key: key, kind: kind, apply: { _, _ in },
                           domain: domain, enumDocs: enumDocs, def: def,
                           min: min, max: max, doc: doc)
    }

    /// Faithful transcription of facet's `configSpec` shapes (FacetConfig+Spec).
    static var facetLike: ConfigSchema.Spec<Sink> {
        ConfigSchema.Spec<Sink>(
            title: "facet config.toml",
            sections: [
                .init("theme", doc: "App-default palette.", fields: [
                    field("name", .scalar(.string), domain: themes, def: .string("terminal"),
                          doc: "Theme name (sill catalog); `random` picks one per launch."),
                    field("color-cycle-ms", .scalar(.integer), min: 1000, max: 120000,
                          doc: "Accent-rotation period for animated themes (ms). Unset = static."),
                ]),
                .init("window", fields: [
                    field("raise-on-open", .scalar(.string), domain: ["raise", "focus", "none"],
                          def: .string("raise"), doc: "How a freshly-opened floating window is surfaced."),
                ]),
                .init("grid", fields: [
                    field("cols", .scalar(.integer), def: .int(4), min: 1, max: 12),
                    field("label-position", .scalar(.string), domain: ["up", "down"], def: .string("up")),
                    field("thumbnail-refresh-seconds", .scalar(.integer), def: .int(4), min: 0, max: 60,
                          doc: "Background thumbnail capture interval; 0 disables."),
                    field("theme", .scalar(.string), domain: themes, def: .string(""),
                          doc: "Per-view theme; `\"\"` inherits `[theme].name`."),
                ]),
                .init("tree", fields: [
                    field("preview-mode", .scalar(.string), domain: ["popover", "mirror"],
                          def: .string("popover"), doc: "How the hover preview is sized/placed."),
                    field("pos-x", .scalar(.integer), doc: "Panel seed X (top-left origin, px). All four needed."),
                    field("line-pets", .stringArray(item: pets), doc: "Arcade pets walking the panel border; `[]` = off."),
                    field("pet-scale", .scalar(.number), def: .number(0.9), min: 0.1, doc: "Pet size multiplier."),
                    field("pet-lap-seconds", .scalar(.number), def: .number(8), min: 0.5,
                          doc: "Seconds for a pet to circle a row once."),
                ]),
                .init("layout", fields: [
                    field("default", .scalar(.string), def: .string("float"),
                          doc: "Startup layout: float | bsp | stack | a registered engine."),
                    field("inner-gap", .scalar(.integer), def: .int(0), min: 0, max: 1000,
                          doc: "Gap between adjacent tiled windows (px)."),
                    field("smart-gaps", .scalar(.boolean), def: .bool(false),
                          doc: "Drop the outer gap for a lone tiled window."),
                ]),
                .init("border", doc: "Tree-panel border effect.", fields: [
                    field("effect", .scalar(.string), domain: ["off", "neon", "pulse"], def: .string("off")),
                    field("glow", .scalar(.boolean), def: .bool(true), doc: "Neon bloom under the stroke."),
                    field("width", .scalar(.number), def: .number(1.5), min: 0.5, max: 30),
                ]),
                // arrays-of-tables (schema-only in facet)
                .init("exclude", kind: .arrayOfTables,
                      doc: "Windows matching a rule are floated/ignored, not tiled.", fields: [
                    field("app", .scalar(.string), doc: "App-name regex (substring unless anchored)."),
                    field("max-width", .scalar(.integer)),
                    field("action", .scalar(.string), domain: ["float", "ignore", "manage"], def: .string("float")),
                ]),
                .init("rule", kind: .arrayOfTables, doc: "Adopt-rules.", fields: [
                    field("match", .scalar(.string), doc: "facet filter WHERE-clause."),
                    field("tags", .stringArray(item: nil), doc: "Tags to add to a matched window."),
                    field("floating", .scalar(.boolean), doc: "Force a matched window floating."),
                ]),
                // dynamic (permissive) table, no own fields
                .init("desktop", kind: .dynamicTable,
                      doc: "`[[desktop.N.section]]` ordered per-mac-desktop display sections."),
            ]
        )
    }

    /// Top-level fields + dotted-header folding + quoted permissive parent +
    /// nested array-of-tables + named dynamic table + per-enum-value hover.
    static var nested: ConfigSchema.Spec<Sink> {
        ConfigSchema.Spec<Sink>(
            title: "nested",
            sections: [
                .init("", fields: [
                    field("view", .scalar(.string), domain: ["tree", "grid"],
                          enumDocs: ["Sidebar tree.", nil], def: .string("tree"),
                          doc: "top-level enum"),
                ]),
                .init("cast", doc: "Cast section.", fields: [
                    field("button", .scalar(.string)),
                ]),
                .init("cast.overlay", fields: [
                    field("enabled", .scalar(.boolean), def: .bool(true)),
                ]),
                .init("cast.cursor.rule", kind: .arrayOfTables, fields: [
                    field("name", .scalar(.string)),
                ]),
                .init("overlay.themes", kind: .dynamicTable, doc: "Custom palettes."),
                .init("behavior.\"<id>\"", kind: .dynamicTable),
                .init("behavior", fields: [
                    field("roles", .stringArray(item: nil)),
                ]),
            ]
        )
    }
}

final class SpecEmitLoweringTests: XCTestCase {

    private func root(_ spec: ConfigSchema.Spec<Sink>) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(spec.jsonSchema().utf8)) as? [String: Any])
    }
    private func props(_ obj: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(obj["properties"] as? [String: Any])
    }

    // MARK: - Output spelling (bare slashes + trailing newline)

    func testOutputSpellingMatchesHistoricSpec() {
        let raw = SpecFixture.facetLike.jsonSchema()
        XCTAssertTrue(raw.hasSuffix("}\n"), "Spec emits a trailing newline")
        XCTAssertTrue(raw.contains("http://json-schema.org/draft-07/schema#"),
                      "Spec emits bare (unescaped) slashes")
        XCTAssertFalse(raw.contains(#"\/"#), "no escaped slashes")
    }

    func testDeterministic() {
        XCTAssertEqual(SpecFixture.facetLike.jsonSchema(), SpecFixture.facetLike.jsonSchema())
        XCTAssertEqual(SpecFixture.nested.jsonSchema(), SpecFixture.nested.jsonSchema())
    }

    // MARK: - Number scalar + float precision (the JSONSerialization passthrough)

    func testNumberScalarType() throws {
        let tree = try XCTUnwrap(props(try root(SpecFixture.facetLike))["tree"] as? [String: Any])
        let petScale = try XCTUnwrap((tree["properties"] as? [String: Any])?["pet-scale"] as? [String: Any])
        XCTAssertEqual(petScale["type"] as? String, "number")
    }

    /// A `Double` default/bound must pass through to JSONSerialization VERBATIM
    /// — it renders the shortest round-trippable form, so `0.9` becomes
    /// `0.90000000000000002`. This is the exact byte shape facet's CI-committed
    /// schema carries; any rounding/Int coercion in the lowering would drift it.
    func testNumberDefaultAndBoundFullPrecision() {
        let raw = SpecFixture.facetLike.jsonSchema()
        XCTAssertTrue(raw.contains("\"default\" : 0.90000000000000002"),
                      "number default 0.9 keeps full Double precision")
        XCTAssertTrue(raw.contains("\"minimum\" : 0.10000000000000001"),
                      "fractional inclusive minimum keeps full Double precision")
        XCTAssertTrue(raw.contains("\"minimum\" : 0.5"),
                      "a cleanly-representable fractional bound stays short")
    }

    /// A whole-valued bound — even though carried as `Double` — must serialise
    /// WITHOUT a decimal point (`30`, not `30.0`), matching the historic output.
    func testWholeBoundsRenderAsIntegers() {
        let raw = SpecFixture.facetLike.jsonSchema()
        XCTAssertTrue(raw.contains("\"maximum\" : 30\n") || raw.contains("\"maximum\" : 30,"),
                      "a whole Double bound renders as `30`, not `30.0`")
        XCTAssertFalse(raw.contains("30.0"), "no spurious trailing .0 on whole bounds")
        XCTAssertFalse(raw.contains("12.0"))
    }

    func testIntegerDefaultStaysInt() throws {
        let grid = try XCTUnwrap(props(try root(SpecFixture.facetLike))["grid"] as? [String: Any])
        let cols = try XCTUnwrap((grid["properties"] as? [String: Any])?["cols"] as? [String: Any])
        XCTAssertEqual(cols["type"] as? String, "integer")
        XCTAssertEqual(cols["default"] as? Int, 4)
        XCTAssertEqual(cols["minimum"] as? Int, 1)
        XCTAssertEqual(cols["maximum"] as? Int, 12)
    }

    // MARK: - Array-of-tables doc PLACEMENT (doc on items, NOT on the array node)

    func testArrayOfTablesDocRidesItemsNotArrayNode() throws {
        let exclude = try XCTUnwrap(props(try root(SpecFixture.facetLike))["exclude"] as? [String: Any])
        XCTAssertEqual(exclude["type"] as? String, "array")
        XCTAssertNil(exclude["description"],
                     "Spec puts the section doc on `items`, never the array node")
        let items = try XCTUnwrap(exclude["items"] as? [String: Any])
        XCTAssertEqual(items["description"] as? String,
                       "Windows matching a rule are floated/ignored, not tiled.")
        XCTAssertEqual(items["additionalProperties"] as? Bool, false)
        XCTAssertNil(items["minItems"], "Spec arrays carry no minItems")
    }

    // MARK: - String-array item enum (present / absent)

    func testStringArrayItemEnum() throws {
        let tree = try XCTUnwrap(props(try root(SpecFixture.facetLike))["tree"] as? [String: Any])
        let linePets = try XCTUnwrap((tree["properties"] as? [String: Any])?["line-pets"] as? [String: Any])
        XCTAssertEqual(linePets["type"] as? String, "array")
        let items = try XCTUnwrap(linePets["items"] as? [String: Any])
        XCTAssertEqual(items["enum"] as? [String], ["chomp", "ghost", "nyan"])

        let rule = try XCTUnwrap(props(try root(SpecFixture.facetLike))["rule"] as? [String: Any])
        let ruleItem = try XCTUnwrap(rule["items"] as? [String: Any])
        let tags = try XCTUnwrap((ruleItem["properties"] as? [String: Any])?["tags"] as? [String: Any])
        XCTAssertNil((tags["items"] as? [String: Any])?["enum"],
                     "a stringArray with no item domain emits bare string items")
    }

    // MARK: - Permissive empty table (the `[desktop]` dynamic-table shape)

    func testPermissiveEmptyTableOmitsProperties() throws {
        let desktop = try XCTUnwrap(props(try root(SpecFixture.facetLike))["desktop"] as? [String: Any])
        XCTAssertEqual(desktop["type"] as? String, "object")
        XCTAssertEqual(desktop["additionalProperties"] as? Bool, true)
        XCTAssertNil(desktop["properties"], "a bare permissive object omits an empty properties map")
        XCTAssertNotNil(desktop["description"])
    }

    // MARK: - Top-level field + dotted fold + quoted permissive (the nested surface)

    func testTopLevelFieldAndEnumDocsThroughSpec() throws {
        let view = try XCTUnwrap(props(try root(SpecFixture.nested))["view"] as? [String: Any])
        XCTAssertEqual(view["type"] as? String, "string",
                       "a root \"\"-section field lands directly in top-level properties")
        XCTAssertEqual(view["enum"] as? [String], ["tree", "grid"])
        // Spec.Field.enumDocs flows to taplo per-value hover (the S4 enabler).
        let enumValues = try XCTUnwrap((((view["x-taplo"] as? [String: Any])?["docs"]
            as? [String: Any])?["enumValues"]) as? [Any])
        XCTAssertEqual(enumValues.count, 2)
        XCTAssertEqual(enumValues[0] as? String, "Sidebar tree.")
        XCTAssertTrue(enumValues[1] is NSNull)
    }

    func testDottedFoldAndPermissiveStructure() throws {
        let p = try props(try root(SpecFixture.nested))

        // cast → own `button` + nested object `overlay` + nested `cursor.rule` array.
        let cast = try XCTUnwrap(p["cast"] as? [String: Any])
        XCTAssertEqual(cast["additionalProperties"] as? Bool, false)
        XCTAssertEqual(cast["description"] as? String, "Cast section.")
        let castProps = try XCTUnwrap(cast["properties"] as? [String: Any])
        XCTAssertNotNil(castProps["button"])
        let overlay = try XCTUnwrap(castProps["overlay"] as? [String: Any])
        XCTAssertEqual(overlay["additionalProperties"] as? Bool, false)
        XCTAssertNil(overlay["description"], "an undocumented folded sub-table has no description")
        XCTAssertNotNil((overlay["properties"] as? [String: Any])?["enabled"])
        let cursor = try XCTUnwrap(castProps["cursor"] as? [String: Any])
        let ruleArr = try XCTUnwrap((cursor["properties"] as? [String: Any])?["rule"] as? [String: Any])
        XCTAssertEqual(ruleArr["type"] as? String, "array")

        // overlay (implicit container, strict) → themes (permissive, documented).
        let ov = try XCTUnwrap(p["overlay"] as? [String: Any])
        XCTAssertEqual(ov["additionalProperties"] as? Bool, false)
        XCTAssertNil(ov["description"])
        let themes = try XCTUnwrap((ov["properties"] as? [String: Any])?["themes"] as? [String: Any])
        XCTAssertEqual(themes["additionalProperties"] as? Bool, true)
        XCTAssertEqual(themes["description"] as? String, "Custom palettes.")

        // behavior: quoted-bundle-id header makes the parent permissive AND it
        // keeps its own `roles` field.
        let behavior = try XCTUnwrap(p["behavior"] as? [String: Any])
        XCTAssertEqual(behavior["additionalProperties"] as? Bool, true)
        XCTAssertNotNil((behavior["properties"] as? [String: Any])?["roles"])
    }

    // MARK: - Edge cases an adversarial review surfaced (byte-divergence fixes +
    // the one intentional normalization).

    /// A documented top-level `Section("")` must keep its `description` on the
    /// root object (regression: the root's own doc was being dropped because the
    /// emit hard-coded an empty sectionDoc for the root).
    func testDocumentedRootSectionEmitsDescription() throws {
        let spec = ConfigSchema.Spec<Sink>(title: "t", sections: [
            .init("", doc: "Top-level scope.", fields: [
                SpecFixture.field("view", .scalar(.string)),
            ]),
        ])
        let obj = try root(spec)
        XCTAssertEqual(obj["description"] as? String, "Top-level scope.")
        XCTAssertNotNil(try props(obj)["view"])
    }

    /// THE ONE intentional normalization vs the historic lowering: an explicit
    /// empty-string `doc` ("") is treated like an absent doc and OMITS
    /// `description` (the old lowering emitted `"description": ""`). No real spec
    /// passes `doc: ""`, and an empty description is noise.
    func testEmptyStringDocNormalizesToOmitted() throws {
        let spec = ConfigSchema.Spec<Sink>(title: "t", sections: [
            .init("sec", doc: "", fields: [
                SpecFixture.field("k", .scalar(.string), doc: ""),
            ]),
            .init("rows", kind: .arrayOfTables, doc: "", fields: [
                SpecFixture.field("c", .scalar(.string)),
            ]),
            .init("dyn", kind: .dynamicTable, doc: ""),
        ])
        let p = try props(try root(spec))
        let sec = try XCTUnwrap(p["sec"] as? [String: Any])
        XCTAssertNil(sec["description"], "empty section doc omits description")
        let k = try XCTUnwrap((sec["properties"] as? [String: Any])?["k"] as? [String: Any])
        XCTAssertNil(k["description"], "empty field doc omits description")
        let rows = try XCTUnwrap(p["rows"] as? [String: Any])
        XCTAssertNil((rows["items"] as? [String: Any])?["description"],
                     "empty arrayOfTables doc omits the items description")
        let dyn = try XCTUnwrap(p["dyn"] as? [String: Any])
        XCTAssertNil(dyn["description"], "empty dynamicTable doc omits description")
        XCTAssertEqual(dyn["additionalProperties"] as? Bool, true)
    }

    /// A `.stringArray` field's stray scalar-only metadata (`domain`/`min`/`max`)
    /// must be DROPPED — only the element enum (via `.stringArray(item:)`) plus
    /// `default`/`doc` survive (matching the historic per-field lowering, whose
    /// `enum`/`minimum`/`maximum` lived only in the `.scalar` branch).
    func testStringArrayDropsScalarOnlyMetadata() throws {
        let spec = ConfigSchema.Spec<Sink>(title: "t", sections: [
            .init("sec", fields: [
                ConfigSchema.Field(key: "tags", kind: .stringArray(item: ["a", "b"]),
                                   apply: { _, _ in },
                                   domain: ["x", "y"],   // stray scalar metadata
                                   def: .stringArray(["a"]),
                                   min: 1, max: 9, doc: "Tags."),
            ]),
        ])
        let sec = try XCTUnwrap(try props(try root(spec))["sec"] as? [String: Any])
        let tags = try XCTUnwrap((sec["properties"] as? [String: Any])?["tags"] as? [String: Any])
        XCTAssertEqual(tags["type"] as? String, "array")
        XCTAssertNil(tags["enum"], "field-level domain is dropped for an array")
        XCTAssertNil(tags["minimum"], "min is dropped for an array")
        XCTAssertNil(tags["maximum"], "max is dropped for an array")
        // The element enum + default + doc DO survive.
        XCTAssertEqual((tags["items"] as? [String: Any])?["enum"] as? [String], ["a", "b"])
        XCTAssertEqual(tags["default"] as? [String], ["a"])
        XCTAssertEqual(tags["description"] as? String, "Tags.")
    }
}
