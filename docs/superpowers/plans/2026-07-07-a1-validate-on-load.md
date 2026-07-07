# A1 — validate on the LOAD path (warn, not reject) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make facet / perch / wand run the sill ConfigSchema validate on their daemon **load** path and surface every violation as a **warning** in the operational log — so an `editor-green-but-load-silently-clamps` config no longer hides until a user manually runs `config --validate`.

**Architecture:** Each app already declares one `configSpec` that drives emit + validate + (uniform) decode, and already has a `validate(_:)` fn wired only to the `--validate` CLI verb (which rejects with exit codes). A1 reuses that exact `validate(_:)` on the daemon load path but routes results to `Log.line` instead of `exit()`. The daemon load stays byte-for-byte lenient (clamps out-of-range, drops typo'd keys, always returns a usable config) — A1 only **adds** warnings. On unparseable TOML A1 emits nothing (`try?` → `[]`), matching today's silent lenient load; only schema violations on a parseable doc are surfaced.

**Tech Stack:** Swift, sill `ConfigSchema` (`ValidationError`, `Spec.validate`). facet tests = **swift-testing** (`import Testing`); perch/wand tests = **XCTest**.

## Global Constraints

- **This is app-per-PR** — three independent PRs, one per repo (facet / perch / wand). Each Task below = one PR on an isolated branch off that repo's clean `origin/main` (worktree; a sibling session is actively working facet — never touch its `feat/swiftui-tree-render` WIP).
- **A1 touches NO sill code** — `validate(_:)` and `ValidationError` already ship in each app's pinned sill. No sill version bump, no `Package.resolved` change.
- **Preserve clamp-don't-reject** — the load path must keep clamping/dropping and returning a usable config. A1 never rejects, throws, or `exit()`s on the load path. Do **not** modify the `config --validate` verb (`runValidate`/`runValidateConfig`) — that is the strict/reject contract and stays as-is.
- **Unparseable TOML ⇒ zero warnings** — use `(try? validate(...)) ?? []`. Never propagate the throw to the daemon.
- **Warning line format (verbatim, all three apps):** `config: <ValidationError.message>` via each app's always-on `Log.line`. `ValidationError.message` is already a located one-liner (e.g. `grid.bogus-key: unknown key 'bogus-key'`). No summary line, no `--validate` hint (YAGNI).
- **Test gate:** compile bar = `swift build` (CLT). Full test suite = **`scripts/test.sh`** in each repo (points `DEVELOPER_DIR` at an installed Xcode) — a plain `swift test` fails on the CLT-only shell. A filtered faster run is `DEVELOPER_DIR=<Xcode>/Contents/Developer swift test --filter <TestName>`.
- **Commits:** gitmoji + Conventional Commits, e.g. `:sparkles: feat(config): …`. **PR body footer** (per each repo's project rules): `SetStatus-task: https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-van5.md in-progress`.
- **Spec:** `akira-toriyama/sill:docs/superpowers/specs/2026-07-07-config-validation-hardening-design.md` (§3 A1).

**Recommended execution order:** Task 1 (wand) → Task 2 (perch) → Task 3 (facet). wand/perch are quiet repos with the simplest call-site wiring; facet is actively churning (SwiftUI pilot) and uses the more involved data-on-config design, so do it last on an isolated branch.

---

### Task 1: wand — warn on the daemon load path

**Repo:** `/Volumes/workspace/github.com/akira-toriyama/wand` (branch off clean `origin/main`).

**Files:**
- Modify: `Sources/WandCore/Config.swift` (add helper after line 138, right after `validate(_:)`)
- Modify: `Sources/WandApp/Main.swift:256` (call helper in `runServer`, after `WandConfig.load()`)
- Test: `Tests/WandCoreTests/ConfigValidateTests.swift` (add cases; `@testable import WandCore`)

**Interfaces:**
- Consumes: `WandConfig.validate(_ text: String) throws -> [ValidationError]` (Config.swift:135); `Log.line(_:)`, `Log.lineCount`, `Log.resetLineCount()` (WandCore Log.swift:22/24/26).
- Produces: `WandConfig.warnSchemaViolations(_ text: String) -> Int` (`@discardableResult`; logs each violation, returns count).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/WandCoreTests/ConfigValidateTests.swift` (mirrors the existing `testUnknownKeyIsReported` shape):

```swift
    // MARK: - A1: the daemon LOAD path warns on a schema violation (no reject)

    func testLoadPathWarnsOnSchemaViolation() throws {
        Log.resetLineCount()
        // `bogus-key` is an unknown key the lenient load()/parse() silently
        // drops; the load-path validate must surface it as a WARNING.
        let count = WandConfig.warnSchemaViolations("""
        [cast.overlay]
        enabled = true
        bogus-key = 1
        """)
        XCTAssertGreaterThanOrEqual(count, 1,
            "a schema violation on the load path must produce a warning")
        XCTAssertGreaterThanOrEqual(Log.lineCount, 1,
            "the violation must reach Log.line (the daemon warning channel)")
    }

    func testLoadPathIsSilentOnCleanConfig() throws {
        Log.resetLineCount()
        let count = WandConfig.warnSchemaViolations("""
        [cast.overlay]
        enabled = true
        """)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(Log.lineCount, 0)
    }

    func testLoadPathDoesNotRejectUnparseableSource() {
        // Unparseable TOML must NOT throw on the daemon path (load stays
        // lenient / keeps starting) — helper swallows it via try?.
        XCTAssertEqual(WandConfig.warnSchemaViolations("[cast.overlay\nbad"), 0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/workspace/github.com/akira-toriyama/wand && scripts/test.sh`
Expected: FAIL — `warnSchemaViolations` is undefined (compile error). (Faster: `DEVELOPER_DIR=<Xcode>/Contents/Developer swift test --filter ConfigValidateTests`.)

- [ ] **Step 3: Implement the helper**

Insert in `Sources/WandCore/Config.swift` immediately after `validate(_:)` (after line 138):

```swift
    /// A1 (load-path validate): run the strict `validate` on the daemon's
    /// load path and surface each violation as a WARNING via `Log.line` — it
    /// does NOT reject. The lenient `load()`/`parse()` already clamped
    /// out-of-range values and dropped typo'd keys; this only makes those
    /// mismatches visible in the log (matching facet/perch). A non-parseable
    /// source yields zero warnings (the lenient loader still continues).
    /// Returns the violation count (0 = clean).
    @discardableResult
    public static func warnSchemaViolations(_ text: String) -> Int {
        let errors = (try? validate(text)) ?? []
        for e in errors {
            Log.line("config: \(e.message)")
        }
        return errors.count
    }
```

- [ ] **Step 4: Wire the daemon load path**

In `Sources/WandApp/Main.swift`, in `runServer`, insert between the current line 256 (`let cfg = WandConfig.load()`) and line 257 (`requireFailsafeBlock(cfg)`):

```swift
        let cfg = WandConfig.load()
        // A1: run the strict schema validate on the daemon load path too and
        // surface violations as WARNINGS (does NOT reject — load() already
        // clamped/dropped; this only makes the mismatches visible in the log,
        // matching facet/perch).
        WandConfig.warnSchemaViolations(
            (try? String(contentsOfFile: WandConfig.path, encoding: .utf8)) ?? "")
        requireFailsafeBlock(cfg)
```

(`Main.swift` already `import ConfigSchema` + `import WandCore`; no new imports.)

- [ ] **Step 5: Run tests to verify they pass + compile**

Run: `cd /Volumes/workspace/github.com/akira-toriyama/wand && swift build && scripts/test.sh`
Expected: PASS — all three new tests green; the existing `testCommittedTemplateValidatesClean` still green (shipped config.toml emits zero startup warnings).

- [ ] **Step 6: Commit**

```bash
cd /Volumes/workspace/github.com/akira-toriyama/wand
git add Sources/WandCore/Config.swift Sources/WandApp/Main.swift Tests/WandCoreTests/ConfigValidateTests.swift
git commit -m ":sparkles: feat(config): warn on schema violations at daemon load (A1)"
```

---

### Task 2: perch — warn on the daemon load path (+ hot-reload)

**Repo:** `/Volumes/workspace/github.com/akira-toriyama/perch` (branch off clean `origin/main`).

**Files:**
- Modify: `Sources/PerchCore/Config.swift` (add helper after line 574, right after `validate(_:)`)
- Modify: `Sources/PerchApp/Main.swift:370-372` (call helper in `runServer`, between `installSchema()` and `load()`)
- Modify: `Sources/PerchApp/Controller.swift:140-142` (call helper in `reload(cause:)` so hot-reload also warns)
- Test: `Tests/PerchCoreTests/ConfigValidateTests.swift` (add a sibling class; `@testable import PerchCore`)

**Interfaces:**
- Consumes: `PerchConfig.validate(_ source: String) throws -> [ValidationError]` (Config.swift:571); `PerchConfig.path`; `Log.line(_:)` (PerchCore Log.swift:23).
- Produces: `PerchConfig.loadWarnings(_ source: String) -> [String]` (the `config: …` lines the daemon logs; `[]` = clean or unparseable).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PerchCoreTests/ConfigValidateTests.swift` (new class; mirrors the existing `testWrongTypeIsReported`):

```swift
/// `PerchConfig.loadWarnings` — the validate-then-warn seam the DAEMON load
/// path (runServer + reload) uses. Same schema check as `--validate`, but
/// surfaced as warnings without rejecting: proves violations warn on the LOAD
/// path, not only via the `config --validate` CLI verb.
final class ConfigLoadWarnTests: XCTestCase {

    func testLoadPathWarnsOnSchemaViolation() {
        let warnings = PerchConfig.loadWarnings("""
        [overlay]
        shortcut-badge = "yes"
        """)
        XCTAssertFalse(warnings.isEmpty,
                       "load path must warn on a schema violation")
        XCTAssertTrue(warnings.contains { $0.contains("shortcut-badge") },
                      "warning should name the offending key; got \(warnings)")
    }

    func testCleanConfigProducesNoWarnings() {
        XCTAssertEqual(PerchConfig.loadWarnings(""), [])
    }

    func testUnparseableSourceProducesNoWarnings() {
        // Matches today's silent lenient load — A1 only surfaces SCHEMA
        // violations on a parseable doc, never a syntax-error warning.
        XCTAssertEqual(PerchConfig.loadWarnings("[overlay\nbad"), [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/workspace/github.com/akira-toriyama/perch && scripts/test.sh`
Expected: FAIL — `loadWarnings` undefined (compile error).

- [ ] **Step 3: Implement the helper**

Insert in `Sources/PerchCore/Config.swift` immediately after `validate(_:)` (after line 574):

```swift
    /// Warning lines the daemon load path (runServer + reload) emits for
    /// schema violations — the validate-then-warn counterpart to the strict
    /// `--validate` verb. Runs the SAME `configSpec.validate` used by
    /// `validate()`, but maps each violation to a `config: …` log line
    /// instead of an exit code: the daemon keeps loading with clamped
    /// defaults (see the clamp policy, top of file). `[]` ⇒ clean or
    /// unparseable (never throws; an unparseable file stays silent, matching
    /// today's lenient load, and the lenient `load()` still returns a usable
    /// config).
    public static func loadWarnings(_ source: String) -> [String] {
        ((try? validate(source)) ?? []).map { "config: \($0.message)" }
    }
```

- [ ] **Step 4: Wire the startup load path**

In `Sources/PerchApp/Main.swift`, in `runServer`, insert between `PerchConfig.installSchema()` (line 370) and `let cfg = PerchConfig.load()` (line 372):

```swift
        PerchConfig.installSchema()

        // A1: validate-then-warn on the load path — surface the schema
        // violations the lenient load() silently clamps/ignores, but DO NOT
        // reject; the daemon keeps loading with clamped defaults.
        let source = (try? String(contentsOfFile: PerchConfig.path,
                                  encoding: .utf8)) ?? ""
        for w in PerchConfig.loadWarnings(source) { Log.line(w) }

        let cfg = PerchConfig.load()
```

- [ ] **Step 5: Wire the hot-reload path**

In `Sources/PerchApp/Controller.swift`, in `reload(cause:)` (lines 140-142), insert the same warn loop before `let new = PerchConfig.load()`:

```swift
    func reload(cause: String) {
        Log.line("config: reloading (\(cause))")
        let source = (try? String(contentsOfFile: PerchConfig.path,
                                  encoding: .utf8)) ?? ""
        for w in PerchConfig.loadWarnings(source) { Log.line(w) }
        let new = PerchConfig.load()
```

- [ ] **Step 6: Run tests to verify they pass + compile**

Run: `cd /Volumes/workspace/github.com/akira-toriyama/perch && swift build && scripts/test.sh`
Expected: PASS — three new tests green; existing `ConfigValidateTests` + committed-template guard still green.

- [ ] **Step 7: Commit**

```bash
cd /Volumes/workspace/github.com/akira-toriyama/perch
git add Sources/PerchCore/Config.swift Sources/PerchApp/Main.swift Sources/PerchApp/Controller.swift Tests/PerchCoreTests/ConfigValidateTests.swift
git commit -m ":sparkles: feat(config): warn on schema violations at daemon load + reload (A1)"
```

---

### Task 3: facet — record schema warnings on load, emit at startup + hot-reload

**Repo:** `/Volumes/workspace/github.com/akira-toriyama/facet` (branch off clean `origin/main`; a sibling session works `feat/swiftui-tree-render` — do NOT branch from or touch it).

facet uses a **data-on-config** design: `load(source:)` records violations onto the returned `FacetConfig`, and the existing `Controller.logConfigWarnings()` seam (already fires once per load — startup + hot-reload, next to `unknownValueWarnings()`) emits them. This gets hot-reload for free and keeps emission out of `--validate`/snapshot paths.

**Files:**
- Modify: `Sources/FacetCore/FacetConfig.swift` (add `import ConfigSchema` + a `schemaWarnings` stored field)
- Modify: `Sources/FacetCore/FacetConfig+Decode.swift:407` (record in `load(source:)` before `return c`)
- Modify: `Sources/FacetApp/Controller.swift:834-836` (extend `logConfigWarnings()`)
- Test: `Tests/FacetCoreTests/ConfigValidateTests.swift` (add cases; **swift-testing**, `@testable import FacetCore`)

**Interfaces:**
- Consumes: `FacetConfig.validate(_ source: String) throws -> [ValidationError]` (FacetConfig+Validate.swift:26); `ValidationError` (sill ConfigSchema); `Log.line(_:)` (FacetCore Log.swift:35).
- Produces: `FacetConfig.schemaWarnings: [ValidationError]` (`public internal(set)`; `[]` when clean/unparseable).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/FacetCoreTests/ConfigValidateTests.swift` (swift-testing; mirrors the existing `unknownKeyIsReported`):

```swift
    /// A schema violation surfaces on the LENIENT load path as a recorded
    /// warning while load STILL clamps — it must never reject (A1).
    @Test func loadPathRecordsSchemaViolationAndStillClamps() throws {
        let cfg = FacetConfig.load(source: """
        [grid]
        cols = "four"
        """)
        // (1) load recorded the violation as a warning
        #expect(cfg.schemaWarnings.contains {
            if case .typeMismatch(let k, _) = $0.rule { return k == "cols" }
            return false
        }, "load(source:) should record the schema violation; got \(cfg.schemaWarnings.map(\.rule))")
        // (2) but load stayed lenient — cols fell back to its clamp default (4)
        #expect(cfg.effectiveGridCols == 4)
    }

    /// A clean config records zero load-path warnings (no false positives).
    @Test func loadPathCleanConfigHasNoSchemaWarnings() {
        #expect(FacetConfig.load(source: "").schemaWarnings.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Volumes/workspace/github.com/akira-toriyama/facet && scripts/test.sh`
Expected: FAIL — `schemaWarnings` undefined (compile error).

- [ ] **Step 3: Add the import + stored field**

In `Sources/FacetCore/FacetConfig.swift`: add `import ConfigSchema` to the import block (after `import Toml`, ~line 26 — free, FacetCore already links ConfigSchema). Then add to `public struct FacetConfig`, alongside the raw fields (after `public var theme: String?`, ~line 47):

```swift
    /// A1: strict schema violations found on the LOAD path, recorded (not
    /// rejected) by `load(source:)`; emitted at startup/hot-reload by
    /// `Controller.logConfigWarnings()`. `[]` when clean or unparseable.
    public internal(set) var schemaWarnings: [ValidationError] = []
```

(`ValidationError` is `Sendable`, so `FacetConfig: Sendable` still holds.)

- [ ] **Step 4: Record violations in `load(source:)`**

In `Sources/FacetCore/FacetConfig+Decode.swift`, inside `load(source:)`, immediately before `return c` (currently line 407):

```swift
        // A1: run the STRICT schema validate on the LOAD path and RECORD any
        // violations as warnings — load still clamps/drops (never rejects).
        // The daemon surfaces these via Controller.logConfigWarnings at
        // startup + hot-reload. `try?`: syntactically-bad TOML can't be
        // strict-parsed and the lenient decode above already produced a
        // usable clamped config.
        c.schemaWarnings = (try? Self.validate(text)) ?? []
        return c
```

- [ ] **Step 5: Emit at the startup/reload seam**

In `Sources/FacetApp/Controller.swift`, extend `logConfigWarnings()` (lines 834-836):

```swift
    private func logConfigWarnings() {
        for warning in config.unknownValueWarnings() { Log.line(warning) }
        for v in config.schemaWarnings { Log.line("config: \(v.message)") }   // A1
    }
```

- [ ] **Step 6: Run tests to verify they pass + compile**

Run: `cd /Volumes/workspace/github.com/akira-toriyama/facet && swift build && scripts/test.sh`
Expected: PASS — both new tests green; existing `ConfigValidateTests` (incl. the committed-template clean guard) still green.

- [ ] **Step 7: Commit**

```bash
cd /Volumes/workspace/github.com/akira-toriyama/facet
git add Sources/FacetCore/FacetConfig.swift Sources/FacetCore/FacetConfig+Decode.swift Sources/FacetApp/Controller.swift Tests/FacetCoreTests/ConfigValidateTests.swift
git commit -m ":sparkles: feat(config): record + surface schema warnings on load (A1)"
```

---

## Notes / deferred

- **Enum-value double-line (facet):** a bad enum value (e.g. `[layout] default = "bogus"`) may be reported both by the existing `unknownValueWarnings()` clamp hint and by schema `.notInEnum`. Accepted as-is (unknown-keys and type/range mismatches are disjoint from `unknownValueWarnings`; only the enum-value case overlaps). No de-dupe — YAGNI.
- **wand hot-reload:** Task 1 wires the startup path (`runServer`) only. If wand has a ConfigWatcher reload call site equivalent to perch's `Controller.reload`, apply the same `warnSchemaViolations(...)` one-liner there in a follow-up; not required for A1's "surface at daemon load" goal.
- **A2 / A3** (perch dynamicTable inner shape / enum-literal DRY) are separate tasks (t-wnvm / t-5qxd) with their own plans.

## Self-review

- **Spec coverage (§3 A1):** validate on load path — Tasks 1/2/3 ✓. warn-not-reject + clamp preserved — asserted in each app's tests (`…DoesNotReject…` / `…StillClamps`) ✓. facet/perch/wand all covered ✓. `--validate` untouched — stated in Global Constraints + each task ✓.
- **Placeholder scan:** no TBD/TODO; every code step shows exact Swift. The "wand hot-reload" note is an explicit deferred non-goal, not a placeholder in a step. ✓
- **Type consistency:** `validate(_:) throws -> [ValidationError]` used consistently; `ValidationError.message`/`.rule` match sill `ValidationError.swift:20-81`; helper names distinct per app (`warnSchemaViolations` / `loadWarnings` / `schemaWarnings`) and each is defined before use ✓.
