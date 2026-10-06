import Foundation

/// Swiping sideways between Spaces and full-screen apps: three or four fingers on a trackpad,
/// two on a Magic Mouse. The Mission Control guard's Dock keys do not cover it — the trackpad
/// driver recognises this swipe itself, from preferences it is handed at login, so writing them
/// changes nothing live. `activateSettings -u`, the tool macOS ships to push mouse and trackpad
/// preferences to the HID event system, makes the driver reread them.
enum SpaceSwipe {
    /// 2 means "swipe between full-screen applications". A three-finger 1 is "swipe between
    /// pages" (back and forward inside an app), which never leaves the show, so it is left alone.
    private static let fullScreenApps = 2

    private static let trackpadDomains = ["com.apple.AppleMultitouchTrackpad",
                                          "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    private static let mouseDomains = ["com.apple.AppleMultitouchMouse",
                                       "com.apple.driver.AppleBluetoothMultitouch.mouse"]

    /// The domains the driver reads; a restore that touches one needs `activate()`.
    static let domains = Set(trackpadDomains + mouseDomains)

    /// Built-in and Magic Trackpad keys, their current-host mirrors (System Settings shows
    /// those), and the Magic Mouse's.
    private static let keys: [PrefKey] =
        ["TrackpadThreeFingerHorizSwipeGesture", "TrackpadFourFingerHorizSwipeGesture"].flatMap { key in
            trackpadDomains.map { PrefKey(domain: $0, key: key) }
        }
        + ["threeFingerHorizSwipeGesture", "fourFingerHorizSwipeGesture"].map {
            PrefKey(domain: "NSGlobalDomain", key: "com.apple.trackpad.\($0)", currentHost: true)
        }
        + mouseDomains.map { PrefKey(domain: $0, key: "MouseTwoFingerHorizSwipeGesture") }

    private static let tool =
        "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

    /// Turns off every swipe set to switch Spaces. Returns false if the change was written but
    /// could not be made live.
    static func engage() -> Bool {
        var changed = false
        for k in keys where (k.read() as? Int) == fullScreenApps {
            changed = k.override(0) || changed
        }
        return !changed || activate()
    }

    /// Pushes the mouse and trackpad preferences to the driver, as happens at login.
    @discardableResult
    static func activate() -> Bool {
        let ok = Shell.run(tool, ["-u"])?.status == 0
        ShowLog.note(ok ? "Swipe settings pushed to the trackpad driver"
                        : "activateSettings failed: swipe settings apply at next login")
        return ok
    }
}
