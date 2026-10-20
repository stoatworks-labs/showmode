import Foundation
import IOKit
import os
import Security

/// The System Management Controller's keys, through AppleSMC's user client. Reading needs no
/// privileges; writing needs root. Undocumented, so a Mac without the service, or a macOS that
/// changes the call, reads as having no fans rather than failing.
final class SMC {
    /// SMCKeyData_t, field for field, with the padding C puts after the key info written out:
    /// Swift would otherwise pack `result` straight after `dataAttributes`.
    private struct KeyData {
        var key: UInt32 = 0
        var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var pLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        var pad: (UInt8, UInt8, UInt8) = (0, 0, 0)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private var conn: io_connect_t = 0

    init?() {
        guard MemoryLayout<KeyData>.size == 80 else { return nil }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(conn) }

    private static func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private func call(_ input: KeyData) -> KeyData? {
        var input = input
        var output = KeyData()
        var size = MemoryLayout<KeyData>.stride
        guard IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<KeyData>.stride, &output, &size) == kIOReturnSuccess,
              output.result == 0 else { return nil }
        return output
    }

    private func info(_ key: String) -> (size: UInt32, type: UInt32)? {
        var i = KeyData()
        i.key = Self.code(key)
        i.data8 = 9
        return call(i).map { ($0.dataSize, $0.dataType) }
    }

    func exists(_ key: String) -> Bool { info(key) != nil }

    func read(_ key: String) -> (type: UInt32, bytes: [UInt8])? {
        guard let k = info(key), k.size <= 32 else { return nil }
        var i = KeyData()
        i.key = Self.code(key)
        i.dataSize = k.size
        i.data8 = 5
        guard let o = call(i) else { return nil }
        return (k.type, withUnsafeBytes(of: o.bytes) { Array($0.prefix(Int(k.size))) })
    }

    @discardableResult
    func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        guard let k = info(key), Int(k.size) == bytes.count else { return false }
        var i = KeyData()
        i.key = Self.code(key)
        i.dataSize = k.size
        i.data8 = 6
        withUnsafeMutableBytes(of: &i.bytes) { b in for (n, v) in bytes.enumerated() { b[n] = v } }
        return call(i) != nil
    }

    func uint8(_ key: String) -> UInt8? {
        guard let r = read(key), r.bytes.count == 1 else { return nil }
        return r.bytes[0]
    }

    /// Apple silicon's "flt " keys are little-endian floats.
    func float(_ key: String) -> Float? {
        guard let r = read(key), r.type == Self.code("flt "), r.bytes.count == 4 else { return nil }
        return r.bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }

    @discardableResult
    func write(_ key: String, float v: Float) -> Bool {
        write(key, withUnsafeBytes(of: v) { Array($0) })
    }
}

/// The fans, held at full speed or at their slowest for a show. Apple silicon only: the keys
/// and the unlock follow Stats (exelban/stats) and were read on an M4 Max. A fan's mode key is
/// 1 for a fixed speed and 0 for macOS's own control. Up to the M4, macOS will not let go of
/// the fans until the SMC's test flag `Ftst` is set; later chips take the mode key directly.
enum Fans {
    enum Mode: String {
        case full, quiet
    }

    struct Fan {
        let index: Int
        let fixed: Bool
        let actual: Float
        let target: Float
        let min: Float
        let max: Float
    }

    /// "F0md" on the Macs that spell it that way, "F0Md" on the rest.
    private static func modeKey(_ smc: SMC, _ i: Int) -> String {
        smc.exists("F0md") ? "F\(i)md" : "F\(i)Md"
    }

    static func fans(_ smc: SMC) -> [Fan] {
        #if arch(arm64)
        let n = Int(smc.uint8("FNum") ?? 0)
        return (0..<n).compactMap { i in
            guard let mode = smc.uint8(modeKey(smc, i)), let target = smc.float("F\(i)Tg"),
                  let min = smc.float("F\(i)Mn"), let max = smc.float("F\(i)Mx") else { return nil }
            return Fan(index: i, fixed: mode != 0, actual: smc.float("F\(i)Ac") ?? 0, target: target, min: min, max: max)
        }
        #else
        return []
        #endif
    }

