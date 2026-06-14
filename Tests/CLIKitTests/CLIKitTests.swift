// Golden matrix for CLIKit — the durable (CI) copy of the local
// `clikit-harness`. Pins the D0 tokenizer contract: arity-driven value
// consumption so `-`-leading / negative / empty values survive the
// `--verb=value` → `--verb VALUE` migration, plus the `--` terminator,
// optional/variadic arity, empty-clear, unknown-flag loud reject, and
// the nearest-match hint. CLT has no XCTest, so this runs in CI; the
// host is verified via the harness.

import XCTest
@testable import CLIKit

final class CLIKitTests: XCTestCase {

    // The app SUPPLIES arity — these specs mirror the real per-app inventories.
    let wand = CLIKit.Spec(arity: [
        "--at": .values(2), "--items": .value, "--selection": .value, "--title": .value,
        "--test": .requiredThenOptional(1), "--show-menu": .flag, "--reload": .flag,
        "--quit": .flag, "--status": .flag, "--validate": .flag, "--help": .flag,
    ], aliases: [:])

    let facetView = CLIKit.Spec(arity: [
        "--view": .value, "--pos-x": .value, "--pos-y": .value, "--width": .value,
        "--height": .value, "--loading": .optional, "--active": .flag, "--theme": .value,
        "--edge": .value, "--follow": .flag,
    ])

    let facetWs = CLIKit.Spec(arity: [
        "--focus": .value, "--layout": .value, "--rotate": .value, "--remove": .optional,
        "--rename": .value, "--move": .value, "--retile": .flag, "--balance": .flag, "--show": .flag,
    ])

    let perch = CLIKit.Spec(arity: [
        "--theme": .value, "--activate": .flag, "--reload": .flag, "--quit": .flag, "--status": .flag,
    ])

    let chord = CLIKit.Spec(arity: [
        "--help": .flag, "--version": .flag, "--validate": .flag, "--strict": .flag,
        "--json": .flag, "--reload": .flag, "--dry-run": .flag, "--quit": .flag,
        "--pause": .flag, "--watch": .flag,
    ], aliases: ["-h": "--help"])

    let lens = CLIKit.Spec(arity: ["--only": .variadic, "--toggle": .value, "--all": .flag, "--show": .flag])

    let jig = CLIKit.Spec(arity: ["-c": .flag, "-r": .flag, "-n": .flag], aliases: [:], allowsPositionals: true)

    // helper: assert flags (name,values) in order + positionals
    private func expect(_ argv: [String], _ spec: CLIKit.Spec,
                        flags: [(String, [String])], positionals: [String] = [],
                        file: StaticString = #filePath, line: UInt = #line) {
        do {
            let inv = try CLIKit.parse(argv, spec: spec)
            let got = inv.flags.map { ($0.name, $0.values) }
            XCTAssertEqual(got.count, flags.count, "flag count \(got)", file: file, line: line)
            for (g, e) in zip(got, flags) {
                XCTAssertEqual(g.0, e.0, file: file, line: line)
                XCTAssertEqual(g.1, e.1, "values for \(e.0)", file: file, line: line)
            }
            XCTAssertEqual(inv.positionals, positionals, "positionals", file: file, line: line)
        } catch {
            XCTFail("unexpected throw \(error)", file: file, line: line)
        }
    }

