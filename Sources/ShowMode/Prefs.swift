import Foundation

/// A preference key in another app's domain, read and written through cfprefsd so the
/// owning process sees the change (after it rereads — the Dock needs a restart).
struct PrefKey {
    let domain: String      // "NSGlobalDomain" for the global domain
    let key: String
    var currentHost = false

    var id: String { "\(domain)|\(key)|\(currentHost ? "host" : "any")" }

    private var cfApp: CFString {
        domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : domain as CFString
    }
    private var cfHost: CFString { currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost }

    func read() -> Any? {
        CFPreferencesCopyValue(key as CFString, cfApp, kCFPreferencesCurrentUser, cfHost) as Any?
    }

    func write(_ value: Any?) {
        CFPreferencesSetValue(key as CFString, value as CFPropertyList?, cfApp, kCFPreferencesCurrentUser, cfHost)
        CFPreferencesSynchronize(cfApp, kCFPreferencesCurrentUser, cfHost)
    }

    /// Journals the current value, then writes the new one. Returns whether anything changed.
    @discardableResult
    func override(_ value: Any) -> Bool {
        let old = read()
        if let old = old as? NSObject, old.isEqual(value) { return false }
        Journal.shared.recordPref(self, previous: old)
        write(value)
        return true
    }
}

enum Prefs {
    static let hotCornerKeys: [PrefKey] = ["tl", "tr", "bl", "br"].flatMap {
        [PrefKey(domain: "com.apple.dock", key: "wvous-\($0)-corner"),
         PrefKey(domain: "com.apple.dock", key: "wvous-\($0)-modifier")]
    }

    /// Restores every journaled preference. Returns the domains touched so the caller can
    /// restart the processes that only read them at launch.
    static func restoreAll() -> Set<String> {
        let prefs = Journal.shared["prefs"] as? [[String: Any]] ?? []
        var domains = Set<String>()
        for e in prefs {
            guard let domain = e["domain"] as? String, let key = e["key"] as? String else { continue }
            let p = PrefKey(domain: domain, key: key, currentHost: e["currentHost"] as? Bool ?? false)
            p.write(e["value"])
            domains.insert(domain)
        }
        return domains
    }
}

enum Shell {
    /// Runs a tool and returns stdout (nil if it failed to launch or timed out).
    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 15) -> (status: Int32, out: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return nil }
        // Drained while it runs: output past the pipe's 64 KB would otherwise block the tool
        // until the timeout.
        let out = OutputBox()
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global().async {
            out.data = pipe.fileHandleForReading.readDataToEndOfFile()
            reading.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        // SIGKILL: anything Show Mode starts inherits SIGTERM ignored.
        if p.isRunning { kill(p.processIdentifier, SIGKILL); return nil }
        // Something else still holding the pipe: give up on the output rather than read it
        // while the reader may still be writing it.
        guard reading.wait(timeout: .now() + 2) == .success else { return (p.terminationStatus, "") }
        return (p.terminationStatus, String(decoding: out.data, as: UTF8.self))
    }

    static func killall(_ name: String) { run("/usr/bin/killall", [name]) }

    /// One argument, quoted for /bin/sh.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// One administrator prompt for every step. Each command runs whatever happened to the
    /// one before it, so one failure no longer skips the rest. Returns the indices of the
    /// steps that failed, or nil if the prompt was cancelled and nothing ran. `privileged`
    /// false runs the same script as the user, for bench tests.
    static func runAsAdmin(_ steps: [AdminStep], prompt: String, privileged: Bool = true) -> Set<Int>? {
        guard !steps.isEmpty else { return [] }
        var lines: [String] = []
        for (i, step) in steps.enumerated() {
            for cmd in step.commands {
                // A newline, not "; ", ends each group: a command may end in "&".
                if cmd.hasSuffix("&") {
                    // Started in the background: nothing may hold its output, or the batch
                    // waits for it to exit.
                    lines.append("{ \(cmd)\n} </dev/null >/dev/null 2>&1")
                    lines.append("echo \"showmode-step \(i) $?\"")
                } else {
                    // Kept, so the log can say why a command failed.
                    lines.append("out=$({ \(cmd)\n} </dev/null 2>&1); rc=$?")
                    lines.append("echo \"showmode-step \(i) $rc\"")
                    lines.append("[ $rc = 0 ] || printf '%s\\n' \"$out\" | /usr/bin/head -c 400 | /usr/bin/sed \"s/^/showmode-out \(i) /\"")
                }
            }
        }
        // AppleScript's own \n turns into the newlines between the shell lines.
        let script = lines.map {
            $0.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
              .replacingOccurrences(of: "\n", with: "\\n")
        }.joined(separator: "\\n")
        let src = "do shell script \"\(script)\"" + (privileged ? " with prompt \"\(prompt)\" with administrator privileges" : "")
        var err: NSDictionary?
        let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err {
            ShowLog.note("admin prompt: nothing ran (\(err[NSAppleScript.errorMessage] ?? err))")
            return nil
        }
        var failed = Set<Int>()
        var said: [Int: [String]] = [:]
        for line in (out?.stringValue ?? "").components(separatedBy: .newlines) {
            let f = line.split(separator: " ", maxSplits: 2)
            guard f.count >= 2, let i = Int(f[1]), steps.indices.contains(i) else { continue }
            if f[0] == "showmode-step", f.count == 3, let rc = Int(f[2]), rc != 0 { failed.insert(i) }
            if f[0] == "showmode-out" { said[i, default: []].append(f.count == 3 ? String(f[2]) : "") }
        }
        for i in failed.sorted() {
            ShowLog.note("admin step failed: \(steps[i].label) \(steps[i].commands): \(said[i, default: []].joined(separator: " / "))")
        }
        return failed
    }
}

private final class OutputBox { var data = Data() }

/// Commands that need root, for one guard, and the journal entries they depend on. Engage
/// journals what they replace before the prompt. A cancelled engage prompt puts those entries
/// back as they were; a failed step keeps them, since some of its commands may have run. On
/// restore a failed step keeps its entries, so Finish Restoring and the next launch try again.
struct AdminStep {
    let label: String
    let journalKeys: [String]
    let commands: [String]
}