    static func fans() -> [Fan] { SMC().map(fans) ?? [] }

    /// Whether macOS has the fans: none fixed and the test flag clear (a Mac without one has
    /// nothing to clear).
    static func automatic(_ smc: SMC) -> Bool {
        !fans(smc).contains(where: \.fixed) && smc.uint8("Ftst") ?? 0 == 0
    }

    static var automatic: Bool { SMC().map(automatic) ?? true }

    static func want(_ mode: Mode, _ f: Fan) -> Float { mode == .full ? f.max : f.min }

    /// Every fan fixed at the speed `mode` asks for.
    static func held(_ mode: Mode, _ smc: SMC) -> Bool {
        let all = fans(smc)
        return !all.isEmpty && all.allSatisfy { $0.fixed && abs($0.target - want(mode, $0)) < 1 }
    }

    static func held(_ mode: Mode) -> Bool { SMC().map { held(mode, $0) } ?? false }

    /// Why the fans cannot be held on this Mac, or nil if they can.
    static var unavailable: String? {
        #if arch(arm64)
        guard let smc = SMC() else { return "Fans left alone: macOS did not let Show Mode read them" }
        if fans(smc).isEmpty { return "Fans left alone: this Mac has none Show Mode can control" }
        if !automatic(smc) { return "Fans left alone: another app is controlling them" }
        return nil
        #else
        return "Fans left alone: holding them needs an Apple silicon Mac"
        #endif
    }

    // MARK: Writing (root)

    /// Fixes every fan at the speed `mode` asks for. Tries each fan's mode key first; if the
    /// SMC refuses, sets the test flag and retries for up to ten seconds while macOS lets go
    /// (Stats waits three seconds, then retries).
    static func take(_ mode: Mode, _ smc: SMC) -> Bool {
        let all = fans(smc)
        guard !all.isEmpty else { return false }
        let keys = all.map { modeKey(smc, $0.index) }
        var pending = keys.filter { !smc.write($0, [1]) }
        if !pending.isEmpty, smc.exists("Ftst") {
            _ = retry(100, every: 50_000) { smc.write("Ftst", [1]) }
            _ = retry(100, every: 100_000) {
                pending = pending.filter { !smc.write($0, [1]) }
                return pending.isEmpty
            }
        }
        guard pending.isEmpty else { return false }
        for f in all where !smc.write("F\(f.index)Tg", float: want(mode, f)) { return false }
        return true
    }

    /// Hands every fixed fan back to macOS, as Stats does: mode 0 and target 0, then the test
    /// flag cleared. A fan macOS already has is not touched.
    @discardableResult
    static func release(_ smc: SMC) -> Bool {
        var ok = true
        for f in fans(smc) where f.fixed {
            ok = retry(10, every: 50_000) { smc.write(modeKey(smc, f.index), [0]) } && ok
            smc.write("F\(f.index)Tg", float: 0)
        }
        if smc.uint8("Ftst") ?? 0 != 0 { ok = retry(10, every: 50_000) { smc.write("Ftst", [0]) } && ok }
        return ok && automatic(smc)
    }

    private static func retry(_ times: Int, every micros: useconds_t, _ body: () -> Bool) -> Bool {
        for n in 0..<times {
            if body() { return true }
            if n < times - 1 { usleep(micros) }
        }
        return false
    }

    /// For `--status`.
    static var summary: String {
        let all = fans()
        guard !all.isEmpty else { return "none readable" }
        let each = all.map { "\(Int($0.actual)) rpm \($0.fixed ? "fixed at \(Int($0.target))" : "auto") (\(Int($0.min))–\(Int($0.max)))" }
        return each.joined(separator: ", ") + (automatic ? "" : ", held")
    }
}

