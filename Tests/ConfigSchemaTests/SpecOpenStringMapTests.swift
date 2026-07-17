import XCTest
import Toml
@testable import ConfigSchema

/// Exercises the `Spec` layer's `.openStringMap` section kind (t-ev5t): an
/// open name→string map (facet's `[alias]` — NAME = 'filter expr') declared
/// straight on the ONE `Spec`, so the emitted schema types the values and
/// `validate` rejects non-string values — the descriptor layer's
/// `SchemaSection.Kind.openStringMap` capability, reachable from the Spec
/// bridge instead of a bare-permissive `.dynamicTable` compromise.
final class SpecOpenStringMapTests: XCTestCase {

    private struct Cfg: Equatable {}

    /// facet's real shape: one strict table + a top-level open string map.
    private nonisolated(unsafe) static let spec = ConfigSchema.Spec<Cfg>(
        title: "open-string-map fixture",
        sections: [
            ConfigSchema.Section("grid", fields: [
                ConfigSchema.Field(key: "mode", kind: .scalar(.string),
                                   apply: { _, _ in }, doc: "layout mode"),
            ]),
            ConfigSchema.Section("alias",
                                 kind: .openStringMap(valueDoc: "facet filter expression"),
                                 doc: "Filter aliases: NAME = 'filter expr'."),
        ]
    )

    private func aliasSubtree(of json: String) throws -> [String: Any] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(json.utf8)) as? [String: Any])
        let props = try XCTUnwrap(root["properties"] as? [String: Any])
        return try XCTUnwrap(props["alias"] as? [String: Any])
    }

    // MARK: - emit

    func testEmitTypesTheMapValues() throws {
        let alias = try aliasSubtree(of: Self.spec.jsonSchema())
        XCTAssertEqual(alias["type"] as? String, "object")
        XCTAssertEqual(alias["description"] as? String,
                       "Filter aliases: NAME = 'filter expr'.")
        let ap = try XCTUnwrap(alias["additionalProperties"] as? [String: Any])
        XCTAssertEqual(ap["type"] as? String, "string")
        XCTAssertEqual(ap["description"] as? String, "facet filter expression")
        // An open map has no enumerable keys — no `properties` block.
        XCTAssertNil(alias["properties"])
    }

    /// The Spec emission is byte-equivalent (as a JSON subtree) to the same
    /// section declared on a hand-built descriptor via
    /// `SchemaSection.Kind.openStringMap` — the bridge cannot drift from the
    /// descriptor capability it reaches.
    func testEmitMatchesHandBuiltDescriptorSection() throws {
        let descriptor = SchemaDescriptor(
            title: "open-string-map fixture",
            sections: [SchemaSection(
                "alias", .openStringMap(valueDoc: "facet filter expression"),
                doc: "Filter aliases: NAME = 'filter expr'.")])
        let fromSpec = try aliasSubtree(of: Self.spec.jsonSchema())
        let fromDescriptor = try aliasSubtree(of: descriptor.jsonSchema())
        XCTAssertEqual(NSDictionary(dictionary: fromSpec),
                       NSDictionary(dictionary: fromDescriptor))
    }

    /// A dotted header folds the open map into its parent object, so a
    /// non-top-level `[cast.alias]` gets the same typed value schema.
    func testDottedHeaderFoldsIntoParent() throws {
        let spec = ConfigSchema.Spec<Cfg>(
            title: "dotted",
            sections: [
                ConfigSchema.Section("cast", fields: [
                    ConfigSchema.Field(key: "fps", kind: .scalar(.integer),
                                       apply: { _, _ in }, doc: "frame rate"),
                ]),
                ConfigSchema.Section("cast.alias",
                                     kind: .openStringMap(valueDoc: "expr"),
                                     doc: "nested aliases"),
            ])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(spec.jsonSchema().utf8)) as? [String: Any])
        let props = try XCTUnwrap(root["properties"] as? [String: Any])
        let cast = try XCTUnwrap(props["cast"] as? [String: Any])
        let castProps = try XCTUnwrap(cast["properties"] as? [String: Any])
        let alias = try XCTUnwrap(castProps["alias"] as? [String: Any])
        let ap = try XCTUnwrap(alias["additionalProperties"] as? [String: Any])
        XCTAssertEqual(ap["type"] as? String, "string")
    }

    // MARK: - validate

    func testValidateAcceptsAllStringValues() throws {
        let root = try Toml.parse("""
        [alias]
        web = 'app~=Chrome or app~=Safari'
        term = 'app~=Terminal'
        """)
        XCTAssertEqual(Self.spec.validate(root), [])
    }

    func testValidateRejectsNonStringValue() throws {
        let root = try Toml.parse("""
        [alias]
        web = 'app~=Chrome'
        bad = 42
        """)
        let errors = Self.spec.validate(root)
        XCTAssertEqual(errors.count, 1)
        let message = try XCTUnwrap(errors.first?.message)
        XCTAssertTrue(message.contains("alias.bad"),
                      "path should name the offending key: \(message)")
        XCTAssertTrue(message.lowercased().contains("string"),
                      "should demand a string value: \(message)")
    }

    // MARK: - decode

    /// `decode` drives `.table` sections only — an `.openStringMap` section is
    /// skipped (the app decodes its open map itself), same as `.dynamicTable`.
    func testDecodeSkipsOpenStringMapSections() {
        var applied: [String] = []
        let spec = ConfigSchema.Spec<Cfg>(
            title: "decode-skip",
            sections: [
                ConfigSchema.Section("grid", fields: [
                    ConfigSchema.Field(key: "mode", kind: .scalar(.string),
                                       apply: { _, _ in applied.append("grid.mode") },
                                       doc: "layout mode"),
                ]),
                ConfigSchema.Section("alias",
                                     kind: .openStringMap(valueDoc: "expr"),
                                     doc: "aliases"),
            ])
        var cfg = Cfg()
        let tables: [String: [String: Toml.Value]] = [
            "grid": ["mode": .string("wide")],
            "alias": ["web": .string("app~=Chrome")],
        ]
        spec.decode(tables, into: &cfg)
        XCTAssertEqual(applied, ["grid.mode"])
    }
}
