// LogKit — the family's shared two-level logger, lifted from six
// byte-similar copies (facet / wand / perch / chord / halo / glance).
//
// Mechanism only. The app supplies its name; from it follow the file
// (`/tmp/<app>.log`) and the switch (`<APP>_DEBUG` in the environment,
// presence is the signal — every copy tested `!= nil`, and `=0` staying
// on is a known family quirk, kept so no launch script changes meaning).
// What to log, and any extra channel (wand's `--validate` mirror, chord's
// per-event watch file), stays in the app.
//
// Contract every copy relied on and this one keeps:
//   * `line` always reaches the file; `debug` only when the switch is on
//     (one bool check on the off path — the message is an autoclosure and
//     is never built).
//   * With the switch on, both levels mirror to stderr so a foreground
//     run streams live and `2>&1 | tee` captures everything; with it off,
//     stderr stays silent so a backgrounded daemon does not pollute the
//     shell that launched it.
//   * One line per write, flushed to the kernel before `line` returns —
//     `/tmp/<app>.log` is the crash-triage record, so nothing may sit in a
//     userland buffer when the process dies.
//
// What changed versus the copies: one appending handle per process
// instead of open / seek / write / close per line (perch logs ~130 sites,
// t-qz19). O_APPEND makes the kernel place every write at the current
// end, so several processes on the same file (chord's daemon and client)
// interleave whole lines instead of overwriting each other's tail. The
// handle is dropped and reopened when the file was unlinked underneath
// it (`rm /tmp/<app>.log` while a daemon runs), because a write into an
// unlinked inode is lost silently — the per-line reopen of the old copies
// recreated the file for free, and that behaviour must survive.

import Foundation

public final class Log: @unchecked Sendable {
    /// The file every line appends to.
    public let path: String
    /// Whether `debug` emits. A launch-time constant, never toggled later.
    public let debugEnabled: Bool

    private let stderr: FileHandle
    private let lock = NSLock()
    private var handle: FileHandle?
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// The family default: `/tmp/<app>.log`, switched by `<APP>_DEBUG`
    /// (the app name upper-cased). `environment` is a seam for tests.
    public convenience init(app: String,
                            environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(path: "/tmp/\(app).log",
                  debugEnabled: environment["\(app.uppercased())_DEBUG"] != nil)
    }

    /// Everything explicit. `stderr` is the mirror target; production never
    /// passes it, tests hand in a pipe.
    public init(path: String, debugEnabled: Bool,
                stderr: FileHandle = .standardError) {
        self.path = path
        self.debugEnabled = debugEnabled
        self.stderr = stderr
    }

    /// Always on.
    public func line(_ message: @autoclosure () -> String) {
        emit(message(), prefix: "")
    }

    /// Only when `debugEnabled`; the message is not built otherwise.
    public func debug(_ message: @autoclosure () -> String) {
        guard debugEnabled else { return }
        emit(message(), prefix: "DEBUG ")
    }

    private func emit(_ message: String, prefix: String) {
        lock.lock()
        defer { lock.unlock() }
        let data = Data("\(formatter.string(from: Date())) \(prefix)\(message)\n".utf8)
        if let h = openedHandle() {
            try? h.write(contentsOf: data)
        }
        if debugEnabled {
            try? stderr.write(contentsOf: data)
        }
    }

    // Caller holds `lock`.
    private func openedHandle() -> FileHandle? {
        if let h = handle {
            var st = stat()
            if fstat(h.fileDescriptor, &st) == 0, st.st_nlink > 0 { return h }
            handle = nil   // unlinked (or unreadable) underneath us: reopen below
        }
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return nil }   // unwritable path: file output is dropped, never fatal
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle = h
        return h
    }
}
