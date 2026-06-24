import XCTest
@testable import ConfigSchema

/// Exercises the decode-free `SchemaDescriptor` family and its JSON-Schema
/// emitter (the chord #138 emit machinery, generalised into sill). A single
/// synthetic descriptor touches EVERY field shape, cross-field rule, section
/// kind, vendor extension, and `EmitOptions` knob, so a lowering regression
/// surfaces here rather than only in a consumer's byte-drift guard.
final class SchemaDescriptorTests: XCTestCase {

    // MARK: - Fixture: one descriptor that uses every feature

    /// A binding-like array-of-tables item that exercises field shapes,
    /// cross-field rules, a nested array-of-tables, initKeys, constraints, and
    /// a `rejected` (recognised-to-reject) field.
    private func bindingShape() -> ObjectShape {
        ObjectShape(
            fields: [
                SchemaField("name", .string, doc: "Display name."),
                SchemaField("input", .string, doc: "Trigger string."),
                SchemaField("action-shell", .string, doc: "Shell command."),
                SchemaField("action-keys", .stringOrStringArray, doc: "Keystroke(s)."),
                SchemaField("action-noop", .constTrue, doc: "Consume and do nothing."),
                SchemaField("action-set-var", .string, doc: "Set a variable."),
                SchemaField("action-set-value", .integer, doc: "Value for action-set-var.", defaultInt: 1),
                SchemaField("when-vars", .intMap, doc: "AND gate."),
                SchemaField("repeat", .string, doc: "Key-repeat handling.",
                            enumDomain: ["fire-each", "ignore", "passthrough"],
                            enumDocs: ["Fire each tick.", nil, "Let repeats through."]),
                SchemaField("hold-while-timeout", .integer,
                            doc: "Clear after ms of inactivity.", exclusiveMinimum: 0),
                SchemaField("passthrough", .boolean, doc: "Pass the original event.", defaultBool: false),
                // recognised-to-reject: in the keySet, OUT of the schema.
                SchemaField("action-toggle-var-on-up", .string,
                            doc: "Invalid form.", rejected: true),
            ],
            required: ["input"],
            exclusions: [
                .anyOfRequired(["action-shell", "action-keys", "action-noop", "action-set-var"]),
                .dependency(key: "action-set-value", needs: "action-set-var"),
                .forbidsTogether(["hold-while", "hold-while-timeout"]),
            ],
            nested: [NestedTable(key: "per-app", item: perAppShape(), nonEmpty: true)],
            doc: "A binding.",
            initKeys: ["input", "action-keys"],
            constraints: ["`@name` must be defined.", "Names must be unique."])
    }

    private func perAppShape() -> ObjectShape {
        ObjectShape(
            fields: [
                SchemaField("bundle-id", .string, doc: "App id."),
                SchemaField("map", .stringMap, doc: "source → action."),
            ],
            required: ["bundle-id"],
            doc: "Per-app override.")
    }

    private func fallbackShape() -> ObjectShape {
        ObjectShape(
            fields: [
                SchemaField("input", .string, doc: "Trigger."),
                SchemaField("inputs", .stringArray, doc: "Triggers."),
            ],
            exclusions: [.oneOfRequired(["input", "inputs"])],
            doc: "Fallback.")
    }

    private func descriptor() -> SchemaDescriptor {
        SchemaDescriptor(
            title: "demo config",
            comment: "demo INPUT schema. Regenerate with `demo --emit-schema`.",
            sections: [
                SchemaSection("options",
                    .table(ObjectShape(fields: [
                        SchemaField("verbose", .boolean, doc: "Chatty.", defaultBool: false),
                    ], doc: "Global options.")),
                    doc: "Global options."),
                SchemaSection("action-aliases",
                    .openStringMap(valueDoc: "Shell command body."),
                    doc: "name → shell command."),
                SchemaSection("v-key-aliases",
                    .openIntMap(valueDoc: "Vendor id 1–255.", min: 1, max: 255),
                    doc: "name → vendor id."),
                SchemaSection("bindings", .arrayOfTables(bindingShape()),
                    doc: "The bindings."),
                SchemaSection("fallbacks", .arrayOfTables(fallbackShape()),
                    doc: "Catch-all bindings."),
            ])
    }

