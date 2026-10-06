import Foundation

/// Which guards engage with show mode. Every one defaults on except the ones that need an
/// admin password on every engage (lid-close sleep).
enum Guard: String, CaseIterable {
    case sleep
    case lidSleep
    case lowPower
    case screenSaver
    case hotCorners
    case missionControl
    case spaceSwipe
    case clickToShowDesktop
    case wallpaper
    case notifications
    case nightShift
    case trueTone
    case autoAppearance
    case colourApps
    case cursorFence
    case displayLayout
    case privacyDots

    var title: String {
        switch self {
        case .sleep: return "Prevent display & system sleep"
        case .lidSleep: return "Prevent sleep on lid close (admin)"
        case .lowPower: return "Turn off Low Power Mode (admin)"
        case .screenSaver: return "Disable screen saver"
        case .hotCorners: return "Disable hot corners"
        case .missionControl: return "Disable Mission Control, Exposé & gestures"
        case .spaceSwipe: return "Disable swipe between Spaces & full-screen apps"
        case .clickToShowDesktop: return "Disable click-wallpaper-to-show-desktop"
        case .wallpaper: return "Black out desktop wallpaper"
        case .notifications: return "Do Not Disturb (notifications)"
        case .nightShift: return "Disable Night Shift"
        case .trueTone: return "Disable True Tone"
        case .autoAppearance: return "Pin light/dark appearance"
        case .colourApps: return "Quit colour-shift apps (f.lux etc.)"
        case .cursorFence: return "Fence cursor off show screens"
        case .displayLayout: return "Lock main display & keep new screens extended"
        case .privacyDots: return "Hide privacy dots on full-screen external displays"
        }
    }

    var defaultOn: Bool { self != .lidSleep }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    func isOn(_ g: Guard) -> Bool {
        d.object(forKey: "guard.\(g.rawValue)") as? Bool ?? g.defaultOn
    }

    func set(_ g: Guard, _ on: Bool) { d.set(on, forKey: "guard.\(g.rawValue)") }

    /// Stable keys (see `DisplayInfo.key`) of displays the cursor may not enter.
    var blockedDisplays: Set<String> {
        get { Set(d.stringArray(forKey: "blockedDisplays") ?? []) }
        set { d.set(Array(newValue).sorted(), forKey: "blockedDisplays") }
    }

    /// Key of the display kept main during a show; nil means whichever is main at start.
    var mainDisplay: String? {
        get { d.string(forKey: "mainDisplay") }
        set { d.set(newValue, forKey: "mainDisplay") }
    }

    /// Hide the cursor when it reaches a blocked display anyway (the fallback when it cannot
    /// be held back, e.g. before Accessibility is granted).
    var hideOnBlocked: Bool {
        get { d.object(forKey: "hideOnBlocked") as? Bool ?? true }
        set { d.set(newValue, forKey: "hideOnBlocked") }
    }

    /// Bundle identifiers quit on engage and relaunched on restore.
    var colourApps: [String] {
        get {
            d.stringArray(forKey: "colourApps") ?? [
                "org.herf.Flux",          // f.lux
                "io.natethompson.Shifty", // Shifty (Night Shift scheduler)
                "fyi.lunar.Lunar",        // Lunar (location/sun-based adaptation)
            ]
        }
        set { d.set(newValue, forKey: "colourApps") }
    }

    /// Shortcuts that turn Focus on and off (see FocusGuard).
    var focusOnShortcut: String {
        d.string(forKey: "focusOnShortcut") ?? "Show Mode Focus On"
    }
    var focusOffShortcut: String {
        d.string(forKey: "focusOffShortcut") ?? "Show Mode Focus Off"
    }
}
