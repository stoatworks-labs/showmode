# Show Mode user guide

Show Mode is **a menu-bar app that locks a Mac down for a show**. One click (or **⌃⌥⌘S**)
stops the machine from sleeping, stops the things that slide over the screen when an
operator's hand slips — hot corners, Mission Control, the click-to-show-desktop wallpaper,
notification banners — stops the colour of the picture drifting with the time of day, and
keeps the mouse cursor off the screens the audience is looking at. A second click puts every
setting back exactly as it was.

> **Field proven:** Show Mode has been run on real events, not just on the bench.
>
> **Checked on the bench:** the power, screen-saver, hot-corner, Mission Control, True
> Tone and Night Shift guards were run end to end on a MacBook Pro running macOS 26.4, and
> restoring was checked three ways: ending show mode, killing the app outright and
> relaunching it, and stopping it with SIGTERM. Every setting came back. The wallpaper
> blackout was checked the same three ways on macOS 26.4.1, but only on its own (not as
> part of a full show-mode start) and only on one display.
>
> **Checked on a second screen (v0.3.0):** with a real extended display attached (a Roland
> USB video output) and a virtual one, the cursor fence held a gliding pointer at the edge
> with Accessibility granted and pulled back a pointer warped onto the show screen; pausing
> and resuming it worked. The display lock split a mirrored display back to extended, made
> the locked display main again after something else took over, gave up after repeated
> reversals instead of fighting, and put the original main display back at the end of the
> show and after the app was killed mid-show.
>
> **Do Not Disturb (checked 2026-09-29, macOS 26.4.1):** both shortcuts ran and switched Do
> Not Disturb on and off, and show mode turned it on at start, off at the end, and off again
> on the next launch after being killed mid-show.
>
> **Checked 2026-09-29 (v0.3.1):** the fence without Accessibility, which pulls the pointer
> back within one mouse step and hides it near the show screen, and hiding the cursor from a
> background app; the main-display warning, both its buttons, and the rule that the last
> screen cannot be blocked; and pinning the light/dark appearance, which System Settings
> showed switching from Auto to the showing appearance and back, including after a crash.
>
> **Privacy dots (coming in v0.4.0):** finding a dot and the screen it is on, naming the app using the
> microphone, telling screen recording apart, and reading whether the Recovery step has been
> done were all checked on macOS 26.4.1. **Not checked:** actually hiding the dots, which needs
> the Recovery step on a Mac with an external display, and noticing the camera in use.
>
> **Swipe between Spaces (coming in v0.4.0, checked 2026-10-06 on macOS 26.4.1):** on a
> MacBook Pro's built-in trackpad, three- and four-finger sideways swipes stopped switching
> desktops during the show. The swipe settings came back when the show ended and on the next
> launch after the app was killed mid-show, and a three-finger swipe set to *Swipe between
> pages* was left as it was. **Not checked:** a Magic Trackpad or Magic Mouse in hand (their
> settings are switched off and back the same way).
>
> **Not yet checked:** the display lock with AirPlay, Sidecar or DisplayLink screens, which
> may not answer the mirroring call the way a cabled display does; and a real sunset under a
> pinned appearance (the pin itself was checked, but not an evening switch it holds off). If
> your show uses one of those screens, try it with them connected before the show.
> **Released at v0.3.1 (field proven).**
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
| Disable swipe between Spaces & full-screen apps | *Coming in v0.4.0.* Stops a sideways three- or four-finger swipe on the trackpad (two fingers on a Magic Mouse) sliding the show off to another desktop or full-screen app. A three-finger swipe set to *Swipe between pages* is left alone, since it only goes back and forward inside an app. Your swipe settings come back when the show ends. |
| Disable click-wallpaper-to-show-desktop | Stops a stray click on the desktop sweeping every window aside. |
| Black out desktop wallpaper | Paints the wallpaper black on every screen, including one plugged in mid-show, so an extended desktop never shows your wallpaper on the projector. The original comes back exactly, dynamic and aerial wallpapers and every Space included. |
| Do Not Disturb | Turns on Do Not Disturb, so no notification banner lands on an output. See [Notifications](#notifications). |
| Disable Night Shift | Turns Night Shift off **and** clears its schedule, so it cannot come back on at sunset mid-show. |
| Disable True Tone | Stops the built-in display re-tinting itself to the room's light. |
| Pin light/dark appearance | If the appearance is set to Auto, switches it to whichever of Light or Dark is showing now, so it cannot flip at sunset mid-show. Auto comes back when the show ends. |
| Quit colour-shift apps | Quits f.lux, Shifty and Lunar if they are running, and opens them again afterwards. |
| Fence cursor off show screens | See [Keeping the cursor off the show screens](#keeping-the-cursor-off-the-show-screens). |
| Lock main display & keep new screens extended | See [Keeping the display arrangement](#keeping-the-display-arrangement). |
| Hide privacy dots on full-screen external displays | *Coming in v0.4.0.* Needs a one-time step in Recovery first. See [Privacy dots](#privacy-dots). |

Starting show mode restarts the Dock once, which makes the Dock and the menu bar flicker
for a moment. Do it before doors, not during a cue.

## Keeping the cursor off the show screens

Under **Keep cursor off**, tick each screen the audience sees. Screens are remembered by
their make, model and serial number, so the choice survives unplugging them and restarting.
The screen with the menu bar is marked so you can tell the built-in panel apart.

The cursor always keeps at least one screen. The last unticked screen cannot be ticked, so
on a Mac with only one screen there is nothing to tick. Ticking the main display — the one
with the menu bar, Show Mode's own menu and the Dock — asks first, because during the show
you could not reach any of those with the mouse. Usually the better fix is to choose the
operator screen under **Main Display**, so the menu bar stays there for the show.

How hard the fence is depends on one permission:

- **With Accessibility granted** (Setup → *Grant Accessibility for a hard cursor fence*):
  every mouse movement that would land on a show screen is caught on its way in and moved to
  the nearest point on a screen you can use. In testing, a pointer glided at a show screen in
  10-pixel steps stopped dead at the edge; in 2 of 12 runs one sample caught it a few pixels
  over for less than one step (under 10 ms) before it was pulled back.
- **Without it**: Show Mode checks the cursor 120 times a second and moves it back. In
  testing, one movement of the mouse — about 10 pixels at a normal pace, 60 on a fast flick —
  could land on the show screen for up to 8 ms before being pulled back. So it also **hides
  the cursor within 48 pixels of a show screen**: an ordinary approach is never drawn on the
  other side, and only a flick that starts further away than that can show for an instant.
  Turn the hiding off with *Hide cursor if it reaches a blocked screen* if you would rather
  see it. Granting Accessibility is the better answer on a show machine.

**⌃⌥⌘F** pauses the fence (and again to resume) when you need to reach a show screen on
purpose — to drag a window onto it, say. The masks change to a circle while it is paused.

The fence also stands down on its own rather than trap you: if every screen is ticked, or the
only screen you left unticked is unplugged, it does nothing until that changes.

## Keeping the display arrangement

With **Lock main display & keep new screens extended** on (it is by default), show mode holds
the display arrangement the show started with.

**The main display stays put.** The main display is the one with the menu bar and the Dock,
and it is where new windows and many apps' dialogs appear. Choose it under **Main Display**,
or leave that on *Whichever is main at start*. If anything makes a different screen main
during the show — a display reconnecting, a projector macOS remembers from another venue —
show mode moves it back within about a second. The arrangement itself is kept: the screens
stay where they are relative to each other, only which one carries the menu bar changes back.
If the display you chose is not connected at start, show mode says so and makes it main the
moment it appears.

**New mirrors become extended.** Whatever is mirrored when the show starts is taken as
deliberate — a confidence monitor showing the output, say — and left alone. Any screen that
starts mirroring during the show, whether a newly plugged-in projector that macOS decides to
mirror or a stray ⌘F1, is split back out to an extended display about a second later.

Changing which display is main makes every screen blink for a moment, the way it does in
System Settings. Show mode only does it when something else has already moved the main
display, but choose the main display before doors rather than mid-cue. If something keeps
undoing the arrangement — four corrections inside twenty seconds — show mode stops fighting
it, says so in its menu, and leaves the screens alone for the rest of the show.

When the show ends, the display that was main before it becomes main again. Screens that
were split out of a mirror stay extended: the mirror was macOS's guess, not yours.

Choosing a main display that is also fenced off puts the menu bar out of the cursor's reach,
so show mode warns you at start. ⌃⌥⌘F pauses the fence.

## Notifications

macOS gives apps no way to switch Do Not Disturb on, so Show Mode uses two tiny shortcuts
that do it for it. Choose **Setup → Install Do Not Disturb shortcuts**. After about half a
minute Shortcuts asks you to add *Show Mode Focus On* and *Show Mode Focus Off*; add both.
From then on show mode runs them itself. Until they are installed, show mode skips Do Not
Disturb and says so.

The shortcuts switch the built-in **Do Not Disturb** Focus, not any custom Focus you have
made. Whatever that Focus allows through — people or apps you have allowed in System Settings
→ Focus → Do Not Disturb — still gets through, so check its allow list on the show machine.

## Privacy dots

> **Coming in v0.4.0.** v0.3.1, the current release, does not have this guard yet.

macOS draws a coloured dot while an app uses the microphone (orange), the camera (green) or
records the screen (purple). No app can turn these off. Apple's own setting (macOS 14.4 or
later) leaves the microphone and camera dots off an **external display showing a full-screen
app**, and it has limits:

- the **main display always keeps its dots**, so make the operator's screen the main display
  (**Main Display** in the menu);
- the **purple screen-recording dot cannot be hidden** anywhere;
- it needs a **one-time step in Recovery**, which no app can do for you.

**The one-time step.** Start up in Recovery (on Apple silicon, shut down, then hold the power
button until *Loading startup options* appears; on Intel, hold ⌘R at startup), choose
**Utilities → Terminal** and run:

```bash
system-override suppress-sw-camera-indication-on-external-displays=on
```

Then restart. **Setup** in Show Mode's menu shows whether this has been done. After that, with
**Hide privacy dots on full-screen external displays** ticked, show mode turns the dots off on
external displays at the start of each show and back on at the end (the same switch as
**Privacy Indicators** under System Settings → Privacy & Security → Microphone). To undo the
step, run the same command with `=off` in Recovery.

Whether or not you have done it, show mode tells you at the start of a show if a dot is
showing, on which screen and why: the app using the microphone, the camera, or (when it is
neither) screen recording. The same line stays in the menu, marked ⚠︎, while the dot shows.

## Driving it from somewhere else

Show Mode answers a URL scheme, so Companion, a show-control script or a Terminal can drive
it:

```bash
open showmode://on
```

The others are `showmode://off`, `showmode://toggle`, `showmode://fence-on`,
`showmode://fence-off`, `showmode://wallpaper-black` and `showmode://wallpaper-restore`.

## Blacking out the wallpaper on its own

**Black Out Wallpaper** in the menu (or `showmode://wallpaper-black`) blacks out every
screen without starting show mode — for a rehearsal, or a desktop share. **Restore
Wallpaper** puts it back and leaves everything else alone. Ending show mode, quitting, or a
relaunch after a crash also restores it.

## What it did

Show mode keeps a plain log of what it changes at `~/Library/Logs/ShowMode.log` — the fence
coming on and in which mode, and every correction the display lock makes. Console.app opens
it.

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
