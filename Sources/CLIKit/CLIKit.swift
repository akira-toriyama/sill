// CLIKit — the family's shared pure CLI argv tokenizer + usage helpers.
//
// Phase 3 of the atelier refactor moves the family's CLIs onto one yabai-
// style grammar (`<tool> <domain> --<verb> [VALUE ...] [--modifier ...]`).
// The daemon-control CLIs (facet / chord / wand / perch) each hand-roll
// their own argv parser today, on four incompatible shapes:
//   • facet  — 100% `--verb=value` (the `=` glues the value to the verb)
//   • wand   — space-separated, a `valueArities` table + index lookahead
//   • perch  — flat `argv.contains(...)`, the lone value flag is `--theme=`
//   • chord  — pure boolean membership, ZERO value-consuming flags
//
// The convention abolishes `--verb=value` in favour of space-separated
// values (`--verb VALUE`). That single change creates ONE sharp hazard
// (the "D0" problem): once the `=` no longer glues the value, a value
// that starts with `-` (a negative coordinate `--at -100 50`, a relative
// index, a `-`-leading name) is indistinguishable from a flag under a
// naive `hasPrefix("-") == flag` tokenizer — and a call that works today
// silently dies with exit 2. (jig proves it: its parser flags every
// `-`-leading token, so `jig -1` already throws unknownFlag and needs
// `jig -- -1`.)
//
// The fix, and the whole point of this module, is ARITY-DRIVEN
// consumption: when a recognised verb declares arity >= 1, CLIKit
// consumes the next N tokens as its values UNCONDITIONALLY — signed,
// `-`-leading, or empty. This is exactly what wand's arity table and
// glance's lookahead already do correctly; CLIKit generalises it so the
// four parsers collapse to one. A `-`-leading token is only ever judged
// "flag vs value" in *flag position* (where it genuinely is a flag);
// in *value position* it is taken verbatim.
//
// MECHANISM ONLY (the D4 line — what stays app-local):
//   • The app SUPPLIES the arity table (`Spec.arity`) — CLIKit owns NO
//     verb vocabulary. The same spelling (`--focus`) is a direction under
//     facet `window` and an index/name under facet `workspace`; that
//     collision is resolved by the app's per-domain spec, never here.
//   • CLIKit does the mechanical part — alias resolution, arity-driven
//     value consumption, unknown-flag detection (loud, with a nearest-
//     match hint), `--` termination — and returns an `Invocation`.
//   • The app keeps its OWN dispatch policy: priority-loser tolerance
//     (chord), allow-list canonicalisation + typo `suggest()` (facet),
//     reject-before-dispatch ordering (perch), clamp-vs-reject, and the
//     `--show` JSON SCHEMA (window tree / binding / cast-tome rule /
//     overlay state are all different and stay app-local). CLIKit only
//     hands back the parsed tokens; the app interprets them.
//
// Foundation only, Sendable, zero AppKit, zero Palette — a pure atom
// alongside Palette / Toml / ConfigSchema, shipped under the one sill tag.

import Foundation

public enum CLIKit {

    // MARK: Spec — supplied BY THE APP (CLIKit owns no verb vocabulary)

    /// How many value tokens a recognised flag consumes. The app declares
    /// this per flag; CLIKit never guesses arity from spelling.
    public enum Arity: Sendable, Equatable {
        /// 0 values — a boolean / action flag (`--reload`, `--toggle-float`).
        case flag
        /// Exactly 1 required value (`--view tree`, `--pos-x -100`). The
        /// next token is taken verbatim (signed / `-`-leading / empty OK);
        /// only the bare terminator `--` is refused (→ missingValue).
        case value
        /// Exactly N required values that travel together (`--at -100 50`
        /// → `.values(2)`). Each is taken verbatim.
        case values(Int)
        /// 0 or 1 — bare, OR one value iff the next token is a plain word
        /// (not flag-shaped). facet `--loading` / `--remove`.
        case optional
        /// N required + 1 trailing optional. wand `--test PATTERN [BUNDLE]`
        /// → `.requiredThenOptional(1)`: PATTERN verbatim, BUNDLE only if
        /// the next token is not flag-shaped (so `--test DLU --selection x`
        /// leaves `--selection` for its own flag).
        case requiredThenOptional(Int)
        /// 1+ plain-word values until the next flag / `--` / end
        /// (`--only a b c`). At least one is required.
        case variadic
    }

    /// The recognised surface for one parse: the flag→arity table plus the
    /// short aliases that survive the canonical-only rule (D7: `-h`/`-V`
    /// only, by default) and whether bare positionals are legal (false for
    /// most daemon CLIs — chord rejects `chord foo`; true where a bare noun
    /// or filter is real — facet `status`, a jq filter).
    public struct Spec: Sendable {
        public var arity: [String: Arity]
        public var aliases: [String: String]
        public var allowsPositionals: Bool

        /// The only short aliases the canonical-only rule permits (D7).
        public static let defaultAliases: [String: String] = ["-h": "--help", "-V": "--version"]

