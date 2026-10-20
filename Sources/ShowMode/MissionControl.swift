import Foundation

/// Mission Control, App Exposé and Show Desktop. The Dock reads `mcx-expose-disabled` and then
/// asks `CFPreferencesAppValueIsForced` about it (macOS 26.4.1's Dock, by disassembly): a value
/// in the user's own preferences changes nothing, and ⌃↑, ⌃↓ and apps that call
/// `CoreDockSendNotification` all still open it. Logi Options+ does that for mouse buttons set
/// to Mission Control or App Exposé, so no shortcut or event guard can stop it. Two guards, then:
///
/// - the shortcuts, off in WindowServer as ⌘Space is (no password, keyboard only);
/// - the key forced, as a configuration profile would force it, by a file in
///   /Library/Managed Preferences (root), which the Dock obeys for every route.
enum MissionControl {
    /// Mission Control ⌃↑ (32), Application windows ⌃↓ (33), their ⇧ slow-motion twins (34,
    /// 35), Show Desktop F11 and ⇧F11 (36, 37), and the Mission Control key with each modifier
    /// (108–117, key code 160), read from CGSGetSymbolicHotKeyValue on macOS 26.4.1.
    static let hotKeys: [Int32] = [32, 33, 34, 35, 36, 37] + Array(108...117)

    static var keysOn: [Int32]? { SymbolicHotKeys.on(hotKeys) }

    /// Returns false if the shortcuts could not be switched off.
    static func engageKeys() -> Bool { SymbolicHotKeys.disable(hotKeys, journalKey: "missionControlKeys") }

    static func restoreKeys() { SymbolicHotKeys.restore(journalKey: "missionControlKeys") }

    // MARK: Forced

    static let dock = "com.apple.dock" as CFString
    static let key = "mcx-expose-disabled" as CFString
    static let stateFlag = "--mission-control-state"

    /// The folder cfprefsd reads this user's managed preferences from, and the Dock's file in it.
    private static var folders: [String] { ["/Library/Managed Preferences", "/Library/Managed Preferences/\(NSUserName())"] }
    private static var file: String { folders[1] + "/com.apple.dock.plist" }

    /// What a fresh process hears from cfprefsd: whether the key is forced, and whether it is
    /// on. A process that has read the Dock's preferences keeps the answer it first got, whatever
    /// cfprefsd says later and with CFPreferencesAppSynchronize (measured: the process that ran
    /// the write read "not forced" for three seconds after it, a new one "forced" at once), so
    /// Show Mode asks its own executable. nil if that could not run.
    static var state: (forced: Bool, on: Bool)? {
        guard let exe = Bundle.main.executablePath,
              let r = Shell.run(exe, [stateFlag], timeout: 5), r.status == 0 else { return nil }
        let words = Set(r.out.split(whereSeparator: \.isWhitespace).map(String.init))
        guard words.contains("state") else { return nil }
        return (words.contains("forced"), words.contains("on"))
    }

    /// Answers `state`, in the fresh process.
    static func printState() {
        let forced = CFPreferencesAppValueIsForced(key, dock)
        let on = (CFPreferencesCopyAppValue(key, dock) as? Bool) == true
        print("state", forced ? "forced" : "free", on ? "on" : "off")
    }

    /// Whether the Dock's key is forced on.
    static var forced: Bool { state.map { $0.forced && $0.on } ?? false }

    enum Engage {
        case step(AdminStep)
        /// Already forced on by a configuration profile: nothing to do.
        case alreadyForced
        /// The Mac's own managed settings are there; they are left alone.
        case managed
    }

