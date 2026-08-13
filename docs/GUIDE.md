<!-- vim: set tw=120: -->

# Guide

A walkthrough of what's actually in the menu, once Wavecraft is installed and running. (This is a
written description, not a set of screenshots — the UI hasn't been screenshotted yet, since that
needs a real install; see [TODO.md](../TODO.md).)

## First launch

The very first time Wavecraft ever opens, it shows a one-time dialog explaining that macOS is about
to ask for "Microphone" access, and why (the virtual audio device it uses to see your system's
audio is classified as a microphone input by macOS, even though nothing about it is a real mic —
see the README's Known Limitations). Click **Continue**, then **Allow** on the actual system
permission prompt that follows.

If you miss that prompt or click **Don't Allow** by mistake, Wavecraft shows an error with an
**Open Privacy Settings** button that jumps straight to **System Settings > Privacy & Security >
Microphone** — check the box for Wavecraft there, then open it again.

## Opening the menu

Click the Wavecraft icon (four bars) in your menu bar. Everything — output device, per-app
controls, preferences — lives in that one menu.

## The main output

Near the top, under **Volumes**, is a slider for your overall output volume and a slider for system
(UI) sound effects. Below the **Output Device** heading is the list of physical devices Wavecraft
can send audio to — pick one the same way you'd use the native macOS sound menu.

## Per-app controls

Every running app with audio (that isn't hidden or a background helper) gets its own row:

- **Icon and name** — self-explanatory.
- **Mute button** — click to mute/unmute. Un-muting restores the volume you had before you muted.
- **Volume slider** — always visible. Snaps to the midpoint (unity gain) if you drop it near the
  middle, so it's easy to find "unchanged" again.
- **The small arrow (▾)** on the right — click it to expand the row and reveal three more sections.
  It highlights (a colored tint on the arrow) whenever the app currently has non-default pan or EQ
  set, so you can tell before expanding the row.

### Pan

A slider that shifts the app's audio left/right in the stereo field.

### EQ

Ten sliders arranged as two columns of five — the standard ISO octave-band spread, low band on the
left (**31Hz, 62Hz, 125Hz, 250Hz, 500Hz**) and high band on the right (**1kHz, 2kHz, 4kHz, 8kHz,
16kHz**), each adjustable from −12dB to +12dB. These apply in the driver, in real time,
independently per app — turning down an app's 31Hz band doesn't affect any other app's bass.

### Output routing

A pop-up button listing **Default** plus every output device currently connected. Pick a device to
send that specific app's audio there instead of your main output — for example, routing a video
call to headphones while music keeps playing on speakers. Pick **Default** again to send it back
through the normal path. Apps with an active route are marked with a small icon next to their name
in the main menu, so you can see which apps are routed without opening each row. If the device
you've routed an app to disconnects, Wavecraft automatically clears that route (the assignment is
still remembered — reconnect the device and reselect it, or just relaunch the app, to restore it).

This needs macOS 26.0+ (see the README's Requirements section). The assignment is remembered even
if you quit and reopen the app you routed — it's tied to the app's bundle ID, not the specific
running process.

## Auto-pause music

In the **Preferences** submenu, pick your music player (iTunes/Music, Spotify, VLC, VOX, Decibel,
Hermes, Swinsian, or GPMDP). Wavecraft will pause it automatically whenever another app starts
playing audio, and unpause it when that audio stops.

## Recording system audio

With Wavecraft running, open **QuickTime Player > File > New Audio Recording**, click the dropdown
next to the record button, and select **Wavecraft** (shown internally as "Background Music") as the
input device. To record a microphone at the same time, create an aggregate device combining your
mic with the Wavecraft device in **Audio MIDI Setup** (**/Applications/Utilities**).

## Keyboard shortcuts

**Preferences > Keyboard Shortcuts** lets you adjust volume without opening the menu at all. Off by
default, since it needs Accessibility permission — something Wavecraft's core function doesn't
otherwise require, so it's opt-in.

- **Enable Keyboard Shortcuts** turns it on. The first time, you'll see an explanation of why
  Accessibility access is needed before macOS's own permission prompt appears. Check the box for
  Wavecraft in the System Settings window that opens, then come back and toggle the switch off and
  back on — macOS doesn't tell an app when this permission gets granted, so there's no way for
  Wavecraft to pick it up automatically.
- Four rows, one per action (**System Volume Up/Down**, **Frontmost App Volume Up/Down**), each
  with a button showing its current shortcut (e.g. "⌥↑"). Click a button, then press any key —
  with or without modifiers held — to rebind that action to it. Press Esc, or click the button
  again, to back out without changing anything. If the key you press is already bound to a
  different action, Wavecraft tells you which one instead of silently overwriting it — record a
  new shortcut for that one first if you want to free it up. The defaults match this feature's
  original Option+Up/Down (system) and Option+Shift+Up/Down (app) behavior, so nothing changes
  until you record something yourself.
- **Fine / Normal / Coarse Steps** controls how much each key press changes the volume by — Fine
  for small adjustments, Coarse for getting from very quiet to very loud in fewer presses.
- The current bindings and step size are shown right in the menu, below the four buttons.

## Do Not Disturb

**Preferences > Do Not Disturb** mutes every other app and lets just one you pick stay audible —
the inverse of auto-pause above, which pauses one specific music player when anything else plays.
Do Not Disturb works with any running app (a video call, a game, whatever you're actually trying to
hear), not just a music player.

- **Enable Do Not Disturb** turns it on. Every other running app gets muted immediately, each
  remembering its own volume from just before — turning this off restores every one of them, not
  just resets them to a default.
- **Priority App** picks which app stays audible. Change it any time, including while Do Not
  Disturb is already on — the app you just switched away from gets muted, the one you switched to
  gets its own volume back.
- An app that launches while Do Not Disturb is on gets muted automatically, the moment it appears —
  you don't have to turn it off and back on to catch it.
- This resumes automatically the next time Wavecraft launches if you left it on.

## Troubleshoot

**Preferences > Troubleshoot** has one-click fixes for the most common stuck states, instead of
making you dig through docs/TROUBLESHOOTING.md or restart things by hand:

- **Reapply Default Output Device** — re-sets your system output to Wavecraft's device, for when
  audio routing gets stuck pointing somewhere else.
- **Reset All App Volumes, Pan & EQ** — returns every app's per-app volume, pan, and EQ bands to
  their defaults. Asks for confirmation first, since it affects every app at once.
- **Remove All Output Routing Overrides** — clears every per-app output-routing assignment, sending
  everything back through your normal default output. Also confirms first.
- **Reconnect to BGMXPCHelper** — re-establishes the connection to `BGMXPCHelper` if the app seems to
  have lost it (a symptom of the helper looking "disconnected" without a full app restart).
- **Check Microphone Permission** — jumps straight to the System Settings pane for Wavecraft's
  Microphone permission, for when the virtual input device isn't showing up correctly.

## Status bar icon

**Preferences > Status Bar Icon** lets you switch between the default four-bar Wavecraft icon and a
volume-level icon. The volume icon shows your current output level at a glance, but isn't the
default because it looks the same as macOS's own built-in volume menu item — picking it means
you'll have two nearly-identical icons in your menu bar if that one's also showing.

## Launch at startup

Not built into the app — add `Wavecraft.app` (installed as `Background Music.app` in
`/Applications`) to **System Settings > General > Login Items**.

## AppleScript

Wavecraft is scriptable — open **Script Editor** and target "Background Music" (its underlying
app/process name; see CLAUDE.md's Icons section for why the display name and process name differ).
Each running app exposes `volume`, `pan`, `EQ band gains` (a list of 10 numbers, lowest frequency
first), and `output devices` (a list of output device objects, empty for no override — set more
than one to play that app's audio through all of them at once):

```applescript
tell application "Background Music"
    set volume of application "Music" to 50
    set EQ band gains of application "Music" to {0, 0, 0, 0, 0, 3, 3, 0, 0, 0}
    set output devices of application "Music" to {first output device whose name is "AirPods"}
    -- Or route to two devices at once:
    -- set output devices of application "Music" to {output device 1, output device 2}
    -- Back to the default output:
    -- set output devices of application "Music" to {}
end tell
```

Wavecraft-the-application (not a specific running app) also still exposes upstream's own
`selected output device`, `output devices`, and `output volume` properties unchanged — that
top-level `output devices` is the full list of every connected device (`get output devices`), a
different thing from the per-app `output devices` property above (`output devices of application
"Music"`, which devices *that specific app* is routed to). AppleScript tells them apart by which
object you ask.
