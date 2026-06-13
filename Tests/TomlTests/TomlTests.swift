import XCTest
@testable import Toml

final class TomlTests: XCTestCase {

    // MARK: - Value model

    func testValueEquatable() {
        XCTAssertEqual(Toml.Value.int(1), .int(1))
        XCTAssertNotEqual(Toml.Value.int(1), .double(1))
        XCTAssertEqual(
            Toml.Value.array([.string("a"), .int(2)]),
            .array([.string("a"), .int(2)])
        )
        XCTAssertEqual(
            Toml.Value.arrayOfTables([["k": .bool(true)]]),
            .arrayOfTables([["k": .bool(true)]])
        )
    }

    func testAccessors() {
        XCTAssertEqual(Toml.Value.string("x").asString, "x")
        XCTAssertEqual(Toml.Value.int(7).asInt, 7)
        XCTAssertEqual(Toml.Value.int(7).asInt64, Int64(7))
        XCTAssertNil(Toml.Value.double(1.5).asInt)        // non-coercing
        XCTAssertEqual(Toml.Value.int(3).asDouble, 3.0)   // widening
        XCTAssertEqual(Toml.Value.double(1.5).asDouble, 1.5)
        XCTAssertEqual(Toml.Value.bool(false).asBool, false)
        XCTAssertEqual(
            Toml.Value.array([.string("a"), .int(2), .string("b")]).asStringArray,
            ["a", "b"]                                     // non-strings dropped
        )
    }

    // MARK: - Nested strict parse (chord)

    func testNestedDottedKeysAndHeaders() throws {
        let root = try Toml.parse("""
        top = 1
        [a]
        x = "hi"
        [a.b]
        y = true
        c.d.e = 2
        """)
        XCTAssertEqual(root["top"]?.asInt, 1)
        XCTAssertEqual(root["a"]?.asTable?["x"]?.asString, "hi")
        XCTAssertEqual(root["a"]?.asTable?["b"]?.asTable?["y"]?.asBool, true)
        // dotted key c.d.e collapses to nested tables
        XCTAssertEqual(
            root["a"]?.asTable?["b"]?.asTable?["c"]?.asTable?["d"]?.asTable?["e"]?.asInt,
            2
        )
    }

