import AppKit
import IOKit.ps
import SystemConfiguration

/// What Show Mode cannot safely switch off, only spot and say. Each line names the problem
/// and the one thing to do about it. Listed under Pre-show Checks in the menu and in the note
/// at the start of a show; the ones that can change mid-show (`live`) also stay at the top of
/// the menu while it runs.
enum Preflight {
    struct Item {
        let text: String
        let live: Bool
    }

    static func items() -> [Item] {
        var out: [Item] = []
        out += RemoteAccess.sessions().map { Item(text: "Remote session active: \($0)", live: true) }
        out += RemoteAccess.blackedOut().map {
            Item(text: "\($0) is blacked out: a remote-access privacy mode (RustDesk's) zeroes its colour table", live: true)
        }
        if let s = thermal { out.append(Item(text: s, live: true)) }
        if let s = battery { out.append(Item(text: s, live: true)) }
        if let s = wifi { out.append(Item(text: s, live: true)) }

        if let u = SoftwareUpdate.pendingMacOSUpdate {
            out.append(Item(text: "\(u) is waiting: never choose Install Tonight on a show Mac, it restarts overnight", live: false))
        }
        if SoftwareUpdate.managed {
            out.append(Item(text: "Updates are managed by your organisation and can restart the Mac on their deadline", live: false))
        }
        if AppUpdaters.mauInstalled, AppUpdaters.mauManaged {
            out.append(Item(text: "Microsoft AutoUpdate is managed by your organisation: its deadlines quit Office apps", live: false))
        }
        out += apps().map { Item(text: $0, live: false) }
        return out
    }

    // MARK: The Mac itself

    static var thermal: String? {
        switch ProcessInfo.processInfo.thermalState {
        case .serious: return "The Mac is running hot: it is slowing itself down"
        case .critical: return "The Mac is critically hot: it is slowing itself down hard"
        default: return nil
        }
    }

