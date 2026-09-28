# Show Mode

A macOS menu-bar app that locks a presentation/playback Mac down for a show, then puts every
setting back exactly as it was.

**⌃⌥⌘S** starts/ends show mode · **⌃⌥⌘F** pauses the cursor fence (to reach a show screen deliberately)

| Guard | How |
|---|---|
| Display & system idle sleep | IOKit power assertions (die with the process) |
| Lid-close sleep *(off by default)* | `pmset disablesleep 1` — admin prompt |
| Low Power Mode | `pmset <source> powermode/lowpowermode 0`, per power source — admin prompt, only if it is on |
| Screen saver | `com.apple.screensaver idleTime 0` (current host) |
| Hot corners | all four `wvous-*` set to no-op, Dock restarted |
| Mission Control / App Exposé / gestures | `mcx-expose-disabled`, the four Dock gesture keys, Dock restarted |
| Click wallpaper to show desktop | `com.apple.WindowManager EnableStandardClickToShowDesktop` |
| Notifications | Do Not Disturb via two generated Shortcuts (see below) |
| Night Shift | CoreBrightness `CBBlueLightClient` — disabled *and* its schedule cleared |
| True Tone | CoreBrightness `CBTrueToneClient` |
| Auto light/dark appearance | pins the current appearance (best effort) |
| Colour-shift apps | quits f.lux, Shifty, Lunar; relaunches them after |
| Cursor fence | keeps the cursor off the screens you tick |

## Cursor fence

Tick the show screens under **Keep cursor off**. With Accessibility granted, an event tap
rewrites any mouse move that would land on one to the nearest point on an allowed screen, so the
cursor never gets in. Without it, a 120 Hz poll warps it back, and the cursor is hidden while it
is near a blocked screen so the crossing is never drawn. If every screen is blocked, or the only
allowed one is unplugged, the fence stands down rather than trap the cursor.

Screens are remembered by vendor/model/serial, so the choice survives replugging and reboots.

## Notifications

macOS has no public Focus API. **Setup → Install Do Not Disturb shortcuts** generates and signs
"Show Mode Focus On/Off" (one *Set Focus* action each); Shortcuts asks you to add them once. After
that show mode runs them with `shortcuts run`.

## Restoring

Every change is journalled (`~/Library/Application Support/ShowMode/journal.plist`) *before* it
is made, with the value it replaced, and restore undoes only what show mode changed. Ending show
mode, quitting, SIGTERM/SIGINT/SIGHUP and relaunching after a crash all restore.

## Automation

`open showmode://on` · `off` · `toggle` · `fence-on` · `fence-off` — e.g. from Companion or a
show-control script. `ShowMode --status` prints what it sees (read-only).

## Build

```bash
scripts/build-app.sh
```

Universal `dist/Show Mode.app`, Developer ID–signed when that identity is in the keychain (a
stable signature keeps the Accessibility grant across rebuilds).
