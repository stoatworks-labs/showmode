# Show Mode user guide

Show Mode is **a menu-bar app that locks a Mac down for a show**. One click (or **⌃⌥⌘S**)
stops the machine from sleeping, stops the things that slide over the screen when an
operator's hand slips — hot corners, Mission Control, the click-to-show-desktop wallpaper,
notification banners — stops the colour of the picture drifting with the time of day, and
keeps the mouse cursor off the screens the audience is looking at. A second click puts every
setting back exactly as it was.

> **Before you rely on this:** the power, screen-saver, hot-corner, Mission Control, True
> Tone and Night Shift guards were run end to end on a MacBook Pro running macOS 26.4, and
> restoring was checked three ways: ending show mode, killing the app outright and
> relaunching it, and stopping it with SIGTERM. Every setting came back.
>
> **Not yet checked:** the cursor fence has only met a single-display Mac, so it has never
> actually held a cursor back from a second screen; the Do Not Disturb shortcuts have been
> generated and signed but not run; hiding the cursor from a background app relies on a
> private WindowServer call; and pinning the light/dark appearance is best effort. Try it
> on the show machine, with the show screens connected, before a show depends on it.
> **Released at v0.1.0 (beta).**
>
> This codebase was created with AI assistance, directed and reviewed by a human author.

---

## Install

Download the `.dmg` from the [latest release](https://github.com/stoatworks-labs/showmode/releases/latest),
open it and drag **Show Mode** to Applications. It is signed and notarised by Apple and
opens normally. Or with Homebrew:

```bash
brew tap stoatworks-labs/tap
brew trust --tap stoatworks-labs/tap
brew install --cask showmode
```

Show Mode needs macOS 13 or later and runs on Apple silicon and Intel Macs. It lives in
the menu bar as a pair of theatre masks and has no Dock icon.

## Starting and ending a show

Click the masks and choose **Start Show Mode**, or press **⌃⌥⌘S** anywhere. The masks
turn solid red while show mode is on. **End Show Mode** (or ⌃⌥⌘S again) puts everything
back.

If something could not be applied — Do Not Disturb before its shortcuts are installed, a
cancelled password prompt — a short note appears under the menu bar for a few seconds and
stays listed in the menu, marked ⚠︎, until the show ends. It deliberately does not use a
notification: show mode may just have silenced them.

## What it turns off

Every guard can be switched off in **What Show Mode Disables**. A change there applies at
the next start.

| Guard | What it does |
|---|---|
| Prevent display & system sleep | Holds a power assertion, the same way a video player does. It goes away with the app, so a crash cannot leave a Mac that never sleeps. |
| Prevent sleep on lid close | Sets `pmset disablesleep`, so a laptop driving a projector keeps going with its lid shut. **Off by default** because it asks for your password on every start and end. |
| Turn off Low Power Mode | Only if it is on, per power source (battery and mains separately). Asks for your password once. |
| Disable screen saver | Sets the idle time to never. |
| Disable hot corners | Sets all four corners to do nothing, and restarts the Dock so it takes effect. |
| Disable Mission Control, Exposé & gestures | Turns off Mission Control and App Exposé, including their keys, and the swipe and pinch gestures for Mission Control, App Exposé, Show Desktop and Launchpad. Restarts the Dock. |
| Disable click-wallpaper-to-show-desktop | Stops a stray click on the desktop sweeping every window aside. |
| Do Not Disturb | Turns on Do Not Disturb, so no notification banner lands on an output. See [Notifications](#notifications). |
| Disable Night Shift | Turns Night Shift off **and** clears its schedule, so it cannot come back on at sunset mid-show. |
| Disable True Tone | Stops the built-in display re-tinting itself to the room's light. |
| Pin light/dark appearance | If the appearance switches automatically, holds whichever one is showing now. |
| Quit colour-shift apps | Quits f.lux, Shifty and Lunar if they are running, and opens them again afterwards. |
| Fence cursor off show screens | See below. |

Starting show mode restarts the Dock once, which makes the Dock and the menu bar flicker
for a moment. Do it before doors, not during a cue.

## Keeping the cursor off the show screens

Under **Keep cursor off**, tick each screen the audience sees. Screens are remembered by
their make, model and serial number, so the choice survives unplugging them and restarting.
The screen with the menu bar is marked so you can tell the built-in panel apart.

How hard the fence is depends on one permission:

- **With Accessibility granted** (Setup → *Grant Accessibility for a hard cursor fence*):
  every mouse movement that would land on a show screen is caught on its way in and moved to
  the nearest point on a screen you can use. The cursor never gets there.
- **Without it**: Show Mode checks the cursor 120 times a second and moves it back. That is
  fast, but a quick flick can land on a show screen for an instant, so it also **hides the
  cursor while it is near a show screen** — the crossing is never drawn. Turn that off with
  *Hide cursor if it reaches a blocked screen* if you would rather see it.

**⌃⌥⌘F** pauses the fence (and again to resume) when you need to reach a show screen on
purpose — to drag a window onto it, say. The masks change to a circle while it is paused.

The fence stands down on its own rather than trap you: if every screen is ticked, or the
only screen you left unticked is unplugged, it does nothing until that changes.

## Notifications

macOS gives apps no way to switch Do Not Disturb on, so Show Mode uses two tiny shortcuts
that do it for it. Choose **Setup → Install Do Not Disturb shortcuts**. After about half a
minute Shortcuts asks you to add *Show Mode Focus On* and *Show Mode Focus Off*; add both.
From then on show mode runs them itself. Until they are installed, show mode skips Do Not
Disturb and says so.

## Driving it from somewhere else

Show Mode answers a URL scheme, so Companion, a show-control script or a Terminal can drive
it:

```bash
open showmode://on
```

The others are `showmode://off`, `showmode://toggle`, `showmode://fence-on` and
`showmode://fence-off`.

## Putting things back

Before Show Mode changes anything it writes down what was there, in
`~/Library/Application Support/ShowMode/journal.plist`. Ending the show restores exactly
those values — a setting you had already switched off yourself stays off. The same happens
when you quit, when a launcher stops the app, and if the app crashes or the Mac restarts
mid-show: the next launch finds the journal, restores it, and tells you it did.

Launch at Login (in Setup) is worth turning on for a show machine, so a restart mid-show is
followed by a clean restore.

## Running it from source

```bash
git clone https://github.com/stoatworks-labs/showmode
cd showmode
scripts/build-app.sh
```

That builds a universal `dist/Show Mode.app`. `swift build` alone gives a bare executable
for development; `.build/debug/ShowMode --status` prints what it can see without changing
anything.
