import AppKit

/// Windows that open over a show output which Do Not Disturb does not hold back, and keys that
/// open them.
enum Interruptions {
    // MARK: Crash reports

    /// "<app> quit unexpectedly" is a window, not a notification. With UseUNC, Problem Reporter
    /// posts it to Notification Center instead, where Do Not Disturb holds it; the report is
    /// still written.
    static let crashNotifications = PrefKey(domain: "com.apple.CrashReporter", key: "UseUNC")

    static func engageCrashDialogs() {
        if (crashNotifications.read() as? Bool) != true { crashNotifications.override(true) }
    }

    // MARK: AirPlay Receiver

    /// While AirPlay Receiver is on, a device signed in to the same Apple ID can put its screen
    /// on the show Mac, and Control Center holds TCP 5000 and 7000, which show tools may want.
    /// macOS 26 spells the key correctly and Control Center applies it at once (checked on
    /// 26.4.1: the listener closed and reopened within seconds, no restart). Earlier versions use
    /// the misspelling the CIS benchmark documents, which 26 ignores, so both are written. An
    /// absent key means on.
    static let airplayReceiver = ["AirplayReceiverEnabled", "AirplayRecieverEnabled"].map {
        PrefKey(domain: "com.apple.controlcenter", key: $0, currentHost: true)
    }

    static func engageAirPlayReceiver() {
        for k in airplayReceiver where (k.read() as? Bool) != false { k.override(false) }
    }

    // MARK: Keyboard Setup Assistant

    /// Opens when anything that presents as a keyboard is plugged in: a clicker, an X-keys
    /// pad, some MIDI and KVM devices. There is no setting for it a user can change, so it is
    /// quit whenever it opens during the show. Closing it unanswered leaves the keyboard type
    /// as ANSI. Nothing to journal.
    static let keyboardSetup = "com.apple.KeyboardSetupAssistant"

    private static var observer: NSObjectProtocol?

    static func startClosingKeyboardSetup() {
        guard observer == nil else { return }
        quitKeyboardSetup()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == keyboardSetup else { return }
            app.terminate()
            ShowLog.note("closed Keyboard Setup Assistant")
        }
    }

    static func stopClosingKeyboardSetup() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private static func quitKeyboardSetup() {
        NSRunningApplication.runningApplications(withBundleIdentifier: keyboardSetup).forEach { $0.terminate() }
    }

    // MARK: ⌘Space

    /// Spotlight's two shortcuts, ⌘Space (64) and ⌥⌘Space (65), switched off in WindowServer
    /// itself through SkyLight, which applies at once and is not saved, so a Mac that restarts
    /// mid-show gets them back anyway. Looked up at runtime like the other private calls.
    private enum SymbolicHotKeys {
        typealias IsEnabled = @convention(c) (Int32) -> Bool
        typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
        private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        static let isEnabled: IsEnabled? = dlsym(handle, "CGSIsSymbolicHotKeyEnabled")
            .map { unsafeBitCast($0, to: IsEnabled.self) }
        static let setEnabled: SetEnabled? = dlsym(handle, "CGSSetSymbolicHotKeyEnabled")
            .map { unsafeBitCast($0, to: SetEnabled.self) }
    }

    static let spotlightHotKeys: [Int32] = [64, 65]

    /// The Spotlight shortcuts that are on now; nil if SkyLight has no such call.
    static var spotlightKeysOn: [Int32]? {
        guard let isEnabled = SymbolicHotKeys.isEnabled else { return nil }
        return spotlightHotKeys.filter { isEnabled($0) }
    }

    /// Returns false if the shortcuts could not be switched off.
    static func engageSpotlightKeys() -> Bool {
        guard let on = spotlightKeysOn, let set = SymbolicHotKeys.setEnabled else { return false }
        guard !on.isEmpty else { return true }
        if Journal.shared["spotlightKeys"] == nil { Journal.shared["spotlightKeys"] = on.map(Int.init) }
        on.forEach { _ = set($0, false) }
        return spotlightKeysOn?.isEmpty == true
    }

    static func restoreSpotlightKeys() {
        guard let keys = Journal.shared["spotlightKeys"] as? [Int], let set = SymbolicHotKeys.setEnabled else { return }
        keys.forEach { _ = set(Int32($0), true) }
    }

    // MARK: Stage Manager

    /// Stage Manager slides the show window aside into a strip when another window is
    /// clicked. WindowManager rereads the key when it restarts.
    static let stageManager = PrefKey(domain: "com.apple.WindowManager", key: "GloballyEnabled")

    /// Returns whether WindowManager needs restarting.
    static func engageStageManager() -> Bool {
        (stageManager.read() as? Bool) == true && stageManager.override(false)
    }
}
