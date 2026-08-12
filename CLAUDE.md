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
```

All three targets build clean as of the initial fork setup (2026-08-11), 36/36 unit tests passing
(27 BGMAppUnitTests + 9 BGMDriverTests, 0 failures).

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
launchctl list | grep bearisdriving
ps aux | grep "Background Music" | grep -v grep
```

The device should show up in `SPAudioDataType`, the XPC helper should be a running launchd job
under `com.bearisdriving.BGM.XPCHelper`, and the menu bar app should be running. Actual audio
verification (does moving a slider actually change an app's volume) needs a human ear — no
headless check can confirm that.

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

Before pulling in any more upstream PRs: check the PR's own review comments first. The maintainer
(kyleneideck) reviews everything by hand and has already cherry-picked the legitimate fixes out of
open PRs into master — check `git log --all --grep` against the PR's commit messages before
assuming an open PR represents work that still needs doing.
