import AppKit
import ServiceManagement

@main
struct ShowModeMain {
    static func main() {
        if CommandLine.arguments.contains("--version") {
            print(appVersion)
            return
        }
        if CommandLine.arguments.contains("--status") {
            printStatus()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Read-only report of everything show mode looks at.
    static func printStatus() {
        let ns = CoreBrightness.nightShift()
        print("Night Shift:     \(ns.map { "enabled=\($0.enabled) mode=\($0.mode)" } ?? "unavailable")")
        print("True Tone:       \(CoreBrightness.trueTone().map { "\($0)" } ?? "unsupported")")
        print("Low power:       \(PMSet.lowPowerBySource().map { "\($0.key) \($0.value.key)=\($0.value.value)" }.sorted())")
        print("Lid sleep off:   \(PMSet.sleepDisabled)")
        print("Focus shortcuts: \(Focus.isInstalled ? "installed" : "not installed")")
        print("Accessibility:   \(CursorFence.accessibilityTrusted)")
        print("Journal pending: \(Journal.shared.exists)")
        print("Dot override:    \(PrivacyDots.externalOverride())")
        print("Dots suppressed: \(PrivacyDots.suppressed.map { "\($0)" } ?? "unavailable")")
        print("Privacy dots:    \(PrivacyDots.showingOn().map(\.name))")
        print("Microphone:      \(PrivacyDots.microphoneUsers())")
        print("Camera in use:   \(PrivacyDots.cameraInUse())")
        Journal.shared.load()
        print("Wallpaper:       \(Wallpaper.blackedOut ? "blacked out" : "untouched")")
        print("Hot corners:     \(Prefs.hotCornerKeys.map { "\($0.key)=\($0.read() ?? "unset")" })")
        for d in DisplayInfo.all() {
            print("Display:         \(d.name) key=\(d.key) bounds=\(d.bounds)\(d.isMain ? " main" : "")")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private let show = ShowController.shared
    private var fencePaused = false
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        show.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()

        // For screenshots and a quick look without clicking through the menu.
        if CommandLine.arguments.contains("--about") { StoatworksAbout.show() }
        if CommandLine.arguments.contains("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.item.button?.performClick(nil) }
        }

        if show.recoverIfNeeded() {
            notify("Show Mode restored settings left over from a session that did not end cleanly.")
        }

        Hotkeys.shared.register(keyCode: 1) { [weak self] in self?.toggleShow() }   // ⌃⌥⌘S
        Hotkeys.shared.register(keyCode: 3) { [weak self] in self?.toggleFence() }  // ⌃⌥⌘F

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.show.fence.recompute()
            Wallpaper.applyBlack()
        }

        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))

        // A launcher or `kill` stopping us mid-show still puts the machine back.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.show.restore()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if show.engaged || Journal.shared.exists { show.restore() }
        return .terminateNow
    }

