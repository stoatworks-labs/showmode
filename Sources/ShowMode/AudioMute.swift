import AppKit
import CoreAudio

/// Mutes every app's audio except the ones allowed to play, so Outlook's chime or a browser tab
/// cannot reach a PA that the show Mac feeds. One global process tap does it: `.muted` keeps the
/// other apps' sound off the hardware, and the allowed apps are excluded by bundle identifier
/// (macOS 26), so one opened mid-show is heard with no change to the tap. Nothing ever reads the
/// tap, which is why it needs no recording permission and lights no privacy dot.
///
/// Measured on macOS 26.4.1 by recording the output device: the mute takes hold of each sound
/// as it starts. A sound already playing when the tap is made keeps playing until it stops — a
/// tap naming the process, or one aimed at the device, does no better — so the start-of-show
/// note names those apps.
///
/// The tap belongs to Show Mode's process. If Show Mode crashes or is killed, coreaudiod drops
/// it and every app is heard again: the failure is lost protection, never a silent show.
/// Nothing to journal. The output's volume and mute are never touched, and an app that sends
/// its sound to its own interface is muted all the same unless allowed.
final class AudioMute {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var listener: AudioObjectPropertyListenerBlock?
    private var allowed: [String] = []
    /// The bundle identifiers the current tap excludes: the allowed apps and their helpers seen so far.
    private var excludedIDs: Set<String> = []

    private static let processList = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    var active: Bool { tap != kAudioObjectUnknown }

    /// Starts muting everything but `allowed`. Returns false before macOS 26, where a tap cannot
    /// exclude by bundle identifier.
    func start(allowing allowed: [String]) -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        guard !active else { update(allowing: allowed); return true }
        self.allowed = allowed
        excludedIDs = Self.excludedIDs(allowed)
        guard let id = Self.makeTap(excluding: excludedIDs) else { return false }
        tap = id
        // A helper an allowed app starts mid-show (a browser's audio process) has an identifier
        // of its own; the tap is remade to let it through.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.active, !Self.excludedIDs(self.allowed).isSubset(of: self.excludedIDs) else { return }
            self.update(allowing: self.allowed)
        }
        var addr = Self.processList
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block) == noErr {
            listener = block
        }
        ShowLog.note("audio: muting all but \(excludedIDs.sorted())")
        return true
    }

    /// A tap's exclusions cannot be changed in place (setting kAudioTapPropertyDescription
    /// answers '!hog'), so a new tap is made before the old one goes. Anything muted that is
    /// still playing is heard once the old tap goes, until it stops: the new tap only takes
    /// hold of sounds that start after it.
    func update(allowing allowed: [String]) {
        guard #available(macOS 26.0, *), active else { return }
        self.allowed = allowed
        let want = Self.excludedIDs(allowed)
        guard want != excludedIDs else { return }
        guard let id = Self.makeTap(excluding: want) else {
            ShowLog.note("audio: could not update the allowed apps; the old list stays")
            return
        }
        AudioHardwareDestroyProcessTap(tap)
        tap = id
        excludedIDs = want
        ShowLog.note("audio: now muting all but \(want.sorted())")
    }

    func stop() {
        guard #available(macOS 26.0, *), active else { return }
        if let listener {
            var addr = Self.processList
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, listener)
        }
        listener = nil
        AudioHardwareDestroyProcessTap(tap)
        tap = AudioObjectID(kAudioObjectUnknown)
        ShowLog.note("audio: muting off")
    }

    @available(macOS 26.0, *)
    private static func makeTap(excluding ids: Set<String>) -> AudioObjectID? {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.bundleIDs = ids.sorted()
        desc.name = "Show Mode"
        desc.isPrivate = true
        desc.muteBehavior = .muted
        var id = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &id) == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// The allowed identifiers, plus those of running helpers that extend one
    /// (com.google.Chrome.helper for com.google.Chrome).
    private static func excludedIDs(_ allowed: [String]) -> Set<String> {
        Set(allowed).union(players().map(\.bundleID).filter { isAllowed($0, allowed) })
    }

    // MARK: Who is playing

    struct Player {
        let object: AudioObjectID
        let bundleID: String
        let pid: pid_t
        let playing: Bool
    }

    /// Every process CoreAudio knows: its bundle identifier (empty for a command-line tool),
    /// pid, and whether it is sending audio to an output right now.
    static func players() -> [Player] {
        var addr = processList
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            Player(object: id, bundleID: string(id, kAudioProcessPropertyBundleID) ?? "",
                   pid: pid_t(bitPattern: uint32(id, kAudioProcessPropertyPID)),
                   playing: uint32(id, kAudioProcessPropertyIsRunningOutput) != 0)
        }
    }

    static func isAllowed(_ bundleID: String, _ allowed: [String]) -> Bool {
        !bundleID.isEmpty && allowed.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    /// Apps playing right now that are not allowed. The mute does not reach a sound that is
    /// already playing, so these stay audible until they stop: named at the start of a show.
    static func playingNotAllowed(_ allowed: [String]) -> [String] {
        let names = players().filter { $0.playing && !isAllowed($0.bundleID, allowed) && $0.pid != getpid() }.map { p in
            NSRunningApplication(processIdentifier: p.pid)?.localizedName
                ?? (p.bundleID.isEmpty ? "process \(p.pid)" : p.bundleID)
        }
        return Array(Set(names)).sorted()
    }

    // MARK: CoreAudio helpers

    private static func address(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func uint32(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
        var a = address(sel)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : 0
    }

    private static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = address(sel)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr, let v else { return nil }
        return v.takeRetainedValue() as String
    }
}
