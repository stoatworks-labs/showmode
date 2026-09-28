import Foundation

/// Everything show mode changed, with the value it replaced, written to disk *before* each
/// change is made. If the app crashes or is killed mid-show, the next launch finds the journal
/// and puts the machine back.
final class Journal {
    static let shared = Journal()

    private(set) var entries: [String: Any] = [:]

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShowMode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.plist")
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { entries = [:]; return }
        entries = dict
    }

    subscript(key: String) -> Any? {
        get { entries[key] }
        set { entries[key] = newValue; save() }
    }

    /// Records a preference's previous value once; later records of the same key keep the
    /// original, so engaging twice never journals show mode's own value as "previous".
    func recordPref(_ p: PrefKey, previous: Any?) {
        var prefs = entries["prefs"] as? [[String: Any]] ?? []
        if prefs.contains(where: { $0["id"] as? String == p.id }) { return }
        var e: [String: Any] = ["id": p.id, "domain": p.domain, "key": p.key, "currentHost": p.currentHost]
        if let previous { e["value"] = previous }
        prefs.append(e)
        self["prefs"] = prefs
    }

    func clear() {
        entries = [:]
        try? FileManager.default.removeItem(at: url)
    }

    private func save() {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}
