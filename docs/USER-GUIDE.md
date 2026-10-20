# Show Mode user guide

Show Mode is a menu-bar app that locks a Mac down for a show, then puts every setting back how
you had it. One click (or **⌃⌥⌘S**) stops the machine sleeping, stops the things that slide over
the screen when an operator's hand slips (hot corners, Mission Control, the click-to-show-desktop
wallpaper, notification banners), stops the colour of the picture drifting with the time of day,
and keeps the mouse cursor off the screens the audience is looking at.

> **Field proven:** Show Mode has been used on real events, not just on the bench.
>
> **Checked on the bench:** I ran the power, screen saver, hot corner, Mission Control, True
> Tone and Night Shift guards end to end on a MacBook Pro running macOS 26.4, and checked
> restoring three ways: ending show mode, killing the app outright and relaunching it, and
> stopping it with SIGTERM. Every setting came back. The wallpaper blackout was checked the
> same three ways on macOS 26.4.1, but only on its own (not as part of a full show-mode start)
> and only on one display.
>
> **Checked on a second screen (v0.3.0):** with a real extended display attached (a Roland
> USB video output) and a virtual one, the cursor fence held a gliding pointer at the edge
> with Accessibility granted and pulled back a pointer warped onto the show screen, and pausing
> and resuming it worked. The display lock split a mirrored display back to extended, made
> the locked display main again after something else took over, gave up after repeated
> reversals instead of fighting, and put the original main display back at the end of the
> show and after the app was killed mid-show.
>
> **Do Not Disturb (checked 2026-09-29, macOS 26.4.1):** both shortcuts ran and switched Do
> Not Disturb on and off, and show mode turned it on at the start, off at the end, and off
> again on the next launch after being killed mid-show.
>
> **Checked 2026-09-29 (v0.3.1):** the fence without Accessibility, which pulls the pointer
> back within one mouse step and hides it near the show screen, and hiding the cursor from a
> background app; the main-display warning, both its buttons, and the rule that the last
> screen can't be blocked; and pinning the light/dark appearance, which System Settings
> showed switching from Auto to the showing appearance and back, including after a crash.
>
> **Privacy dots (v0.4.0):** finding a dot and the screen it's on, naming the app using the
> microphone, telling screen recording apart, and reading whether the Recovery step has been
> done were all checked on macOS 26.4.1. **Not checked:** actually hiding the dots, which needs
> the Recovery step on a Mac with an external display, and noticing the camera in use.
>
> **Swipe between Spaces (v0.4.0, checked 2026-10-06 on macOS 26.4.1):** on a
> MacBook Pro's built-in trackpad, three- and four-finger sideways swipes stopped switching
> desktops during the show. The swipe settings came back when the show ended and on the next
> launch after the app was killed mid-show, and a three-finger swipe set to *Swipe between
> pages* was left as it was. **Not checked:** a Magic Trackpad or Magic Mouse in hand (their
> settings are switched off and back the same way).
>
> **System sounds (v0.5.0, checked 2026-10-09 on macOS 26.4.1):** with the alert
> volume at half and interface sound effects and volume feedback on, starting a show turned all
> three off, and macOS's own readings agreed. An interface sound effect and the volume-key pop
> then sent nothing to the audio output. Both played again after the show ended, on the next
> launch after the app was killed mid-show, and after it was stopped with SIGTERM, and the alert
> volume came back to its exact value. A sound that was already off was left alone. Output
> volume and mute weren't touched. **Not checked by ear:** the alert beep itself. macOS still
> runs a silent beep through the output at alert volume 0, so the check there is that show mode
> leaves the same setting as dragging the slider to zero.
>
> **Background work, interruptions and remote sessions (v0.5.0, checked 2026-10-11
> on macOS 26.4.1):** on a MacBook Pro, photo and media analysis were paused, and with the
> password so were Spotlight's indexing workers (the system's own and new ones started mid-show)
> and AWDL. All of them were running again at the end of the show. After the app was killed
> outright mid-show, the pause undid itself within five seconds and the relaunch put the rest
> back. Automatic macOS and App Store updates went off at the start and back on at the end, and
> on the next launch after a crash. Cancelling the password prompt at the start changed nothing;
> cancelling it at the end left only the update settings, which the next launch put back.
> ⌘Space opened nothing during the show and Spotlight again after. A test app that crashed
> mid-show opened no "quit unexpectedly" window, and its report was still saved. AirPlay
> Receiver stopped listening at the start and was back at the end and after a crash. Muting other
> apps was checked by ear and then by recording what reached a loopback output with test tones:
> a sound started during the show by an app not allowed to play never reached the output, nor did
> one aimed straight at that output by its own app; an allowed app opened mid-show was heard
> alongside it; and when Show Mode was killed the muted sound came back at once. A sound already
> playing when the show started carried on until it stopped, as the guide now says. No permission
> prompt and no privacy dot appeared (built-in display only). Stage Manager
> went off and came back. A wallpaper another app set mid-show was black again within seven
> seconds. A test connection on port 5900 showed as a remote session, and its end was logged.
> Game Mode was forced on and went back to automatic, after a crash too. Update checks went off
> and came back for a running Sparkle app and for Microsoft AutoUpdate. The pre-show checks found
> a waiting macOS update, OneDrive, battery power and Wi-Fi. **Not checked:** Time Machine (it
> was off on that Mac); whether Spotlight catches up without re-indexing, and how much any of
> this saves on a real show; real Syncthing (only a stand-in for its interface), the five sync
> apps (TextEdit stood in for the list), a real remote session, TeamViewer, and the
> blacked-out-display warning; whether a running app takes the update-check change without a
> relaunch; Keyboard Setup Assistant, which needs a device macOS doesn't recognise; and what the
> experimental user-activity heartbeat changes.
>
> **Fans (not released yet):** checked without the password on a MacBook Pro (M4 Max,
> macOS 26.4.1): reading both fans' speeds and limits, the helper refusing to change anything
> when it isn't root, and the copy check passing a good copy and refusing one with a changed
> byte of code, an edited Info.plist or another developer's signature. **Not checked:**
> everything that needs the password, which is everything that actually moves a fan.
>
> **Not yet checked:** the display lock with AirPlay, Sidecar or DisplayLink screens, which
> may not answer the mirroring call the way a cabled display does; and a real sunset under a
> pinned appearance (the pin itself was checked, but not an evening switch it holds off). If
> your show uses one of those screens, try it with them connected before the show.
> **Released at v0.5.0.** v0.3.1 is field proven; the guards new in v0.4.0 (privacy dots,
> swipe between Spaces) and v0.5.0 (everything marked v0.5.0 above) haven't been run on a
> show yet. v0.5.0 also draws the menu-bar masks in the menu bar's own colour, white over the
> blacked-out wallpaper, instead of red; a capture of the menu bar during a show (2026-10-11,
> macOS 26.4.1) showed them solid white on the black bar.
>
> This codebase was created with AI assistance, directed and reviewed by a human author.

