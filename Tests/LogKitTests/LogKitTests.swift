// LogKit — unit tests. CI only (the maintainer's machine is
// CommandLineTools-only; `import XCTest` needs full Xcode). Every write
// goes to a per-test temp directory, never to /tmp/<app>.log.

import XCTest
@testable import LogKit

final class LogKitTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func path(_ name: String = "app.log") -> String {
        dir.appendingPathComponent(name).path
    }

    private func lines(_ p: String) throws -> [String] {
        let text = try String(contentsOfFile: p, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: the family default

    func testAppNameDerivesPathAndSwitch() {
        let off = Log(app: "glance", environment: [:])
        XCTAssertEqual(off.path, "/tmp/glance.log")
        XCTAssertFalse(off.debugEnabled)

        let on = Log(app: "glance", environment: ["GLANCE_DEBUG": "1"])
        XCTAssertTrue(on.debugEnabled)
    }

    func testSwitchIsPresenceNotValue() {
        // Every copy tested `!= nil`: an empty value and "0" both switch on.
        XCTAssertTrue(Log(app: "perch", environment: ["PERCH_DEBUG": ""]).debugEnabled)
        XCTAssertTrue(Log(app: "perch", environment: ["PERCH_DEBUG": "0"]).debugEnabled)
        XCTAssertFalse(Log(app: "perch", environment: ["PERCHDEBUG": "1"]).debugEnabled)
    }

    // MARK: file output

    func testLineAppendsTimestampedLines() throws {
        let log = Log(path: path(), debugEnabled: false)
        log.line("first")
        log.line("second")
        let got = try lines(path())
        XCTAssertEqual(got.count, 2)
        XCTAssertTrue(got[0].hasSuffix(" first"), got[0])
        XCTAssertTrue(got[1].hasSuffix(" second"), got[1])
        // ISO 8601 with fractional seconds and a zone, then one space.
        let stamp = got[0].dropLast(" first".count)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: String(stamp).replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)), String(stamp))
    }

    func testDebugIsSilentWhenOff() throws {
        let log = Log(path: path(), debugEnabled: false)
        var built = false
        log.debug({ built = true; return "never" }())
        XCTAssertFalse(built, "the autoclosure must not run on the off path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path()),
                       "nothing was written, so the file is not even created")
    }

    func testDebugWritesWithPrefixWhenOn() throws {
        let log = Log(path: path(), debugEnabled: true)
        log.debug("probe")
        log.line("plain")
        let got = try lines(path())
        XCTAssertEqual(got.count, 2)
        XCTAssertTrue(got[0].hasSuffix(" DEBUG probe"), got[0])
        XCTAssertTrue(got[1].hasSuffix(" plain"), got[1])
    }

    func testTwoWritersOnOneFileInterleaveWholeLines() throws {
        // chord's daemon and client both append to /tmp/chord.log.
        let a = Log(path: path(), debugEnabled: false)
        let b = Log(path: path(), debugEnabled: false)
        a.line("a1")
        b.line("b1")
        a.line("a2")
        let got = try lines(path()).map { String($0.split(separator: " ").last!) }
        XCTAssertEqual(got, ["a1", "b1", "a2"])
    }

    func testReopensAfterTheFileIsUnlinked() throws {
        let log = Log(path: path(), debugEnabled: false)
        log.line("before")
        try FileManager.default.removeItem(atPath: path())
        log.line("after")
        let got = try lines(path())
        XCTAssertEqual(got.count, 1)
        XCTAssertTrue(got[0].hasSuffix(" after"), got[0])
    }

    func testSurvivesTruncation() throws {
        let log = Log(path: path(), debugEnabled: false)
        log.line("old")
        try Data().write(to: URL(fileURLWithPath: path()))
        log.line("new")
        let got = try lines(path())
        XCTAssertEqual(got.count, 1)
        XCTAssertTrue(got[0].hasSuffix(" new"), got[0])
    }

    func testUnwritablePathIsNotFatal() {
        let log = Log(path: dir.appendingPathComponent("missing/dir/app.log").path,
                      debugEnabled: false)
        log.line("dropped")
        log.line("dropped again")
    }

    // MARK: stderr mirror

    func testMirrorsBothLevelsToStderrOnlyWhenOn() throws {
        let pipe = Pipe()
        let on = Log(path: path("on.log"), debugEnabled: true,
                     stderr: pipe.fileHandleForWriting)
        on.line("L")
        on.debug("D")
        try pipe.fileHandleForWriting.close()
        let mirrored = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let got = mirrored.split(separator: "\n").map(String.init)
        XCTAssertEqual(got.count, 2)
        XCTAssertTrue(got[0].hasSuffix(" L"))
        XCTAssertTrue(got[1].hasSuffix(" DEBUG D"))

        let quiet = Pipe()
        let off = Log(path: path("off.log"), debugEnabled: false,
                      stderr: quiet.fileHandleForWriting)
        off.line("L")
        try quiet.fileHandleForWriting.close()
        XCTAssertTrue(quiet.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }
}
