# Show Mode

> **AI-assisted project.** This codebase was created with [Claude](https://claude.com/claude-code)
> (Anthropic), directed and reviewed by a human author.

A macOS menu-bar app that locks a presentation or playback Mac down for a show, then puts
every setting back exactly as it was.

**⌃⌥⌘S** starts/ends show mode · **⌃⌥⌘F** pauses the cursor fence (to reach a show screen deliberately)

> **Field proven** — run on real events, not just on the bench. The power, screen-saver,
> hot-corner, Mission Control, True Tone and Night Shift guards and every restore path were
> also run end to end on macOS 26.4, and the cursor fence (with and without Accessibility), the
> display lock, Do Not Disturb and appearance pinning on a real two-screen setup. Still
> unchecked: the display lock with AirPlay, Sidecar or DisplayLink screens. The two guards new
> in v0.4.0, privacy dots and swipe between Spaces, have not yet been run on a show, and the
> guards coming in v0.5.0 (system sounds, background work, interruptions, remote sessions) have
> only been checked on the bench. Full details in the [user guide](docs/USER-GUIDE.md).

![The Show Mode menu](docs/screenshots/menu.png)

<!-- downloads:start -->

## Download

**[v0.4.0](https://github.com/stoatworks-labs/showmode/releases/tag/v0.4.0)** — prebuilt for macOS. Pick your platform:

<details>
<summary><b>macOS</b> — Universal (Apple Silicon + Intel)</summary>

| Build | Download | Size |
| --- | --- | --- |
| Universal (Apple Silicon + Intel) · .dmg disk image | [`showmode-0.4.0-macos-universal.dmg`](https://github.com/stoatworks-labs/showmode/releases/download/v0.4.0/showmode-0.4.0-macos-universal.dmg) | 656 KB |

</details>

All builds, checksums and release notes: [github.com/stoatworks-labs/showmode/releases](https://github.com/stoatworks-labs/showmode/releases).

macOS builds are signed and notarised by Apple, so they open normally — no Gatekeeper warning and no quarantine step.

<!-- downloads:end -->

| Guard | How |
|---|---|
| Display & system idle sleep | IOKit power assertions (die with the process) |
| Lid-close sleep *(off by default)* | `pmset disablesleep 1` — admin prompt |
| Low Power Mode | `pmset <source> powermode/lowpowermode 0`, per power source — admin prompt, only if it is on |
| Screen saver | `com.apple.screensaver idleTime 0` (current host) |
| Hot corners | all four `wvous-*` set to no-op, Dock restarted |
| Mission Control / App Exposé / gestures | `mcx-expose-disabled`, the four Dock gesture keys, Dock restarted |
| Swipe between Spaces | `Trackpad{Three,Four}FingerHorizSwipeGesture` and the Magic Mouse's `MouseTwoFingerHorizSwipeGesture`, only where set to swipe between full-screen apps (2 → 0), then `activateSettings -u` so the trackpad driver rereads them; swipe between pages is left alone |
| Click wallpaper to show desktop | `com.apple.WindowManager EnableStandardClickToShowDesktop` |
| Desktop wallpaper | black on every screen (and any plugged in mid-show); the WallpaperAgent store is copied and put back, so dynamic/aerial wallpapers and every Space return exactly |
| Notifications | Do Not Disturb via two generated Shortcuts (see below) |
| System sounds *(coming in v0.5.0)* | alert volume and "Play user interface sound effects" to 0 through AudioServices (`ssvl`, `uion`), the calls System Settings' Sound pane makes, and `com.apple.sound.beep.feedback` to 0 (an integer: loginwindow plays the pop and reads it as one); only where on, restored after. Output volume, mute and app audio are untouched |
| Other apps' sound *(coming in v0.5.0, off by default, macOS 26+)* | one private global Core Audio process tap (`muteBehavior = .muted`) mutes every app except those ticked under **Allowed to Play**, excluded by bundle ID (`CATapDescription.bundleIDs`) so one opened mid-show is simply heard; their helpers (`com.google.Chrome.helper`) count. Nothing reads the tap: no recording permission, no privacy dot. Measured by recording a loopback output: the mute takes hold of each sound as it starts, and a sound already playing when the show starts carries on until it stops, so the start-of-show note names those apps. It dies with Show Mode, so a crash brings sound back rather than silencing the show |
| Night Shift | CoreBrightness `CBBlueLightClient` — disabled *and* its schedule cleared |
| True Tone | CoreBrightness `CBTrueToneClient` |
| Auto light/dark appearance | SkyLight `SLSSetAppearanceThemeSwitchesAutomatically(false)` pins the showing appearance, the same call System Settings makes (the preference key alone changes nothing live); restored after |
| Colour-shift apps | quits f.lux, Shifty, Lunar; relaunches them after |
| Cursor fence | keeps the cursor off the screens you tick |
| Display arrangement | keeps the chosen (or starting) main display main, and splits any screen that starts mirroring mid-show back to extended |
| Privacy dots | SkyLight `SLSSetSuppressPrivacyIndicatorOnExternalDisplays(true)`, the Privacy Indicators switch; only once the Recovery-only `system-override suppress-sw-camera-indication-on-external-displays=on` is set, and only on full-screen external displays (macOS rule). Restored after |
| Stage Manager *(coming in v0.5.0)* | `com.apple.WindowManager GloballyEnabled` off, WindowManager restarted |
| ⌘Space *(coming in v0.5.0)* | Spotlight's shortcuts (64 ⌘Space, 65 ⌥⌘Space) off in WindowServer through SkyLight `CGSSetSymbolicHotKeyEnabled`, which is not saved, so a restart mid-show brings them back anyway |
| Crash reports *(coming in v0.5.0)* | `com.apple.CrashReporter UseUNC`: "quit unexpectedly" goes to Notification Center, where Do Not Disturb holds it, instead of a window. The report is still written |
| AirPlay Receiver *(coming in v0.5.0)* | `-currentHost com.apple.controlcenter AirplayReceiverEnabled` off, which Control Center applies at once (macOS 26 spells it correctly; the older misspelling `AirplayRecieverEnabled` is written too). Frees TCP 5000/7000 and stops another device taking over the screen |
| Keyboard Setup Assistant *(coming in v0.5.0)* | quit whenever it opens mid-show (a clicker or keypad that presents as a keyboard). Nothing to restore |
| Photo & media analysis *(coming in v0.5.0)* | `photoanalysisd` and `mediaanalysisd` paused (SIGSTOP) by a sweeper, resumed (SIGCONT) at the end or as soon as Show Mode goes away. See [Background work](#background-work) |
| App update checks *(coming in v0.5.0)* | `SUEnableAutomaticChecks` off in each running Sparkle app's own defaults (Sparkle 2 watches the key while it runs); Microsoft AutoUpdate `HowToCheck` set to `Manual` unless the organisation manages it. Restored after |
| Syncthing *(coming in v0.5.0)* | every folder that is syncing paused through Syncthing's local REST API (`PATCH /rest/config/folders/<id>`, key from its `config.xml`); only those are resumed |
| Sync apps *(coming in v0.5.0)* | quits Resilio Sync, Synology Drive, MEGA, Sync.com and Box Drive, and opens them again after. Several sync through File Provider, which may carry on after the app quits |
| Time Machine *(coming in v0.5.0, off by default)* | `tmutil stopbackup` and `tmutil disable` — admin prompt, only if automatic backups are on. Read back after: without Full Disk Access `tmutil` reports success and changes nothing |
| Spotlight indexing *(coming in v0.5.0, off by default)* | Spotlight's importers (`mdworker_shared`, `mdworker`) paused by a root sweeper started from the admin prompt; `mds` and `mds_stores` keep running and answering searches |
| Automatic updates *(coming in v0.5.0, off by default)* | `AutomaticDownload` and `AutomaticallyInstallMacOSUpdates` (`com.apple.SoftwareUpdate`) and the App Store's `AutoUpdate` (`com.apple.commerce`) off — admin prompt; left alone on a managed Mac. Security responses and XProtect data are not touched |
| Remote sessions *(coming in v0.5.0)* | every 5 s: inbound connections on 5900, 3283, 4000 and 7070 and TeamViewer's session process name the session in the menu and the log; the black wallpaper is put back if anything changed it |
| AWDL *(coming in v0.5.0, expert, off by default)* | `ifconfig awdl0 down`, held down by the root sweeper (macOS raises it again on its own). Costs AirDrop, peer-to-peer AirPlay, Sidecar and Universal Control |
| Look in use *(coming in v0.5.0, experimental, off)* | `IOPMAssertionDeclareUserActivity` every four minutes, so the untouched Mac is not taken for idle |
| Game Mode *(coming in v0.5.0, experimental, off)* | Xcode's `gamepolicyctl game-mode set on`, and the previous policy put back. Needs Xcode itself |

## Cursor fence

Tick the show screens under **Keep cursor off**. With Accessibility granted, an event tap
rewrites any mouse move that would land on one to the nearest point on an allowed screen, so the
cursor never gets in. Without it, a 120 Hz poll warps it back, and the cursor is hidden while it
is near a blocked screen so the crossing is never drawn. The menu will not let you block the
last unblocked screen (so a single-display Mac cannot be fenced at all), and blocking the main
display — the menu bar and Dock — asks first. If every screen still ends up blocked, or the only
allowed one is unplugged, the fence stands down rather than trap the cursor.

Screens are remembered by vendor/model/serial, so the choice survives replugging and reboots.

## Display arrangement

The main display is made main by moving it to the origin of the global display space
(`CGConfigureDisplayOrigin`, every display shifted by the same amount, so the arrangement is
kept). A reconfiguration callback, debounced by a second, re-applies it and splits new mirrors
(`CGConfigureDisplayMirrorOfDisplay(…, kCGNullDirectDisplay)`); displays already mirrored at
start are left alone. Four corrections in twenty seconds and it stops. The previous main
display is journalled and restored. Activity goes to `~/Library/Logs/ShowMode.log`.

## Privacy dots

No app can hide the microphone/camera/screen-recording dots. Show Mode reports them instead:
WindowServer draws each dot as a window named `StatusIndicator` (readable without Screen
Recording access), which gives the screens showing one; CoreAudio process objects
(`kAudioProcessPropertyIsRunningInput`, macOS 14.2+) name the app on the microphone, and
CoreMediaIO says whether a camera is running. If neither, it is screen recording. The Recovery
override is read with `/usr/bin/system-override <key>`, which needs no root outside Recovery.
See the [user guide](docs/USER-GUIDE.md#privacy-dots) for the one-time setup.

## Background work

*Coming in v0.5.0.* A show Mac left untouched for hours looks idle, which is when macOS and other
apps start their maintenance. Processes that may only be paused, never switched off, go to a
**sweeper**: a small shell loop that sends SIGSTOP to every process with one of a few exact names
every two seconds (so copies launchd starts mid-show are caught), and SIGCONT to them all when the
show ends. It learns that Show Mode has gone — crash and `kill -9` included — from its end of a
pipe closing, never from a pid, and it gives up after three days regardless. The user-level
sweeper (media analysis) is Show Mode's child. Spotlight's `_spotlight` workers and AWDL need
root, so that sweeper starts from the show's one admin prompt, listens on a FIFO Show Mode holds
open, and has its script passed inline rather than from a file anyone could rewrite. At the end
Show Mode reads back what it paused and asks root to resume anything still paused.

What is deliberately left alone: `mds` and `mds_stores` (stopping them hangs every search),
`trustd`, `mobileassetd`, `softwareupdated`, XProtect and the iCloud daemons, real-time
protection in any antivirus, `launchctl` on Apple services (SIP refuses it, or it does not stick),
and Apple Intelligence (turning it off can delete its models and download them again).

## Pre-show checks

*Coming in v0.5.0.* What no app can safely switch off is listed under **Pre-show Checks**, each
with the one thing to do: a macOS update waiting (someone choosing *Install Tonight* restarts the
Mac overnight), updates or Microsoft AutoUpdate managed by an organisation, Dropbox, Google Drive
and OneDrive running (they can only be paused from their own menus; Dropbox keeps syncing after
it quits), backup apps with schedules (Arq, Carbon Copy Cloner, Backblaze, ChronoSync), security
software that opens its own windows or scans on a schedule (Intego, Sophos, Trend Micro, Norton,
LuLu, BlockBlock, Defender, and IT-managed EDR, which is never touched), an active remote session,
a display blacked out by a remote-access privacy mode, the Mac running hot, running on battery,
and a network on Wi-Fi. The ones that can change mid-show stay at the top of the menu while it
runs.

## Notifications

macOS has no public Focus API. **Setup → Install Do Not Disturb shortcuts** generates and signs
"Show Mode Focus On/Off" (one *Set Focus* action each); Shortcuts asks you to add them once. After
that show mode runs them with `shortcuts run`.

## Restoring

Every change is journalled (`~/Library/Application Support/ShowMode/journal.plist`) *before* it
is made, with the value it replaced, and restore undoes only what show mode changed. Ending show
mode, quitting, SIGTERM/SIGINT/SIGHUP and relaunching after a crash all restore.

Everything that needs root shares one password prompt at the start and one at the end. Each
command runs whatever happened to the one before it. Cancelling the prompt at the start changes
nothing; a command that fails keeps its journal entry, so the end writes the original back. At
the end, anything whose command fails or whose prompt is cancelled stays in the journal, the
menu offers **Finish Restoring**, and the next launch tries again. Syncthing folders that could
not be resumed (Syncthing not running yet at login) are retried the same way.

## Automation

`open showmode://on` · `off` · `toggle` · `fence-on` · `fence-off` · `wallpaper-black` ·
`wallpaper-restore` — e.g. from Companion or a
show-control script. `ShowMode --status` prints what it sees (read-only).

## Build

```bash
scripts/build-app.sh
```

Universal `dist/Show Mode.app`, Developer ID–signed when that identity is in the keychain (a
stable signature keeps the Accessibility grant across rebuilds).