    private func emitted(_ options: SchemaDescriptor.EmitOptions = .init()) throws -> [String: Any] {
        let text = descriptor().jsonSchema(options: options)
        let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        return try XCTUnwrap(obj)
    }

    private func bindingItem(_ root: [String: Any]) throws -> [String: Any] {
        let props = try XCTUnwrap(root["properties"] as? [String: Any])
        let bindings = try XCTUnwrap(props["bindings"] as? [String: Any])
        return try XCTUnwrap(bindings["items"] as? [String: Any])
    }

    // MARK: - Root

    func testRootIsStrictDraft07WithCommentAndSections() throws {
        let root = try emitted()
        XCTAssertEqual(root["$schema"] as? String, "http://json-schema.org/draft-07/schema#")
        XCTAssertEqual(root["title"] as? String, "demo config")
        XCTAssertEqual(root["type"] as? String, "object")
        XCTAssertEqual(root["additionalProperties"] as? Bool, false)
        XCTAssertEqual(root["$comment"] as? String,
                       "demo INPUT schema. Regenerate with `demo --emit-schema`.")
        let props = try XCTUnwrap(root["properties"] as? [String: Any])
        XCTAssertEqual(Set(props.keys),
                       ["options", "action-aliases", "v-key-aliases", "bindings", "fallbacks"])
    }

