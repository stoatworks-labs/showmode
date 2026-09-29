import AppKit

/// One function pointer for register and remove: removal matches on the pointer, and two
/// identical closure literals are two different pointers.
private let displayLayoutCallback: CGDisplayReconfigurationCallBack = { _, flags, info in
    guard !flags.contains(.beginConfigurationFlag), let info else { return }
    let layout = Unmanaged<DisplayLayout>.fromOpaque(info).takeUnretainedValue()
    DispatchQueue.main.async { layout.scheduleEnforce() }
}

/// Keeps the display arrangement the show started with.
///
/// Two rules, enforced on engage and again after every display reconfiguration:
///
/// - **The main display stays put.** macOS makes a display main by putting it at the origin
///   of the global coordinate space, so a different display is made main by shifting every
///   display's origin by the same amount — the arrangement is unchanged, only which display
///   sits at (0,0). The target is the display chosen in the menu, or whichever was main when
///   the show started.
/// - **New mirrors become extended.** Whatever is mirrored when the show starts is taken as
///   deliberate (a confidence monitor showing the output) and left alone. Any display that
///   starts mirroring during the show — a projector plugged in that macOS remembers as a
///   mirror, or ⌘F1 — is split back out to an extended display.
///
/// macOS sends several reconfiguration callbacks per change and may itself be mid-change, so
/// work is debounced, and a layout that keeps reverting stops being fought after a few
/// attempts rather than looping.
final class DisplayLayout {
    private(set) var active = false
    /// Keys of displays that were mirroring when the show started, left mirrored.
    private var baselineMirrors: Set<String> = []
    private var targetMain: String?
    private var pending: DispatchWorkItem?
    private var recentApplies: [Date] = []
    private(set) var problem: String?

    var onChange: (() -> Void)?

    static func key(_ id: CGDirectDisplayID) -> String {
        let serial = CGDisplaySerialNumber(id)
        let unit = serial == 0 ? "-u\(CGDisplayUnitNumber(id))" : ""
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(serial)\(unit)"
    }

    static func online() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// The display (by key) that will be kept main: the chosen one, else the current main.
    static var intendedMain: String {
        Settings.shared.mainDisplay ?? key(CGMainDisplayID())
    }

    // MARK: Engage / restore

    func start() {
        guard !active else { return }
        active = true
        problem = nil
        recentApplies = []
        if Journal.shared["displayLayout"] == nil {
            Journal.shared["displayLayout"] = ["previousMain": Self.key(CGMainDisplayID())]
        }
        targetMain = Self.intendedMain
        defer { ShowLog.note("display layout: on, keeping \(targetMain ?? "?") main, leaving \(baselineMirrors) mirrored") }
        baselineMirrors = Set(Self.online().filter { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay }.map(Self.key))
        let me = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayLayoutCallback, me)
        enforce()
    }

    func stop() {
        guard active else { return }
        active = false
        pending?.cancel()
        let me = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(displayLayoutCallback, me)
    }

    /// Puts back the display that was main before the show, if it is connected. Mirrors that
    /// were split out stay extended: they were macOS's guess, not the operator's choice.
    static func restore() {
        guard let j = Journal.shared["displayLayout"] as? [String: Any],
              let previous = j["previousMain"] as? String,
              let id = online().first(where: { key($0) == previous && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }),
              id != CGMainDisplayID()
        else { return }
        _ = makeMain(id)
    }

    // MARK: Enforcing

    fileprivate func scheduleEnforce() {
        guard active else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.enforce() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func enforce() {
        guard active else { return }
        ShowLog.note("display layout: checking \(Self.online().map { "\($0)=\(Self.key($0))>\(CGDisplayMirrorsDisplay($0))" })")
        let ids = Self.online()
        let newMirrors = ids.filter {
            CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay && !baselineMirrors.contains(Self.key($0))
        }
        let target = ids.first {
            Self.key($0) == targetMain && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay
        }
        let needMain = target.map { $0 != CGMainDisplayID() } ?? false
        guard !newMirrors.isEmpty || needMain else { return }

        // Our own changes raise callbacks too. Each pass is idempotent, so that settles; a
        // layout that keeps coming back means something else is fighting, and fighting back
        // forever would leave the screens flashing through the show.
        let now = Date()
        recentApplies = recentApplies.filter { now.timeIntervalSince($0) < 20 } + [now]
        if recentApplies.count > 4 {
            problem = "Display layout keeps changing back; stopped enforcing it"
            ShowLog.note("display layout: \(problem!)")
            stop()
            onChange?()
            return
        }

        if !newMirrors.isEmpty {
            var cfg: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return }
            for id in newMirrors { CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay) }
            if CGCompleteDisplayConfiguration(cfg, .forSession) != .success {
                CGCancelDisplayConfiguration(cfg)
            } else {
                ShowLog.note("display layout: split \(newMirrors.map(Self.key)) back to extended")
            }
            // Its bounds only become real once the split has landed; the callback it raises
            // brings us back here for the main-display rule.
            return
        }
        if let target, needMain, Self.makeMain(target) {
            ShowLog.note("display layout: made \(Self.key(target)) main again")
        }
    }

    /// Shifts every extended display so `id` lands on the origin, which is what makes it main.
    @discardableResult
    static func makeMain(_ id: CGDirectDisplayID) -> Bool {
        let masters = online().filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
        let origins = originsMakingMain(id, bounds: Dictionary(uniqueKeysWithValues: masters.map { ($0, CGDisplayBounds($0)) }))
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return false }
        for (d, p) in origins { CGConfigureDisplayOrigin(cfg, d, Int32(p.x), Int32(p.y)) }
        guard CGCompleteDisplayConfiguration(cfg, .forSession) == .success else {
            CGCancelDisplayConfiguration(cfg)
            return false
        }
        return true
    }

    /// Pure: the new origin of every display when `target` is moved to (0,0) and everything
    /// else keeps its position relative to it.
    static func originsMakingMain(_ target: CGDirectDisplayID,
                                  bounds: [CGDirectDisplayID: CGRect]) -> [CGDirectDisplayID: CGPoint] {
        guard let t = bounds[target] else { return [:] }
        return bounds.mapValues { CGPoint(x: $0.minX - t.minX, y: $0.minY - t.minY) }
    }
}
