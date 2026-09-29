import AppKit
import ApplicationServices

struct DisplayInfo {
    let id: CGDirectDisplayID
    let name: String
    let bounds: CGRect       // global CG coordinates (origin top-left of the main display)
    let isMain: Bool
    let isBuiltin: Bool

    /// Survives reboots and replugging, unlike the display ID: vendor/model/serial, plus the
    /// unit number to tell apart identical panels with no serial.
    var key: String {
        let serial = CGDisplaySerialNumber(id)
        let unit = serial == 0 ? "-u\(CGDisplayUnitNumber(id))" : ""
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(serial)\(unit)"
    }

    static func all() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let names: [CGDirectDisplayID: String] = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { s in
            guard let n = s.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { return nil }
            return (n.uint32Value, s.localizedName)
        })
        return ids
            // A mirror shares its master's bounds; only the master takes part in fencing.
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { id in
                DisplayInfo(id: id, name: names[id] ?? "Display \(id)", bounds: CGDisplayBounds(id),
                            isMain: CGDisplayIsMain(id) != 0, isBuiltin: CGDisplayIsBuiltin(id) != 0)
            }
            .sorted { $0.bounds.minX < $1.bounds.minX }
    }
}

/// Keeps the cursor off blocked displays.
///
/// With Accessibility granted, an event tap rewrites every mouse-move/drag that would land on a
/// blocked display to the nearest allowed point and warps the cursor there, so it never gets
/// in. A 120 Hz poll backs that up (and is the whole mechanism without Accessibility, since
/// warping needs no permission). If the cursor is ever seen on a blocked display it is hidden
/// until it leaves, so the audience never sees it.
final class CursorFence {
    private(set) var active = false
    private var allowed: [CGRect] = []
    private var blocked: [CGRect] = []
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var poll: Timer?
    private var hidden = false

    var tapInstalled: Bool { tap != nil }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let opt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([opt: true] as CFDictionary)
    }

    func start() {
        active = true
        recompute()
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        installTap()
        poll?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        poll = t
        check()
        ShowLog.note("cursor fence: on, \(blocked.count) screen(s) blocked, "
                     + (tap != nil ? "event tap (hard fence)" : "poll + hide (no Accessibility)"))
    }

    func stop() {
        active = false
        poll?.invalidate(); poll = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil; tapSource = nil
        setHidden(false)
    }

    /// Call when displays are added, removed or rearranged, or the blocked set changes.
    func recompute() {
        let blockedKeys = Settings.shared.blockedDisplays
        let displays = DisplayInfo.all()
        allowed = displays.filter { !blockedKeys.contains($0.key) }.map(\.bounds)
        blocked = displays.filter { blockedKeys.contains($0.key) }.map(\.bounds)
        // Never trap the cursor with nowhere to go: if every display is blocked (or the only
        // allowed one was unplugged), the fence stands down until that changes.
        if allowed.isEmpty { blocked = [] }
        if active { check() }
    }

    var fencing: Bool { active && !blocked.isEmpty }

    // MARK: Geometry

    private func isBlocked(_ p: CGPoint) -> Bool {
        !allowed.contains { $0.contains(p) } && blocked.contains { $0.contains(p) }
    }

    private func nearestAllowed(to p: CGPoint) -> CGPoint {
        var best = p
        var bestD = CGFloat.infinity
        for r in allowed {
            let q = CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < bestD { bestD = d; best = q }
        }
        return best
    }

    // MARK: Event tap

    private func installTap() {
        guard tap == nil, Self.accessibilityTrusted else { return }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, refcon in
            let fence = Unmanaged<CursorFence>.fromOpaque(refcon!).takeUnretainedValue()
            return fence.handle(type: type, event: event)
        }, userInfo: me) else { return }
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        tapSource = src
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, active { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard fencing else { return Unmanaged.passUnretained(event) }
        let p = event.location
        if isBlocked(p) {
            let q = nearestAllowed(to: p)
            event.location = q
            CGWarpMouseCursorPosition(q)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: Poll + hide fallback

    private func check() {
        guard fencing else { setHidden(false); return }
        if tap == nil { installTap() } // Accessibility may have been granted since start()
        guard let p = CGEvent(source: nil)?.location else { return }
        let now = Date()
        if isBlocked(p) {
            lastSeenBlocked = now
            CGWarpMouseCursorPosition(nearestAllowed(to: p))
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        // Without the tap the poll only catches a crossing after it happens, so hide the cursor
        // while it is close to a blocked display: then the crossing itself is never drawn.
        let nearEdge = tap == nil && blocked.contains { distance(p, $0) < Self.guardBand }
        let recent = now.timeIntervalSince(lastSeenBlocked) < 0.25
        setHidden(Settings.shared.hideOnBlocked && (nearEdge || recent))
    }

    private static let guardBand: CGFloat = 48
    private var lastSeenBlocked = Date.distantPast

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    private func setHidden(_ hide: Bool) {
        guard hide != hidden else { return }
        hidden = hide
        if hide {
            BackgroundCursor.allow()
            CGDisplayHideCursor(CGMainDisplayID())
        } else {
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }
}

/// A background app's hide/show cursor calls are ignored unless the WindowServer connection
/// is flagged "SetsCursorInBackground" — private SPI, looked up at runtime.
enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static var done = false

    static func allow() {
        guard !done else { return }
        done = true
        let h = dlopen(nil, RTLD_NOW)
        guard let c = dlsym(h, "_CGSDefaultConnection"), let s = dlsym(h, "CGSSetConnectionProperty") else { return }
        let cid = unsafeBitCast(c, to: DefaultConnection.self)()
        _ = unsafeBitCast(s, to: SetProperty.self)(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
