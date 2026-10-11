import Foundation

/// Pauses background processes by name for the show, and resumes them however the show ends.
///
/// A small shell loop sends SIGSTOP to every process with one of the given exact names every
/// two seconds, so a copy launchd starts mid-show is caught too. It resumes them all (SIGCONT)
/// and exits when Show Mode writes "stop", when Show Mode goes away for any reason — its end of
/// the pipe closes, which a crash or `kill -9` does too — or after three days as a backstop. It
/// never watches Show Mode's pid: pids get reused.
///
/// The user-level sweeper is Show Mode's child, fed through a pipe. Processes that are not the
/// user's (Spotlight's `_spotlight` workers) need root, so that sweeper is started from the
/// show's one admin prompt and listens on a FIFO Show Mode holds open. Its script is passed
/// inline, never run from a file the user could rewrite.
///
/// Only exact names on the lists in `Paused` are ever stopped. Stopping logd, WindowServer,
/// configd, opendirectoryd or fseventsd panics the Mac or loses file events for every app;
/// stopping mds or mds_stores hangs every Spotlight search.
final class Sweeper {
    static let user = Sweeper()
    static let root = Sweeper()

    /// Three days; a show that runs longer gets its background work back. Writing "stop" to
    /// a sweeper that has already gone is harmless (see `startUser`).
    static let lifetime = 3 * 24 * 3600

    /// No single quotes: it travels inside them. Arguments: the FIFO (or "-" for stdin), the
    /// lifetime in seconds, then process names, plus "awdl" to hold the AWDL interface down.
    /// One blocking read covers all three ways out (a "stop" line, end of file, the lifetime
    /// timing out), because bash 3.2 reports a timeout and end of file alike. The sweeping
    /// child is stopped with SIGKILL: started from the admin prompt, both processes run with
    /// SIGTERM ignored, and bash can neither trap nor reset a signal ignored at its start.
    static let script = """
        src=$1; life=$2; shift 2
        awdl=0; names=
        for a in "$@"; do if [ "$a" = awdl ]; then awdl=1; else names="$names $a"; fi; done
        if [ "$src" = - ]; then exec 3<&0; else exec 3<"$src"; fi
        sweep() { while :; do for n in $names; do /usr/bin/pkill -STOP -x "$n"; done; if [ $awdl = 1 ]; then /sbin/ifconfig awdl0 down; fi; /bin/sleep 2; done; }
        sweep 3<&- &
        finish() { kill -KILL %1 2>/dev/null; wait; for i in 1 2; do for n in $names; do /usr/bin/pkill -CONT -x "$n"; done; if [ $awdl = 1 ]; then /sbin/ifconfig awdl0 up; fi; /bin/sleep 1; done; exit 0; }
        trap finish TERM HUP INT
        read -t "$life" -r line <&3
        finish
        """

    private var writer: FileHandle?
    private var process: Process?
    private var fifo: URL?

    var running: Bool { writer != nil }

    /// Starts sweeping the user's own processes. Returns false if the shell would not start.
    func startUser(_ names: [String]) -> Bool {
        guard writer == nil else { return true }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", Self.script, "showmode-sweeper", "-", String(Self.lifetime)] + names
        let pipe = Pipe()
        p.standardInput = pipe
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        // Only this child may hold the write end: one inherited by anything else would keep
        // the pipe open after a crash, and the processes would stay paused.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)
        // A sweeper gone before "stop" (its lifetime ran out, or it was killed) leaves no
        // reader: the write must fail quietly, not raise SIGPIPE and take the restore with it.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try p.run() } catch { return false }
        try? pipe.fileHandleForReading.close()
        writer = pipe.fileHandleForWriting
        process = p
        ShowLog.note("sweeper (user): pausing \(names.joined(separator: ", "))")
        return true
    }

