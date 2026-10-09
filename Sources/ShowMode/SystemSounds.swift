import AudioToolbox
import Foundation

/// The alert beep, the interface sound effects (emptying the Trash, taking a screenshot) and
/// the pop a volume key plays — all of which go out through whatever the show's audio is
/// plugged into. System Settings' Sound pane changes the first two through AudioServices
/// properties with no public name and the third through a preference key, then posts a
/// distributed notification so anything showing them catches up; Show Mode makes the same
/// calls. AudioServices answers a property it does not know with an error, so a macOS that
/// drops one degrades to a warning rather than a crash. Sound from apps is left alone.
enum SystemSounds {
    /// Alert volume, a Float32 where 0 is silent. The pane's slider shows log(v) + 1 of it;
    /// the raw value is what is journaled, so it comes back exactly.
    private static let alertVolume = fourCC("ssvl")
    /// "Play user interface sound effects", a UInt32.
    private static let uiSounds = fourCC("uion")
    /// "Play feedback when volume is changed".
    private static let feedback = PrefKey(domain: "NSGlobalDomain", key: "com.apple.sound.beep.feedback")

    private static let alertVolumeChanged = "com.apple.sound.alertVolumeChanged"
    private static let settingsChanged = "com.apple.sound.settingsChangedNotification"

    /// Silences whichever of the three is on. Returns false if macOS would not read or take
    /// one of the changes.
    static func engage() -> Bool {
        var ok = true

        if let v = get(alertVolume, Float32(0)) {
            if v > 0 {
                if Journal.shared["alertVolume"] == nil { Journal.shared["alertVolume"] = Double(v) }
                ok = set(alertVolume, Float32(0)) && ok
                post(alertVolumeChanged, allSessions: true)
            }
        } else { ok = false }

        var changed = false
        if let on = get(uiSounds, UInt32(1)) {
            if on != 0 {
                if Journal.shared["uiSounds"] == nil { Journal.shared["uiSounds"] = true }
                ok = set(uiSounds, UInt32(0)) && ok
                changed = true
            }
        } else { ok = false }

        if (feedback.read() as? NSNumber)?.boolValue == true {
            changed = feedback.override(false) || changed
        }
        if changed { post(settingsChanged) }
        return ok
    }

    /// Puts back what `engage()` journaled. The feedback key is restored with the other
    /// preferences, so this runs after `Prefs.restoreAll()` and only announces it.
    static func restore() {
        if let v = Journal.shared["alertVolume"] as? Double {
            set(alertVolume, Float32(v))
            post(alertVolumeChanged, allSessions: true)
        }
        let ui = Journal.shared["uiSounds"] as? Bool == true
        if ui { set(uiSounds, UInt32(1)) }
        let prefs = Journal.shared["prefs"] as? [[String: Any]] ?? []
        if ui || prefs.contains(where: { $0["id"] as? String == feedback.id }) { post(settingsChanged) }
    }

    // MARK: AudioServices helpers

    private static func fourCC(_ s: String) -> AudioServicesPropertyID {
        s.utf8.reduce(0) { $0 << 8 | AudioServicesPropertyID($1) }
    }

    private static func get<T>(_ id: AudioServicesPropertyID, _ initial: T) -> T? {
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &v) { AudioServicesGetProperty(id, 0, nil, &size, $0.baseAddress) }
        return status == noErr ? v : nil
    }

    @discardableResult
    private static func set<T>(_ id: AudioServicesPropertyID, _ value: T) -> Bool {
        withUnsafeBytes(of: value) { AudioServicesSetProperty(id, 0, nil, UInt32($0.count), $0.baseAddress!) } == noErr
    }

    /// The pane posts the alert-volume change to every login session and the others to this one.
    private static func post(_ name: String, allSessions: Bool = false) {
        var options: DistributedNotificationCenter.Options = [.deliverImmediately]
        if allSessions { options.insert(.postToAllSessions) }
        DistributedNotificationCenter.default()
            .postNotificationName(.init(name), object: nil, userInfo: nil, options: options)
    }
}
