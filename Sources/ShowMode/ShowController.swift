import AppKit

/// Engages and restores every enabled guard. Each guard journals what it replaces before
/// changing it, so `restore()` — including a restore on the next launch after a crash — puts
/// back exactly what was there, and only what show mode changed.
final class ShowController {
    static let shared = ShowController()

    private(set) var engaged = false
    let fence = CursorFence()
    let layout = DisplayLayout()
    private let sleep = SleepAssertion()
    /// Messages from the last engage worth showing (a guard that could not apply).
    private(set) var warnings: [String] = []

    var onChange: (() -> Void)?

    private let s = Settings.shared

    func engage() {
        guard !engaged else { return }
        warnings = []
        Journal.shared.load()
        Journal.shared["engaged"] = Date()

        if s.isOn(.sleep) { sleep.take() }

        var admin: [String] = []
        if s.isOn(.lowPower) { admin += PMSet.engageLowPower() }
        if s.isOn(.lidSleep) { admin += PMSet.engageLidSleep() }
        if !Shell.runAsAdmin(admin, prompt: "Show Mode needs to change power settings for the show.") {
            warnings.append("Power settings unchanged (admin prompt cancelled)")
        }

        if s.isOn(.screenSaver) {
            PrefKey(domain: "com.apple.screensaver", key: "idleTime", currentHost: true).override(0)
        }

        var dock = false
        if s.isOn(.hotCorners) {
            for k in Prefs.hotCornerKeys {
                dock = k.override(k.key.hasSuffix("corner") ? 1 : 0) || dock
            }
        }
        if s.isOn(.missionControl) {
            dock = PrefKey(domain: "com.apple.dock", key: "mcx-expose-disabled").override(true) || dock
            for key in ["showMissionControlGestureEnabled", "showAppExposeGestureEnabled",
                        "showDesktopGestureEnabled", "showLaunchpadGestureEnabled"] {
                dock = PrefKey(domain: "com.apple.dock", key: key).override(false) || dock
            }
        }
        if dock { Shell.killall("Dock") }

        if s.isOn(.spaceSwipe), !SpaceSwipe.engage() {
            warnings.append("Swipe between Spaces is still on: the trackpad settings could not be applied")
        }

        if s.isOn(.clickToShowDesktop),
           PrefKey(domain: "com.apple.WindowManager", key: "EnableStandardClickToShowDesktop").override(false) {
            Shell.killall("WindowManager")
        }

        if s.isOn(.wallpaper) { Wallpaper.blackOut() }

        if s.isOn(.notifications) {
            if !Focus.isInstalled {
                warnings.append("Do Not Disturb skipped: install the Focus shortcuts from the menu")
            } else if !Focus.engage() {
                warnings.append("Do Not Disturb shortcut failed to run")
            }
        }

        if s.isOn(.colourApps) { ColourShift.quitColourApps() }
        if s.isOn(.nightShift) { ColourShift.engageNightShift() }
        if s.isOn(.trueTone) { ColourShift.engageTrueTone() }
        if s.isOn(.autoAppearance) { ColourShift.engageAppearance() }
        if s.isOn(.privacyDots) { PrivacyDots.engage() }

        // Before the fence, so it fences the arrangement the show will actually run on.
        if s.isOn(.displayLayout) {
            layout.onChange = { [weak self] in self?.onChange?() }
            layout.start()
            if let want = s.mainDisplay, !DisplayLayout.online().contains(where: { DisplayLayout.key($0) == want }) {
                warnings.append("The chosen main display is not connected; it becomes main when it is")
            }
            if s.isOn(.cursorFence), s.blockedDisplays.contains(DisplayLayout.intendedMain) {
                warnings.append("The main display is fenced off: the menu bar is out of the cursor's reach (⌃⌥⌘F pauses the fence)")
            }
        }

        if s.isOn(.cursorFence) {
            fence.start()
            if !CursorFence.accessibilityTrusted {
                warnings.append("Cursor fence is in fallback mode: grant Accessibility for a hard fence")
            }
        }

        engaged = true
        onChange?()
    }

    func restore() {
        fence.stop()
        layout.stop()
        sleep.release()
        Journal.shared.load()
        guard Journal.shared.exists else { engaged = false; onChange?(); return }

        let admin = PMSet.restoreLowPower() + PMSet.restoreLidSleep()
        _ = Shell.runAsAdmin(admin, prompt: "Show Mode is restoring your power settings.")

        let domains = Prefs.restoreAll()
        if domains.contains("com.apple.dock") { Shell.killall("Dock") }
        if domains.contains("com.apple.WindowManager") { Shell.killall("WindowManager") }
        if !domains.isDisjoint(with: SpaceSwipe.domains) { SpaceSwipe.activate() }

        DisplayLayout.restore()
        Wallpaper.restore()
        Focus.restore()
        ColourShift.restoreNightShift()
        ColourShift.restoreTrueTone()
        ColourShift.restoreAppearance()
        PrivacyDots.restore()
        ColourShift.relaunchColourApps()

        Journal.shared.clear()
        engaged = false
        warnings = []
        onChange?()
    }

    func toggle() { engaged ? restore() : engage() }

    /// A journal on disk at launch means the last session never restored.
    func recoverIfNeeded() -> Bool {
        guard Journal.shared.exists else { return false }
        restore()
        return true
    }
}
