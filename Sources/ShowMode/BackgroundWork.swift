import Foundation

/// Time Machine's automatic backups. Pausing them needs root, and `tmutil disable` also needs
/// the calling app to have Full Disk Access: without it the command reportedly exits 0 and
/// changes nothing, so the setting is read back after the prompt rather than trusted.
enum TimeMachine {
    private static let domain = "/Library/Preferences/com.apple.TimeMachine"

    /// Whether automatic backups are on, read through cfprefsd as `defaults` does (the file is
    /// readable without root); nil if it cannot be read.
    static var autoBackup: Bool? {
        guard let r = Shell.run("/usr/bin/defaults", ["read", domain, "AutoBackup"], timeout: 5), r.status == 0
        else { return nil }
        return r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    static var backingUp: Bool {
        (Shell.run("/usr/bin/tmutil", ["status"], timeout: 5)?.out ?? "").contains("Running = 1")
    }

    /// Stops a backup in progress (its own step: it can fail simply because the backup ended
    /// while the password prompt was up) and turns automatic backups off, if they are on.
    static func engage() -> [AdminStep] {
        var steps: [AdminStep] = []
        if backingUp {
            steps.append(AdminStep(label: "The running backup", journalKeys: [], commands: ["/usr/bin/tmutil stopbackup"]))
        }
        if autoBackup == true {
            if Journal.shared["timeMachine"] == nil { Journal.shared["timeMachine"] = true }
            steps.append(AdminStep(label: "Time Machine", journalKeys: ["timeMachine"], commands: ["/usr/bin/tmutil disable"]))
        }
        return steps
    }

    /// After the prompt. Returns a warning if automatic backups are still on. The entry stays:
    /// `tmutil enable` at the end is harmless if they never went off.
    static func confirmEngaged() -> String? {
        guard Journal.shared["timeMachine"] as? Bool == true, autoBackup == true else { return nil }
        return "Time Machine is still on: give Show Mode Full Disk Access (Setup menu)"
    }

    static func restore() -> AdminStep? {
        guard Journal.shared["timeMachine"] as? Bool == true else { return nil }
        return AdminStep(label: "Time Machine", journalKeys: ["timeMachine"], commands: ["/usr/bin/tmutil enable"])
    }

    /// After the restore prompt: whether automatic backups really are back on.
    static var restored: Bool { autoBackup != false }
}

/// Automatic macOS and App Store updates. An App Store update quits the app it updates, and
/// a downloaded macOS update can install itself overnight. These are system-wide settings
/// written as root. The security responses (CriticalUpdateInstall) and XProtect data
/// (ConfigDataInstall) are left alone. A Mac whose updates are managed by its organisation is
/// left alone too: its deadlines restart the Mac whatever these say.
enum SoftwareUpdate {
    private static let settings: [(domain: String, key: String)] = [
        ("com.apple.SoftwareUpdate", "AutomaticDownload"),
        ("com.apple.SoftwareUpdate", "AutomaticallyInstallMacOSUpdates"),
        ("com.apple.commerce", "AutoUpdate"),
    ]

    private static func value(_ domain: String, _ key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString, domain as CFString, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
    }

    static var managed: Bool {
        settings.contains { CFPreferencesAppValueIsForced($0.key as CFString, $0.domain as CFString) }
    }

    private static func path(_ domain: String) -> String { Shell.quote("/Library/Preferences/\(domain)") }

    /// Turns off whichever of the three is on (an absent key counts as on), journaling each
    /// previous value, an absent one as absent. A key already in the journal (a restore that
    /// never finished) keeps the value recorded there.
    static func engage() -> AdminStep? {
        guard !managed else { return nil }
        var entries = Journal.shared["softwareUpdate"] as? [[String: Any]] ?? []
        var cmds: [String] = []
        for s in settings {
            let v = value(s.domain, s.key)
            guard (v as? Bool) != false else { continue }
            if !entries.contains(where: { $0["domain"] as? String == s.domain && $0["key"] as? String == s.key }) {
                var e: [String: Any] = ["domain": s.domain, "key": s.key]
                if let v { e["value"] = v }
                entries.append(e)
            }
            cmds.append("/usr/bin/defaults write \(path(s.domain)) \(s.key) -bool false")
        }
        guard !cmds.isEmpty else { return nil }
        Journal.shared["softwareUpdate"] = entries
        return AdminStep(label: "Automatic updates", journalKeys: ["softwareUpdate"], commands: cmds)
    }