    func testCommentOmittedWhenNil() throws {
        let d = SchemaDescriptor(title: "no comment", sections: [])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(d.jsonSchema().utf8)) as? [String: Any])
        XCTAssertNil(obj["$comment"])
    }

    // MARK: - Field shapes

    func testScalarShapes() throws {
        let props = try XCTUnwrap(bindingItem(try emitted())["properties"] as? [String: Any])
        XCTAssertEqual((props["input"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertEqual((props["action-set-value"] as? [String: Any])?["type"] as? String, "integer")
        XCTAssertEqual((props["passthrough"] as? [String: Any])?["type"] as? String, "boolean")
    }

    func testStringOrStringArrayIsOneOf() throws {
        let props = try XCTUnwrap(bindingItem(try emitted())["properties"] as? [String: Any])
        let field = try XCTUnwrap(props["action-keys"] as? [String: Any])
        let oneOf = try XCTUnwrap(field["oneOf"] as? [[String: Any]])
        XCTAssertEqual(oneOf.count, 2)
        XCTAssertEqual(oneOf[0]["type"] as? String, "string")
        XCTAssertEqual(oneOf[1]["type"] as? String, "array")
    }

    func testStringArrayShape() throws {
        let root = try emitted()
        let props = try XCTUnwrap(root["properties"] as? [String: Any])
        let fb = try XCTUnwrap((props["fallbacks"] as? [String: Any])?["items"] as? [String: Any])
        let fbProps = try XCTUnwrap(fb["properties"] as? [String: Any])
        let inputs = try XCTUnwrap(fbProps["inputs"] as? [String: Any])
        XCTAssertEqual(inputs["type"] as? String, "array")
        XCTAssertEqual((inputs["items"] as? [String: Any])?["type"] as? String, "string")
    }

    func testConstTrueShape() throws {
        let props = try XCTUnwrap(bindingItem(try emitted())["properties"] as? [String: Any])
        XCTAssertEqual((props["action-noop"] as? [String: Any])?["const"] as? Bool, true)
    }

    func testIntMapShape() throws {
        let props = try XCTUnwrap(bindingItem(try emitted())["properties"] as? [String: Any])
        let field = try XCTUnwrap(props["when-vars"] as? [String: Any])
        XCTAssertEqual(field["type"] as? String, "object")
        XCTAssertEqual(field["minProperties"] as? Int, 1)
        XCTAssertEqual((field["additionalProperties"] as? [String: Any])?["type"] as? String, "integer")
    }

    func testStringMapShape() throws {
        let root = try emitted()
        let props = try XCTUnwrap(root["properties"] as? [String: Any])
        let binding = try bindingItem(root)
        let perApp = try XCTUnwrap(
            (binding["properties"] as? [String: Any])?["per-app"] as? [String: Any])
        let item = try XCTUnwrap(perApp["items"] as? [String: Any])
        let map = try XCTUnwrap((item["properties"] as? [String: Any])?["map"] as? [String: Any])
        XCTAssertEqual(map["type"] as? String, "object")
        XCTAssertEqual((map["additionalProperties"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertNil(map["minProperties"], "stringMap has no minProperties (unlike intMap)")
        _ = props
    }

    func testDefaultsAndExclusiveMinimum() throws {
        let props = try XCTUnwrap(bindingItem(try emitted())["properties"] as? [String: Any])
        XCTAssertEqual((props["action-set-value"] as? [String: Any])?["default"] as? Int, 1)
        XCTAssertEqual((props["passthrough"] as? [String: Any])?["default"] as? Bool, false)
        XCTAssertEqual((props["hold-while-timeout"] as? [String: Any])?["exclusiveMinimum"] as? Int, 0)
    }

    // MARK: - Enum + per-value hover

    func testEnumAndEnumDocsAlignIndexWise() throws {
        let props = try XCTUnwrap(bindingItem(try emitted())["properties"] as? [String: Any])
        let field = try XCTUnwrap(props["repeat"] as? [String: Any])
        XCTAssertEqual(field["enum"] as? [String], ["fire-each", "ignore", "passthrough"])
        let xtaplo = try XCTUnwrap(field["x-taplo"] as? [String: Any])
        let docs = try XCTUnwrap(xtaplo["docs"] as? [String: Any])
        let enumDocs = try XCTUnwrap(docs["enumValues"] as? [Any])
        XCTAssertEqual(enumDocs.count, 3, "enumValues must be index-aligned to enum")
        XCTAssertEqual(enumDocs[0] as? String, "Fire each tick.")
        XCTAssertTrue(enumDocs[1] is NSNull, "a nil enumDoc entry lowers to JSON null")
        XCTAssertEqual(enumDocs[2] as? String, "Let repeats through.")
    }

    // MARK: - Cross-field rules

    func testAnyOfRequiredBecomesAllOfAnyOf() throws {
        let allOf = try XCTUnwrap(bindingItem(try emitted())["allOf"] as? [[String: Any]])
        let clause = allOf.first { $0["anyOf"] != nil }
        let anyOf = try XCTUnwrap(clause?["anyOf"] as? [[String: Any]])
        let required = anyOf.compactMap { ($0["required"] as? [String])?.first }
        XCTAssertEqual(Set(required), ["action-shell", "action-keys", "action-noop", "action-set-var"])
    }

    func testOneOfRequiredBecomesAllOfOneOf() throws {
        let root = try emitted()
        let props = try XCTUnwrap(root["properties"] as? [String: Any])
        let fb = try XCTUnwrap((props["fallbacks"] as? [String: Any])?["items"] as? [String: Any])
        let allOf = try XCTUnwrap(fb["allOf"] as? [[String: Any]])
        let clause = try XCTUnwrap(allOf.first { $0["oneOf"] != nil })
        let oneOf = try XCTUnwrap(clause["oneOf"] as? [[String: Any]])
        let required = oneOf.compactMap { ($0["required"] as? [String])?.first }
        XCTAssertEqual(Set(required), ["input", "inputs"])
    }

    func testForbidsTogetherBecomesNot() throws {
        let allOf = try XCTUnwrap(bindingItem(try emitted())["allOf"] as? [[String: Any]])
        let clause = try XCTUnwrap(allOf.first { $0["not"] != nil })
        let not = try XCTUnwrap(clause["not"] as? [String: Any])
        XCTAssertEqual(Set(not["required"] as? [String] ?? []), ["hold-while", "hold-while-timeout"])
    }

    func testDependencyBecomesDependencies() throws {
        let item = try bindingItem(try emitted())
        let deps = try XCTUnwrap(item["dependencies"] as? [String: Any])
        XCTAssertEqual(deps["action-set-value"] as? [String], ["action-set-var"])
    }

    func testRequiredEmitted() throws {
        XCTAssertEqual(try bindingItem(try emitted())["required"] as? [String], ["input"])
    }

    // MARK: - Nested array-of-tables

    func testNestedTableIsArrayWithMinItems() throws {
        let binding = try bindingItem(try emitted())
        let perApp = try XCTUnwrap(
            (binding["properties"] as? [String: Any])?["per-app"] as? [String: Any])
        XCTAssertEqual(perApp["type"] as? String, "array")
        XCTAssertEqual(perApp["minItems"] as? Int, 1, "nonEmpty nested table → minItems:1")
        let item = try XCTUnwrap(perApp["items"] as? [String: Any])
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        XCTAssertEqual(item["required"] as? [String], ["bundle-id"])
    }

    // MARK: - Vendor extensions

    func testInitKeysAndConstraints() throws {
        let item = try bindingItem(try emitted(.init(constraintsKey: "x-demo-constraints")))
        XCTAssertEqual((item["x-taplo"] as? [String: Any])?["initKeys"] as? [String],
                       ["input", "action-keys"])
        XCTAssertEqual(item["x-demo-constraints"] as? [String],
                       ["`@name` must be defined.", "Names must be unique."])
    }

    func testConstraintsKeyIsConfigurable() throws {
        let item = try bindingItem(try emitted(.init(constraintsKey: "x-chord-constraints")))
        XCTAssertNotNil(item["x-chord-constraints"], "constraints emit under the chosen vendor key")
        XCTAssertNil(item["x-constraints"], "the default key is not used when overridden")
    }

    // MARK: - rejected fields

    func testRejectedFieldInKeySetButNotInSchema() throws {
        XCTAssertTrue(bindingShape().keySet.contains("action-toggle-var-on-up"),
                      "rejected key stays in keySet so the unknown-key check recognises it")
        let props = try XCTUnwrap(bindingItem(try emitted())["properties"] as? [String: Any])
        XCTAssertNil(props["action-toggle-var-on-up"], "rejected key is omitted from the schema")
    }

    func testKeySetExcludesVendorKeys() {
        let keySet = bindingShape().keySet
        XCTAssertTrue(keySet.contains("input"))
        XCTAssertTrue(keySet.contains("per-app"), "a nested table key is part of the keySet")
        XCTAssertFalse(keySet.contains("x-taplo"))
        XCTAssertFalse(keySet.contains("x-constraints"))
    }

    // MARK: - Open-map sections

    func testOpenStringMapSection() throws {
        let props = try XCTUnwrap(try emitted()["properties"] as? [String: Any])
        let aliases = try XCTUnwrap(props["action-aliases"] as? [String: Any])
        XCTAssertEqual(aliases["type"] as? String, "object")
        let ap = try XCTUnwrap(aliases["additionalProperties"] as? [String: Any])
        XCTAssertEqual(ap["type"] as? String, "string")
        XCTAssertEqual(ap["description"] as? String, "Shell command body.")
    }

    func testOpenIntMapSection() throws {
        let props = try XCTUnwrap(try emitted()["properties"] as? [String: Any])
        let vkeys = try XCTUnwrap(props["v-key-aliases"] as? [String: Any])
        let ap = try XCTUnwrap(vkeys["additionalProperties"] as? [String: Any])
        XCTAssertEqual(ap["type"] as? String, "integer")
        XCTAssertEqual(ap["minimum"] as? Int, 1)
        XCTAssertEqual(ap["maximum"] as? Int, 255)
    }

    func testArrayOfTablesCarriesSectionAndItemDocs() throws {
        let props = try XCTUnwrap(try emitted()["properties"] as? [String: Any])
        let bindings = try XCTUnwrap(props["bindings"] as? [String: Any])
        XCTAssertEqual(bindings["type"] as? String, "array")
        XCTAssertEqual(bindings["description"] as? String, "The bindings.",
                       "the array node carries the SECTION doc")
        let item = try XCTUnwrap(bindings["items"] as? [String: Any])
        XCTAssertEqual(item["description"] as? String, "A binding.",
                       "the item node carries the SHAPE doc")
    }

    // MARK: - EmitOptions byte knobs

    func testSlashEscapingKnob() {
        let escaped = descriptor().jsonSchema(options: .init(escapeSlashes: true))
        XCTAssertTrue(escaped.contains(#"http:\/\/json-schema.org"#),
                      "default escapes slashes (JSONSerialization baseline)")
        let bare = descriptor().jsonSchema(options: .init(escapeSlashes: false))
        XCTAssertTrue(bare.contains("http://json-schema.org"))
        XCTAssertFalse(bare.contains(#"\/"#))
    }

    func testTrailingNewlineKnob() {
        XCTAssertFalse(descriptor().jsonSchema().hasSuffix("\n"),
                       "default emits no trailing newline")
        XCTAssertTrue(descriptor().jsonSchema(options: .init(trailingNewline: true)).hasSuffix("}\n"))
    }

    // MARK: - Determinism

    func testEmissionIsDeterministic() {
        XCTAssertEqual(descriptor().jsonSchema(), descriptor().jsonSchema())
        let opts = SchemaDescriptor.EmitOptions(escapeSlashes: false, trailingNewline: true,
                                                constraintsKey: "x-demo")
        XCTAssertEqual(descriptor().jsonSchema(options: opts),
                       descriptor().jsonSchema(options: opts))
    }

    // MARK: - Negative paths: optional keys are OMITTED when their source is empty

    /// A deliberately "bare" array-of-tables item: a single field with an enum
    /// but NO enumDocs and an EMPTY doc, and a shape with no required /
    /// exclusions / initKeys / constraints / sectionDoc. Exercises every
    /// `if !…isEmpty` / `if let` omission branch in the emitter — the negative
    /// of the happy-path fixture above.
    private func bareEmitted() throws -> [String: Any] {
        let d = SchemaDescriptor(title: "bare", sections: [
            SchemaSection("rows", .arrayOfTables(ObjectShape(fields: [
                SchemaField("mode", .string, doc: "",        // empty doc → no description
                            enumDomain: ["a", "b"]),          // enum, but no enumDocs → no x-taplo
            ])), doc: "rows section"),                        // section doc on the ARRAY node only
        ])
        let obj = try JSONSerialization.jsonObject(with: Data(d.jsonSchema().utf8)) as? [String: Any]
        let props = try XCTUnwrap((try XCTUnwrap(obj)["properties"] as? [String: Any]))
        let rows = try XCTUnwrap(props["rows"] as? [String: Any])
        return try XCTUnwrap(rows["items"] as? [String: Any])
    }

    func testEmptyFieldDocOmitsDescription() throws {
        let field = try XCTUnwrap((bareEmitted()["properties"] as? [String: Any])?["mode"] as? [String: Any])
        XCTAssertEqual(field["enum"] as? [String], ["a", "b"])
        XCTAssertNil(field["description"], "an empty doc string must not emit a description key")
    }

    func testEnumWithoutEnumDocsOmitsXTaplo() throws {
        let field = try XCTUnwrap((bareEmitted()["properties"] as? [String: Any])?["mode"] as? [String: Any])
        XCTAssertNil(field["x-taplo"], "enumDomain without enumDocs must not emit x-taplo.docs")
    }

    func testEmptyShapeOmitsAllOptionalKeys() throws {
        let item = try bareEmitted()
        XCTAssertNil(item["required"], "empty required → no required key")
        XCTAssertNil(item["allOf"], "no exclusions → no allOf key")
        XCTAssertNil(item["dependencies"], "no dependency rule → no dependencies key")
        XCTAssertNil(item["x-taplo"], "empty initKeys → no object-level x-taplo")
        XCTAssertNil(item["x-constraints"], "empty constraints → no vendor key")
        XCTAssertNil(item["description"], "empty shape doc → no item description")
        XCTAssertEqual(item["additionalProperties"] as? Bool, false, "strict object regardless")
    }

    func testAllNilEnumDocsLowerToAllNull() throws {
        let d = SchemaDescriptor(title: "t", sections: [
            SchemaSection("rows", .arrayOfTables(ObjectShape(fields: [
                SchemaField("k", .string, doc: "x",
                            enumDomain: ["a", "b", "c"],
                            enumDocs: [nil, nil, nil]),
            ])), doc: "d"),
        ])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(d.jsonSchema().utf8)) as? [String: Any])
        let item = try XCTUnwrap(((obj["properties"] as? [String: Any])?["rows"] as? [String: Any])?["items"] as? [String: Any])
        let field = try XCTUnwrap((item["properties"] as? [String: Any])?["k"] as? [String: Any])
        let enumDocs = try XCTUnwrap(((field["x-taplo"] as? [String: Any])?["docs"] as? [String: Any])?["enumValues"] as? [Any])
        XCTAssertEqual(enumDocs.count, 3)
        XCTAssertTrue(enumDocs.allSatisfy { $0 is NSNull }, "an all-nil enumDocs lowers to [null, null, null]")
    }

    func testMultipleNestedTablesInOneShape() throws {
        let leaf = ObjectShape(fields: [SchemaField("v", .string, doc: "v")])
        let d = SchemaDescriptor(title: "t", sections: [
            SchemaSection("rows", .arrayOfTables(ObjectShape(
                fields: [SchemaField("id", .string, doc: "id")],
                nested: [NestedTable(key: "per-app", item: leaf),
                         NestedTable(key: "per-space", item: leaf, nonEmpty: true)])),
                doc: "rows"),
        ])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(d.jsonSchema().utf8)) as? [String: Any])
        let item = try XCTUnwrap(((obj["properties"] as? [String: Any])?["rows"] as? [String: Any])?["items"] as? [String: Any])
        let props = try XCTUnwrap(item["properties"] as? [String: Any])
        let perApp = try XCTUnwrap(props["per-app"] as? [String: Any])
        let perSpace = try XCTUnwrap(props["per-space"] as? [String: Any])
        XCTAssertEqual(perApp["type"] as? String, "array")
        XCTAssertNil(perApp["minItems"], "a non-nonEmpty nested table has no minItems")
        XCTAssertEqual(perSpace["minItems"] as? Int, 1, "the nonEmpty nested table keeps minItems:1")
        // Both nested keys join the keySet.
        let shape = ObjectShape(fields: [SchemaField("id", .string, doc: "id")],
                                nested: [NestedTable(key: "per-app", item: leaf),
                                         NestedTable(key: "per-space", item: leaf)])
        XCTAssertEqual(shape.keySet, ["id", "per-app", "per-space"])
    }

    // MARK: - #138 S3: shared vocabulary additions (number / bounds / typed
    // defaults / array-item enum / permissive object / nested single object).
    // These let `Spec.jsonSchema()` route through this emitter; they are also
    // available to a descriptor written by hand (perch/wand).

    /// One table exercising every S3 leaf addition.
    private func s3Fields() throws -> [String: Any] {
        let d = SchemaDescriptor(title: "t", sections: [
            SchemaSection("opts", .table(ObjectShape(fields: [
                SchemaField("scale", .number, doc: "A float.",
                            defaultNumber: 0.9, minimum: 0.1, maximum: 30),
                SchemaField("name", .string, doc: "", defaultString: "tree"),
                SchemaField("pets", .stringArray, doc: "",
                            arrayItemEnum: ["chomp", "ghost"],
                            defaultStringArray: ["chomp"]),
            ])), doc: "opts"),
        ])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(d.jsonSchema().utf8)) as? [String: Any])
        return try XCTUnwrap((obj["properties"] as? [String: Any])?["opts"] as? [String: Any])
    }

    func testNumberShapeAndInclusiveBounds() throws {
        let props = try XCTUnwrap(s3Fields()["properties"] as? [String: Any])
        let scale = try XCTUnwrap(props["scale"] as? [String: Any])
        XCTAssertEqual(scale["type"] as? String, "number")
        XCTAssertEqual(scale["default"] as? Double, 0.9)
        // Inclusive bounds carried as Double; a whole one still serialises clean.
        XCTAssertEqual(scale["maximum"] as? Int, 30)
        XCTAssertEqual(scale["minimum"] as? Double, 0.1)
    }

    func testTypedDefaultsStringAndNumberAndArray() throws {
        let props = try XCTUnwrap(s3Fields()["properties"] as? [String: Any])
        XCTAssertEqual((props["name"] as? [String: Any])?["default"] as? String, "tree")
        let pets = try XCTUnwrap(props["pets"] as? [String: Any])
        XCTAssertEqual(pets["default"] as? [String], ["chomp"])
        XCTAssertEqual((pets["items"] as? [String: Any])?["enum"] as? [String], ["chomp", "ghost"])
    }

    /// A whole-valued `Double` bound must render as `30`, not `30.0`.
    func testWholeDoubleBoundRendersClean() throws {
        let d = SchemaDescriptor(title: "t", sections: [
            SchemaSection("o", .table(ObjectShape(fields: [
                SchemaField("n", .integer, doc: "", minimum: 1, maximum: 12),
            ])), doc: "o"),
        ])
        let raw = d.jsonSchema()
        XCTAssertTrue(raw.contains("\"maximum\" : 12"))
        XCTAssertFalse(raw.contains("12.0"))
        XCTAssertFalse(raw.contains("1.0"))
    }

    func testPermissiveObjectAndNestedSingleObject() throws {
        // A strict parent table holding one permissive child object and one
        // strict child object (the dotted-header fold target).
        let permissiveChild = ObjectShape(fields: [], doc: "Dynamic names.", permissive: true)
        let strictChild = ObjectShape(fields: [SchemaField("enabled", .boolean, doc: "")])
        let parent = ObjectShape(
            fields: [SchemaField("button", .string, doc: "")],
            objects: [NestedObject(key: "themes", shape: permissiveChild),
                      NestedObject(key: "overlay", shape: strictChild)],
            doc: "Parent.")
        let d = SchemaDescriptor(title: "t", sections: [
            SchemaSection("cast", .table(parent), doc: "cast"),
        ])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(d.jsonSchema().utf8)) as? [String: Any])
        let cast = try XCTUnwrap((obj["properties"] as? [String: Any])?["cast"] as? [String: Any])
        XCTAssertEqual(cast["additionalProperties"] as? Bool, false)
        let castProps = try XCTUnwrap(cast["properties"] as? [String: Any])
        XCTAssertNotNil(castProps["button"], "own field sits beside nested objects")

        // Permissive child: additionalProperties true, NO properties map.
        let themes = try XCTUnwrap(castProps["themes"] as? [String: Any])
        XCTAssertEqual(themes["additionalProperties"] as? Bool, true)
        XCTAssertNil(themes["properties"], "an empty permissive object omits properties")
        XCTAssertEqual(themes["description"] as? String, "Dynamic names.")

        // Strict child: additionalProperties false, with its own properties.
        let overlay = try XCTUnwrap(castProps["overlay"] as? [String: Any])
        XCTAssertEqual(overlay["additionalProperties"] as? Bool, false)
        XCTAssertNotNil((overlay["properties"] as? [String: Any])?["enabled"])

        // Nested-object keys join the keySet.
        XCTAssertEqual(parent.keySet, ["button", "themes", "overlay"])
    }

    func testNonPermissiveDefaultUnchanged() throws {
        // The permissive flag defaults false: an ordinary table is still strict
        // (guards the chord byte-identity — chord never sets `permissive`).
        let item = try bindingItem(try emitted())
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
    }
}