    /// Opens the FIFO and returns the admin step that starts a root sweeper on it. The FIFO
    /// is held read-write, so the sweeper's open never blocks and only Show Mode's exit (or
    /// "stop") ends it. `close()` it if the admin prompt is cancelled.
    func rootStep(_ names: [String], awdl: Bool, label: String, journalKeys: [String]) -> AdminStep? {
        guard writer == nil else { return nil }
        let url = Journal.directory.appendingPathComponent("sweeper.fifo")
        unlink(url.path)
        guard mkfifo(url.path, 0o600) == 0 else { return nil }
        let fd = open(url.path, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else { unlink(url.path); return nil }
        writer = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        fifo = url
        let args = [Self.script, "showmode-sweeper", url.path, String(Self.lifetime)] + names + (awdl ? ["awdl"] : [])
        ShowLog.note("sweeper (root): pausing \((names + (awdl ? ["awdl0"] : [])).joined(separator: ", "))")
        return AdminStep(label: label, journalKeys: journalKeys,
                         commands: ["/bin/bash -c " + args.map(Shell.quote).joined(separator: " ") + " &"])
    }

    /// Tells the sweeper to resume everything and exit. It takes a couple of seconds; see
    /// `waitForResume`.
    func stop() {
        guard let w = writer else { return }
        try? w.write(contentsOf: Data("stop\n".utf8))
        close()
    }

    func close() {
        try? writer?.close()
        writer = nil
        process = nil
        if let fifo { unlink(fifo.path) }
        fifo = nil
    }

    // MARK: Reading back

    /// Whether a root sweeper is running, this session's or one left behind. ps shows root's
    /// command lines without root.
    static var rootRunning: Bool {
        (Shell.run("/bin/ps", ["-axo", "user=,command="])?.out ?? "").split(separator: "\n").contains {
            $0.hasPrefix("root ") && $0.contains("showmode-sweeper")
        }
    }

    /// Every process with one of `names`: its pid, its name and whether it is stopped. The
    /// name is ps's `ucomm`, the same short name `pkill -x` matches.
    static func processes(_ names: [String]) -> [(pid: pid_t, name: String, stopped: Bool)] {
        guard !names.isEmpty, let out = Shell.run("/bin/ps", ["-axo", "pid=,stat=,ucomm="])?.out else { return [] }
        let wanted = Set(names)
        return out.split(separator: "\n").compactMap { line in
            let f = line.split(whereSeparator: \.isWhitespace)
            guard f.count >= 3, let pid = pid_t(f[0]) else { return nil }
            let name = f[2...].joined(separator: " ")
            guard wanted.contains(name) else { return nil }
            return (pid, name, f[1].hasPrefix("T"))
        }
    }

    static func stopped(_ names: [String]) -> [pid_t] {
        processes(names).filter(\.stopped).map(\.pid)
    }

    /// Waits up to `timeout` for every process with one of `names` to be running again, then
    /// resumes any of the user's own that are not. Returns the names still stopped, which
    /// only root can resume.
    static func waitForResume(_ names: [String], timeout: TimeInterval = 4) -> [String] {
        guard !names.isEmpty else { return [] }
        let deadline = Date().addingTimeInterval(timeout)
        while !stopped(names).isEmpty && Date() < deadline { usleep(250_000) }
        for pid in stopped(names) { kill(pid, SIGCONT) }
        return Array(Set(processes(names).filter(\.stopped).map(\.name))).sorted()
    }

    /// Waits up to `timeout` for the sweeper to pause something, as proof it started. True
    /// when nothing by those names is running to pause.
    static func confirmStarted(_ names: [String], timeout: TimeInterval = 3) -> Bool {
        guard !processes(names).isEmpty else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !stopped(names).isEmpty { return true }
            usleep(250_000)
        } while Date() < deadline
        return false
    }
}

/// The exact process names the sweepers pause.
enum Paused {
    /// Photos' and the system's image and video analysis (faces, scenes, Live Text). User
    /// agents: no password. Photos, Live Text and Visual Look Up wait while they are paused.
    static let mediaAnalysis = ["photoanalysisd", "mediaanalysisd"]
    /// Spotlight's importers, which read new and changed files (a drive plugged in mid-show
    /// included). Never mds or mds_stores, which answer searches: they keep running and keep
    /// taking file events, so indexing should catch up once the workers resume rather than
    /// start again (read from Apple's source, not yet measured). mds kills and respawns a
    /// worker that stops answering; the sweep pauses the new one too.
    static let spotlight = ["mdworker_shared", "mdworker"]
}
