import AppKit

/// Do Not Disturb. macOS has no public API for Focus and the old preference keys are dead,
/// but the Shortcuts "Set Focus" action works and `shortcuts run` can call it. Show Mode
/// generates two one-action shortcuts, signs them, and hands them to Shortcuts to import once.
enum Focus {
    static var onName: String { Settings.shared.focusOnShortcut }
    static var offName: String { Settings.shared.focusOffShortcut }

    static func installedShortcuts() -> Set<String> {
        let out = Shell.run("/usr/bin/shortcuts", ["list"])?.out ?? ""
        return Set(out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    static var isInstalled: Bool {
        let have = installedShortcuts()
        return have.contains(onName) && have.contains(offName)
    }

    /// Turns DND on if the shortcut exists. Returns false when it isn't installed.
    static func engage() -> Bool {
        guard isInstalled else { return false }
        Journal.shared["focus"] = true
        return Shell.run("/usr/bin/shortcuts", ["run", onName], timeout: 20)?.status == 0
    }

    static func restore() {
        guard Journal.shared["focus"] as? Bool == true else { return }
        Shell.run("/usr/bin/shortcuts", ["run", offName], timeout: 20)
    }

    // MARK: Installing the shortcuts

    private static func workflow(enable: Bool) -> [String: Any] {
        let params: [String: Any] = [
            "Enabled": enable ? 1 : 0,
            "FocusModes": [
                "Identifier": "com.apple.donotdisturb.mode.default",
                "DisplayString": "Do Not Disturb",
            ],
        ]
        return [
            "WFWorkflowActions": [[
                "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
                "WFWorkflowActionParameters": params,
            ]],
            "WFWorkflowClientVersion": "2607.0.2",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": [
                "WFWorkflowIconStartColor": enable ? 4292093695 : 1440408063,
                "WFWorkflowIconGlyphNumber": 59511,
            ],
            "WFWorkflowImportQuestions": [],
            "WFWorkflowTypes": [],
            "WFWorkflowInputContentItemClasses": [],
            "WFWorkflowOutputContentItemClasses": [],
            "WFWorkflowHasOutputFallback": false,
            "WFQuickActionSurfaces": [],
        ]
    }

    /// Writes, signs and opens both shortcuts. Shortcuts shows its own "Add Shortcut" sheet
    /// for each; the user confirms there. Returns an error message on failure.
    static func install() -> String? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShowModeShortcuts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var signed: [URL] = []
        for (name, enable) in [(onName, true), (offName, false)] {
            let raw = dir.appendingPathComponent("\(name).wflow")
            let out = dir.appendingPathComponent("\(name).shortcut")
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: workflow(enable: enable),
                                                              format: .binary, options: 0)
                try data.write(to: raw)
            } catch { return "Could not write \(name): \(error.localizedDescription)" }
            try? FileManager.default.removeItem(at: out)
            let r = Shell.run("/usr/bin/shortcuts", ["sign", "--mode", "anyone", "--input", raw.path, "--output", out.path],
                              timeout: 60)
            guard r?.status == 0, FileManager.default.fileExists(atPath: out.path) else {
                return "shortcuts sign failed for \(name): \(r?.out ?? "timed out")"
            }
            signed.append(out)
        }
        signed.forEach { NSWorkspace.shared.open($0) }
        return nil
    }
}
