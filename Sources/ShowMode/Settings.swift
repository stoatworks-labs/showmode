import Foundation

/// Which guards engage with show mode. Every one defaults on except the ones that need an
/// admin password on every engage, the expert ones and the experimental ones.
enum Guard: String, CaseIterable {
    case sleep
    case lidSleep
    case lowPower
    case fansFull
    case fansQuiet
    case screenSaver
    case hotCorners
    case missionControl
    case missionControlApps
    case spaceSwipe
    case clickToShowDesktop
    case stageManager
    case spotlightKey
    case wallpaper
    case notifications
    case systemSounds
    case muteOtherApps
    case crashDialogs
    case airplayReceiver
    case keyboardSetup
    case nightShift
    case trueTone
    case autoAppearance
    case colourApps
    case cursorFence
    case displayLayout
    case privacyDots
    case mediaAnalysis
    case appUpdaters
    case syncthing
    case syncApps
    case timeMachine
    case spotlight
    case softwareUpdate
    case remoteAccess
    case awdl
    case userActivity
    case gameMode

    var title: String {
        switch self {
        case .sleep: return "Prevent display & system sleep"
        case .lidSleep: return "Prevent sleep on lid close (admin)"
        case .lowPower: return "Turn off Low Power Mode (admin)"
        case .fansFull: return "Run the fans at full speed (admin)"
        case .fansQuiet: return "Keep the fans at their quietest (admin)"
        case .screenSaver: return "Disable screen saver"
        case .hotCorners: return "Disable hot corners"
        case .missionControl: return "Disable Mission Control, Exposé & gestures"
        case .missionControlApps: return "Stop mouse & other apps opening Mission Control (admin)"
        case .spaceSwipe: return "Disable swipe between Spaces & full-screen apps"
        case .clickToShowDesktop: return "Disable click-wallpaper-to-show-desktop"
        case .stageManager: return "Turn off Stage Manager"
        case .spotlightKey: return "Disable ⌘Space (Spotlight search)"
        case .wallpaper: return "Black out desktop wallpaper"
        case .notifications: return "Do Not Disturb (notifications)"
        case .systemSounds: return "Disable system sounds (alerts & UI effects)"
        case .muteOtherApps: return "Mute apps not allowed to play"
        case .crashDialogs: return "Send crash reports to Notification Center"
        case .airplayReceiver: return "Turn off AirPlay Receiver"
        case .keyboardSetup: return "Close Keyboard Setup Assistant"
        case .nightShift: return "Disable Night Shift"
        case .trueTone: return "Disable True Tone"
        case .autoAppearance: return "Pin light/dark appearance"
        case .colourApps: return "Quit colour-shift apps (f.lux etc.)"
        case .cursorFence: return "Fence cursor off show screens"
        case .displayLayout: return "Lock main display & keep new screens extended"
        case .privacyDots: return "Hide privacy dots on full-screen external displays"
        case .mediaAnalysis: return "Pause photo & media analysis"
        case .appUpdaters: return "Turn off app update checks (Sparkle, Microsoft)"
        case .syncthing: return "Pause Syncthing"
        case .syncApps: return "Quit sync apps (Resilio, Synology, MEGA, Sync.com, Box)"
        case .timeMachine: return "Pause Time Machine (admin)"
        case .spotlight: return "Pause Spotlight indexing (admin)"
        case .softwareUpdate: return "Turn off automatic macOS & App Store updates (admin)"
        case .remoteAccess: return "Watch for remote sessions & keep the output black"
        case .awdl: return "Hold AWDL down: AirDrop, AirPlay, Sidecar (admin)"
        case .userActivity: return "Keep the Mac looking in use"
        case .gameMode: return "Force Game Mode (needs Xcode)"
        }
    }

    var defaultOn: Bool {
        switch self {
        case .lidSleep, .fansFull, .fansQuiet, .missionControlApps, .timeMachine, .spotlight, .softwareUpdate, .awdl,
             .userActivity, .gameMode, .muteOtherApps:
            return false
        default:
            return true
        }
    }

    /// How the menu groups them.
    static let sections: [(title: String, guards: [Guard])] = [
        ("Power", [.sleep, .lidSleep, .lowPower, .screenSaver, .fansFull, .fansQuiet]),
        ("Screen & input", [.hotCorners, .missionControl, .missionControlApps, .spaceSwipe, .clickToShowDesktop,
                            .stageManager, .spotlightKey, .wallpaper]),
        ("Interruptions", [.notifications, .systemSounds, .muteOtherApps, .crashDialogs, .airplayReceiver, .keyboardSetup]),
        ("Colour", [.nightShift, .trueTone, .autoAppearance, .colourApps]),
        ("Displays", [.cursorFence, .displayLayout, .privacyDots]),
        ("Background work", [.mediaAnalysis, .appUpdaters, .syncthing, .syncApps, .timeMachine, .spotlight,
                             .softwareUpdate]),
        ("Remote access", [.remoteAccess]),
        ("Network (expert)", [.awdl]),
        ("Experimental", [.userActivity, .gameMode]),
    ]
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    func isOn(_ g: Guard) -> Bool {
        d.object(forKey: "guard.\(g.rawValue)") as? Bool ?? g.defaultOn
    }

    func set(_ g: Guard, _ on: Bool) { d.set(on, forKey: "guard.\(g.rawValue)") }

    /// The two fan guards are one choice: ticking one unticks the other.
    var fanMode: Fans.Mode? {
        isOn(.fansFull) ? .full : isOn(.fansQuiet) ? .quiet : nil
    }

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

    /// Sync apps with no pause Show Mode can reach, quit on engage and relaunched on restore.
    /// Several now sync through macOS's File Provider, which may carry on after the app quits.
    var syncApps: [String] {
        get {
            d.stringArray(forKey: "syncApps") ?? [
                "com.resilio.Sync",                         // Resilio Sync
                "com.synology.SynologyDrive.CloudStationUI", // Synology Drive Client
                "io.com.synology.CloudStationUI",           // Synology Drive Client (older)
                "mega.mac",                                 // MEGA
                "com.sync.desktop",                         // Sync.com
                "com.box.desktop",                          // Box Drive
            ]
        }
        set { d.set(newValue, forKey: "syncApps") }
    }

    /// Bundle identifiers of the apps still heard while the other apps are muted.
    var allowedAudioApps: [String] {
        get { d.stringArray(forKey: "allowedAudioApps") ?? [] }
        set { d.set(newValue, forKey: "allowedAudioApps") }
    }

    /// Shortcuts that turn Focus on and off (see FocusGuard).
    var focusOnShortcut: String {
        d.string(forKey: "focusOnShortcut") ?? "Show Mode Focus On"
    }
    var focusOffShortcut: String {
        d.string(forKey: "focusOffShortcut") ?? "Show Mode Focus Off"
    }
}
