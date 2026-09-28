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

    /// Commands to turn Low Power Mode off, journaling what each source had.
    static func engageLowPower() -> [String] {
        var cmds: [String] = []
        var journaled: [String: [String: Any]] = [:]
        for (flag, cur) in lowPowerBySource() where cur.value == 1 {
            journaled[flag] = ["key": cur.key, "value": cur.value]
            cmds.append("/usr/bin/pmset \(flag) \(cur.key) 0")
        }
        if !journaled.isEmpty { Journal.shared["lowPower"] = journaled }
        return cmds
    }

    static func restoreLowPower() -> [String] {
        guard let j = Journal.shared["lowPower"] as? [String: [String: Any]] else { return [] }
        return j.compactMap { flag, e in
            guard let k = e["key"] as? String, let v = e["value"] as? Int else { return nil }
            return "/usr/bin/pmset \(flag) \(k) \(v)"
        }
    }

    static func engageLidSleep() -> [String] {
        guard !sleepDisabled else { return [] }
        Journal.shared["lidSleep"] = true
        return ["/usr/bin/pmset -a disablesleep 1"]
    }

    static func restoreLidSleep() -> [String] {
        Journal.shared["lidSleep"] as? Bool == true ? ["/usr/bin/pmset -a disablesleep 0"] : []
    }
}
