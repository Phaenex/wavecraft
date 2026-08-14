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

All three targets build clean (Debug and Release). 71/71 unit tests passing (47 BGMAppUnitTests +
24 BGMDriverTests, 0 failures — re-run directly via the commands above, not carried over from an
older count). Two driver tests are regression tests for real bugs found in this fork, not ordinary
feature tests:
`BGM_DeviceTests::testCustomPropertyInfoListSizeMatchesActualEntryCount` (a property-discovery-list
size mismatch that crashed `BGMApp` on this fork's first real install) and
`BGM_DeviceTests::testConcurrentAddRemoveClientDuringProcessOutputDoesNotCorruptEQProcessorMap` (a
genuine data race in `BGM_Device::DoIOOperation`'s real-time IO path — reliably reproduced a real
crash when reverted, see docs/LESSONS.md for both). No unit tests were added for the EQ/routing UI
itself: it's ordinary AppKit/CoreAudio glue code (`BGMAppVolumesController`,
`BGMOutputDeviceMenuSection`, `BGMPreferredOutputDevices` already follow the same pattern), and
`BGMTapRouteTests`'s own comment explains why — this test target links mocked
`CAHALAudioDevice`/`CAHALAudioSystemObject`, so anything that touches a real device or
`BGMPlayThrough` can't be exercised here regardless of how the test is written. **A fully
mocked/isolated test suite passing 100% is not the same claim as "works on a real install"** — see
that same LESSONS.md entry for exactly how that gap showed up in practice.

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
system_profiler SPAudioDataType | grep -A5 "Wavecraft"
launchctl print system/com.bearisdriving.BGM.XPCHelper | grep "state = running"
ps aux | grep "Background Music" | grep -v grep
```

Two different names here on purpose, not a typo: the CoreAudio device's own display name
(`kDeviceName` in `BGM_Device.h`) was renamed to "Wavecraft", but the `.app` bundle, its
executable, `CFBundleName`, and the bundle identifier were all deliberately left as "Background
Music"/`com.bearisdriving.BGM.*` — see `CFBundleDisplayName`'s addition to `Info.plist` and
docs/LESSONS.md for why. So `ps` (which reports the real executable name) still needs to match
"Background Music", while `system_profiler` (which reports the device's own display string) now
needs "Wavecraft".

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
  (called from `DoIOOperation`, before `ApplyClientRelativeVolume`, both inside the same
  `mIOMutex` critical section — see the data-race entry in docs/LESSONS.md for why that matters).
  See `docs/LESSONS.md` for the filter-state-ownership design decision this was built around
  (real-time delay-line state can't live where `BGM_Client` gets copied by value; it's owned by
  `BGM_Device` instead, in `mClientEQProcessors`). **10 bands**, the standard ISO octave-band
  spread (31/62/125/250/500/1k/2k/4k/8k/16k Hz, ±12dB each) — `BGM_AppEQ::kNumBands`
  (`BGM_Biquad.h`) and `kBGMAppEQNumBands` (`SharedSource/BGM_Types.h`) are two independent
  constants that have to be edited together; a `static_assert` in `BGM_Device.cpp` catches them
  drifting apart. **UI**: each app's menu item has 10 band sliders arranged as two columns of 5
  (low bands left, high bands right — MainMenu.xib's `appVolumeView` custom view, 390x147),
  alongside Pan in the "extra controls" area. First shipped as one column of 10, which grew that
  row 51% taller than it had ever been (147pt -> 222pt); a real-install report of the whole menu
  closing on any slider click/drag led to reverting to two columns of 5 (same 147pt height as the
  original 5-band layout, just wider) instead — the working theory is that a taller-than-ever
  custom-view menu row pushed the overall dropdown into needing to scroll with multiple apps'
  rows expanded, and NSMenu's built-in scrolling is known to interact badly with custom-view menu
  items' mouse tracking. Unconfirmed which exact mechanism was at fault (never reproduced
  directly, no way to interact with a live running menu from this environment) — if this comes up
  again, that's the first thing to check. `BGMAVM_EQBandSlider` in
  `BGMApp/BGMApp/BGMAppVolumes.{h,m}`, wired straight to
  the existing `BGMAppVolumesController::setEQBandGains:forAppWithProcessID:bundleID:`. Initial
  gains are read back from `BGMBackgroundMusicDevice::GetAppEQ()` the same way Volume/Pan already
  are, via the now-public `BGMAppVolumesController::getEQBandGainsForApp:` (wraps the original
  private `fromEQ:` version — added for AppleScript support, see below). The show-more-controls
  arrow (`BGMAVM_ShowMoreControlsButton::bgm_syncHighlightForCurrentControls`) highlights when an
  app has non-default EQ or pan set, so that state isn't invisible on the collapsed row; has to run
  *after* `insertMenuItemForApp:...` writes real slider values, not from `setUpWithApp:` itself,
  since siblings don't have their real values yet at that point in setup.
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
  routing living in `BGMApp`'s own process rather than the driver, not a bug to fix. Routed apps are
  marked in the main menu (`BGMAppDelegate::menuWillOpen:`, an SF Symbol appended to the app name
  via `NSTextAttachment`) so a route is visible without opening that app's row. If the routed
  device disconnects mid-route, `BGMAppOutputRoutingController` now listens for
  `kAudioHardwarePropertyDevices` and tears the route down automatically (keeping the persisted
  assignment so it reapplies if the device reconnects) instead of leaving `BGMTapRoute::IsRunning()`
  reporting `true` against a dead device indefinitely. `BGMTapRoute::Start()`'s thrown
  `CAException` now distinguishes `kMacOSTooOld`, `kOutputDeviceVanished` (checked directly via
  `CAHALAudioObject::ObjectExists`/`IsAlive`, not inferred from an ambiguous OSStatus), and a
  generic CoreAudio failure, so the error alert shown for a failed route names the actual cause
  instead of always blaming "needs macOS 26."
- **AppleScript support** — `BGMASApplication` (`BGMApp/BGMApp/Scripting/`) gained `eqBandGains`
  (wraps the getter/setter above) and `outputDevices` (a list; resolves to/from `BGMASOutputDevice`
  objects via `BGMAppOutputRoutingController`'s newly-public
  `outputOverrideDeviceUIDsForBundleID:`/`findConnectedDeviceIDForUID:`) properties, declared in
  `BGMApp.sdef`. `BGMAppDelegate` gained a public `outputRoutingController` property (mirroring the
  existing `appVolumes` one) so the scripting layer can reach it.
- **Multiple output devices per route** (added 2026-08-12, see docs/PROCESS-TAP-ROUTING.md's "Phase
  3") — `BGMTapRoute` generalized from exactly one `BGMPlayThrough` per tap to a `std::vector` of
  them, all reading the same aggregate input device (CoreAudio devices support several independent
  `IOProcID`s on one device simultaneously, the same way multiple apps can record from one mic).
  `AddOutputDevice:`/`RemoveOutputDevice:` manage outputs independently of the tap's lifecycle, so
  changing an app's target device set diffs against what's already running instead of tearing the
  whole route down. `BGMUserDefaults.outputRouteDeviceUIDsByBundleID` changed from
  `NSDictionary<NSString*, NSString*>*` to `NSDictionary<NSString*, NSArray<NSString*>*>*` — the
  getter defensively drops any entry that isn't actually an array of strings, since a plist saved
  by the earlier single-device version would otherwise deserialize as the wrong shape (Objective-C
  generics are erased at runtime) and crash the first caller that treats it as an array. The
  per-app pop-up (`BGMAVM_OutputRouteButton`) deliberately kept its existing click-and-close
  `NSPopUpButton` interaction rather than becoming a persistent multi-select checklist — clicking a
  device now toggles it in/out of the set instead of replacing it, so multi-device selection is
  several individual clicks, not one gesture. That's a deliberate scope decision to avoid a second
  unverified custom-view-menu interaction risk stacked on top of the EQ menu-closing bug from
  earlier this session (still not confirmed fixed) — see PROCESS-TAP-ROUTING.md for the reasoning.

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
  Shortcuts**) — four independently rebindable actions (system/app volume up/down), each any key +
  any modifiers, via `NSEvent addGlobalMonitorForEventsMatchingMask:`. Off by default: unlike
  Microphone, the Accessibility permission this needs isn't required for the app's core function.
  Accessibility trust has no grant-completion callback (unlike `AVCaptureDevice`'s async microphone
  request), so turning shortcuts on shows a one-time explanation, opens the system prompt, and
  leaves the user to toggle the switch again after granting — there's no way to detect the grant
  automatically.
- **Arbitrary key rebinding** (added 2026-08-12, replacing an earlier fixed Option/Control preset)
  — `BGMHotkeyRecorderButton` (click-to-record, one per action in Preferences) plus
  `BGMHotkeyBinding`/`BGMHotkeyAction` in `BGMHotkeys.h` and per-action storage in
  `BGMUserDefaults::hotkeyBindingForAction:`/`setHotkeyBinding:forAction:`. Conflicting bindings are
  rejected with an alert naming the action already using that key. A step-size preset
  (Fine/Normal/Coarse, indexing into `kSystemVolumeSteps`/`kAppVolumeSteps` arrays in
  `BGMHotkeys.mm`) still applies to all four actions. **Untested**: whether the recorder's local
  `NSEvent` monitor actually wins the race against the Preferences menu's own tracking loop for
  keys the menu itself might intercept (arrows especially) — see TODO.md's "Needs a human" section.
- **Do Not Disturb** (added 2026-08-12, `BGMApp/BGMApp/BGMDoNotDisturb.{h,mm}`, **Preferences > Do
  Not Disturb**) — mutes every app except one chosen priority app, via the same
  `SetAppVolume`/`GetAppVolumes` API the volume sliders and hotkeys already use, not a separate mute
  mechanism. Snapshots each muted app's volume to restore on disable; an `NSWorkspace.
  runningApplications` KVO observer catches apps that launch while it's on. **Untested** like
  everything else in this section — see TODO.md's "Needs a human" section for the specific
  real-audio checks it still needs (does the muted app actually go silent, does the restored volume
  match what it was before, not a default).

71/71 unit tests passing after this work (47 BGMAppUnitTests + 24 BGMDriverTests). The 10
`BGMUserDefaultsTests.mm` tests cover the hotkey-binding storage/defaults/clamping/helper-function
logic, which is plain Foundation/plist code with no CoreAudio HAL dependency; the 1 new
`BGMTapRouteTests.mm` test (`testHasOutputDeviceIsFalseForAnyDeviceBeforeAddOutputDeviceIsCalled`)
only covers construction-time state, matching that file's existing "construction/validation only"
scope; the 8 new `BGMOutputDeviceDiffTests.mm` tests fully cover `BGMComputeOutputDeviceDiff`
(`BGMOutputDeviceDiff.{h,cpp}`), the multi-output device-set reconciliation logic extracted out of
`BGMAppOutputRoutingController` specifically because it's pure `std::vector<AudioObjectID>` set
math with no HAL dependency, unlike the *action* of actually adding/removing an output on a real
`BGMTapRoute`. Confirmed by directly reading `Mock_CAHALAudioObject.cpp`'s `GetPropertyData`/
`SetPropertyData` (2026-08-12, not assumed): they implement a small fixed set of selectors and
abort via `Mock_Unimplemented()` for anything else, including every app-volume/main-volume-control
property — so `BGMHotkeys` itself, `BGMHotkeyRecorderButton`'s actual key-capture behavior,
`BGMDoNotDisturb`, and the rest of the troubleshooters/EQ/routing UI genuinely can't get automated
coverage this way, not just "haven't gotten around to it." They still depend on real system state
(`AXIsProcessTrusted()`, `NSWorkspace.frontmostApplication`, live `AudioObjectSetPropertyData`,
`AVCaptureDevice` authorization, a real live `NSMenu` tracking session, real CoreAudio tap/aggregate
devices) that the mocked `BGMAppUnitTests` target can't exercise, the same limitation
`BGMTapRouteTests.mm` documents. See TODO.md's "Needs a human" section for what real-install
verification these still need.

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
