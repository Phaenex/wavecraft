# mac-volume-mixer — working agreement

## What this is

A personal fork of [kyleneideck/BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic)
(GPL-2.0), built from source on this machine instead of installed from the upstream `.pkg`. It
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

All three targets build clean. 43/43 unit tests passing as of the per-app EQ DSP core
(27 BGMAppUnitTests + 16 BGMDriverTests — 9 original + 7 for `BGM_Biquad`/`BGM_AppEQ`, verified by
measuring actual RMS gain from a real sine wave, not just checking the code runs), 0 failures.

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
the design rationale. `tools/verify-icons.py` measures every icon file's actual pixel dimensions
against what `Contents.json` declares, rather than trusting a generation script got it right; run
it after regenerating any icon. The app icon updates in `/Applications` without `sudo` (that
bundle is user-owned after install); `DeviceIcon.icns`, shown in Audio MIDI Setup, is inside the
root-owned driver bundle and needs a real reinstall to update.

## In-progress work beyond stock Background Music

Two features being built on top of upstream, past parity with SoundSource:

- **Per-app EQ** — DSP core done and tested (`BGMDriver/BGMDriver/DeviceClients/BGM_Biquad.*`,
  `BGMDriverTests/BGM_BiquadTests.mm`). Not yet wired to a settable property or the real-time IO
  path — see `docs/LESSONS.md` for the filter-state-ownership design decision that has to hold
  before that wiring goes in (real-time delay-line state can't live where `BGM_Client` gets copied
  by value).
- **Per-app output routing** (send one app to headphones while another stays on speakers) — not
  possible in upstream's architecture at all (one virtual device, one `PlayThrough` output). Being
  built via CoreAudio Process Taps instead — see `docs/PROCESS-TAP-ROUTING.md` for the verified API
  surface and `tools/tap-poc/` for the proof-of-concept that confirmed the approach works (real
  audio measured, no unexpected permission prompt).

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
