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
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func killall(_ name: String) { run("/usr/bin/killall", [name]) }

    /// One administrator prompt for a batch of shell commands. Returns false if cancelled.
    static func runAsAdmin(_ commands: [String], prompt: String) -> Bool {
        guard !commands.isEmpty else { return true }
        let joined = commands.joined(separator: " && ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(joined)\" with prompt \"\(prompt)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err { NSLog("ShowMode admin command failed: \(err)") }
        return err == nil
    }
}