/// The root process that holds the fans for the show, and gives them back to macOS however
/// the show ends.
///
/// It is Show Mode's own executable, started from the show's one admin prompt with `--fans`.
/// Root never runs the copy in the app bundle, which the user could rewrite mid-show: the
/// admin step copies the whole bundle into a directory only root can write, checks the copy
/// with `codesign` against the running app's own designated requirement, and runs that.
///
/// Like the root sweeper, it listens on a FIFO Show Mode holds open, and gives the fans back
/// and exits when Show Mode writes "stop", when Show Mode goes away for any reason (its end
/// closes), on SIGTERM or SIGINT, or after `Sweeper.lifetime`. A crash therefore hands
/// the fans back rather than leaving them fixed.
///
/// Every two seconds it checks the fans are still where it put them. Quiet mode hands them back
/// while the Mac is hot enough to be slowing itself down, and takes them again once it has
/// been cool for five minutes. Something that keeps taking them back is let go, not fought.
final class FanHold {
    static let shared = FanHold()

    /// Only root can write /var/run, so nothing else can swap the copy between the check
    /// and the run. Cleared at startup.
    static let directory = "/private/var/run/com.stoatworks.showmode.fans"
    private static let copy = directory + "/Show Mode.app"

    private var writer: FileHandle?
    private var fifo: URL?

    // MARK: App side

    /// Why Show Mode cannot start the helper, or nil.
    static var cannotStart: String? {
        Bundle.main.bundlePath.hasSuffix(".app") && requirement != nil
            ? nil : "Fans left alone: Show Mode is not running from its signed app"
    }