    // MARK: URL scheme: showmode://on | off | toggle | fence-on | fence-off | wallpaper-black | wallpaper-restore

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let host = URL(string: s)?.host?.lowercased() else { return }
        switch host {
        case "on": if !show.engaged { toggleShow() }
        case "off": if show.engaged { toggleShow() }
        case "toggle": toggleShow()
        case "fence-on": if fencePaused { toggleFence() }
        case "fence-off": if !fencePaused { toggleFence() }
        case "wallpaper-black": if !Wallpaper.blackedOut { toggleWallpaper() }
        case "wallpaper-restore": if Wallpaper.blackedOut { toggleWallpaper() }
        default: break
        }
    }

    // MARK: Actions

    @objc private func toggleShow() {
        fencePaused = false
        show.toggle()
        guard show.engaged else { return }
        let notes = show.warnings + [PrivacyDots.problem()].compactMap { $0 }
        if !notes.isEmpty { notify(notes.joined(separator: "\n")) }
    }

    @objc private func toggleFence() {
        guard show.engaged, Settings.shared.isOn(.cursorFence) else { return }
        fencePaused.toggle()
        fencePaused ? show.fence.stop() : show.fence.start()
        updateIcon()
    }

    /// Black out or restore the wallpaper on its own, in or out of show mode.
    @objc private func toggleWallpaper() {
        Wallpaper.blackedOut ? Wallpaper.restoreOnly() : Wallpaper.blackOut()
    }

    @objc private func toggleGuard(_ sender: NSMenuItem) {
        guard let g = sender.representedObject as? Guard else { return }
        Settings.shared.set(g, !Settings.shared.isOn(g))
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        var blocked = Settings.shared.blockedDisplays
        if blocked.contains(key) {
            blocked.remove(key)
        } else {
            let displays = DisplayInfo.all()
            // The cursor always keeps at least one connected screen: never block the last one.
            guard displays.contains(where: { $0.key != key && !blocked.contains($0.key) }) else { return }
            if let d = displays.first(where: { $0.key == key }), d.isMain, !confirmBlockMain(d) { return }
            blocked.insert(key)
        }
        Settings.shared.blockedDisplays = blocked
        show.fence.recompute()
    }

    /// The menu bar, the Dock and new windows live on the main display, so blocking it is
    /// rarely what an operator means. Asks first.
    private func confirmBlockMain(_ d: DisplayInfo) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Keep the cursor off \(d.name)?"
        a.informativeText = """
            This is the main display: it has the menu bar, including Show Mode's own menu, and \
            the Dock. With it blocked during a show you cannot reach either with the mouse. \
            ⌃⌥⌘F pauses the fence, and ⌃⌥⌘S ends show mode.

            To keep the menu bar on the operator's screen instead, choose that screen under \
            Main Display in Show Mode's menu: it becomes the main display when the show starts.
            """
        a.addButton(withTitle: "Block Main Display")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    @objc private func chooseMain(_ sender: NSMenuItem) {
        Settings.shared.mainDisplay = sender.representedObject as? String
        // Mid-show, a new choice takes effect now rather than at the next start.
        if show.engaged && Settings.shared.isOn(.displayLayout) {
            show.layout.stop()
            show.layout.start()
        }
    }

    @objc private func toggleHide() { Settings.shared.hideOnBlocked.toggle() }

    @objc private func grantAccessibility() {
        CursorFence.promptForAccessibility()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func installFocus() {
        // Signing goes through Apple's servers and takes ~15 s per shortcut.
        notify("Creating the Do Not Disturb shortcuts… Shortcuts will ask to add each one.")
        DispatchQueue.global().async {
            let err = Focus.install()
            DispatchQueue.main.async {
                if let err { self.alert("Could not create the Focus shortcuts", err) }
            }
        }
    }

    /// Hiding the dots needs a restart into Recovery, which Show Mode cannot do for you.
    @objc private func explainPrivacyDots() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Hide privacy dots on external displays"
        a.informativeText = """
            macOS shows an orange dot while the microphone is in use and a green one for the \
            camera. No app can turn them off, but macOS can leave them off an external display \
            that is showing a full-screen app:

            1. Start up in Recovery, choose Utilities ▸ Terminal and run:
               system-override \(PrivacyDots.overrideKey)=on
            2. Restart. From then on Show Mode turns the dots off on external displays for \
            each show and back on afterwards (the Privacy Indicators switch under System \
            Settings ▸ Privacy & Security ▸ Microphone does the same by hand).

            The main display always keeps its dots, so make the operator's screen the main \
            display (Main Display in this menu). The purple screen-recording dot cannot be \
            hidden at all.
            """
        a.addButton(withTitle: "Open Apple's Instructions")
        a.addButton(withTitle: "Close")
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(PrivacyDots.appleGuide) }
    }

    @objc private func openPrivacyIndicators() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do { svc.status == .enabled ? try svc.unregister() : try svc.register() }
        catch { alert("Launch at login", error.localizedDescription) }
    }

    @objc private func about() { StoatworksAbout.show() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared

        let state = NSMenuItem(title: show.engaged ? "Show Mode is ON" : "Show Mode is off", action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        let toggle = add(menu, show.engaged ? "End Show Mode" : "Start Show Mode", #selector(toggleShow))
        toggle.keyEquivalent = "s"
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        for w in show.warnings + [show.layout.problem, PrivacyDots.problem()].compactMap({ $0 }) {
            let i = NSMenuItem(title: "⚠︎ " + w, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }

        add(menu, Wallpaper.blackedOut ? "Restore Wallpaper" : "Black Out Wallpaper", #selector(toggleWallpaper))

        menu.addItem(.separator())
        let head = NSMenuItem(title: "Keep cursor off:", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        let displays = DisplayInfo.all()
        let blocked = s.blockedDisplays
        for d in displays {
            var title = d.name
            if d.isMain { title += " (menu bar)" }
            let i = add(menu, title, #selector(toggleDisplay(_:)))
            i.representedObject = d.key
            i.state = blocked.contains(d.key) ? .on : .off
            i.indentationLevel = 1
            // The last screen left to the cursor cannot be ticked.
            if !blocked.contains(d.key),
               !displays.contains(where: { $0.key != d.key && !blocked.contains($0.key) }) {
                i.action = nil
                i.toolTip = "The cursor needs at least one screen it can reach"
            }
        }
        if displays.count == 1 {
            let i = NSMenuItem(title: "Only one screen: nothing to fence off", action: nil, keyEquivalent: "")
            i.isEnabled = false
            i.indentationLevel = 1
            menu.addItem(i)
        }
        if displays.allSatisfy({ blocked.contains($0.key) }) {
            let i = NSMenuItem(title: "⚠︎ Every screen blocked: fence stands down", action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        let hide = add(menu, "Hide cursor if it reaches a blocked screen", #selector(toggleHide))
        hide.state = s.hideOnBlocked ? .on : .off
        hide.indentationLevel = 1
        if show.engaged && s.isOn(.cursorFence) {
            let p = add(menu, fencePaused ? "Resume Cursor Fence" : "Pause Cursor Fence", #selector(toggleFence))
            p.keyEquivalent = "f"
            p.keyEquivalentModifierMask = [.control, .option, .command]
            p.indentationLevel = 1
        }

        menu.addItem(.separator())
        let mainMenu = NSMenu()
        let intended = s.mainDisplay
        let atStart = NSMenuItem(title: "Whichever is main at start", action: #selector(chooseMain(_:)), keyEquivalent: "")
        atStart.target = self
        atStart.state = intended == nil ? .on : .off
        mainMenu.addItem(atStart)
        mainMenu.addItem(.separator())
        for d in displays {
            let i = NSMenuItem(title: d.name + (d.isMain ? " (main now)" : ""), action: #selector(chooseMain(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = d.key
            i.state = intended == d.key ? .on : .off
            mainMenu.addItem(i)
        }
        if let intended, !displays.contains(where: { $0.key == intended }) {
            let i = NSMenuItem(title: "Chosen display (not connected)", action: nil, keyEquivalent: "")
            i.state = .on
            i.isEnabled = false
            mainMenu.addItem(i)
        }
        if !s.isOn(.displayLayout) {
            mainMenu.addItem(.separator())
            let off = NSMenuItem(title: "Off: turn on in What Show Mode Disables", action: nil, keyEquivalent: "")
            off.isEnabled = false
            mainMenu.addItem(off)
        }
        let mainItem = NSMenuItem(title: "Main Display", action: nil, keyEquivalent: "")
        mainItem.submenu = mainMenu
        menu.addItem(mainItem)

        menu.addItem(.separator())
        let guards = NSMenu()
        for g in Guard.allCases {
            let i = NSMenuItem(title: g.title, action: #selector(toggleGuard(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = g
            i.state = s.isOn(g) ? .on : .off
            guards.addItem(i)
        }
        if show.engaged {
            guards.addItem(.separator())
            let n = NSMenuItem(title: "Changes apply at the next Start", action: nil, keyEquivalent: "")
            n.isEnabled = false
            guards.addItem(n)
        }
        let gi = NSMenuItem(title: "What Show Mode Disables", action: nil, keyEquivalent: "")
        gi.submenu = guards
        menu.addItem(gi)

        let setup = NSMenu()
        if CursorFence.accessibilityTrusted {
            let i = NSMenuItem(title: "Accessibility: granted (hard fence)", action: nil, keyEquivalent: "")
            i.isEnabled = false
            setup.addItem(i)
        } else {
            let i = NSMenuItem(title: "Grant Accessibility for a hard cursor fence…",
                               action: #selector(grantAccessibility), keyEquivalent: "")
            i.target = self
            setup.addItem(i)
        }
        if Focus.isInstalled {
            let i = NSMenuItem(title: "Do Not Disturb shortcuts: installed", action: nil, keyEquivalent: "")
            i.isEnabled = false
            setup.addItem(i)
        } else {
            let i = NSMenuItem(title: "Install Do Not Disturb shortcuts…", action: #selector(installFocus), keyEquivalent: "")
            i.target = self
            setup.addItem(i)
        }
        switch PrivacyDots.externalOverride() {
        case .on:
            let hidden = PrivacyDots.suppressed == true
            let i = NSMenuItem(title: "Privacy dots on external full screen: " + (hidden ? "hidden" : "shown"),
                               action: nil, keyEquivalent: "")
            i.isEnabled = false
            setup.addItem(i)
            let p = NSMenuItem(title: "Privacy Indicator Settings…", action: #selector(openPrivacyIndicators), keyEquivalent: "")
            p.target = self
            setup.addItem(p)
        case .off:
            let i = NSMenuItem(title: "Hide Privacy Dots on External Displays…", action: #selector(explainPrivacyDots), keyEquivalent: "")
            i.target = self
            setup.addItem(i)
        case .unavailable:
            let i = NSMenuItem(title: "Privacy dots: hiding needs macOS 14.4", action: nil, keyEquivalent: "")
            i.isEnabled = false
            setup.addItem(i)
        }
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        setup.addItem(login)
        let si = NSMenuItem(title: "Setup", action: nil, keyEquivalent: "")
        si.submenu = setup
        menu.addItem(si)

        menu.addItem(.separator())
        add(menu, "About Show Mode", #selector(about))
        add(menu, show.engaged ? "Quit (restores settings)" : "Quit", #selector(quit)).keyEquivalent = "q"
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        menu.addItem(i)
        return i
    }

    private func updateIcon() {
        let name: String
        if !show.engaged { name = "theatermasks" }
        else if fencePaused { name = "theatermasks.circle" }
        else { name = "theatermasks.fill" }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Show Mode")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.contentTintColor = show.engaged ? .systemRed : nil
        item.button?.toolTip = show.engaged ? "Show Mode is ON (⌃⌥⌘S to end)" : "Show Mode is off (⌃⌥⌘S to start)"
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    /// Show Mode may have just silenced notifications, so it reports in an alert-free way:
    /// a floating label near the menu bar for a few seconds.
    private func notify(_ text: String) {
        guard let screen = NSScreen.main else { return }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        let size = label.sizeThatFits(NSSize(width: 420, height: 400))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size.width + 32, height: size.height + 24),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        label.frame = NSRect(x: 16, y: 12, width: size.width, height: size.height)
        bg.addSubview(label)
        panel.contentView = bg
        let v = screen.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: v.maxX - panel.frame.width - 12, y: v.maxY - 8))
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { panel.orderOut(nil) }
    }
}