    private func expectThrow(_ argv: [String], _ spec: CLIKit.Spec, _ want: CLIKit.ParseError,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try CLIKit.parse(argv, spec: spec), file: file, line: line) { err in
            XCTAssertEqual(err as? CLIKit.ParseError, want, file: file, line: line)
        }
    }

    // MARK: D0 — negative / -leading required values consumed verbatim

    func testNegativeCoordsConsumed() {
        expect(["--at", "-100", "50"], wand, flags: [("--at", ["-100", "50"])])
        expect(["--show-menu", "--items", "m.toml", "--at", "-1280", "-300"], wand,
               flags: [("--show-menu", []), ("--items", ["m.toml"]), ("--at", ["-1280", "-300"])])
        expect(["--view", "tree", "--pos-x", "-100", "--pos-y", "-50", "--width", "400", "--height", "600"], facetView,
               flags: [("--view", ["tree"]), ("--pos-x", ["-100"]), ("--pos-y", ["-50"]), ("--width", ["400"]), ("--height", ["600"])])
    }

    func testDashLeadingValues() {
        expect(["--selection", "-rf"], wand, flags: [("--selection", ["-rf"])])
        expect(["--items", "-config.toml"], wand, flags: [("--items", ["-config.toml"])])
        expect(["--focus", "-work"], facetWs, flags: [("--focus", ["-work"])])
    }

    func testEmptyRequiredValue() {
        expect(["--rename", ""], facetWs, flags: [("--rename", [""])])
    }

    // MARK: optional-trailing (wand --test PATTERN [BUNDLE])

    func testRequiredThenOptional() {
        expect(["--test", "DLU"], wand, flags: [("--test", ["DLU"])])
        expect(["--test", "DLU", "com.apple.Safari"], wand, flags: [("--test", ["DLU", "com.apple.Safari"])])
        // optional 2nd not consumed when next token is flag-shaped; --selection then takes -x
        expect(["--test", "DLU", "--selection", "-x"], wand,
               flags: [("--test", ["DLU"]), ("--selection", ["-x"])])
    }

    // MARK: optional arity (facet --loading / --remove)

    func testOptionalArity() {
        expect(["--loading", "2000"], facetView, flags: [("--loading", ["2000"])])
        expect(["--loading", "--active"], facetView, flags: [("--loading", []), ("--active", [])])
        expect(["--loading"], facetView, flags: [("--loading", [])])
        expect(["--remove"], facetWs, flags: [("--remove", [])])
        expect(["--remove", "2"], facetWs, flags: [("--remove", ["2"])])
    }

    // MARK: perch empty-clear migration (--theme= → --theme '')

    func testEmptyClear() {
        expect(["--theme", "", "--activate"], perch, flags: [("--theme", [""]), ("--activate", [])])
        expect(["--theme", "dracula", "--activate"], perch, flags: [("--theme", ["dracula"]), ("--activate", [])])
        expectThrow(["--theme"], perch, .missingValue(flag: "--theme", expected: 1, got: 0))
    }

    // MARK: chord — boolean-only, positionals forbidden

    func testChordBooleanOnly() {
        expect(["--validate", "--strict", "--json"], chord,
               flags: [("--validate", []), ("--strict", []), ("--json", [])])
        expectThrow(["foo"], chord, .unexpectedPositional("foo"))
        expectThrow(["-x"], chord, .unknownFlag("-x", suggestion: nil))
        expect(["-h"], chord, flags: [("--help", [])])
    }

    // MARK: variadic (convention --only a b c)

    func testVariadic() {
        expect(["--only", "a", "b", "c"], lens, flags: [("--only", ["a", "b", "c"])])
        expect(["--only", "a", "b", "--all"], lens, flags: [("--only", ["a", "b"]), ("--all", [])])
        expectThrow(["--only"], lens, .missingValue(flag: "--only", expected: 1, got: 0))
    }

    // MARK: jig (OUT-ref) — the canonical D0 failure + `--` fix + lone `-`

    func testJigTerminatorAndStdin() {
        expectThrow(["-1"], jig, .unknownFlag("-1", suggestion: nil))
        expect(["--", "-1"], jig, flags: [], positionals: ["-1"])
        expect([".", "-"], jig, flags: [], positionals: [".", "-"])
        expect(["-c", ".", "file.json"], jig, flags: [("-c", [])], positionals: [".", "file.json"])
    }

    // MARK: arity shortfall / terminator-as-value refusal / typo hint

    func testLoudFailures() {
        expectThrow(["--items", "--"], wand, .missingValue(flag: "--items", expected: 1, got: 0))
        expectThrow(["--at", "800"], wand, .missingValue(flag: "--at", expected: 2, got: 1))
        expectThrow(["--follo"], facetView, .unknownFlag("--follo", suggestion: "--follow"))
    }

    // MARK: usage rendering / exit floor

    func testUsageMessages() {
        XCTAssertEqual(CLIKit.ParseError.unknownFlag("--foo", suggestion: "--follow").usageMessage,
                       "unknown flag '--foo' (did you mean '--follow'?). See --help.")
        XCTAssertEqual(CLIKit.ParseError.missingValue(flag: "--at", expected: 2, got: 1).usageMessage,
                       "'--at' expects 2 values, got 1. See --help.")
        XCTAssertEqual(CLIKit.ExitCode.usage, 2)
        XCTAssertEqual(CLIKit.ExitCode.daemonNotRunning, 3)
    }
}
