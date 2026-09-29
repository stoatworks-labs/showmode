import AppKit

/// Night Shift and True Tone through CoreBrightness, the private framework System Settings
/// uses. Every call is looked up at runtime, so a macOS that renames them degrades to
/// "unavailable" rather than crashing.
enum CoreBrightness {
    private static let loaded: Bool = {
        Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework")?.load() ?? false
    }()

    private static func client(_ name: String) -> NSObject? {
        guard loaded, let cls = NSClassFromString(name) as? NSObject.Type else { return nil }
        return cls.init()
    }

    private static func imp<T>(_ obj: NSObject, _ sel: String, as: T.Type) -> T? {
        let s = NSSelectorFromString(sel)
        guard obj.responds(to: s), let m = class_getInstanceMethod(type(of: obj), s) else { return nil }
        return unsafeBitCast(method_getImplementation(m), to: T.self)
    }

    // MARK: Night Shift (CBBlueLightClient)

    /// Layout of CBBlueLightClient's status struct: active, enabled, sunSchedulePermitted (BOOLs),
    /// then int mode at offset 4 (0 off, 1 sunset→sunrise, 2 custom schedule).
    struct NightShift { var enabled: Bool; var mode: Int32 }

    static func nightShift() -> NightShift? {
        guard let c = client("CBBlueLightClient"),
              let f = imp(c, "getBlueLightStatus:",
                          as: (@convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool).self)
        else { return nil }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { buf.deallocate() }
        buf.initializeMemory(as: UInt8.self, repeating: 0, count: 64)
        guard f(c, NSSelectorFromString("getBlueLightStatus:"), buf) else { return nil }
        return NightShift(enabled: buf.load(fromByteOffset: 1, as: UInt8.self) != 0,
                          mode: buf.load(fromByteOffset: 4, as: Int32.self))
    }

    static func setNightShift(_ s: NightShift) {
        guard let c = client("CBBlueLightClient") else { return }
        // Mode first: clearing the schedule stops it switching itself back on at sunset.
        if let setMode = imp(c, "setMode:", as: (@convention(c) (AnyObject, Selector, Int32) -> Bool).self) {
            _ = setMode(c, NSSelectorFromString("setMode:"), s.mode)
        }
        if let setEnabled = imp(c, "setEnabled:", as: (@convention(c) (AnyObject, Selector, Bool) -> Bool).self) {
            _ = setEnabled(c, NSSelectorFromString("setEnabled:"), s.enabled)
        }
    }

    // MARK: True Tone (CBTrueToneClient)

    static func trueTone() -> Bool? {
        guard let c = client("CBTrueToneClient"),
              let supported = imp(c, "supported", as: (@convention(c) (AnyObject, Selector) -> Bool).self),
              supported(c, NSSelectorFromString("supported")),
              let enabled = imp(c, "enabled", as: (@convention(c) (AnyObject, Selector) -> Bool).self)
        else { return nil }
        return enabled(c, NSSelectorFromString("enabled"))
    }

    static func setTrueTone(_ on: Bool) {
        guard let c = client("CBTrueToneClient"),
              let f = imp(c, "setEnabled:", as: (@convention(c) (AnyObject, Selector, Bool) -> Bool).self)
        else { return }
        _ = f(c, NSSelectorFromString("setEnabled:"), on)
    }
}

enum ColourShift {
    static func engageNightShift() {
        guard let s = CoreBrightness.nightShift(), s.enabled || s.mode != 0 else { return }
        if Journal.shared["nightShift"] == nil {
            Journal.shared["nightShift"] = ["enabled": s.enabled, "mode": Int(s.mode)]
        }
        CoreBrightness.setNightShift(.init(enabled: false, mode: 0))
    }

    static func restoreNightShift() {
        guard let j = Journal.shared["nightShift"] as? [String: Any] else { return }
        CoreBrightness.setNightShift(.init(enabled: j["enabled"] as? Bool ?? false,
                                           mode: Int32(j["mode"] as? Int ?? 0)))
    }

    static func engageTrueTone() {
        guard CoreBrightness.trueTone() == true else { return }
        if Journal.shared["trueTone"] == nil { Journal.shared["trueTone"] = true }
        CoreBrightness.setTrueTone(false)
    }

    static func restoreTrueTone() {
        if Journal.shared["trueTone"] as? Bool == true { CoreBrightness.setTrueTone(true) }
    }

    // MARK: Automatic light/dark appearance

    /// SkyLight's appearance calls — what System Settings itself uses. Writing the
    /// AppleInterfaceStyleSwitchesAutomatically preference instead changes nothing live: the
    /// appearance manager never rereads it, and System Settings kept showing Auto (checked on
    /// macOS 26.4.1). Looked up at runtime, like the other private calls.
    private enum SkyLightAppearance {
        typealias GetAuto = @convention(c) () -> Bool
        typealias SetAuto = @convention(c) (Bool) -> Void
        private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        static let get: GetAuto? = dlsym(handle, "SLSGetAppearanceThemeSwitchesAutomatically")
            .map { unsafeBitCast($0, to: GetAuto.self) }
        static let set: SetAuto? = dlsym(handle, "SLSSetAppearanceThemeSwitchesAutomatically")
            .map { unsafeBitCast($0, to: SetAuto.self) }
    }

    /// Freezes whatever appearance is showing now, so it cannot flip at sunset mid-show.
    /// Turning automatic switching off leaves the current theme in place.
    static func engageAppearance() {
        guard let get = SkyLightAppearance.get, let set = SkyLightAppearance.set, get() else { return }
        if Journal.shared["appearanceAuto"] == nil { Journal.shared["appearanceAuto"] = true }
        set(false)
    }

    static func restoreAppearance() {
        guard Journal.shared["appearanceAuto"] as? Bool == true, let set = SkyLightAppearance.set else { return }
        set(true)
    }

    // MARK: Third-party colour apps

    static func quitColourApps() {
        var quit = Journal.shared["quitApps"] as? [String] ?? []
        for id in Settings.shared.colourApps {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
                if let path = app.bundleURL?.path, !quit.contains(path) { quit.append(path) }
                app.terminate()
            }
        }
        if !quit.isEmpty { Journal.shared["quitApps"] = quit }
    }

    static func relaunchColourApps() {
        for path in Journal.shared["quitApps"] as? [String] ?? [] {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
        }
    }
}