        public init(arity: [String: Arity],
                    aliases: [String: String] = Spec.defaultAliases,
                    allowsPositionals: Bool = false) {
            self.arity = arity
            self.aliases = aliases
            self.allowsPositionals = allowsPositionals
        }

        /// Every recognised long flag (arity keys) plus alias spellings —
        /// the set unknown-flag detection and nearest-match hints draw on.
        var recognised: Set<String> {
            var s = Set(arity.keys)
            for k in aliases.keys { s.insert(k) }
            return s
        }
    }

    // MARK: Invocation — the mechanical parse result

    /// One recognised flag with its consumed values. `values` may contain
    /// empty strings, `-`-leading tokens, or signed numbers — they are
    /// returned verbatim for the app to interpret.
    public struct Flag: Sendable, Equatable {
        public let name: String          // canonical long flag (alias resolved)
        public let values: [String]
        public var value: String? { values.first }
        public init(name: String, values: [String]) {
            self.name = name
            self.values = values
        }
    }

    /// The parse result. Flags are in argv order (so the app can do
    /// priority-loser dispatch / "no verb given" detection on `names`).
    /// `positionals` holds bare tokens and everything after `--`.
    public struct Invocation: Sendable, Equatable {
        public var flags: [Flag]
        public var positionals: [String]

        public init(flags: [Flag], positionals: [String]) {
            self.flags = flags
            self.positionals = positionals
        }

        /// Flag names in argv order — for priority dispatch and detecting
        /// an empty / verb-less invocation.
        public var names: [String] { flags.map(\.name) }

        public func has(_ name: String) -> Bool { flags.contains { $0.name == name } }
        public func flag(_ name: String) -> Flag? { flags.first { $0.name == name } }
        /// First value of `name`, or nil if absent / value-less.
        public func value(_ name: String) -> String? { flag(name)?.value }
        /// All values of `name` (variadic / repeated), empty if absent.
        public func values(_ name: String) -> [String] { flag(name)?.values ?? [] }
    }

    // MARK: Errors — every parse failure is a usage error (exit 2, loud)

    public enum ParseError: Swift.Error, Sendable, Equatable {
        /// A flag-shaped token (`-`-leading, not `-`) that the spec does
        /// not recognise. `suggestion` is the nearest known flag, if close.
        case unknownFlag(String, suggestion: String?)
        /// A verb needed more values than argv supplied (or hit `--`).
        case missingValue(flag: String, expected: Int, got: Int)
        /// A bare token in flag position when the spec forbids positionals.
        case unexpectedPositional(String)
    }

    // MARK: Tokenizer (D0) — pure, single left-to-right pass

    /// Tokenize `argv` (already `dropFirst()`-ed of the binary name) into
    /// recognised flags + positionals, consuming values by app-declared
    /// arity. Throws `ParseError` (a usage error) on the first problem —
    /// so an app that calls this BEFORE dispatching preserves the
    /// reject-before-act ordering (perch). Never exits the process.
    public static func parse(_ argv: [String], spec: Spec) throws -> Invocation {
        var flags: [Flag] = []
        var positionals: [String] = []
        var terminated = false
        var i = 0

        while i < argv.count {
            let tok = argv[i]

            if terminated {
                positionals.append(tok); i += 1; continue
            }
            if tok == "--" {                       // end-of-flags terminator
                terminated = true; i += 1; continue
            }
            if isFlagShaped(tok) {
                let name = spec.aliases[tok] ?? tok
                guard let arity = spec.arity[name] else {
                    throw ParseError.unknownFlag(tok, suggestion: nearest(tok, in: spec.recognised))
                }
                let (values, consumed) = try take(arity, from: argv, at: i, flag: name)
                flags.append(Flag(name: name, values: values))
                i += consumed
                continue
            }
            // Not flag-shaped: a bare word, lone "-", or "" → positional.
            guard spec.allowsPositionals else {
                throw ParseError.unexpectedPositional(tok)
            }
            positionals.append(tok); i += 1
        }
        return Invocation(flags: flags, positionals: positionals)
    }

    /// Consume the values for `flag` at index `at` (which holds the flag
    /// token). Returns the values and the total tokens consumed (incl. the
    /// flag). REQUIRED values are taken verbatim (signed / `-`-leading /
    /// empty), refusing only the bare terminator `--`. OPTIONAL / VARIADIC
    /// values stop at the next flag-shaped token (or `--`).
    private static func take(_ arity: Arity, from argv: [String], at: Int, flag: String) throws -> (values: [String], consumed: Int) {
        switch arity {
        case .flag:
            return ([], 1)

        case .value:
            return try (required(argv, after: at, n: 1, flag: flag), 2)

        case .values(let n):
            return try (required(argv, after: at, n: n, flag: flag), 1 + n)

        case .optional:
            if let v = optionalValue(argv, after: at) { return ([v], 2) }
            return ([], 1)

        case .requiredThenOptional(let n):
            var vs = try required(argv, after: at, n: n, flag: flag)
            if let v = optionalValue(argv, after: at + n) { vs.append(v); return (vs, 1 + n + 1) }
            return (vs, 1 + n)

        case .variadic:
            var vs: [String] = []
            var j = at + 1
            while j < argv.count, isConsumableValue(argv[j]) { vs.append(argv[j]); j += 1 }
            guard !vs.isEmpty else {
                throw ParseError.missingValue(flag: flag, expected: 1, got: 0)
            }
            return (vs, 1 + vs.count)
        }
    }

