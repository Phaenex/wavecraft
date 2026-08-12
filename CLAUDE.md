# Wavecraft — working agreement

## What this is

Wavecraft is a personal fork of
[kyleneideck/BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) (GPL-2.0), built
from source on this machine instead of installed from the upstream `.pkg`. It
gives macOS a real per-app volume slider — something the OS has no native API for — by installing
a CoreAudio HAL virtual audio device that all app output routes through, then remixing it before
it reaches the real output device.

## Why a fork instead of a paid app

We tried SoundSource (Rogue Amoeba) first, installed and running. Nick asked to remove it and
build something free/open instead. Background Music does the same core job for $0 and is GPL-2.0,
but the *official* release binary runs under Rosetta on Apple Silicon — tracked upstream as
[issue #395](https://github.com/kyleneideck/BackgroundMusic/issues/395), open since 2020 and still
unresolved as of a July 2026 comment. That's a release-process limitation, not a codebase one:
building from source on this machine (Xcode 26.5, macOS 26.5.1) produces a universal binary with a
native `arm64` slice, confirmed with `file` on the built driver. So the fork exists to get a
native build, not because the upstream code needed functional changes.

## Repo layout

Inherited from upstream — see `README.md` (upstream's own) for the full architecture writeup.
Short version: `BGMDriver/` is the CoreAudio HAL plugin (the virtual device), `BGMApp/` is the menu
bar app with the volume sliders, `BGMApp/BGMXPCHelper/` is the privileged helper that talks to the
driver. `BGM.xcworkspace` builds all three.

## Build & test

```bash
xcodebuild -workspace BGM.xcworkspace -scheme "Background Music Device" -configuration Release -destination 'platform=macOS' build
xcodebuild -workspace BGM.xcworkspace -scheme "BGMXPCHelper" -configuration Release -destination 'platform=macOS' build
xcodebuild -workspace BGM.xcworkspace -scheme "Background Music" -configuration Release -destination 'platform=macOS' build

# Unit tests (no sudo needed, safe to run anytime):
xcodebuild -workspace BGM.xcworkspace -scheme "Background Music" -configuration Debug -destination 'platform=macOS' -only-testing:BGMAppUnitTests test
xcodebuild -workspace BGM.xcworkspace -scheme "Background Music Device" -configuration Debug -destination 'platform=macOS' -only-testing:BGMDriverTests test

# Icon assets (measures real pixel dimensions, doesn't just trust filenames):
python3 tools/verify-icons.py
```

All three targets build clean (Debug and Release). 51/51 unit tests passing (28 BGMAppUnitTests +
23 BGMDriverTests, 0 failures — re-run directly via the commands above, not carried over from an
older count). The 23rd driver test
(`BGM_DeviceTests::testCustomPropertyInfoListSizeMatchesActualEntryCount`) is a regression test for
a real crash found on this fork's first actual install — see docs/LESSONS.md's "device-wide crash
on first real install" entry. No unit tests were added for the EQ/routing UI itself: it's ordinary
AppKit/CoreAudio glue code (`BGMAppVolumesController`, `BGMOutputDeviceMenuSection`,
`BGMPreferredOutputDevices` already follow the same pattern), and `BGMTapRouteTests`'s own comment
explains why — this test target links mocked `CAHALAudioDevice`/`CAHALAudioSystemObject`, so
anything that touches a real device or `BGMPlayThrough` can't be exercised here regardless of how
the test is written. **A fully mocked/isolated test suite passing 100% is not the same claim as
"works on a real install"** — see that same LESSONS.md entry for exactly how that gap showed up in
practice.

## The one step that always needs a human

```bash
./build_and_install.sh
```

installs the driver into `/Library/Audio/Plug-Ins/HAL/`, registers `BGMXPCHelper` with `launchd`,
and restarts `coreaudiod`. This **cannot be automated by an agent**, and that's not a tooling gap
to work around — `coreaudiod` is a root daemon and CoreAudio HAL plugins only load from that one
system path; there is no per-user install location. Confirmed empirically (2026-08-11): running
the script non-interactively fails immediately with `sudo: a terminal is required to read the
password; either use the -S option to read from standard input or configure an askpass helper`.
An agent should never attempt to work around this (no askpass helper, no stored password, no
`NOPASSWD` sudoers edit) — it needs Nick at a real terminal typing his own password. Re-run it
after any change to `BGMDriver` or `BGMXPCHelper` — a Release build sitting in `xcodebuild`'s
DerivedData isn't installed until this script (or a manual copy) puts it in place.

### Verifying after install

```bash
system_profiler SPAudioDataType | grep -A5 "Background Music"
launchctl print system/com.bearisdriving.BGM.XPCHelper | grep "state = running"
ps aux | grep "Background Music" | grep -v grep
```

The device should show up in `SPAudioDataType`, the XPC helper should report `state = running`,
and the menu bar app should be running. **Don't use plain `launchctl list` for the XPC helper** —
it only shows the calling user's launchd domain, not root-owned system `LaunchDaemon`s, so it
reports the helper as missing even when it's genuinely running (`setup.sh` had this bug and it was
fixed; see `docs/TROUBLESHOOTING.md`). Actual audio verification (does moving a slider actually
change an app's volume) needs a human ear — no headless check can confirm that.

`setup.sh` runs the install and all of the above checks in one pass — see it for the exact
commands.

### Icons

Custom app + device icon (not upstream's Fermata mark) — see the commit that introduced them for
the design rationale. The menu bar status icon (`Images.xcassets/WavecraftIcon.imageset`, shown by
`BGMStatusBarItem`) was also replaced — upstream's original there (also literally named
"FermataIcon", though the artwork was three concentric rings, not an actual fermata glyph) read as
a microphone/recording icon at status-bar size, which is a bad look for an app that separately
needs "Microphone" permission for its virtual input device (see Known limitations, below) for
unrelated reasons. It's now four rounded bars (an EQ-meter motif matching the app icon), generated
with `reportlab` as a vector PDF at the same 283.46×283.46pt canvas size upstream's icon used.
`tools/generate-icons.py` regenerates all three icon deliverables (the AppIcon PNGs, DeviceIcon.icns,
and this PDF) from that same four-bar design — colors and geometry were measured directly off the
shipped `appicon_1024.png`, not hand-copied — rather than hand-editing any of them if the design
ever needs to change; pass `--out-dir` to render to a scratch location first rather than overwriting
the real assets directly. `iconutil` (used for the `.icns` step) needs to run unsandboxed if you're
doing this from an AI coding agent's shell — see the script's own docstring.
`tools/verify-icons.py` measures every icon file's actual pixel dimensions
against what `Contents.json` declares, rather than trusting a generation script got it right; run
it after regenerating any icon. The app icon updates in `/Applications` without `sudo` (that
bundle is user-owned after install); `DeviceIcon.icns`, shown in Audio MIDI Setup, is inside the
root-owned driver bundle and needs a real reinstall to update.

## In-progress work beyond stock Background Music

Two features being built on top of upstream, past parity with SoundSource. Both now have driver
(where relevant) and `BGMApp` UI wired end to end and build clean, but **neither has been
installed and used with real audio yet** — that needs `./build_and_install.sh` (the one step that
always needs a human, above) followed by actually moving the new sliders/pop-up while audio plays.

- **Per-app EQ** — DSP core (`BGMDriver/BGMDriver/DeviceClients/BGM_Biquad.*`), the
  `kAudioDeviceCustomPropertyAppEQ` device property (get/set/validate, mirroring how
  `AppVolumes` already works), and real-time application in `BGM_Device::ApplyClientEQ`
  (called from `DoIOOperation`, before `ApplyClientRelativeVolume`) — all driver-side, 22/22
  `BGMDriverTests` passing. See `docs/LESSONS.md` for the filter-state-ownership design decision
  this was built around (real-time delay-line state can't live where `BGM_Client` gets copied by
  value; it's owned by `BGM_Device` instead, in `mClientEQProcessors`). **UI**: each app's menu
  item now has 5 band sliders (60Hz/250Hz/1kHz/4kHz/12kHz, ±12dB, in the "extra controls" area
  alongside Pan) — `BGMAVM_EQBandSlider` in `BGMApp/BGMApp/BGMAppVolumes.{h,m}`, wired straight to
  the existing `BGMAppVolumesController::setEQBandGains:forAppWithProcessID:bundleID:`. Initial
  gains are read back from `BGMBackgroundMusicDevice::GetAppEQ()` the same way Volume/Pan already
  are, in `BGMAppVolumesController::getEQBandGainsForApp:fromEQ:`.
- **Per-app output routing** (send one app to headphones while another stays on speakers) — not
  possible in upstream's architecture at all (one virtual device, one `PlayThrough` output). Built
  via CoreAudio Process Taps instead — see `docs/PROCESS-TAP-ROUTING.md` for the verified API
  surface, `tools/tap-poc/` for the Phase 1 proof-of-concept, and `BGMApp/BGMApp/BGMTapRoute.*` for
  the Phase 2 per-app `PlayThrough`-equivalent engine (runs in `BGMApp`'s own process, not the
  driver — see that doc's "hybrid, not a replacement" design decision). **UI**: each app's menu
  item has an output-device pop-up ("Default" + every device `BGMOutputDeviceMenuSection` would
  offer) in the extra controls area, driven by the new `BGMAppOutputRoutingController` (owns the
  bundle-ID → `BGMTapRoute` map, starts/stops routes on its own serial queue so a slow
  `BGMPlayThrough::Start()` never blocks the main thread, and persists assignments in
  `BGMUserDefaults.outputRouteDeviceUIDsByBundleID`). Assignments survive both `BGMApp` restarting
  (persisted, restored for apps that are running when they're needed) and the *target* app being
  quit and relaunched (`CATapDescription.processRestoreEnabled`, macOS 26.0+) — they do **not**
  survive an app that was never running again during the `BGMApp` session it was assigned in, since
  restoring only happens for apps `NSWorkspace` already knows about; that's an inherent limit of
  routing living in `BGMApp`'s own process rather than the driver, not a bug to fix.

## Also new in Wavecraft: troubleshooters, hotkeys, customization

Three smaller features, all built end-to-end (`BGMApp` UI + `BGMUserDefaults` persistence) and
compiling/passing tests clean, but — same caveat as EQ/routing above — **not yet exercised against
a real install**:

- **In-app troubleshooters** (`BGMApp/BGMApp/Preferences/BGMTroubleshootMenu.{h,mm}`,
  **Preferences > Troubleshoot**) — five one-click fixes: reapply the default output device, reset
  every app's volume/pan/EQ to flat (confirmation alert first), clear every output-routing override
  (confirmation alert first), reconnect to `BGMXPCHelper`, and jump to the Microphone privacy pane.
  Each does the real repair action directly (e.g. `BGMAppOutputRoutingController::
  removeAllOutputOverrides`), not just a diagnostic message.
- **Global keyboard shortcuts** (`BGMApp/BGMApp/BGMHotkeys.{h,mm}`, **Preferences > Keyboard
  Shortcuts**) — Up/Down for system volume, Shift+Up/Down for the frontmost app's volume, via
  `NSEvent addGlobalMonitorForEventsMatchingMask:`. Off by default: unlike Microphone, the
  Accessibility permission this needs isn't required for the app's core function. Accessibility
  trust has no grant-completion callback (unlike `AVCaptureDevice`'s async microphone request), so
  turning shortcuts on shows a one-time explanation, opens the system prompt, and leaves the user to
  toggle the switch again after granting — there's no way to detect the grant automatically.
- **Customizable hotkey behavior** — a modifier preset (Option or Control, in case one conflicts
  with something else) and a step-size preset (Fine/Normal/Coarse, indexing into
  `kSystemVolumeSteps`/`kAppVolumeSteps` arrays in `BGMHotkeys.mm`) — both persisted in
  `BGMUserDefaults` and shown live in the Preferences menu via `currentBindingsDescription`.

51/51 unit tests passing after this work (28 BGMAppUnitTests + 23 BGMDriverTests — no new tests
were added for these three features specifically; they depend on real system state
(`AXIsProcessTrusted()`, `NSWorkspace.frontmostApplication`, live `AudioObjectSetPropertyData`,
`AVCaptureDevice` authorization) that the mocked `BGMAppUnitTests` target can't exercise, the same
limitation `BGMTapRouteTests.mm` documents for the EQ/routing UI). See TODO.md's "Needs a human"
section for what real-install verification these three still need.

## Known limitations (inherited from upstream, not introduced by us)

- Only 2-channel (stereo) output devices are supported. An 8-channel DisplayPort monitor caused a
  "severe choppiness" report ([issue #856](https://github.com/kyleneideck/BackgroundMusic/issues/856))
  that looked like a macOS Tahoe regression but was actually this limitation — confirmed by both
  the reporter and the maintainer. Don't reach for "Tahoe compat" fixes if choppiness shows up;
  check `Audio MIDI Setup.app` for the output device's channel count first.
- Volume above 50% on an app can clip. Keep your main output near max and lower individual apps
  instead of boosting them.
- First run needs "Microphone" permission in System Settings for the virtual input device — it
  doesn't actually listen to the mic, macOS just classifies BGM's input side that way.

## If you're picking this up

Read `docs/LESSONS.md` first — it has the specific things that turned out not to be what they
looked like on first read (an "open Tahoe bug" that wasn't, an "official fix PR" that was half
rejected by the maintainer for looking unverified). Don't re-learn those the slow way.

Hit a build error, install failure, or icon-not-updating problem? Check `docs/TROUBLESHOOTING.md`
first — every entry there is something that actually happened while building this fork, with the
real fix, not a guess.

Before pulling in any more upstream PRs: check the PR's own review comments first. The maintainer
(kyleneideck) reviews everything by hand and has already cherry-picked the legitimate fixes out of
open PRs into master — check `git log --all --grep` against the PR's commit messages before
assuming an open PR represents work that still needs doing.
