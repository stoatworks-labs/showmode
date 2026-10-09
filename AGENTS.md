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
- **The app icon is drawn, not an SF Symbol** — Apple's SF Symbols licence does not allow
  them in app icons. `scripts/make-icon.swift` writes `Resources/AppIcon.icns`.
