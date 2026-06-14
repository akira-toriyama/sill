import XCTest
import Toml
@testable import ConfigSchema

/// A toy config to exercise the spec-drives-both contract: one `Spec`
/// must (a) decode the flat `tables` map and (b) emit a schema that
/// mentions the same keys/domains/ranges — proving the single source.
private struct Demo: Equatable {
    var theme: String?
    var cols: Int?
    var width: Double?
    var glow: Bool?
    var pets: [String]?
}

private let demoSpec = ConfigSchema.Spec<Demo>(
    title: "demo config",
    sections: [
        ConfigSchema.Section("", fields: [
            ConfigSchema.Field(
                key: "view", kind: .scalar(.string),
                apply: { c, v in if let s = v.asString { c.theme = s } },
                domain: ["tree", "grid"], def: .string("tree"),
                doc: "top-level enum")
        ]),
        ConfigSchema.Section("grid", fields: [
            ConfigSchema.Field(
                key: "cols", kind: .scalar(.integer),
                apply: { c, v in if let n = v.asInt { c.cols = n } },
                def: .int(4), min: 1, max: 12, doc: "column count"),
            ConfigSchema.Field(
                key: "width", kind: .scalar(.number),
                apply: { c, v in if let d = v.asDouble { c.width = d } },
                min: 0.5, max: 30),
            ConfigSchema.Field(
                key: "glow", kind: .scalar(.boolean),
                apply: { c, v in if let b = v.asBool { c.glow = b } },
                def: .bool(true)),
            ConfigSchema.Field(
                key: "pets", kind: .stringArray(item: ["chomp", "ghost"]),
                apply: { c, v in if let a = v.asStringArray { c.pets = a } }),
        ]),
        ConfigSchema.Section("rules", kind: .arrayOfTables, fields: [
            ConfigSchema.Field(
                key: "app", kind: .scalar(.string),
                apply: { _, _ in }),
        ]),
    ]
)

final class ConfigSchemaTests: XCTestCase {

    func testDecodePopulatesPresentKeysOnly() {
        let doc = Toml.parseFlat("""
        view = "grid"
        [grid]
        cols = 8
        glow = false
        pets = ["chomp", "ghost"]
        """)
        var c = Demo()
        demoSpec.decode(doc.tables, into: &c)
        XCTAssertEqual(c.theme, "grid")
        XCTAssertEqual(c.cols, 8)
        XCTAssertEqual(c.glow, false)
        XCTAssertEqual(c.pets, ["chomp", "ghost"])
        // `width` was absent → Optional stays nil (no default forced here).
        XCTAssertNil(c.width)
    }

    func testDecodeIgnoresWrongTypedValue() {
        // `.asInt` is int-only — a fractional/string value is left unread,
        // matching the hand-written `if let n = …asInt` idiom.
        let doc = Toml.parseFlat("""
        [grid]
        cols = 1.5
        """)
        var c = Demo()
        demoSpec.decode(doc.tables, into: &c)
        XCTAssertNil(c.cols)
    }

    func testJSONSchemaIsValidAndStable() throws {
        let text = demoSpec.jsonSchema()
        let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        let root = try XCTUnwrap(obj)
        XCTAssertEqual(root["$schema"] as? String,
                       "http://json-schema.org/draft-07/schema#")
        XCTAssertEqual(root["additionalProperties"] as? Bool, false)

        let props = try XCTUnwrap(root["properties"] as? [String: Any])
        // Top-level "" field surfaces directly.
        let view = try XCTUnwrap(props["view"] as? [String: Any])
        XCTAssertEqual(view["enum"] as? [String], ["tree", "grid"])
        XCTAssertEqual(view["default"] as? String, "tree")

        // `[grid]` is a nested object with strict keys + ranges.
        let grid = try XCTUnwrap(props["grid"] as? [String: Any])
        XCTAssertEqual(grid["additionalProperties"] as? Bool, false)
        let gridProps = try XCTUnwrap(grid["properties"] as? [String: Any])
        let cols = try XCTUnwrap(gridProps["cols"] as? [String: Any])
        XCTAssertEqual(cols["type"] as? String, "integer")
        XCTAssertEqual(cols["minimum"] as? Int, 1)
        XCTAssertEqual(cols["maximum"] as? Int, 12)
        let pets = try XCTUnwrap(gridProps["pets"] as? [String: Any])
        XCTAssertEqual(pets["type"] as? String, "array")

        // `[[rules]]` is an array of objects.
        let rules = try XCTUnwrap(props["rules"] as? [String: Any])
        XCTAssertEqual(rules["type"] as? String, "array")

        // Deterministic: same spec → byte-identical output.
        XCTAssertEqual(text, demoSpec.jsonSchema())
    }
}