    func testInlineTableNested() throws {
        let root = try Toml.parse(#"m = { a = 1, "q.k" = "v", flag = false }"#)
        let t = try XCTUnwrap(root["m"]?.asTable)
        XCTAssertEqual(t["a"]?.asInt, 1)
        XCTAssertEqual(t["q.k"]?.asString, "v")       // quoted inline-table key
        XCTAssertEqual(t["flag"]?.asBool, false)
    }

    func testQuotedDottedHeaderKeepsInteriorDots() throws {
        // [behavior."com.apple.Safari"] must NOT split the bundle id.
        let root = try Toml.parse(#"""
        [behavior."com.apple.Safari"]
        roles = ["Link"]
        """#)
        let inner = try XCTUnwrap(root["behavior"]?.asTable?["com.apple.Safari"]?.asTable)
        XCTAssertEqual(inner["roles"]?.asStringArray, ["Link"])
    }

    func testNestedArrayOfTablesDrillAndLineKey() throws {
        let root = try Toml.parse("""
        [[server]]
        name = "alpha"
        [[server.port]]
        num = 80
        """)
        let rows = try XCTUnwrap(root["server"]?.asArrayOfTables)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"]?.asString, "alpha")
        XCTAssertEqual(rows[0][Toml.lineKey]?.asInt, 1)     // [[server]] on line 1
        let ports = try XCTUnwrap(rows[0]["port"]?.asArrayOfTables)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0]["num"]?.asInt, 80)
        XCTAssertEqual(ports[0][Toml.lineKey]?.asInt, 3)    // [[server.port]] on line 3
    }

    func testStrictThrowsOnUnrecognisedScalar() {
        XCTAssertThrowsError(try Toml.parse("color = red")) { err in
            guard let pe = err as? Toml.ParseError else { return XCTFail("wrong error") }
            XCTAssertEqual(pe.line, 1)
            XCTAssertTrue(pe.message.contains("unrecognised"))
        }
        XCTAssertThrowsError(try Toml.parse("[a\nx = 1"))   // unterminated header
        XCTAssertThrowsError(try Toml.parse("x 1"))          // missing '='
    }

    // MARK: - Flat lenient parse (facet / perch / wand)

    func testFlatLiteralHeaders() {
        let doc = Toml.parseFlat("""
        [cast]
        button = "right"
        [cast.overlay.trail]
        width = 3
        color = "#3b82f6"
        """)
        // headers stay LITERAL (dotted text), not nested
        XCTAssertEqual(doc.tables["cast"]?["button"]?.asString, "right")
        XCTAssertEqual(doc.tables["cast.overlay.trail"]?["width"]?.asInt, 3)
        XCTAssertEqual(doc.tables["cast.overlay.trail"]?["color"]?.asString, "#3b82f6")
        XCTAssertNil(doc.tables["cast"]?["overlay.trail"])   // not folded into cast
    }

    func testFlatArrayOfTables() {
        let doc = Toml.parseFlat("""
        [[exclude]]
        app = "A"
        action = "float"
        [[exclude]]
        app = "B"
        [other]
        z = 1
        """)
        let rows = try? XCTUnwrap(doc.arrays["exclude"])
        XCTAssertEqual(rows?.count, 2)
        XCTAssertEqual(rows?[0]["app"]?.asString, "A")
        XCTAssertEqual(rows?[0]["action"]?.asString, "float")
        XCTAssertEqual(rows?[1]["app"]?.asString, "B")
        // a plain [section] closes the AoT; no __line__ in flat rows
        XCTAssertNil(rows?[0][Toml.lineKey])
        XCTAssertEqual(doc.tables["other"]?["z"]?.asInt, 1)
    }

    func testLenientDropsBadLineKeepsRest() {
        let doc = Toml.parseFlat("""
        [s]
        good = 1
        bad = red
        also-good = "yes"
        """)
        XCTAssertEqual(doc.tables["s"]?["good"]?.asInt, 1)
        XCTAssertNil(doc.tables["s"]?["bad"])               // unrecognised → dropped
        XCTAssertEqual(doc.tables["s"]?["also-good"]?.asString, "yes")
    }

    func testHexInt() {
        let doc = Toml.parseFlat("""
        [c]
        white = 0xFFFFFF
        black = 0x000000
        """)
        XCTAssertEqual(doc.tables["c"]?["white"]?.asInt, 0xFFFFFF)
        XCTAssertEqual(doc.tables["c"]?["black"]?.asInt, 0)
    }

    func testIntBeforeDouble() {
        let doc = Toml.parseFlat("""
        [n]
        whole = 2
        frac = 1.5
        exp = 1e3
        """)
        XCTAssertEqual(doc.tables["n"]?["whole"], .int(2))   // bare int stays int
        XCTAssertEqual(doc.tables["n"]?["frac"], .double(1.5))
        XCTAssertEqual(doc.tables["n"]?["exp"], .double(1000))
    }

    func testQuotesAndEscapes() {
        let doc = Toml.parseFlat(#"""
        [q]
        dq = "a\tb\nc\"d"
        literal = 'raw \n stays'
        unknown = "x\qy"
        """#)
        XCTAssertEqual(doc.tables["q"]?["dq"]?.asString, "a\tb\nc\"d")
        XCTAssertEqual(doc.tables["q"]?["literal"]?.asString, #"raw \n stays"#)
        XCTAssertEqual(doc.tables["q"]?["unknown"]?.asString, "xqy")  // \q → q
    }

    func testCommentInsideQuotedStringPreserved() {
        let doc = Toml.parseFlat("""
        [c]
        url = "https://x/#frag"   # trailing comment stripped
        """)
        XCTAssertEqual(doc.tables["c"]?["url"]?.asString, "https://x/#frag")
    }

    /// An escaped quote `\"` inside a BASIC string must not close it, so
    /// a `#` that follows the *real* closing quote is the comment — not
    /// swallowed as string interior (which would leave the value with an
    /// unbalanced quote and drop the whole binding). Regression guard:
    /// perch's old in-tree parser tracked escape state in its comment
    /// stripper; the shared parser must too (else a shell `action-cmd`
    /// like `"echo \"hi\""  # greet` silently vanishes).
    func testEscapedQuoteBeforeTrailingComment() {
        let doc = Toml.parseFlat(#"""
        [s]
        say = "echo \"hi\""   # greet
        plain = "no escapes"   # comment
        """#)
        XCTAssertEqual(doc.tables["s"]?["say"]?.asString, #"echo "hi""#)
        XCTAssertEqual(doc.tables["s"]?["plain"]?.asString, "no escapes")
    }

    /// Escaped quotes inside an array element must not desync the
    /// comma/bracket split (the element boundary is the unescaped quote,
    /// not the escaped one) — and the trailing comment after `]` still
    /// strips.
    func testEscapedQuoteInsideArrayElement() {
        let doc = Toml.parseFlat(#"""
        [s]
        xs = ["a, \"b\"", "c"]   # two elements, not three
        """#)
        XCTAssertEqual(doc.tables["s"]?["xs"]?.asStringArray, [#"a, "b""#, "c"])
    }

    /// Multi-line array whose element contains an escaped quote: the
    /// bracket-balance accumulator must keep the basic string open across
    /// the `\"` so it doesn't think the array closed early.
    func testEscapedQuoteInMultilineArray() {
        let doc = Toml.parseFlat(#"""
        [s]
        xs = [
            "plain",
            "with \"quote\" inside",
        ]
        after = 1
        """#)
        XCTAssertEqual(doc.tables["s"]?["xs"]?.asStringArray,
                       ["plain", #"with "quote" inside"#])
        XCTAssertEqual(doc.tables["s"]?["after"]?.asInt, 1)
    }

    func testEmptyAndTrailingCommaArrays() {
        let doc = Toml.parseFlat("""
        [a]
        empty = []
        trail = ["x", "y",]
        """)
        XCTAssertEqual(doc.tables["a"]?["empty"], .array([]))
        XCTAssertEqual(doc.tables["a"]?["trail"]?.asStringArray, ["x", "y"])
    }

    // MARK: - Multi-line arrays (the Phase 1.6 superset delta + perch bug fix)

    func testMultilineArrayFlat() {
        let doc = Toml.parseFlat("""
        [behavior]
        roles = [
            "Button",
            "MenuItem",   # inline comment inside the array
            "Link",
        ]
        min-size = 6
        """)
        XCTAssertEqual(
            doc.tables["behavior"]?["roles"]?.asStringArray,
            ["Button", "MenuItem", "Link"]
        )
        // the key AFTER the multi-line array still parses
        XCTAssertEqual(doc.tables["behavior"]?["min-size"]?.asInt, 6)
    }

    func testMultilineArrayNested() throws {
        let root = try Toml.parse("""
        [opt]
        exclude = [
            "a.app",
            "b.app",
        ]
        """)
        XCTAssertEqual(
            root["opt"]?.asTable?["exclude"]?.asStringArray,
            ["a.app", "b.app"]
        )
    }

    // MARK: - Real config golden corpus

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "toml",
                              subdirectory: "Fixtures"),
            "missing fixture \(name).toml"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testChordRealConfigParsesStrict() throws {
        let root = try Toml.parse(try fixture("chord.config"))
        // [options] is a nested table with real keys
        let opts = try XCTUnwrap(root["options"]?.asTable)
        XCTAssertEqual(opts["passthrough-unmatched"]?.asBool, true)
        XCTAssertNotNil(opts["exclude-apps"]?.asArray)
    }

    func testFacetRealConfigParsesFlat() throws {
        let doc = Toml.parseFlat(try fixture("facet.config"))
        XCTAssertEqual(doc.tables["theme"]?["name"]?.asString, "terminal")
        XCTAssertEqual(doc.tables["grid"]?["cols"]?.asInt, 5)
        // [[exclude]] array-of-tables
        XCTAssertGreaterThanOrEqual(doc.arrays["exclude"]?.count ?? 0, 3)
        XCTAssertEqual(doc.arrays["exclude"]?.first?["app"]?.asString,
                       "com.apple.systempreferences")
        // inline table value under a dotted [desktop.1] section
        XCTAssertEqual(doc.tables["desktop.1"]?["1"]?.asTable?["name"]?.asString, "Dev")
    }

    func testWandRealConfigParsesFlat() throws {
        let doc = Toml.parseFlat(try fixture("wand.config"))
        XCTAssertEqual(doc.tables["cast.overlay.trail"]?["color"]?.asString, "#3b82f6")
        XCTAssertEqual(doc.tables["cast.overlay.trail"]?["width"]?.asInt, 3)
        // [[...]] AoT keyed by literal dotted name
        XCTAssertNotNil(doc.arrays["cast.cursor.rule"] ?? doc.arrays["tome.cursor.item"])
    }

    func testPerchRealConfigParsesFlat() throws {
        let doc = Toml.parseFlat(try fixture("perch.config"))
        XCTAssertEqual(doc.tables["hotkey"]?["active"]?.asString, "shift+space")
        XCTAssertEqual(doc.tables["overlay.sound"]?["volume"]?.asDouble, 0.5)
    }

    /// The Phase 1.6 fix: perch ships a MULTI-LINE `roles` array that the
    /// old single-line parsers silently dropped (falling back to the
    /// default). The shared parser now reads it. Proven on the REAL config.
    func testPerchMultilineRolesNowParses() throws {
        let doc = Toml.parseFlat(try fixture("perch.config"))
        let roles = try XCTUnwrap(
            doc.tables["behavior"]?["roles"]?.asStringArray,
            "perch [behavior].roles multi-line array did not parse"
        )
        XCTAssertEqual(roles.count, 11)
        XCTAssertEqual(roles.first, "Button")
        XCTAssertEqual(roles.last, "SearchField")
        XCTAssertTrue(roles.contains("SearchField"))
    }
}
