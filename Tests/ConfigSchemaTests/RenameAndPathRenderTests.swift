import XCTest
import Toml
@testable import ConfigSchema

/// Guards the two shared primitives the descriptor family DRY'd onto (R12):
///
///   • `SchemaField.renamed(to:)` — a copy-of-self, so a property added to
///     `SchemaField` rides along instead of being silently dropped by a
///     hand-rolled re-init (the latent bug class this replaced).
///   • `ValidationError.render(_:)` — the ONE path renderer behind BOTH
///     `pathString` and every validator message, so the two can never drift.
///
/// Both are internal seams with public consequences: a drop here reaches the
/// leaf `DynamicValue` field checks (perch's `[search.synonyms]`), a drift there
/// reaches every rendered diagnostic.
final class RenameAndPathRenderTests: XCTestCase {

    // MARK: - SchemaField.renamed(to:)

    /// Every knob set to a distinctive NON-default value, so a property the copy
    /// forgets to carry shows up as an inequality rather than as default-vs-default.
    private func fullyPopulated(key: String) -> SchemaField {
        SchemaField(key, .stringArray, doc: "Every knob set.",
                    enumDomain: ["alpha", "beta"],
                    enumDocs: ["The first one.", nil],
                    arrayItemEnum: ["one", "two"],
                    defaultBool: true, defaultInt: 7,
                    defaultString: "seven", defaultNumber: 7.5,
                    defaultStringArray: ["a", "b"],
                    exclusiveMinimum: 1,
                    minimum: 2, maximum: 30,
                    rejected: true)
    }

    func testRenamedRebindsOnlyTheKeyAndPreservesEveryOtherProperty() {
        let original = fullyPopulated(key: "<word>")
        let renamed = original.renamed(to: "close")

        XCTAssertEqual(renamed.key, "close", "the key is rebound")
        XCTAssertEqual(renamed, fullyPopulated(key: "close"),
                       "a rename changes ONLY the key — the copy-of-self carries every other "
                     + "property, so adding one to SchemaField can never silently drop it here")
    }

    // MARK: - ValidationError path rendering

    private func rendered(_ path: [String]) -> String {
        ValidationError(path: path, rule: .unknownKey(key: "x"), message: "").pathString
    }

    func testIndexSegmentsFoldOntoThePrecedingKey() {
        XCTAssertEqual(rendered(["bindings", "[0]", "input"]), "bindings[0].input")
    }

    func testConsecutiveIndexSegmentsBothFold() {
        XCTAssertEqual(rendered(["synonyms", "close", "[1]"]), "synonyms.close[1]")
        XCTAssertEqual(rendered(["grid", "[0]", "[2]"]), "grid[0][2]")
    }

    func testRootAndEmptyPaths() {
        XCTAssertEqual(rendered(["options"]), "options", "a root section renders bare")
        XCTAssertEqual(rendered([]), "", "an empty path renders empty, not a stray dot")
    }

    func testLeadingIndexNeedsNoPrecedingKey() {
        XCTAssertEqual(rendered(["[0]", "input"]), "[0].input",
                       "an index in first position folds onto nothing and starts the path")
    }

    // MARK: - a validator message and pathString render the same path

    // Sharing ONE renderer is what makes drift impossible; this pins the
    // agreement as BEHAVIOR, so a future re-fork shows up as a red test.

    private func descriptor() -> SchemaDescriptor {
        SchemaDescriptor(title: "demo", sections: [
            SchemaSection("bindings", .arrayOfTables(ObjectShape(
                fields: [SchemaField("input", .string, doc: "Trigger.")],
                doc: "A binding.")), doc: "Bindings."),
        ])
    }

    func testValidatorMessageCarriesTheSamePathAsPathString() throws {
        let errs = descriptor().validate(try Toml.parse("""
        [[bindings]]
        input = "cmd - c"
        actoin = "typo"
        """))
        let err = try XCTUnwrap(errs.first { if case .unknownKey = $0.rule { return true }; return false },
                                "the typo'd key is flagged: \(errs.map(\.message))")

        XCTAssertEqual(err.pathString, "bindings[0].actoin",
                       "pathString folds the row index just like the message does")
        XCTAssertTrue(err.message.hasPrefix(err.pathString + ":"),
                      "an unknown-key message opens with the same rendering pathString "
                    + "returns: \(err.message)")
    }
}
