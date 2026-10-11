import Foundation
import IOKit.pwr_mgt

/// Idle display/system sleep: IOKit power assertions, released on restore or when the
/// process dies — nothing to journal.
final class SleepAssertion {
    private var ids: [IOPMAssertionID] = []

    var held: Bool { !ids.isEmpty }

    func take() {
        guard ids.isEmpty else { return }
        for type in [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep] {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Show Mode" as CFString, &id) == kIOReturnSuccess {
                ids.append(id)
            }
        }
    }

    func release() {
        ids.forEach { IOPMAssertionRelease($0) }
        ids = []
    }
}

/// Experimental. Tells macOS every four minutes that someone is using the Mac, as a key press
/// would, so an untouched show machine is not taken for idle: idle is when macOS schedules its
/// own maintenance. The display assertion alone leaves the HID idle timer running out after
/// five minutes. Nothing outlives the app, so there is nothing to journal.
final class UserActivity {
    private var timer: Timer?
    private var id: IOPMAssertionID = 0

    func start() {
        guard timer == nil else { return }
        declare()
        timer = Timer.scheduledTimer(withTimeInterval: 240, repeats: true) { [weak self] _ in self?.declare() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if id != 0 { IOPMAssertionRelease(id); id = 0 }
    }

    /// Passing the same id back renews the declaration rather than adding another.
    private func declare() {
        IOPMAssertionDeclareUserActivity("Show Mode" as CFString, kIOPMUserActiveLocal, &id)
    }
}

/// Low Power Mode and lid-close sleep live in pmset and need root to change.
enum PMSet {
    /// Per power source ("-b" battery, "-c" AC, "-u" UPS) → (key, value), from `pmset -g custom`.
    /// Newer Macs call it `powermode` (0 auto, 1 low, 2 high); older ones `lowpowermode`.
    static func lowPowerBySource() -> [String: (key: String, value: Int)] {
        guard let out = Shell.run("/usr/bin/pmset", ["-g", "custom"])?.out else { return [:] }
        var result: [String: (String, Int)] = [:]
        var flag: String?
        for line in out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("Battery Power") { flag = "-b"; continue }
            if s.hasPrefix("AC Power") { flag = "-c"; continue }
            if s.hasPrefix("UPS Power") { flag = "-u"; continue }
            let parts = s.split(separator: " ", omittingEmptySubsequences: true)
            guard let flag, parts.count >= 2, let v = Int(parts[1]) else { continue }
            let k = String(parts[0])
            if k == "powermode" || k == "lowpowermode" { result[flag] = (k, v) }
        }
        return result
    }

    static var sleepDisabled: Bool {
        (Shell.run("/usr/bin/pmset", ["-g"])?.out ?? "")
            .split(separator: "\n")
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("SleepDisabled") && $0.hasSuffix("1") }
    }

    /// Turns Low Power Mode off, journaling what each source had.
    static func engageLowPower() -> AdminStep? {
        var cmds: [String] = []
        // An entry left by a restore that never finished already holds those sources' original
        // values; only sources it lacks are added.
        var journaled = Journal.shared["lowPower"] as? [String: [String: Any]] ?? [:]
        for (flag, cur) in lowPowerBySource() where cur.value == 1 {
            if journaled[flag] == nil { journaled[flag] = ["key": cur.key, "value": cur.value] }
            cmds.append("/usr/bin/pmset \(flag) \(cur.key) 0")
        }
        guard !cmds.isEmpty else { return nil }
        Journal.shared["lowPower"] = journaled
        return AdminStep(label: "Low Power Mode", journalKeys: ["lowPower"], commands: cmds)
    }

    static func restoreLowPower() -> AdminStep? {
        guard let j = Journal.shared["lowPower"] as? [String: [String: Any]] else { return nil }
        let cmds = j.compactMap { flag, e -> String? in
            guard let k = e["key"] as? String, let v = e["value"] as? Int else { return nil }
            return "/usr/bin/pmset \(flag) \(k) \(v)"
        }
        return AdminStep(label: "Low Power Mode", journalKeys: ["lowPower"], commands: cmds)
    }

    static func engageLidSleep() -> AdminStep? {
        guard !sleepDisabled else { return nil }
        if Journal.shared["lidSleep"] == nil { Journal.shared["lidSleep"] = true }
        return AdminStep(label: "Lid-close sleep", journalKeys: ["lidSleep"], commands: ["/usr/bin/pmset -a disablesleep 1"])
    }

    static func restoreLidSleep() -> AdminStep? {
        guard Journal.shared["lidSleep"] as? Bool == true else { return nil }
        return AdminStep(label: "Lid-close sleep", journalKeys: ["lidSleep"], commands: ["/usr/bin/pmset -a disablesleep 0"])
    }
}