    /// The running app's designated requirement, which the root copy must meet: any Show
    /// Mode signed by the same Developer ID, or this exact build for an ad hoc one.
    private static var requirement: String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var req: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &req) == errSecSuccess, let req,
              SecRequirementCopyString(req, [], &text) == errSecSuccess, let text
        else { return nil }
        return text as String
    }

    /// One shell command: copies the bundle to `directory`, checks the copy, then runs it with
    /// `args`, in the background if asked. Nothing runs unless the check passes, and the
    /// command fails if it does not.
    private static func verified(_ args: [String], background: Bool) -> String? {
        guard cannotStart == nil, let req = requirement, let exe = Bundle.main.executableURL?.lastPathComponent
        else { return nil }
        let d = Shell.quote(directory), c = Shell.quote(copy)
        let run = ([copy + "/Contents/MacOS/" + exe] + args).map(Shell.quote).joined(separator: " ")
        return "/bin/rm -rf \(d) && /bin/mkdir -m 700 \(d)"
            + " && /usr/bin/ditto --noqtn \(Shell.quote(Bundle.main.bundlePath)) \(c)"
            + " && /usr/bin/codesign --verify --strict --arch arm64 --test-requirement=\(Shell.quote("=" + req)) \(c)"
            // Nothing may hold the batch's output, or the prompt waits for the helper to exit.
            + " && " + (background ? "{ \(run) </dev/null >/dev/null 2>&1 & }" : run)
    }

    /// Opens the FIFO and returns the admin step that starts the helper on it. `close()` it if
    /// the admin prompt is cancelled.
    func step(_ mode: Fans.Mode) -> AdminStep? {
        guard writer == nil else { return nil }
        let url = Journal.directory.appendingPathComponent("fans.fifo")
        unlink(url.path)
        guard mkfifo(url.path, 0o600) == 0 else { return nil }
        let fd = open(url.path, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else { unlink(url.path); return nil }
        guard let cmd = Self.verified(["--fans", mode.rawValue, url.path, String(Sweeper.lifetime)], background: true) else {
            Darwin.close(fd)
            unlink(url.path)
            return nil
        }
        writer = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        fifo = url
        ShowLog.note("fans: starting the helper (\(mode.rawValue))")
        return AdminStep(label: "Fans", journalKeys: ["fans"], commands: [cmd])
    }

    /// Tells the helper to give the fans back and exit.
    func stop() {
        guard let w = writer else { return }
        try? w.write(contentsOf: Data("stop\n".utf8))
        close()
    }

    func close() {
        try? writer?.close()
        writer = nil
        if let fifo { unlink(fifo.path) }
        fifo = nil
    }

    /// Whether a helper is running, this session's or one left behind.
    static var running: Bool {
        (Shell.run("/bin/ps", ["-axo", "user=,command="])?.out ?? "").split(separator: "\n").contains {
            $0.hasPrefix("root ") && $0.contains(directory + "/")
        }
    }

    /// After the prompt: waits for the helper to fix the fans, which takes a few seconds when
    /// macOS has to be talked out of them.
    static func confirmHeld(_ mode: Fans.Mode, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if Fans.held(mode) { return true }
            usleep(250_000)
        } while Date() < deadline
        return false
    }

    /// After "stop": waits for the helper to hand the fans back and exit.
    static func waitForRelease(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while (running || !Fans.automatic) && Date() < deadline { usleep(250_000) }
        return !running && Fans.automatic
    }

    /// After a show: kills a helper that never exited and hands the fans back with a fresh
    /// checked copy.
    static func resetStep() -> AdminStep? {
        guard let cmd = verified(["--fans", "auto"], background: false) else { return nil }
        return AdminStep(label: "Fans", journalKeys: ["fans"],
                         commands: ["/usr/bin/pkill -KILL -f \(Shell.quote(directory.replacingOccurrences(of: ".", with: "\\.") + "/")) || true", cmd])
    }

    // MARK: Root side

    private static let log = Logger(subsystem: "com.stoatworks.showmode", category: "fans")

    /// Hot enough that macOS is slowing the Mac down: when quiet mode lets go.
    static var hot: Bool { ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
    private static var stopRequested: sig_atomic_t = 0

    /// `--fans auto` hands the fans back and exits; `--fans full|quiet <fifo> <seconds>` holds
    /// them until told to stop. Returns the exit status.
    static func main(_ args: [String]) -> Int32 {
        guard let smc = SMC() else { return 1 }
        if args.first == "auto" { return Fans.release(smc) ? 0 : 1 }
        guard args.count == 3, let mode = Fans.Mode(rawValue: args[0]), let life = TimeInterval(args[2]) else { return 2 }

        // SIGHUP stays ignored, as Show Mode leaves it: the admin batch ending is no reason to
        // let go. A shutdown sends SIGTERM.
        for sig in [SIGTERM, SIGINT] { signal(sig) { _ in FanHold.stopRequested = 1 } }
        // A FIFO, and not a link to one: root is opening a path in the user's Library.
        let fd = open(args[1], O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        var st = stat()
        guard fd >= 0, fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFIFO else { return 3 }
        Thread.detachNewThread {
            var b = [UInt8](repeating: 0, count: 64)
            _ = read(fd, &b, b.count)    // "stop", or end of file when Show Mode goes
            FanHold.stopRequested = 1
        }

        // Quiet mode, while macOS has the fans back: since when the Mac has been cool.
        var handedBack = false
        var coolSince: Date?
        if mode == .quiet && FanHold.hot {
            log.notice("running hot at the start: fans stay with macOS until it cools")
            handedBack = true
        } else if Fans.take(mode, smc) {
            log.notice("holding the fans (\(mode.rawValue, privacy: .public))")
        } else {
            log.error("could not take the fans (\(mode.rawValue, privacy: .public))")
            Fans.release(smc)
            return 4
        }

        let end = Date().addingTimeInterval(life)
        var retakes: [Date] = []
        var tick = 0
        while stopRequested == 0 && Date() < end {
            usleep(250_000)
            tick += 1
            guard tick % 8 == 0 else { continue }
            let now = Date()
            if mode == .quiet {
                if handedBack {
                    coolSince = ProcessInfo.processInfo.thermalState == .nominal ? coolSince ?? now : nil
                    guard let since = coolSince, now.timeIntervalSince(since) >= 300 else { continue }
                    handedBack = false
                    coolSince = nil
                    log.notice("cool again: quiet fans")
                    if !Fans.take(mode, smc) { break }
                    continue
                }
                if hot {
                    log.notice("running hot: fans back to macOS")
                    Fans.release(smc)
                    handedBack = true
                    continue
                }
            }
            guard !Fans.held(mode, smc) else { continue }
            retakes = retakes.filter { now.timeIntervalSince($0) < 60 } + [now]
            if retakes.count > 4 {
                log.notice("something keeps taking the fans back: letting go")
                break
            }
            log.notice("fans changed under us: taking them again")
            if !Fans.take(mode, smc) { break }
        }
        let ok = Fans.release(smc)
        log.notice("fans back to macOS (\(ok ? "done" : "incomplete", privacy: .public))")
        return ok ? 0 : 5
    }
}
