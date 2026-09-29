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
