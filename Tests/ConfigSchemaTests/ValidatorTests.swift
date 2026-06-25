import XCTest
import Toml
@testable import ConfigSchema

/// Exercises `SchemaDescriptor.validate` (issue #155): the generic runtime
/// validator runs the SAME structural + cross-field rules the emitter lowers to
/// Draft-07, over a decoded `Toml.parse` document. One fixture descriptor (a
/// binding-like array-of-tables + open maps + a table section) is validated
/// against hand-written valid / invalid TOML so a rule regression surfaces here.
///
/// The contract under test: "editor green" (taplo vs the emitted schema) and
/// "loader accepts it" (this validator) cannot diverge — both read the descriptor.
final class ValidatorTests: XCTestCase {

    // MARK: - Fixture (mirrors SchemaDescriptorTests' shape, tuned for validation)

    private func bindingShape() -> ObjectShape {
        ObjectShape(
            fields: [
                SchemaField("name", .string, doc: "Display name."),
                SchemaField("input", .string, doc: "Trigger."),
                SchemaField("action-keys", .stringOrStringArray, doc: "Keystroke(s)."),
                SchemaField("action-noop", .constTrue, doc: "Consume."),
                SchemaField("action-set-var", .string, doc: "Set a variable."),
                SchemaField("action-set-value", .integer, doc: "Value.", defaultInt: 1),
                SchemaField("repeat", .string, doc: "Repeat handling.",
                            enumDomain: ["fire-each", "ignore", "passthrough"]),
                SchemaField("hold-while", .string, doc: "Modifier mask."),
                SchemaField("hold-while-timeout", .integer,
                            doc: "Inactivity timeout.", exclusiveMinimum: 0),
                SchemaField("when-vars", .intMap, doc: "AND gate."),
            ],
            required: ["input"],
            exclusions: [
                .anyOfRequired(["action-keys", "action-set-var", "action-noop"]),
                .dependency(key: "action-set-value", needs: "action-set-var"),
                .forbidsTogether(["hold-while", "hold-while-timeout"]),
            ],
            nested: [NestedTable(key: "per-app", item: perAppShape(), nonEmpty: true)],
            doc: "A binding.")
    }

    private func perAppShape() -> ObjectShape {
        ObjectShape(
            fields: [SchemaField("bundle-id", .string, doc: "App id.")],
            required: ["bundle-id"], doc: "Per-app override.")
    }

    private func fallbackShape() -> ObjectShape {
        ObjectShape(
            fields: [
                SchemaField("input", .string, doc: "Trigger."),
                SchemaField("inputs", .stringArray, doc: "Triggers."),
                SchemaField("action-keys", .stringOrStringArray, doc: "Keystroke(s)."),
            ],
            exclusions: [.oneOfRequired(["input", "inputs"])],
            doc: "Fallback.")
    }

    private func descriptor() -> SchemaDescriptor {
        SchemaDescriptor(title: "demo", sections: [
            SchemaSection("options", .table(ObjectShape(fields: [
                SchemaField("verbose", .boolean, doc: "Chatty.", defaultBool: false),
                SchemaField("scale", .number, doc: "Float.", minimum: 0.1, maximum: 30),
            ], doc: "Options.")), doc: "Options."),
            SchemaSection("v-key-aliases",
                .openIntMap(valueDoc: "1–255.", min: 1, max: 255), doc: "vkeys."),
            SchemaSection("action-aliases",
                .openStringMap(valueDoc: "Shell body."), doc: "aliases."),
            SchemaSection("bindings", .arrayOfTables(bindingShape()), doc: "Bindings."),
            SchemaSection("fallbacks", .arrayOfTables(fallbackShape()), doc: "Fallbacks."),
        ])
    }

    private func validate(_ toml: String) throws -> [ValidationError] {
        descriptor().validate(try Toml.parse(toml))
    }