    static var battery: String? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String == kIOPSBatteryPowerValue else { return nil }
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let percent = list.lazy.compactMap { src -> Int? in
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { return nil }
            return cur * 100 / max
        }.first
        return "Running on battery\(percent.map { " (\($0)%)" } ?? ""): plug in for the show"
    }

    /// Whether the network macOS routes through first is Wi-Fi.
    static var wifi: String? {
        guard let store = SCDynamicStoreCreate(nil, "Show Mode" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primary = global["PrimaryInterface"] as? String,
              let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface],
              let iface = all.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == primary }),
              SCNetworkInterfaceGetInterfaceType(iface) == kSCNetworkInterfaceTypeIEEE80211
        else { return nil }
        return "The network is on Wi-Fi: a cable is steadier for show traffic (NDI, Dante, OSC)"
    }

    // MARK: Other software

    /// Sync and backup clients Show Mode cannot pause, and security software Show Mode must not
    /// touch. Do Not Disturb already holds the security products that use notifications
    /// (Malwarebytes, Bitdefender, Kaspersky, ESET 7 and later, ClamXAV); these are the ones
    /// that open their own windows or scan on a schedule.
    private static let known: [(prefixes: [String], text: String)] = [
        (["com.getdropbox.dropbox"], "Dropbox is running: pause syncing from its menu (quitting it does not stop the sync)"),
        (["com.google.drivefs"], "Google Drive is running: pause syncing in its settings"),
        (["com.microsoft.OneDrive"], "OneDrive is running: pause syncing from its menu"),
        (["com.haystacksoftware."], "Arq can back up mid-show: pause its backups from its menu"),
        (["com.bombich."], "Carbon Copy Cloner can run a task mid-show: disable its scheduled tasks for the show"),
        (["com.backblaze."], "Backblaze can back up mid-show: pause it from its menu"),
        (["com.econtechnologies."], "ChronoSync can run mid-show: suspend its scheduler from its menu"),
        (["com.intego."], "Intego opens its own windows: untick Display scheduled scans in Task Manager, and set a default network profile"),
        (["com.sophos."], "Sophos alerts are windows, not notifications: move its scan schedule outside the show"),
        (["com.trendmicro."], "Trend Micro asks a minute before each scheduled scan: move the schedule outside the show"),
        (["com.norton.", "com.symantec."], "Norton scans when the Mac looks idle: turn off Idle Time Scan, or turn on Silent Mode"),
        (["com.objective-see.lulu"], "LuLu alerts take the keyboard from the show app: rehearse so every connection has a rule, or use a passive profile"),
        (["com.objective-see.blockblock"], "BlockBlock alerts are windows: rehearse the show with it, or switch it to passive mode"),
        (["com.microsoft.wdav"], "Microsoft Defender: check its scheduled scan does not fall inside the show"),
        (["com.crowdstrike.", "com.sentinelone.", "com.jamf.protect", "com.vmware.carbonblack", "com.carbonblack.", "co.elastic."],
         "Security software managed by your IT team: ask them about scans before the show, and leave it alone"),
    ]

    private static var extensionsCache: (at: Date, ids: [String])?

    /// Bundle identifiers of system extensions (where security software lives), cached for a
    /// few minutes: they change only with an install.
    private static var systemExtensions: [String] {
        if let c = extensionsCache, Date().timeIntervalSince(c.at) < 300 { return c.ids }
        let out = Shell.run("/usr/bin/systemextensionsctl", ["list"], timeout: 5)?.out ?? ""
        let ids = out.split(separator: "\n").compactMap { line -> String? in
            // Inactive extensions leave the first columns empty: keep them, to keep the count.
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 4 else { return nil }
            return cols[3].split(separator: " ").first.map(String.init)
        }
        extensionsCache = (Date(), ids)
        return ids
    }

    private static func apps() -> [String] {
        let ids = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) + systemExtensions
        return known.filter { k in ids.contains { id in k.prefixes.contains { id.hasPrefix($0) } } }.map(\.text)
    }
}

/// Remote-access hosts on the show Mac. Show Mode does not block them (the operator may need
/// one), but it says when a session is live: several change what the audience sees when
/// someone connects.
enum RemoteAccess {
    /// Local TCP ports hosts take sessions on.
    private static let ports: [String: String] = [
        "5900": "Screen Sharing or VNC", "3283": "Apple Remote Desktop", "4000": "NoMachine", "7070": "AnyDesk",
    ]

    /// Who is connected, by host, from established inbound connections (netstat needs no
    /// root) and TeamViewer's per-session process.
    static func sessions() -> [String] {
        var found = Set<String>()
        for line in (Shell.run("/usr/sbin/netstat", ["-an", "-p", "tcp"], timeout: 3)?.out ?? "").split(separator: "\n") {
            let f = line.split(whereSeparator: \.isWhitespace)
            guard f.count >= 6, f[5] == "ESTABLISHED", let port = f[3].split(separator: ".").last,
                  let name = ports[String(port)] else { continue }
            found.insert(name)
        }
        let commands = Shell.run("/bin/ps", ["-axo", "command="], timeout: 3)?.out ?? ""
        if commands.split(separator: "\n").contains(where: { $0.contains("TeamViewer_Desktop") && $0.contains("--Module 1") }) {
            found.insert("TeamViewer")
        }
        return found.sorted()
    }

    /// Displays whose colour table is all zeros: black whatever is sent to them.
    static func blackedOut() -> [String] {
        DisplayInfo.all().compactMap { d in
            var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r
            var n: UInt32 = 0
            guard CGGetDisplayTransferByTable(d.id, 256, &r, &g, &b, &n) == .success, n > 0 else { return nil }
            let top = (0..<Int(n)).map { max(r[$0], g[$0], b[$0]) }.max() ?? 1
            return top == 0 ? d.name : nil
        }
    }
}
