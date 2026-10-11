# AGENTS.md — Show Mode

Invariants for anyone (human or agent) changing this repo.

- **Journal before you change.** Every guard records the value it replaces in `Journal`
  *before* writing the new one (`PrefKey.override`, the `Journal.shared[...]` writes in
  `Power.swift`, `ColourShift.swift`, `Focus.swift`). Restore must only undo what show mode
  changed, and a crash mid-engage must still be recoverable on the next launch. A new guard
  that writes first and journals second is a bug even if it works on your machine.
- **Never trap the cursor.** `CursorFence.recompute()` stands the fence down when no allowed
  display is connected. Keep that property for any change to the fence.
- **Private API is looked up at runtime** (CoreBrightness, `CGSSetConnectionProperty`) so a
  macOS that renames it degrades to "unavailable" rather than crashing. Keep it that way.
- **Generated, do not edit:** `Sources/ShowMode/StoatworksAbout*.swift` come from
  `stoatworks-backend/scripts/sync-about.py`; `.github/FUNDING.yml` and
  `.github/ISSUE_TEMPLATE/` from the backend's sync scripts; the README block between the
  `downloads` markers from `release/gen-downloads.py`.
- **One version:** `Sources/ShowMode/Version.swift`. `scripts/build-app.sh` and sync-about
  both read it.
- **Verify on a real machine.** What is and is not verified lives in `docs/USER-GUIDE.md`'s
  status block — update it when something new is actually run, never because it compiles.
- **Display lock:** `DisplayLayout` registers and removes ONE C callback constant — removal
  matches on the function pointer, and two identical closure literals are two pointers. Keep
  its fight limit: a layout something else keeps reverting must be let go, not looped on.
- **Testing multi-display without a rig:** a `CGVirtualDisplay` (private, CoreGraphics) makes
  a real second display in-process. A helper that inspects display state must run a run loop
  or be a fresh process each time — CoreGraphics caches display state per process and only
  refreshes it from the run loop.
- **Appearance goes through SkyLight** (`SLSSetAppearanceThemeSwitchesAutomatically`). Writing
  `AppleInterfaceStyleSwitchesAutomatically` changes nothing live — System Settings kept
  showing Auto — so never go back to the preference-key approach.
- **Trackpad and mouse gestures are read by the driver, not the Dock.** Writing
  `TrackpadThreeFingerHorizSwipeGesture` and friends changes nothing live — the driver's
  `HIDEventServiceProperties` (visible in `ioreg -l`) keep the old value until
  `activateSettings -u` pushes the preferences to the HID event system. Check `ioreg`, not
  `defaults`, when testing a gesture guard.
- **System sounds go through AudioServices**, as System Settings' Sound pane does (read from
  its disassembly on macOS 26.4.1): `AudioServicesSetProperty` with `ssvl` (alert volume, a
  raw Float32; the slider shows log(v) + 1) and `uion` (interface sound effects), then the
  pane's distributed notifications. The `com.apple.sound.*` preference keys were never tried as
  a way in. Volume feedback is the exception: it is only a preference key, and loginwindow
  (BezelServices) plays the pop. It reads `com.apple.sound.beep.feedback` as a number, so a
  boolean `true` plays nothing. Write the SInt32 the pane writes.
- **Testing sound guards without ears:** watch CoreAudio's per-process
  `kAudioProcessPropertyIsRunningOutput` while triggering the sound. A sound marked with
  `kAudioServicesPropertyIsUISound` and the volume-key pop start no output when switched off.
  The alert beep is different: systemsoundserverd runs the output even at alert volume 0, so
  this cannot tell a silent beep from an audible one. A posted Shift+volume key inverts the
  feedback setting, which shows whether loginwindow saw a change.
- **Testing without Accessibility:** copy the built app, give it another bundle id, remove
  its URL types and ad-hoc sign it. It has no TCC grant, so the fence runs its fallback, and
  your own Security settings stay untouched. Drive it with a posted ⌃⌥⌘S.
- **One admin prompt, every command run.** `Shell.runAsAdmin` runs each command whatever the
  one before did and reports failures per `AdminStep`. A cancelled engage prompt puts each
  step's journal entries back to their state before the show (a leftover from an unfinished
  restore survives); a step that fails keeps them, since some of its commands may have run. At
  restore a failed step keeps its entries, so **Finish Restoring** and the next launch retry —
  a cancelled restore must never clear the journal. Engage adds to a leftover entry, never
  overwrites it. Restore commands must be safe to run twice (`defaults delete` only if the key is
  there). Read back anything that can report success without taking effect (`tmutil disable`
  without Full Disk Access), and keep the entry when in doubt: undoing a no-op is harmless.
- **Pausing processes (`Sweeper`).** Only the exact names in `Paused`, never a pattern. Never
  mds, mds_stores, logd, WindowServer, configd, opendirectoryd, fseventsd, trustd or the iCloud
  daemons: they panic the Mac, lose file events for every app, or hang every caller. A sweeper
  learns Show Mode has gone from its pipe or FIFO closing, never from a pid (pids get reused),
  so keep both ends close-on-exec: any other child holding one would keep things paused after
  a crash. Show Mode ignores SIGTERM, SIGINT and SIGHUP (AppDelegate), anything it starts
  inherits that, and bash cannot trap or reset a signal ignored at its start: the sweeper stops
  its child with SIGKILL. The old SIGTERM version left Spotlight paused after End. The root
  sweeper's script is passed inline, never run from a file the user could rewrite.
- **Testing the root sweeper without a password:** `Shell.runAsAdmin(…, privileged: false)`
  runs the same batch as the user. Ignore SIGTERM/SIGINT/SIGHUP in the harness as AppDelegate
  does, or it passes where the app fails.
- **AirPlay Receiver on macOS 26 is `AirplayReceiverEnabled`**, spelt correctly (`-currentHost
  com.apple.controlcenter`), found by diffing preferences around the System Settings switch.
  ControlCenter applies it at once: check the TCP 7000 listener, not the key. The misspelling
  CIS documents (`AirplayRecieverEnabled`) changes nothing on 26, even after a ControlCenter
  restart; the guard writes both for older macOS.
- **Dead ends on macOS 26.4.1:** `com.apple.locationd` cannot be written even as root (`Could
  not write domain`), so Location Services cannot be switched off. Keyboard Setup Assistant
  quits at once when opened by hand, so its guard needs a real unrecognised keyboard to test.
  When a documented key does nothing, diff the preferences around the System Settings switch
  before giving up.
- **The app icon is drawn, not an SF Symbol** — Apple's SF Symbols licence does not allow
  them in app icons. `scripts/make-icon.swift` writes `Resources/AppIcon.icns`.
