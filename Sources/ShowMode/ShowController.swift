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
    private let activity = UserActivity()
    private let appQuits = AppQuits()
    private var watch: Timer?
    private var lastSessions: [String] = []
    /// Messages from the last engage worth showing (a guard that could not apply), or from a
    /// restore that could not put everything back.
    private(set) var warnings: [String] = []

    var onChange: (() -> Void)?

    private let s = Settings.shared

    func engage() {
        guard !engaged else { return }
        warnings = []
        Journal.shared.load()
        Journal.shared["engaged"] = Date()

        if s.isOn(.sleep) { sleep.take() }

        engageAdmin()

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

        var windowManager = false
        if s.isOn(.clickToShowDesktop) {
            windowManager = PrefKey(domain: "com.apple.WindowManager", key: "EnableStandardClickToShowDesktop").override(false)
        }
        if s.isOn(.stageManager) { windowManager = Interruptions.engageStageManager() || windowManager }
        if windowManager { Shell.killall("WindowManager") }

        if s.isOn(.spotlightKey), !Interruptions.engageSpotlightKeys() {
            warnings.append("⌘Space may still open Spotlight: macOS did not take the change")
        }

        if s.isOn(.wallpaper) { Wallpaper.blackOut() }

        if s.isOn(.notifications) {
            if !Focus.isInstalled {
                warnings.append("Do Not Disturb skipped: install the Focus shortcuts from the menu")
            } else if !Focus.engage() {
                warnings.append("Do Not Disturb shortcut failed to run")
            }
        }

        if s.isOn(.systemSounds), !SystemSounds.engage() {
            warnings.append("System sounds may still play: macOS did not take the change")
        }
        if s.isOn(.crashDialogs) { Interruptions.engageCrashDialogs() }
        if s.isOn(.airplayReceiver) { Interruptions.engageAirPlayReceiver() }
        if s.isOn(.keyboardSetup) { Interruptions.startClosingKeyboardSetup() }

        if s.isOn(.colourApps) { ColourShift.quitColourApps() }
        if s.isOn(.nightShift) { ColourShift.engageNightShift() }
        if s.isOn(.trueTone) { ColourShift.engageTrueTone() }
        if s.isOn(.autoAppearance) { ColourShift.engageAppearance() }
        if s.isOn(.privacyDots) { PrivacyDots.engage() }

        if s.isOn(.mediaAnalysis) {
            if Journal.shared["mediaAnalysis"] == nil { Journal.shared["mediaAnalysis"] = true }
            if !Sweeper.user.startUser(Paused.mediaAnalysis) {
                warnings.append("Photo and media analysis not paused: the pause could not start")
            }
        }
        if s.isOn(.appUpdaters) { AppUpdaters.engage() }
        if s.isOn(.syncthing), !Syncthing.engage() {
            warnings.append("Syncthing did not pause every folder")
        }
        if s.isOn(.syncApps) { QuitApps.quit(s.syncApps) }
        if s.isOn(.userActivity) { activity.start() }
        if s.isOn(.holdRestarts) { appQuits.start() }
        if s.isOn(.gameMode), !GameMode.engage() {
            warnings.append("Game Mode not forced on: it needs Xcode installed")
        }

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

        if s.isOn(.remoteAccess) { startWatch() }

        engaged = true
        onChange?()
    }

    /// Everything that needs root, in one password prompt. Each guard has journaled what it
    /// replaces. A cancelled prompt ran nothing, so each step's entries go back to what they
    /// were before (an entry left by a restore that never finished stays). A step that failed
    /// may have run some of its commands, so its entries stay and End writes the originals back.
    private func engageAdmin() {
        let before = Journal.shared.entries
        var admin: [AdminStep] = []
        if s.isOn(.lowPower), let a = PMSet.engageLowPower() { admin.append(a) }
        if s.isOn(.lidSleep), let a = PMSet.engageLidSleep() { admin.append(a) }
        if s.isOn(.timeMachine) { admin += TimeMachine.engage() }
        if s.isOn(.softwareUpdate) {
            if SoftwareUpdate.managed {
                warnings.append("Automatic updates left alone: your organisation manages them")
            } else if let a = SoftwareUpdate.engage() {
                admin.append(a)
            }
        }

        let spotlight = s.isOn(.spotlight)
        let awdl = s.isOn(.awdl) && AWDL.up == true
        var sweeperStep: Int?
        if spotlight || awdl {
            let keys = [(spotlight, "spotlightPaused"), (awdl, "awdlDown")].filter(\.0).map(\.1)
            for key in keys where Journal.shared[key] == nil { Journal.shared[key] = true }
            let label = [spotlight ? "Spotlight indexing" : nil, awdl ? "AWDL" : nil].compactMap { $0 }.joined(separator: " and ")
            if let a = Sweeper.root.rootStep(spotlight ? Paused.spotlight : [], awdl: awdl, label: label, journalKeys: keys) {
                sweeperStep = admin.count
                admin.append(a)
            } else {
                keys.forEach { Journal.shared[$0] = before[$0] }
                warnings.append("\(label) unchanged: the pause could not be set up")
            }
        }

        guard !admin.isEmpty else { return }
        let labels = Self.list(admin.map(\.label))
        guard let failed = Shell.runAsAdmin(admin, prompt: "Show Mode needs your password to change \(labels) for the show.") else {
            for step in admin { step.journalKeys.forEach { Journal.shared[$0] = before[$0] } }
            if sweeperStep != nil { Sweeper.root.close() }
            warnings.append("\(labels) unchanged (password prompt cancelled)")
            return
        }
        for i in failed.sorted() {
            if i == sweeperStep {
                // Its only command starts the sweeper: if that failed, nothing was paused.
                admin[i].journalKeys.forEach { Journal.shared[$0] = before[$0] }
                Sweeper.root.close()
                warnings.append("\(admin[i].label) unchanged: the pause did not start")
            } else {
                warnings.append("\(admin[i].label) may be only partly changed: End puts back what was there")
            }
        }

        // Read back what can report success without taking effect.
        if let w = TimeMachine.confirmEngaged() { warnings.append(w) }
        if spotlight, Sweeper.root.running, !Sweeper.confirmStarted(Paused.spotlight) {
            warnings.append("Spotlight indexing may not be paused: no indexing process stopped")
        }
    }

    func restore() {
        fence.stop()
        layout.stop()
        sleep.release()
        activity.stop()
        appQuits.stop()
        watch?.invalidate()
        watch = nil
        Interruptions.stopClosingKeyboardSetup()
        // The sweepers resume what they paused (a crash already made them) while the rest is
        // put back, journal or not; what they paused is read back below.
        Sweeper.user.stop()
        Sweeper.root.stop()
        Journal.shared.load()
        guard Journal.shared.exists else { engaged = false; warnings = []; onChange?(); return }

        var admin = [PMSet.restoreLowPower(), PMSet.restoreLidSleep(), TimeMachine.restore(),
                     SoftwareUpdate.restore()].compactMap { $0 }
        admin += resumeSteps()

        var unrestored = Set<String>()
        var notes: [String] = []
        if !admin.isEmpty {
            let failed = Shell.runAsAdmin(admin, prompt: "Show Mode needs your password to put back \(Self.list(admin.map(\.label))).")
            for (i, step) in admin.enumerated() where failed?.contains(i) ?? true {
                unrestored.formUnion(step.journalKeys)
                notes.append(step.label)
            }
        }
        if Journal.shared["timeMachine"] as? Bool == true, !unrestored.contains("timeMachine"), !TimeMachine.restored {
            unrestored.insert("timeMachine")
            notes.append("Time Machine (it needs Full Disk Access)")
        }

        let domains = Prefs.restoreAll()
        if domains.contains("com.apple.dock") { Shell.killall("Dock") }
        if domains.contains("com.apple.WindowManager") { Shell.killall("WindowManager") }
        if !domains.isDisjoint(with: SpaceSwipe.domains) { SpaceSwipe.activate() }

        DisplayLayout.restore()
        Wallpaper.restore()
        Focus.restore()
        SystemSounds.restore()
        Interruptions.restoreSpotlightKeys()
        ColourShift.restoreNightShift()
        ColourShift.restoreTrueTone()
        ColourShift.restoreAppearance()
        PrivacyDots.restore()
        if !Syncthing.restore() {
            unrestored.insert("syncthingFolders")
            notes.append("Syncthing folders (Syncthing did not answer)")
        }
        if !GameMode.restore() {
            unrestored.insert("gameMode")
            notes.append("Game Mode")
        }
        QuitApps.relaunch()

        Journal.shared.retain(unrestored)
        engaged = false
        warnings = notes.isEmpty ? [] : ["Not put back yet: \(notes.joined(separator: ", ")). Choose Finish Restoring."]
        if !notes.isEmpty { ShowLog.note("restore incomplete: \(notes)") }
        onChange?()
    }

    /// An admin step for whatever the sweepers paused that is still paused once they have had
    /// time to finish: Spotlight's own workers and AWDL need root. A root sweeper still running
    /// after "stop" would pause them again, so it is killed first.
    private func resumeSteps() -> [AdminStep] {
        let pick = { (key: String) in Journal.shared[key] as? Bool == true }
        let (media, spotlight, awdl) = (pick("mediaAnalysis"), pick("spotlightPaused"), pick("awdlDown"))
        guard media || spotlight || awdl else { return [] }
        let names = (media ? Paused.mediaAnalysis : []) + (spotlight ? Paused.spotlight : [])

        let deadline = Date().addingTimeInterval(4)
        while Sweeper.rootRunning && Date() < deadline { usleep(250_000) }
        let helperStuck = Sweeper.rootRunning
        let stuck = helperStuck ? names : Sweeper.waitForResume(names)
        var cmds: [String] = []
        if helperStuck {
            ShowLog.note("sweeper (root): still running after stop")
            cmds.append("/usr/bin/pkill -KILL -f showmode-sweeper || true")
        }
        cmds += stuck.map { "/usr/bin/pkill -CONT -x \(Shell.quote($0)) || true" }
        if awdl && (helperStuck || AWDL.up == false) { cmds.append("/sbin/ifconfig awdl0 up") }
        guard !cmds.isEmpty else { return [] }
        let keys = [(media, "mediaAnalysis"), (spotlight, "spotlightPaused"), (awdl, "awdlDown")].filter(\.0).map(\.1)
        return [AdminStep(label: "Paused background work", journalKeys: keys, commands: cmds)]
    }

    /// A restart, shut-down or log-out arrived mid-show and Show Mode refused it, which stops
    /// it. The apps macOS asked to quit alongside get a few seconds to finish; then the ones
    /// that did are opened again, the one that was in front brought back to the front. `done`
    /// gets their names.
    func refused(_ kind: Restarts.Kind, done: @escaping ([String]) -> Void) {
        let at = Date()
        let front = appQuits.front
        let when = DateFormatter.localizedString(from: at, dateStyle: .none, timeStyle: .short)
        ShowLog.note("refused a \(kind.rawValue) during the show")
        warnings.append("Stopped a \(kind.rawValue) at \(when): end the show to let it through")
        onChange?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.engaged else { return }
            // Not the apps Show Mode quit itself at the start (colour and sync apps).
            let ours = Set((Journal.shared["quitApps"] as? [String] ?? []).map { URL(fileURLWithPath: $0).standardizedFileURL })
            let urls = self.appQuits.quit(since: at.addingTimeInterval(-15)).filter { !ours.contains($0.standardizedFileURL) }
            for url in urls {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = url == front
                NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            }
            let names = urls.map { $0.deletingPathExtension().lastPathComponent }
            if !names.isEmpty { ShowLog.note("reopened after the refused \(kind.rawValue): \(names)") }
            done(names)
        }
    }

    func toggle() { engaged ? restore() : engage() }

    /// A journal on disk at launch means the last session never restored.
    func recoverIfNeeded() -> Bool {
        guard Journal.shared.exists else { return false }
        restore()
        return true
    }

    // MARK: Watching mid-show

    /// Every five seconds: notes remote sessions starting and ending, and puts the black
    /// wallpaper back if something changed it (TeamViewer, for one, restores the wallpaper it
    /// saw when a session ends).
    private func startWatch() {
        lastSessions = []
        watch = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        Wallpaper.applyBlack()
        // netstat and ps off the main thread: the cursor fence's event tap runs on it, and
        // waiting for them there would hitch the cursor every five seconds.
        DispatchQueue.global().async {
            let sessions = RemoteAccess.sessions()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.watch != nil, sessions != self.lastSessions else { return }
                ShowLog.note(sessions.isEmpty ? "remote session ended" : "remote session: \(sessions.joined(separator: ", "))")
                self.lastSessions = sessions
                self.onChange?()
            }
        }
    }

    // MARK: Helpers

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
