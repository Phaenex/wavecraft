<!-- vim: set tw=120: -->

# Guide

A walkthrough of what's actually in the menu, once Wavecraft is installed and running. (This is a
written description, not a set of screenshots — the UI hasn't been screenshotted yet, since that
needs a real install; see [TODO.md](../TODO.md).)

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
- **The small arrow (▾)** on the right — click it to expand the row and reveal three more sections:

### Pan

A slider that shifts the app's audio left/right in the stereo field.

### EQ

Five vertical-stacked sliders, one per band: **60Hz, 250Hz, 1kHz, 4kHz, 12kHz**, each adjustable
from −12dB to +12dB. These apply in the driver, in real time, independently per app — turning down
an app's 60Hz band doesn't affect any other app's bass.

There's no visual indicator on the collapsed row for whether an app currently has non-flat EQ set
(same known gap as Pan already had — see [TODO.md](../TODO.md)), so if something sounds off, expand
the row and check.

### Output routing

A pop-up button listing **Default** plus every output device currently connected. Pick a device to
send that specific app's audio there instead of your main output — for example, routing a video
call to headphones while music keeps playing on speakers. Pick **Default** again to send it back
through the normal path.

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

## Status bar icon

**Preferences > Status Bar Icon** lets you switch between the default four-bar Wavecraft icon and a
volume-level icon. The volume icon shows your current output level at a glance, but isn't the
default because it looks the same as macOS's own built-in volume menu item — picking it means
you'll have two nearly-identical icons in your menu bar if that one's also showing.

## Launch at startup

Not built into the app — add `Wavecraft.app` (installed as `Background Music.app` in
`/Applications`) to **System Settings > General > Login Items**.