---

## Install

Download the `.dmg` from the [latest release](https://github.com/stoatworks-labs/showmode/releases/latest),
open it and drag **Show Mode** to Applications. It's signed and notarised by Apple, so it
opens normally. Or use Homebrew:

```bash
brew tap stoatworks-labs/tap
brew trust --tap stoatworks-labs/tap
brew install --cask showmode
```

Show Mode needs macOS 13 or later and runs on Apple silicon and Intel Macs. It lives in
the menu bar as a pair of theatre masks and doesn't have a Dock icon.

## Starting and ending a show

Click the masks and choose **Start Show Mode**, or press **⌃⌥⌘S** anywhere. The masks
turn solid while show mode is on, drawn in the menu bar's own colour, so they show up white
over the blacked-out wallpaper. **End Show Mode** (or ⌃⌥⌘S again) puts everything
back.

If something couldn't be applied (Do Not Disturb before its shortcuts are installed, say, or
a cancelled password prompt), a short note appears under the menu bar for a few seconds and
stays listed in the menu, marked ⚠︎, until the show ends. It doesn't use a notification for
this, since show mode may just have silenced them.

## What it turns off

You can switch any guard off in **What Show Mode Disables**. A change there takes effect at
the next start.

| Guard | What it does |
|---|---|
| Prevent display & system sleep | Holds a power assertion, the same way a video player does. It goes away with the app, so a crash cannot leave a Mac that never sleeps. |
| Prevent sleep on lid close | Sets `pmset disablesleep`, so a laptop driving a projector keeps going with its lid shut. **Off by default** because it asks for your password on every start and end. |
| Turn off Low Power Mode | Only if it is on, per power source (battery and mains separately). Asks for your password once. |
| Disable screen saver | Sets the idle time to never. |
| Run the fans at full speed (admin) | **Off by default.** Every fan at its top speed for the whole show. See [Fans](#fans). |
| Keep the fans at their quietest (admin) | **Off by default.** Every fan at its slowest, for a room quiet enough to hear them. See [Fans](#fans). |
| Disable hot corners | Sets all four corners to do nothing, and restarts the Dock so it takes effect. |
| Disable Mission Control, Exposé & gestures | Turns off Mission Control and App Exposé, including their keys, and the swipe and pinch gestures for Mission Control, App Exposé, Show Desktop and Launchpad. Restarts the Dock. |
| Disable swipe between Spaces & full-screen apps | Stops a sideways three- or four-finger swipe on the trackpad (two fingers on a Magic Mouse) sliding the show off to another desktop or full-screen app. A three-finger swipe set to *Swipe between pages* is left alone, since it only goes back and forward inside an app. Your swipe settings come back when the show ends. |
| Disable click-wallpaper-to-show-desktop | Stops a stray click on the desktop sweeping every window aside. |
| Black out desktop wallpaper | Paints the wallpaper black on every screen, including one plugged in mid-show, so an extended desktop never shows your wallpaper on the projector. The original comes back exactly, dynamic and aerial wallpapers and every Space included. |
| Do Not Disturb | Turns on Do Not Disturb, so no notification banner lands on an output. See [Notifications](#notifications). |
| Disable system sounds (alerts & UI effects) | Silences the alert beep, interface sound effects such as emptying the Trash or taking a screenshot, and the pop a volume key plays, so none of them goes out through the show's audio. It does not mute or turn down the Mac's output: sound from apps, the show included, plays as normal. Your alert volume and sound settings come back when the show ends. |
| Mute apps not allowed to play | **Off by default.** See [Keeping other apps off the PA](#keeping-other-apps-off-the-pa). |
| Disable Night Shift | Turns Night Shift off **and** clears its schedule, so it cannot come back on at sunset mid-show. |
| Disable True Tone | Stops the built-in display re-tinting itself to the room's light. |
| Pin light/dark appearance | If the appearance is set to Auto, switches it to whichever of Light or Dark is showing now, so it cannot flip at sunset mid-show. Auto comes back when the show ends. |
| Quit colour-shift apps | Quits f.lux, Shifty and Lunar if they are running, and opens them again afterwards. |
| Fence cursor off show screens | See [Keeping the cursor off the show screens](#keeping-the-cursor-off-the-show-screens). |
| Lock main display & keep new screens extended | See [Keeping the display arrangement](#keeping-the-display-arrangement). |
| Hide privacy dots on full-screen external displays | Needs a one-time step in Recovery first. See [Privacy dots](#privacy-dots). |
| Turn off Stage Manager | Stops Stage Manager sliding the show window into a strip at the side when another window is clicked. Restarts WindowManager. |
| Disable ⌘Space (Spotlight search) | Stops ⌘Space and ⌥⌘Space opening Spotlight over the show. |
| Send crash reports to Notification Center | When an app crashes, macOS opens a "quit unexpectedly" window over everything. This sends it to Notification Center instead, where Do Not Disturb holds it. The crash report is still saved. |
| Turn off AirPlay Receiver | Stops a phone or Mac signed in to the same Apple ID putting its screen on the show Mac, and frees the network ports AirPlay holds (5000 and 7000), which some show tools want. It comes back on when the show ends if it was on. |
| Close Keyboard Setup Assistant | Plugging in a clicker, a keypad or some MIDI and KVM devices can open Keyboard Setup Assistant on the main display. Show mode closes it as soon as it opens. Plug every device in before doors anyway: macOS assumes a standard keyboard when the assistant is closed unanswered. |
| Pause photo & media analysis | See [Background work](#background-work). |
| Turn off app update checks (Sparkle, Microsoft) | Stops the apps you have open checking for updates and opening "a new version is available" windows during the show. |
| Pause Syncthing | Pauses every Syncthing folder that is syncing, and resumes only those. |
| Quit sync apps (Resilio, Synology, MEGA, Sync.com, Box) | Quits them if they are running and opens them again afterwards. None of them can be paused from outside, and some keep syncing through macOS after they quit, so treat it as a best effort. **Untick it if your show media lives in one of their folders.** |
| Pause Time Machine (admin) | **Off by default.** Stops a backup in progress and turns automatic backups off for the show. Needs Full Disk Access as well as your password: see [Background work](#background-work). |
| Pause Spotlight indexing (admin) | **Off by default.** See [Background work](#background-work). |
| Turn off automatic macOS & App Store updates (admin) | **Off by default.** An App Store update quits the app it is updating, and a downloaded macOS update can install itself overnight. Left alone on a Mac whose updates your organisation manages. |
| Watch for remote sessions & keep the output black | See [Remote access](#remote-access). |
| Hold AWDL down: AirDrop, AirPlay, Sidecar (admin) | **Expert, off by default.** AWDL is the Wi-Fi link behind AirDrop and AirPlay; it pulls the Wi-Fi radio off your network's channel, which causes regular spikes of 100–200 ms on a show network that runs over Wi-Fi. Holding it down for the show costs AirDrop, AirPlay from a nearby device, Sidecar and Universal Control. A cable is the real fix. |
| Keep the Mac looking in use | **Experimental, off by default.** Tells macOS every four minutes that someone is using the Mac, so an untouched show Mac is not taken for idle, which is when macOS starts its own maintenance. Not yet measured. |
| Force Game Mode (needs Xcode) | **Experimental, off by default.** Game Mode gives the full-screen app priority and turns down background work. It normally only comes on for games; this forces it on, with Apple's own tool from Xcode. Apple silicon, macOS 14 or later. |

Starting show mode restarts the Dock once, so the Dock and the menu bar flicker for a
moment. Do it before doors rather than during a cue.

## Keeping the cursor off the show screens

Under **Keep cursor off**, tick each screen the audience sees. Screens are remembered by
their make, model and serial number, so your choice survives unplugging them and restarting.
The screen with the menu bar is marked so you can tell the built-in panel apart.

The cursor always keeps at least one screen. You can't tick the last unticked screen, so
on a Mac with only one screen there's nothing to tick. Ticking the main display (the one
with the menu bar, Show Mode's own menu and the Dock) asks first, because during the show
you couldn't reach any of those with the mouse. Usually the better fix is to choose the
operator screen under **Main Display**, so the menu bar stays there for the show.

How hard the fence is depends on one permission:

- **With Accessibility granted** (Setup → *Grant Accessibility for a hard cursor fence*):
  every mouse movement that would land on a show screen is caught on its way in and moved to
  the nearest point on a screen you can use. In testing, a pointer glided at a show screen in
  10-pixel steps stopped dead at the edge; in 2 of 12 runs one sample caught it a few pixels
  over for less than one step (under 10 ms) before it was pulled back.
- **Without it**, Show Mode checks the cursor 120 times a second and moves it back. In
  testing, one movement of the mouse (about 10 pixels at a normal pace, 60 on a fast flick)
  could land on the show screen for up to 8 ms before being pulled back. So it also **hides
  the cursor within 48 pixels of a show screen**: an ordinary approach never gets drawn on the
  other side, and only a flick that starts further away than that can show for an instant.
  Turn the hiding off with *Hide cursor if it reaches a blocked screen* if you'd rather
  see it. Granting Accessibility is the better answer on a show machine.

**⌃⌥⌘F** pauses the fence (press it again to resume) when you need to reach a show screen on
purpose, to drag a window onto it, say. The masks change to a circle while it's paused.

The fence also stands down on its own rather than trap you: if every screen is ticked, or the
only screen you left unticked gets unplugged, it does nothing until that changes.

## Keeping the display arrangement

With **Lock main display & keep new screens extended** on (it is by default), show mode holds
on to the display arrangement the show started with.

**The main display stays put.** The main display is the one with the menu bar and the Dock,
and it's where new windows and a lot of apps' dialogs appear. Choose it under **Main Display**,
or leave that on *Whichever is main at start*. If anything makes a different screen main
during the show (a display reconnecting, say, or a projector macOS remembers from another
venue), show mode moves it back within about a second. The arrangement itself is kept: the
screens stay where they are relative to each other, and only which one carries the menu bar
changes back. If the display you chose isn't connected at start, show mode says so and makes
it main the moment it appears.

**New mirrors become extended.** Whatever's mirrored when the show starts is taken as
intentional (a confidence monitor showing the output, say) and left alone. Any screen that
starts mirroring during the show, whether it's a newly plugged-in projector macOS has decided
to mirror or a stray ⌘F1, is split back out to an extended display about a second later.

Changing which display is main makes every screen blink for a moment, the way it does in
System Settings. Show mode only does it when something else has already moved the main
display, but choose the main display before doors rather than mid-cue. If something keeps
undoing the arrangement (four corrections inside twenty seconds), show mode stops fighting
it, says so in its menu, and leaves the screens alone for the rest of the show. Whatever it
is, it clearly wants the displays more than show mode does.

When the show ends, the display that was main before it becomes main again. Screens that
were split out of a mirror stay extended: the mirror was macOS's guess, not yours.

Choosing a main display that's also fenced off puts the menu bar out of the cursor's reach,
so show mode warns you at start. ⌃⌥⌘F pauses the fence.

## Notifications

macOS gives apps no way to switch Do Not Disturb on, so Show Mode uses two tiny shortcuts
to do it instead. Choose **Setup → Install Do Not Disturb shortcuts**. After about half a
minute Shortcuts asks you to add *Show Mode Focus On* and *Show Mode Focus Off*; add both.
From then on show mode runs them itself. Until they're installed, show mode skips Do Not
Disturb and says so.

The shortcuts switch the built-in **Do Not Disturb** Focus, not any custom Focus you've
made. Whatever that Focus lets through (people or apps you've allowed in System Settings
→ Focus → Do Not Disturb) still gets through, so check its allow list on the show machine.

## Keeping other apps off the PA

*macOS 26 or later.* When the Mac's output feeds a PA, Outlook's new-mail chime or a browser
tab is one stray click away from the audience. With **Mute apps not allowed to play** ticked,
every app is silent during the show except the ones ticked under **Allowed to Play** in the
menu: your show app, and anything else that should be heard. The menu lists the apps that are
open, marks the ones playing sound right now, and remembers your choices. An allowed app
opened after the show starts is heard straight away.

- **The muting catches each sound as it starts.** A sound that's already playing when the show
  starts, such as a browser tab or music, carries on until it stops. The note at the start of a
  show names those apps: pause them, or tick them if they belong in the show.
- **Tick the show app before doors.** Ticking or unticking mid-show works, but it lets through
  any muted sound that happens to be playing at that moment, until that sound stops.
- **Apps that send sound to their own interface** (QLab, a DAW) are muted too unless ticked.
  Muting is per app, not per output.
- **Nothing is turned down.** The output's volume and mute are never touched, and if Show Mode
  quits or crashes every app is heard again straight away. A failure costs you the protection,
  and never silences the show.
- macOS asks for no permission and shows no recording dot for this, because Show Mode never
  listens to the sound it mutes.

## Privacy dots

macOS draws a coloured dot while an app uses the microphone (orange), the camera (green) or
records the screen (purple). No app can turn these off. Apple's own setting (macOS 14.4 or
later) leaves the microphone and camera dots off an **external display showing a full-screen
app**, and it comes with conditions:

- the **main display always keeps its dots**, so make the operator's screen the main display
  (**Main Display** in the menu);
- the **purple screen-recording dot can't be hidden** anywhere;
- it needs a **one-time step in Recovery**, which no app can do for you.

**The one-time step.** Start up in Recovery (on Apple silicon, shut down, then hold the power
button until *Loading startup options* appears; on Intel, hold ⌘R at startup), choose
**Utilities → Terminal** and run:

```bash
system-override suppress-sw-camera-indication-on-external-displays=on
```

Then restart. **Setup** in Show Mode's menu shows whether this has been done. After that, with
**Hide privacy dots on full-screen external displays** ticked, show mode turns the dots off on
external displays at the start of each show and back on at the end (it's the same switch as
**Privacy Indicators** under System Settings → Privacy & Security → Microphone). To undo the
step, run the same command with `=off` in Recovery.

Whether or not you've done it, show mode tells you at the start of a show if a dot is
showing, on which screen and why: the app using the microphone, the camera, or (when it's
neither) screen recording. The same line stays in the menu, marked ⚠︎, while the dot shows.

## Background work

A show Mac left untouched for hours looks idle to macOS, and idle is when macOS and every
other app get stuck into their housekeeping: indexing, photo analysis, backups, updates. The
cost is disk, network and heat more than processor time (on Apple silicon that work runs on the
efficiency cores), and heat matters most on a fanless MacBook Air.

**Pausing, not switching off.** Photo and media analysis and Spotlight's indexing are paused
for the show and resumed afterwards, so nothing has to start again from scratch. A small helper
pauses them and checks every two seconds for new copies. It resumes everything at the end of
the show, and by itself as soon as Show Mode goes away, crash included. While they're paused,
Photos, Live Text and Visual Look Up wait, and files that change aren't added to Spotlight
until the show ends. Spotlight search itself keeps working.

**Spotlight indexing** needs your password, because some of its processes belong to the
system. It covers every drive, including one plugged in mid-show, and writes nothing to the
drives themselves.

**Time Machine** needs your password and **Full Disk Access**: without it macOS cheerfully
reports that backups are off when they aren't. Show mode checks and tells you. To give it
access, choose **Setup → Full Disk Access (to pause Time Machine)** and turn on Show Mode in
the list. Automatic backups come back on at the end of the show if they were on before.

What I've left alone on purpose: the processes that answer Spotlight searches, iCloud,
security scanning, anything to do with Apple Intelligence (switching it off can delete its
models and download them again), and Location Services (macOS 26 doesn't let an app switch it
off).

## Fans

There are two fan guards and you get one or the other: ticking one unticks the other. Both ask
for your password at the start of the show, and both need an Apple silicon Mac with fans (a
MacBook Air hasn't got any).

**Full speed** runs every fan flat out for the show. A Mac working hard for hours warms up, and
once it's hot enough macOS slows it down to cope, which on a show looks like dropped frames.
Full speed gives it all the cooling it has from the first cue, so it gets there later, if at
all. It's loud: a 16-inch MacBook Pro's fans top out near 5,800 rpm. Fine at the back of a
tent, less so beside a string quartet.

**Quiet** holds every fan at its slowest (1,350 rpm on that MacBook Pro), so they don't ramp up
in the middle of a scene when the Mac gets busy. The Mac does warm up faster. If it gets hot
enough for macOS to start slowing it down, Show Mode hands the fans back to macOS until the Mac
has been cool for five minutes, then holds them at their slowest again, and the menu says so
while it's happening. A Mac doing almost nothing can stop its fans altogether, so on an idle Mac
quiet can be a touch louder than leaving them alone; it earns its keep on a Mac that's working.

Fan speeds can only be set as root, so a small helper holds them for the show. The helper is
Show Mode itself, run from a copy in a folder only the system can write to, and only after macOS
has checked that the copy is signed by the same developer as the app you're running. It gives the fans back
to macOS at the end of the show, when you quit, and by itself the moment Show Mode goes away,
crash included, so the fans can't be left stuck. If another app is already controlling the fans
(Macs Fan Control, TG Pro, Stats), Show Mode leaves them alone and tells you. If something takes
them back mid-show, it takes them again a few times and then lets go rather than fight over them.

## Pre-show checks

Some things no app can safely switch off. **Pre-show Checks** in the menu
lists the ones it finds on this Mac, each with the one thing to do about it:

- **A macOS update is waiting.** If anyone chooses *Install Tonight*, macOS installs it and
  restarts overnight whatever the settings say, and that can't be cancelled.
- **Updates managed by your organisation** can restart the Mac, or quit Office apps, on their
  deadline.
- **Dropbox, Google Drive, OneDrive** can only be paused from their own menus, and Dropbox keeps
  syncing after it quits. **Arq, Carbon Copy Cloner, Backblaze, ChronoSync** can start a backup
  mid-show: pause or disable them for the show.
- **Security software** that opens its own windows or scans on a schedule: Intego, Sophos, Trend
  Micro, Norton, LuLu, BlockBlock and Microsoft Defender each get their own line. Security
  software run by your IT team is never touched. Do Not Disturb already silences the ones that
  use ordinary notifications (Malwarebytes, Bitdefender, Kaspersky, ESET, ClamXAV).
- **The Mac itself:** running hot, running on battery, or a network on Wi-Fi.
- **A remote session** is active (see below).

The menu also reminds you of two things to do before doors: allow any "find devices on your
local network" prompt (NDI and Dante find nothing until it's allowed, and don't give you an
error to say so), and plug in every accessory, so a laptop never asks "Allow accessory to
connect?" during the show.

The ones that can change during the show (a remote session, heat, battery, the network)
also stay at the top of the menu, marked ⚠︎, while it runs.

## Remote access

Show mode doesn't block remote access, since whoever runs the show may need it.
But several remote-access tools change what the audience sees when someone connects. RustDesk's
privacy mode blacks out every display, Jump Desktop and Splashtop can change the resolution,
Splashtop and Parsec can add a virtual display, Apple's high-performance Screen Sharing blanks
the screens, and TeamViewer puts its own idea of the wallpaper back when a session ends.

With **Watch for remote sessions & keep the output black** ticked, show mode checks every five
seconds. It names an active session in the menu and in its log (Screen Sharing or VNC, Apple
Remote Desktop, NoMachine, AnyDesk and TeamViewer are recognised), warns if a display has been
blacked out (in the menu, marked ⚠︎), and puts the black wallpaper back if anything changed it.
The display lock keeps your main display main whatever a session does. If you use a remote tool
on the show Mac, set it not to change the resolution or the wallpaper on connect, and rehearse
with it.

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
screen without starting show mode, for a rehearsal or a desktop share. **Restore
Wallpaper** puts it back and leaves everything else alone. Ending show mode, quitting, or a
relaunch after a crash also restores it.

## What it did

Show mode keeps a plain log of what it changes at `~/Library/Logs/ShowMode.log`: the fence
coming on and in which mode, and every correction the display lock makes. Console.app opens
it.

## Putting things back

Before Show Mode changes anything it writes down what was there, in
`~/Library/Application Support/ShowMode/journal.plist`. Ending the show restores those values
and nothing else, so a setting you'd already switched off yourself stays off. The same happens
when you quit, when a launcher stops the app, and if the app crashes or the Mac restarts
mid-show: the next launch finds the journal, restores it, and tells you it did.

Settings that need your password are put back with one password prompt at the end of the show.
If you cancel it, show mode tells you what it couldn't put back and keeps a note of it: **Finish
Restoring** in the menu asks again, and so does the next launch.

Launch at Login (in Setup) is worth turning on for a show machine, so a restart mid-show is
followed by a clean restore.

## Running it from source

```bash
git clone https://github.com/stoatworks-labs/showmode
cd showmode
scripts/build-app.sh
```

That builds a universal `dist/Show Mode.app`. `swift build` on its own gives you a bare
executable for development; `.build/debug/ShowMode --status` prints what it can see without
changing anything.