    /// Journals which of the two folders do not exist yet, so restore removes only those. A
    /// leftover entry (a restore that never finished) is kept: the file in it is show mode's.
    static func engage() -> Engage {
        if Journal.shared["forcedExpose"] == nil {
            let now = state ?? (false, false)
            if now.forced && now.on { return .alreadyForced }
            if now.forced || FileManager.default.fileExists(atPath: file) { return .managed }
            Journal.shared["forcedExpose"] = ["createdFolders": folders.filter { !FileManager.default.fileExists(atPath: $0) }]
        }
        let f = Shell.quote(file)
        return .step(AdminStep(label: "Mission Control for mouse apps", journalKeys: ["forcedExpose"], commands: [
            "/bin/mkdir -p \(Shell.quote(folders[1])) && /usr/bin/plutil -create xml1 \(f) && " +
            "/usr/bin/plutil -replace mcx-expose-disabled -bool YES \(f) && /bin/chmod 644 \(f)",
        ]))
    }

    /// Removes the file and the folders show mode made, deepest first. Safe to run twice.
    static func restore() -> AdminStep? {
        guard let e = Journal.shared["forcedExpose"] as? [String: Any] else { return nil }
        let created = e["createdFolders"] as? [String] ?? []
        let rmdirs = folders.reversed().filter(created.contains).map { "/bin/rmdir \(Shell.quote($0)) 2>/dev/null || true" }
        return AdminStep(label: "Mission Control for mouse apps", journalKeys: ["forcedExpose"],
                         commands: ["/bin/rm -f \(Shell.quote(file))"] + rmdirs)
    }

    /// Waits up to `seconds` for the key to be forced on, or not; returns whether it is.
    static func waitForced(_ want: Bool, seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        var now = forced
        while now != want && Date() < deadline {
            usleep(250_000)
            now = forced
        }
        return now == want
    }

    /// After the file has gone; returns whether the key is still forced. cfprefsd lets go
    /// within moments, but once (after a `defaults write` into the folder) went on reporting it
    /// forced, and the Dock obeying it, until this user's cfprefsd agent was restarted, which
    /// launchd does on demand.
    static func releaseForced() -> Bool {
        if waitForced(false, seconds: 2) { return false }
        ShowLog.note("mission control: still forced after the file went; restarting cfprefsd")
        Shell.run("/usr/bin/pkill", ["-U", String(getuid()), "-x", "cfprefsd"])
        return !waitForced(false, seconds: 3)
    }
}

/// WindowServer's symbolic hot keys, switched off in WindowServer itself through SkyLight,
/// which applies at once and is not saved, so a Mac that restarts mid-show gets them back
/// anyway. Looked up at runtime like the other private calls.
enum SymbolicHotKeys {
    typealias IsEnabled = @convention(c) (Int32) -> Bool
    typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static let isEnabled: IsEnabled? = dlsym(handle, "CGSIsSymbolicHotKeyEnabled")
        .map { unsafeBitCast($0, to: IsEnabled.self) }
    private static let setEnabled: SetEnabled? = dlsym(handle, "CGSSetSymbolicHotKeyEnabled")
        .map { unsafeBitCast($0, to: SetEnabled.self) }

    /// Those of `ids` that are on now; nil if SkyLight has no such call.
    static func on(_ ids: [Int32]) -> [Int32]? {
        guard let isEnabled else { return nil }
        return ids.filter { isEnabled($0) }
    }

    /// Journals the ones that are on, adding to a leftover entry, then switches them off.
    /// Returns false if they could not be switched off.
    static func disable(_ ids: [Int32], journalKey: String) -> Bool {
        guard let on = on(ids), let setEnabled else { return false }
        guard !on.isEmpty else { return true }
        let journaled = Journal.shared[journalKey] as? [Int] ?? []
        let add = on.map(Int.init).filter { !journaled.contains($0) }
        if !add.isEmpty { Journal.shared[journalKey] = journaled + add }
        on.forEach { _ = setEnabled($0, false) }
        return self.on(ids)?.isEmpty == true
    }

    static func restore(journalKey: String) {
        guard let keys = Journal.shared[journalKey] as? [Int], let setEnabled else { return }
        keys.forEach { _ = setEnabled(Int32($0), true) }
    }
}