    private func rules(_ errors: [ValidationError]) -> [ValidationError.Rule] {
        errors.map(\.rule)
    }

    // MARK: - Happy path

    func testFullyValidDocumentHasNoErrors() throws {
        let errs = try validate("""
        [options]
        verbose = true
        scale = 1.5

        [v-key-aliases]
        hyper = 42

        [action-aliases]
        focus = "open -a Foo"

        [[bindings]]
        name = "copy"
        input = "cmd - c"
        action-keys = ["cmd - a", "cmd - c"]

        [[bindings]]
        input = "cmd - m"
        action-set-var = "mode"
        action-set-value = 2
        when-vars = { a = 1, b = 2 }

          [[bindings.per-app]]
          bundle-id = "com.foo"

        [[fallbacks]]
        input = "*"
        action-keys = "cmd - z"
        """)
        XCTAssertEqual(errs, [], "a fully valid document validates clean: \(errs.map(\.message))")
    }

    // MARK: - Structural: unknown-key / required / type

    func testUnknownKeyFlagged() throws {
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-keys = "cmd - v"
        actoin-keys = "typo"
        """)
        XCTAssertTrue(errs.contains { if case .unknownKey(let k) = $0.rule { return k == "actoin-keys" }; return false },
                      "a typo'd key is an unknownKey: \(errs.map(\.message))")
    }

    func testRequiredKeyMissing() throws {
        let errs = try validate("""
        [[bindings]]
        action-keys = "cmd - v"
        """)
        XCTAssertTrue(errs.contains { if case .requiredMissing(let k) = $0.rule { return k == "input" }; return false })
    }

    func testTypeMismatchIntegerFieldGivenString() throws {
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-set-var = "m"
        action-set-value = "two"
        """)
        XCTAssertTrue(errs.contains { if case .typeMismatch(let k, _) = $0.rule { return k == "action-set-value" }; return false })
    }

    func testStringArrayWithNonStringElement() throws {
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-keys = ["cmd - a", 42]
        """)
        XCTAssertTrue(errs.contains { if case .typeMismatch = $0.rule { return true }; return false },
                      "a non-string array element is a type mismatch")
    }

    // MARK: - enum / range

    func testEnumViolation() throws {
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-keys = "cmd - v"
        repeat = "sometimes"
        """)
        XCTAssertTrue(errs.contains { if case .notInEnum(let k, let v, _) = $0.rule { return k == "repeat" && v == "sometimes" }; return false })
    }

    func testExclusiveMinimumViolation() throws {
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-keys = "cmd - v"
        hold-while-timeout = 0
        """)
        XCTAssertTrue(errs.contains { if case .outOfRange(let k, _) = $0.rule { return k == "hold-while-timeout" }; return false })
    }

    func testNumberInclusiveBoundsViolation() throws {
        let errs = try validate("""
        [options]
        scale = 99.0
        """)
        XCTAssertTrue(errs.contains { if case .outOfRange(let k, _) = $0.rule { return k == "scale" }; return false })
    }

    func testConstTrueRejectsFalse() throws {
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-noop = false
        """)
        XCTAssertTrue(errs.contains { if case .notInEnum(let k, _, _) = $0.rule { return k == "action-noop" }; return false },
                      "constTrue field set to false is rejected")
    }

    // MARK: - cross-field

    func testAnyOfRequiredViolation() throws {
        // input present but NO action-* → anyOfRequired fails.
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        """)
        XCTAssertTrue(errs.contains { if case .anyOfRequired = $0.rule { return true }; return false })
    }

    func testDependencyViolation() throws {
        // action-set-value without action-set-var.
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-keys = "cmd - v"
        action-set-value = 3
        """)
        XCTAssertTrue(errs.contains { if case .dependency(let k, let n) = $0.rule { return k == "action-set-value" && n == "action-set-var" }; return false })
    }

    func testForbidsTogetherViolation() throws {
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-set-var = "m"
        hold-while = "cmd"
        hold-while-timeout = 800
        """)
        XCTAssertTrue(errs.contains { if case .forbidsTogether = $0.rule { return true }; return false })
    }

    func testOneOfRequiredViolation() throws {
        // fallbacks: both input and inputs → oneOf fails (count 2).
        let errs = try validate("""
        [[fallbacks]]
        input = "a"
        inputs = ["b", "c"]
        action-keys = "cmd - z"
        """)
        XCTAssertTrue(errs.contains { if case .oneOfRequired(_, let n) = $0.rule { return n == 2 }; return false })
    }

    // MARK: - nested array-of-tables

    func testNestedPerAppRequiredFieldMissing() throws {
        let errs = try validate("""
        [[bindings]]
        input = "cmd - c"
        action-keys = "cmd - v"

          [[bindings.per-app]]
          # bundle-id missing
          name = "x"
        """)
        XCTAssertTrue(errs.contains {
            if case .requiredMissing(let k) = $0.rule { return k == "bundle-id" }; return false
        }, "a missing required key inside a nested table is reported")
        // path includes the array index of the per-app row.
        XCTAssertTrue(errs.contains { $0.pathString.contains("per-app") })
    }

    func testNonEmptyNestedTableEmptyIsFlagged() throws {
        // per-app declared but empty (no [[bindings.per-app]] rows) — represent
        // as an explicit empty array-of-tables.
        let doc: [String: Toml.Value] = [
            "bindings": .arrayOfTables([
                Toml.Row(fields: [
                    "input": .string("cmd - c"),
                    "action-keys": .string("cmd - v"),
                    "per-app": .arrayOfTables([]),
                ]),
            ]),
        ]
        let errs = descriptor().validate(doc)
        XCTAssertTrue(errs.contains { if case .emptyArrayOfTables(let k) = $0.rule { return k == "per-app" }; return false })
    }

    // MARK: - open maps

    func testOpenIntMapOutOfRange() throws {
        let errs = try validate("""
        [v-key-aliases]
        ok = 200
        bad = 999
        """)
        XCTAssertTrue(errs.contains { if case .outOfRange = $0.rule { return true }; return false })
        XCTAssertFalse(errs.contains { $0.pathString.contains("ok") }, "the in-range entry is clean")
    }

    func testOpenStringMapNonStringValue() throws {
        let errs = try validate("""
        [action-aliases]
        focus = 42
        """)
        XCTAssertTrue(errs.contains { if case .typeMismatch = $0.rule { return true }; return false })
    }

    // MARK: - section-level type + permissive

    func testSectionWrongShapeFlagged() throws {
        // `bindings` is an array-of-tables; giving it a plain table is a mismatch.
        let errs = try validate("""
        [bindings]
        input = "x"
        """)
        XCTAssertTrue(errs.contains { if case .typeMismatch = $0.rule { return true }; return false })
    }

    func testPermissiveObjectSkipsUnknownKey() {
        let permissive = SchemaDescriptor(title: "p", sections: [
            SchemaSection("custom", .table(ObjectShape(
                fields: [SchemaField("known", .string, doc: "")],
                permissive: true)), doc: "dynamic"),
        ])
        let doc: [String: Toml.Value] = [
            "custom": .table(["known": .string("a"), "whatever": .string("b")]),
        ]
        XCTAssertEqual(permissive.validate(doc), [], "a permissive object accepts arbitrary keys")
    }

    // MARK: - multiple errors accumulate

    func testValidatorReportsAllViolationsNotJustFirst() throws {
        let errs = try validate("""
        [[bindings]]
        repeat = "nope"
        actoin = "typo"
        """)
        // input missing (required) + anyOfRequired + repeat enum + unknown key.
        XCTAssertGreaterThanOrEqual(errs.count, 3,
            "validator accumulates every violation: \(errs.map(\.message))")
    }
}