    static func restore() -> AdminStep? {
        guard let entries = Journal.shared["softwareUpdate"] as? [[String: Any]] else { return nil }
        let cmds = entries.compactMap { e -> String? in
            guard let domain = e["domain"] as? String, let key = e["key"] as? String else { return nil }
            if let b = e["value"] as? Bool { return "/usr/bin/defaults write \(path(domain)) \(key) -bool \(b)" }
            // Only if present: a retry after a restore that half ran must not fail on it.
            return "if /usr/bin/defaults read \(path(domain)) \(key) >/dev/null 2>&1; then /usr/bin/defaults delete \(path(domain)) \(key); fi"
        }
        return AdminStep(label: "Automatic updates", journalKeys: ["softwareUpdate"], commands: cmds)
    }

    /// The first macOS update waiting to install, from the list Software Update keeps (no
    /// network, no root). Someone choosing "Install Tonight" on it makes macOS install and
    /// restart overnight whatever the settings above say, and that cannot be cancelled.
    static var pendingMacOSUpdate: String? {
        let list = value("com.apple.SoftwareUpdate", "RecommendedUpdates") as? [[String: Any]] ?? []
        return list.first { ($0["MobileSoftwareUpdate"] as? Bool) == true }?["Display Name"] as? String
    }
}

/// AWDL, the peer-to-peer Wi-Fi link behind AirDrop, AirPlay and Sidecar, which takes the
/// single radio off the network's channel and causes spikes of 100–200 ms. Expert and off by
/// default: macOS brings it back up whenever it likes, so the root sweeper holds it down for
/// the whole show, and AirDrop, peer-to-peer AirPlay, Sidecar and Universal Control stop.
enum AWDL {
    /// nil on a Mac without the interface.
    static var up: Bool? {
        guard let r = Shell.run("/sbin/ifconfig", ["awdl0"], timeout: 3), r.status == 0 else { return nil }
        let flags = r.out.split(separator: "\n").first ?? ""
        return flags.contains("<UP,") || flags.contains("<UP>")
    }
}

/// Game Mode (macOS 14+, Apple silicon) gives the full-screen app priority and turns down
/// background work. It normally only comes on for a full-screen game; Xcode's gamepolicyctl
/// can force it on without one. Experimental: it needs Xcode itself (not just the Command Line
/// Tools), and what forcing it does without a game has not been measured.
enum GameMode {
    /// gamepolicyctl in the selected Xcode. Never through xcrun: on a Mac without developer
    /// tools xcrun opens an install dialog, which could land on a show output.
    static var tool: String? {
        guard let r = Shell.run("/usr/bin/xcode-select", ["-p"], timeout: 3), r.status == 0 else { return nil }
        let path = r.out.trimmingCharacters(in: .whitespacesAndNewlines) + "/usr/bin/gamepolicyctl"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// "auto", "on" or "off", the arguments `game-mode set` takes.
    static func policy(_ tool: String) -> String? {
        let out = Shell.run(tool, ["game-mode", "status"], timeout: 5)?.out ?? ""
        if out.contains("currently automatic") { return "auto" }
        if out.contains("forced always on") { return "on" }
        if out.contains("forced always off") { return "off" }
        return nil
    }

    /// Returns false if Game Mode could not be forced on (no Xcode, or the tool refused).
    static func engage() -> Bool {
        guard let tool, let current = policy(tool) else { return false }
        if current == "on" { return true }
        if Journal.shared["gameMode"] == nil { Journal.shared["gameMode"] = current }
        Shell.run(tool, ["game-mode", "set", "on"], timeout: 5)
        return policy(tool) == "on"
    }

    /// Returns false if the previous policy did not come back (it is then retried); true
    /// when there was nothing to do or Xcode has gone.
    static func restore() -> Bool {
        guard let previous = Journal.shared["gameMode"] as? String, let tool else { return true }
        Shell.run(tool, ["game-mode", "set", previous], timeout: 5)
        return policy(tool) == previous
    }
}