    /// Take `n` required values starting right after `from`. Each is taken
    /// verbatim; the bare terminator `--` is not a value (→ missingValue).
    private static func required(_ argv: [String], after from: Int, n: Int, flag: String) throws -> [String] {
        var vs: [String] = []
        var j = from + 1
        while vs.count < n, j < argv.count, argv[j] != "--" { vs.append(argv[j]); j += 1 }
        guard vs.count == n else {
            throw ParseError.missingValue(flag: flag, expected: n, got: vs.count)
        }
        return vs
    }

    /// One trailing optional value: consumed iff the next token exists and
    /// is a plain word (not flag-shaped, not `--`).
    private static func optionalValue(_ argv: [String], after from: Int) -> String? {
        let j = from + 1
        guard j < argv.count, isConsumableValue(argv[j]) else { return nil }
        return argv[j]
    }

    // MARK: token classification

    /// A token is "flag-shaped" iff it begins with `-` and is not the lone
    /// `-` (which is a value sentinel, e.g. stdin) and not empty. Note
    /// `--` is also flag-shaped but is always handled as the terminator
    /// before this is consulted in flag position.
    static func isFlagShaped(_ t: String) -> Bool {
        t.hasPrefix("-") && t != "-"
    }

    /// Consumable as an OPTIONAL / VARIADIC value: a plain word (covers the
    /// lone `-` and the empty string, both legitimate values; excludes any
    /// flag-shaped token and the `--` terminator since `isFlagShaped("--")`).
    private static func isConsumableValue(_ t: String) -> Bool {
        !isFlagShaped(t)
    }

    // MARK: nearest-match hint (pure — for loud unknown-flag errors)

    /// The recognised LONG flag closest to `token` by Levenshtein distance,
    /// when within a small edit budget (so `--follo` hints `--follow`, but a
    /// wild typo hints nothing). Did-you-mean is deliberately limited to
    /// `--`-form flags on both sides: short flags (`-x`) are too dense in
    /// edit space — every `-a`…`-z` is distance 1 — so a numeric value like
    /// `-1` must NOT masquerade as a typo of `-n`.
    static func nearest(_ token: String, in known: Set<String>) -> String? {
        guard token.hasPrefix("--") else { return nil }
        let budget = max(2, token.count / 3)
        var best: (flag: String, dist: Int)? = nil
        for cand in known where cand.hasPrefix("--") {
            let d = levenshtein(token, cand)
            if d <= budget, best == nil || d < best!.dist { best = (cand, d) }
        }
        return best?.flag
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}

// MARK: - Exit codes & usage rendering (D5) — app composes its own extension codes

public extension CLIKit {
    /// The daemon-control common floor (D5). Apps add documented extension
    /// codes of their own (facet 1=resign-fail / 4=status-malformed,
    /// perch 1=doctor-fail, …) on top — CLIKit does not own those.
    enum ExitCode {
        public static let ok: Int32 = 0
        public static let usage: Int32 = 2        // usage / typo — loud stderr
        public static let daemonNotRunning: Int32 = 3
    }

    /// Write a loud `tool: message` line to stderr (never silent).
    static func warn(_ tool: String, _ message: String) {
        FileHandle.standardError.write(Data("\(tool): \(message)\n".utf8))
    }

    /// Loud stderr + `exit(code)`. The app maps a caught `ParseError` to
    /// this; the tokenizer itself never exits (so it stays unit-testable).
    static func die(_ tool: String, _ message: String, code: Int32 = ExitCode.usage) -> Never {
        warn(tool, message)
        exit(code)
    }
}

public extension CLIKit.ParseError {
    /// A human, greppable one-liner (no leading tool name — pass through
    /// `CLIKit.die(tool, error.usageMessage)`). Always an exit-2 usage error.
    var usageMessage: String {
        switch self {
        case let .unknownFlag(flag, suggestion):
            if let s = suggestion { return "unknown flag '\(flag)' (did you mean '\(s)'?). See --help." }
            return "unknown flag '\(flag)'. See --help."
        case let .missingValue(flag, expected, got):
            return "'\(flag)' expects \(expected) value\(expected == 1 ? "" : "s"), got \(got). See --help."
        case let .unexpectedPositional(token):
            return "unexpected argument '\(token)'. See --help."
        }
    }
}

// MARK: - --show emitter (D6) — human line by default, JSON under --json

public extension CLIKit {
    /// Print the human form, or the machine form when `asJSON` (i.e. the
    /// caller saw `--json`). The CONTENT of both is built by the app — the
    /// `--show` JSON schema is deliberately app-local (window tree vs
    /// binding list vs overlay state are not one schema). CLIKit only
    /// routes which one is written to stdout.
    static func emitShow(human: @autoclosure () -> String,
                         json: @autoclosure () -> String,
                         asJSON: Bool) {
        print(asJSON ? json() : human())
    }
}
