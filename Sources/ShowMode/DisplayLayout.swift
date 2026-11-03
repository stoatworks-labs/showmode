import AppKit

/// One function pointer for register and remove: removal matches on the pointer, and two
/// identical closure literals are two different pointers.
private let displayLayoutCallback: CGDisplayReconfigurationCallBack = { _, flags, info in
    guard !flags.contains(.beginConfigurationFlag), let info else { return }
    let layout = Unmanaged<DisplayLayout>.fromOpaque(info).takeUnretainedValue()
    DispatchQueue.main.async { layout.scheduleEnforce() }
}

/// The screen layout lock: keeps the display arrangement the show started with.
///
/// Three rules, enforced on engage and again after every display reconfiguration:
///
/// - **The main display stays put.** macOS makes a display main by putting it at the origin
///   of the global coordinate space, so a different display is made main by shifting every
///   display's origin by the same amount — the arrangement is unchanged, only which display
///   sits at (0,0). The target is the display chosen in the menu, or whichever was main when
///   the show started.
/// - **Clones stay clones.** Whatever is mirrored when the show starts is the operator's
///   choice (the laptop's screen cloned to a monitor at the desk, say). If something splits
///   it — PowerPoint does, for Presenter View — it is mirrored again. Not while something is
///   full screen on it, which would be left with nowhere to show: PowerPoint's slides are moved
///   to the show screen first (see `PowerPoint`), anything else keeps the split.
/// - **New mirrors become extended.** Any display that starts mirroring during the show — a
///   projector plugged in that macOS remembers as a mirror, ⌘F1, or PowerPoint mirroring every
///   screen for a show without Presenter View — is split back out to an extended display, and
///   PowerPoint's slides follow it.
///
/// macOS sends several reconfiguration callbacks per change and may itself be mid-change, so
/// work is debounced, and a layout that keeps reverting stops being fought after a few
/// attempts rather than looping. Anything that asks PowerPoint runs off the main thread, where
/// the cursor fence's event tap lives.
final class DisplayLayout {
    private(set) var active = false
    /// Displays mirroring when the show started, by key, each with the key of its master.
    private var clones: [String: String] = [:]
    /// Displays extended and not main when the show started: where PowerPoint's slides belong.
    private var showScreens: [String] = []
    private var targetMain: String?
    private var pending: DispatchWorkItem?
    private var recentApplies: [Date] = []
    /// After a correction made during a PowerPoint show, until when its slides are moved to
    /// the show screen: the screen a split puts them on only has its own bounds once it lands.
    private var placeSlidesUntil: Date?
    /// A pass is asking PowerPoint off the main thread; a callback meanwhile runs another after.
    private var working = false
    private var again = false
    private var lastLogged: [String] = []
    private let queue = DispatchQueue(label: "com.stoatworks.showmode.display-layout")
    private(set) var problem: String?
    /// A clone left split for now, and why. Clears once the layout is back.
    private(set) var notice: String?

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

