import AppKit
import CoreAudio
import CoreMediaIO

/// The coloured privacy dots macOS draws while the microphone, camera or screen capture is in
/// use. No app can hide them. Apple's one sanctioned route hides the microphone and camera
/// dots on external displays showing a full-screen app, after a one-time step in Recovery;
/// the main display always keeps them, and the screen-recording dot cannot be hidden at all.
/// Show Mode reports where a dot is showing, what is causing it and whether that Recovery step
/// has been done; once it has, Show Mode flips the Privacy Indicators switch for the show.
enum PrivacyDots {
    static let overrideKey = "suppress-sw-camera-indication-on-external-displays"
    static let appleGuide = URL(string: "https://support.apple.com/en-us/118449")!

    enum Override { case on, off, unavailable }

    /// The Recovery-only system override. Setting it needs Recovery, but reading it does not.
    static func externalOverride() -> Override {
        guard let r = Shell.run("/usr/bin/system-override", [overrideKey], timeout: 3), r.status == 0 else {
            return .unavailable   // older than macOS 14.4
        }
        if r.out.contains("= on") { return .on }
        if r.out.contains("= off") { return .off }
        return .unavailable
    }

    /// The Privacy Indicators switch in System Settings ▸ Privacy & Security (Microphone and
    /// Camera show the same one). SkyLight stores it as SuppressPrivacyIndicatorOnExternalDisplays
    /// and tells WindowServer; it only has an effect once the Recovery override is on.
    private enum SkyLightSuppress {
        typealias Get = @convention(c) () -> Bool
        typealias Set = @convention(c) (Bool) -> Void
        private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        static let get: Get? = dlsym(handle, "SLSGetSuppressPrivacyIndicatorOnExternalDisplays")
            .map { unsafeBitCast($0, to: Get.self) }
        static let set: Set? = dlsym(handle, "SLSSetSuppressPrivacyIndicatorOnExternalDisplays")
            .map { unsafeBitCast($0, to: Set.self) }
    }

    /// Whether the dots are switched off for external full-screen displays; nil if SkyLight
    /// has no such call.
    static var suppressed: Bool? { SkyLightSuppress.get?() }

    /// Switches the dots off on external displays for the show. Without the Recovery override
    /// the switch does nothing, so it is left alone.
    static func engage() {
        guard externalOverride() == .on, let get = SkyLightSuppress.get, let set = SkyLightSuppress.set,
              !get() else { return }
        if Journal.shared["privacyDotsShown"] == nil { Journal.shared["privacyDotsShown"] = true }
        set(true)
    }

    static func restore() {
        guard Journal.shared["privacyDotsShown"] as? Bool == true, let set = SkyLightSuppress.set else { return }
        set(false)
    }

    /// Displays showing a dot right now. WindowServer draws each dot as a window named
    /// "StatusIndicator", and that name is readable without Screen Recording access.
    static func showingOn() -> [DisplayInfo] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let dots = windows.compactMap { w -> CGRect? in
            guard w[kCGWindowOwnerName as String] as? String == "Window Server",
                  w[kCGWindowName as String] as? String == "StatusIndicator",
                  let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: b)
        }
        return DisplayInfo.all().filter { d in dots.contains { d.bounds.intersects($0) } }
    }

    /// Apps recording from any audio input. Siri's listener (corespeechd) always runs and never
    /// lights a dot.
    static func microphoneUsers() -> [String] {
        guard #available(macOS 14.2, *) else { return [] }
        return audioObjects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            .filter { audioUInt32($0, kAudioProcessPropertyIsRunningInput) != 0 }
            .compactMap { p -> String? in
                var pid: pid_t = 0
                var size = UInt32(MemoryLayout<pid_t>.size)
                var a = address(kAudioProcessPropertyPID)
                guard AudioObjectGetPropertyData(p, &a, 0, nil, &size, &pid) == noErr else { return nil }
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? processName(pid)
                return name == "corespeechd" ? nil : name
            }
    }

    /// Whether any camera is streaming to any app.
    static func cameraInUse() -> Bool {
        var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                          mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                          mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        var used: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        guard CMIOObjectGetPropertyData(system, &a, 0, nil, size, &used, &ids) == noErr else { return false }
        return ids.contains { id in
            var r = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            return CMIOObjectGetPropertyData(id, &r, 0, nil, 4, &used, &running) == noErr && running != 0
        }
    }

    /// One line for the menu and the start-of-show note, or nil when no dot is showing.
    static func problem() -> String? {
        let displays = showingOn()
        guard !displays.isEmpty else { return nil }
        var causes: [String] = []
        let mic = microphoneUsers()
        if !mic.isEmpty { causes.append("microphone: " + mic.joined(separator: ", ")) }
        if cameraInUse() { causes.append("camera") }
        let because = causes.isEmpty ? "screen recording or capture, which cannot be hidden" : causes.joined(separator: "; ")
        return "Privacy dot on \(displays.map(\.name).joined(separator: ", ")) (\(because))"
    }

    // MARK: CoreAudio helpers

    private static func address(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioObjects(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = address(sel)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func audioUInt32(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = address(sel)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : 0
    }

    private static func processName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "process \(pid)"
    }
}