    /// The display `id` mirrors, if any.
    private static func master(_ id: CGDirectDisplayID) -> CGDirectDisplayID? {
        let m = CGDisplayMirrorsDisplay(id)
        return m == kCGNullDirectDisplay ? nil : m
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
        notice = nil
        recentApplies = []
        placeSlidesUntil = nil
        lastLogged = []
        // A restart mid-show (a new main display chosen) keeps the clones the show began with:
        // PowerPoint may have split them since.
        var entry = Journal.shared["displayLayout"] as? [String: Any] ?? ["previousMain": Self.key(CGMainDisplayID())]
        if let c = entry["clones"] as? [String: String], let s = entry["showScreens"] as? [String] {
            clones = c
            showScreens = s
        } else {
            let ids = Self.online()
            clones = Dictionary(ids.compactMap { id in Self.master(id).map { (Self.key(id), Self.key($0)) } },
                                uniquingKeysWith: { a, _ in a })
            showScreens = ids.filter { Self.master($0) == nil && $0 != CGMainDisplayID() }.map(Self.key)
            entry["clones"] = clones
            entry["showScreens"] = showScreens
        }
        Journal.shared["displayLayout"] = entry
        targetMain = Self.intendedMain
        ShowLog.note("display layout: on, keeping \(targetMain ?? "?") main, clones \(clones), show screens \(showScreens)")
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

    fileprivate func scheduleEnforce(after delay: TimeInterval = 1.0) {
        guard active else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.enforce() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func enforce() {
        guard active else { return }
        guard !working else { again = true; return }
        let ids = Self.online()
        // Once per state: a clone left split is re-checked every few seconds.
        let state = ids.map { "\($0)=\(Self.key($0))>\(CGDisplayMirrorsDisplay($0))" }
        if state != lastLogged {
            lastLogged = state
            ShowLog.note("display layout: checking \(state)")
        }
        let byKey = Dictionary(ids.map { (Self.key($0), $0) }, uniquingKeysWith: { a, _ in a })

        // Clones out of their mirror, or mirroring something else, whose master is still there.
        let remirror: [(id: CGDirectDisplayID, master: CGDirectDisplayID)] = clones.compactMap { k, mk in
            guard let id = byKey[k], let m = byKey[mk], Self.master(m) == nil, Self.master(id) != m else { return nil }
            return (id, m)
        }
        let newMirrors = ids.filter { Self.master($0) != nil && clones[Self.key($0)] == nil }
        let needMain = mainTarget().map { $0 != CGMainDisplayID() } ?? false
        // On the main thread: off it, NSRunningApplication sometimes missed a PowerPoint that
        // had been running for minutes.
        let pptPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: PowerPoint.bundleID)
            .map(\.processIdentifier))
        let powerPoint = !pptPIDs.isEmpty
        let placing = powerPoint && placeSlidesUntil.map { Date() < $0 } ?? false
        guard !newMirrors.isEmpty || !remirror.isEmpty || needMain || placing else {
            if notice != nil { notice = nil; onChange?() }
            return
        }

        // Our own changes raise callbacks too. Each pass is idempotent, so that settles; a
        // layout that keeps coming back means something else is fighting, and fighting back
        // forever would leave the screens flashing through the show.
        let now = Date()
        recentApplies = recentApplies.filter { now.timeIntervalSince($0) < 20 }
        if recentApplies.count >= 4 {
            problem = "Display layout keeps changing back; stopped enforcing it"
            ShowLog.note("display layout: \(problem!)")
            stop()
            onChange?()
            return
        }

        if newMirrors.isEmpty && remirror.isEmpty && !placing {
            fixMain()
            return
        }

        // The rest may need PowerPoint, which can take seconds to answer.
        let bounds = Dictionary(ids.map { ($0, CGDisplayBounds($0)) }, uniquingKeysWith: { a, _ in a })
        let plan = Plan(split: newMirrors, remirror: remirror,
                        mirrored: newMirrors.compactMap { Self.master($0).flatMap { bounds[$0] } },
                        slides: slidesScreen(ids, excluding: remirror.map(\.id)),
                        splitSlides: chosenScreen(newMirrors) ?? newMirrors.first { showScreens.contains(Self.key($0)) },
                        bounds: bounds,
                        names: Dictionary(ids.map { ($0, Self.name($0)) }, uniquingKeysWith: { a, _ in a }),
                        pptPIDs: pptPIDs, place: placing)
        working = true
        queue.async {
            let result = plan.run()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active else { self?.working = false; return }
                self.working = false
                result.log.forEach { ShowLog.note("display layout: \($0)") }
                if result.changed {
                    self.recentApplies.append(Date())
                    if powerPoint { self.placeSlidesUntil = Date().addingTimeInterval(10) }
                } else if needMain {
                    // Nothing changed, so no callback is coming to bring the main display back.
                    self.fixMain()
                }
                if result.placed { self.placeSlidesUntil = nil }
                if self.notice != result.notice {
                    self.notice = result.notice
                    if let n = result.notice { ShowLog.note("display layout: \(n)") }
                    self.onChange?()
                }
                if self.again {
                    self.again = false
                    self.scheduleEnforce()
                } else if result.notice != nil {
                    // What held it back — PowerPoint busy starting its show, a player full
                    // screen, Automation not yet allowed — goes away without a display callback.
                    self.scheduleEnforce(after: 3)
                }
            }
        }
    }

    /// The display to keep main, if it is connected and not a mirror.
    private func mainTarget() -> CGDirectDisplayID? {
        Self.online().first { Self.key($0) == targetMain && Self.master($0) == nil }
    }

    private func fixMain() {
        guard let target = mainTarget(), target != CGMainDisplayID() else { return }
        recentApplies.append(Date())
        if Self.makeMain(target) {
            ShowLog.note("display layout: made \(Self.key(target)) main again")
        }
    }

    /// Where PowerPoint's slides go: the screen chosen under PowerPoint Slides On, else the
    /// first screen that was extended at the start, as long as it is extended and not main now.
    private func slidesScreen(_ ids: [CGDirectDisplayID], excluding: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        let candidates = ids.filter { Self.master($0) == nil && $0 != CGMainDisplayID() && !excluding.contains($0) }
        return chosenScreen(candidates) ?? candidates.first { showScreens.contains(Self.key($0)) }
    }

    private func chosenScreen(_ ids: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        guard let want = Settings.shared.slidesDisplay else { return nil }
        return ids.first { Self.key($0) == want }
    }

    /// The name macOS shows for a display. A mirror has no screen of its own to ask.
    static func name(_ id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { ($0.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?
            .localizedName ?? "Display \(id)"
    }

    /// One correction pass, worked out on the main thread and run off it.
    private struct Plan {
        let split: [CGDirectDisplayID]
        let remirror: [(id: CGDirectDisplayID, master: CGDirectDisplayID)]
        /// The bounds of the displays the new mirrors show.
        let mirrored: [CGRect]
        /// The show screen as things stand; nil if it is mirrored or missing.
        let slides: CGDirectDisplayID?
        /// The new mirror the slides follow once split out (PowerPoint mirrors every screen
        /// for a show without Presenter View).
        let splitSlides: CGDirectDisplayID?
        let bounds: [CGDirectDisplayID: CGRect]
        let names: [CGDirectDisplayID: String]
        /// PowerPoint's processes, empty if it is not running.
        let pptPIDs: Set<pid_t>
        let place: Bool
        var powerPoint: Bool { !pptPIDs.isEmpty }

        struct Result {
            var changed = false
            var placed = false
            var notice: String?
            var log: [String] = []
        }

        func run() -> Result {
            var r = Result()
            let answer = powerPoint ? PowerPoint.slideShows() : .none
            var shows: [CGRect] = []
            if case .shows(let s) = answer { shows = s }
            func name(_ id: CGDirectDisplayID) -> String { names[id] ?? "Display \(id)" }

            // Clones go back only if nothing full screen would be stranded on them.
            var remake: [(id: CGDirectDisplayID, master: CGDirectDisplayID)] = []
            for c in remirror {
                guard let b = bounds[c.id] else { continue }
                let owners = FullScreen.owners(on: b)
                if owners.isEmpty { remake.append(c); continue }
                let clone = name(c.id)
                let others = owners.filter { !pptPIDs.contains($0.pid) }
                // Most lasting reason first, so a window passing through mid-show does not flip
                // the notice back and forth.
                if slides == nil && others.count < owners.count {
                    r.notice = "\(clone) left out of its clone: PowerPoint is full screen on it and no other screen is free for its slides"
                } else if let other = others.first {
                    r.notice = "\(clone) left out of its clone: \(other.name) is full screen on it"
                } else if let i = shows.firstIndex(where: { $0.integral == b.integral }) {
                    if let s = slides, let to = bounds[s], PowerPoint.move(i + 1, to: to) {
                        r.log.append("moved PowerPoint's slides from \(clone) to \(name(s))")
                        r.placed = true
                        remake.append(c)
                    } else {
                        r.notice = "\(clone) left out of its clone: PowerPoint's slides are on it and would not move"
                    }
                } else if answer.notAllowed {
                    r.notice = "\(clone) left out of its clone: allow Show Mode to control PowerPoint (Setup) so it can move the slides"
                } else if case .none = answer {
                    r.notice = "\(clone) left out of its clone for now: PowerPoint is not answering"
                } else {
                    // Full screen, but not one of its slide shows: a document window, say.
                    r.notice = "\(clone) left out of its clone: PowerPoint is full screen on it"
                }
            }

            // A new mirror carrying PowerPoint's slides is split only if they can follow it out.
            var split = self.split
            if powerPoint, !split.isEmpty {
                let carriesSlides = answer.notAllowed
                    ? mirrored.contains { b in FullScreen.owners(on: b).contains { pptPIDs.contains($0.pid) } }
                    : shows.contains { s in mirrored.contains { $0.integral == s.integral } }
                if carriesSlides && (answer.notAllowed || splitSlides == nil) {
                    r.notice = answer.notAllowed
                        ? "PowerPoint mirrored the screens for its show: allow Show Mode to control PowerPoint (Setup) so it can split them and move the slides"
                        : "PowerPoint mirrored the screens for its show, and no screen extended at the start is free for its slides: left mirrored"
                    split = []
                }
            }

            if !split.isEmpty || !remake.isEmpty {
                var cfg: CGDisplayConfigRef?
                if CGBeginDisplayConfiguration(&cfg) == .success, let cfg {
                    for id in split { CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay) }
                    for c in remake { CGConfigureDisplayMirrorOfDisplay(cfg, c.id, c.master) }
                    if CGCompleteDisplayConfiguration(cfg, .forSession) == .success {
                        r.changed = true
                        if !split.isEmpty { r.log.append("split \(split.map(name)) back to extended") }
                        if !remake.isEmpty { r.log.append("mirrored \(remake.map { "\(name($0.id)) of \(name($0.master))" }) again") }
                    } else {
                        CGCancelDisplayConfiguration(cfg)
                        r.log.append("could not change the mirrors")
                    }
                }
                // A split screen only has its own bounds once the split lands: its callback
                // brings the next pass, which moves the slides.
                return r
            }

            // PowerPoint's slides onto the show screen, after a correction made for its show.
            if place, let s = slides, let to = bounds[s], !shows.isEmpty,
               !shows.contains(where: { $0.integral == to.integral }) {
                if PowerPoint.move(1, to: to) {
                    r.log.append("moved PowerPoint's slides to \(name(s))")
                    r.placed = true
                } else {
                    r.log.append("could not move PowerPoint's slides to \(name(s))")
                }
            }
            return r
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
