<!-- vim: set tw=120: -->

# TODO

This is Wavecraft's own list — things specific to the fork (native build, per-app EQ, per-app
output routing). For the much longer list of general Background Music issues/ideas (more music
players, system-wide volume boost, more than 2 output channels, etc.), see [upstream's
TODO.md](https://github.com/kyleneideck/BackgroundMusic/blob/master/TODO.md) and [upstream's
issues](https://github.com/kyleneideck/BackgroundMusic/issues) — most of that still applies here
unchanged, since this fork hasn't touched that code.

## Feature parity with SoundSource / Sound Control

The goal is to eventually match or beat what the paid alternatives do — see
[Images/README/comparison.png](Images/README/comparison.png) for where things stand today.
Roughly ordered by effort, cheapest first:

- **"Do Not Disturb" / priority-app auto-mute** — mute everything except a chosen app, the inverse
  of auto-pause. Similar shape to the existing auto-pause feature
  (`BGMApp/BGMApp/BGMAutoPauseMusic.mm`), could likely reuse a lot of its audible-state-change
  plumbing.
- **Device grouping / multi-output** — send audio to more than one physical device at once. Doesn't
  fit the current per-app output routing design as-is (`BGMTapRoute` assumes one output device per
  route); would need either multiple simultaneous `BGMPlayThrough` instances per tap or an aggregate
  device on the *output* side too.
- **AutoEQ headphone calibration** — apply a pre-measured correction curve for specific headphone
  models. Needs integrating (or writing) a headphone measurement database and mapping it onto the
  existing per-band gain API; the DSP side is already there once the target curve is known.
  Significant scope on its own.
  - Sound Control also emphasizes 31-band EQ for this — finer-grained correction needs more bands
    than the 10 fixed ISO bands Wavecraft has now, so this isn't a simple reuse of the existing
    10-band `BGM_AppEQ`/`BGM_Biquad` chain as-is.
- **Audio Unit (AU) plugin hosting per app** — let users insert their own AU effects in an app's
  real-time audio path, not just the built-in EQ. This is new real-time-safe architecture, not an
  extension of the existing EQ code — AU plugins aren't guaranteed real-time safe themselves, so
  hosting them from `BGM_Device`'s IO thread (which has hard real-time constraints — see
  DEVELOPING.md's "Real-time Constraints" section) needs real design work, not just a hookup.
- **AirPlay streaming** — SoundSource can stream to AirPlay receivers. Not something Background
  Music's architecture does anywhere today; would need real investigation into whether it fits the
  existing output-device model at all or needs its own path.

None of this is started. If you want to tackle one, open an issue first so effort doesn't overlap.

## Needs a human (can't be done by an agent building this)

- **Install and run the full QA sweep.** The first real install (2026-08-12) crashed `BGMApp` on
  every launch — a real bug, now fixed and pushed (see docs/LESSONS.md's "device-wide crash on
  first real install" entry: `kAudioObjectPropertyCustomPropertyInfoList`'s size query had gone
  stale after AppEQ became the 8th custom property). That fix needs a **fresh**
  `./build_and_install.sh` to actually take effect — re-running it is required, not optional, even
  if you already installed once today. After that, nothing in per-app EQ or per-app output routing
  has been verified against real audio yet — only that it builds clean and the parts that can be
  unit tested (DSP math, construction/validation, and now the property-discovery list) pass. Work
  through [docs/QA-PLAN.md](docs/QA-PLAN.md) — every menu control, every new-feature edge case, and
  the app's own error dialogs, in order, nothing marked done without actually watching it happen.
  The same applies to the in-app troubleshooters (does each one actually fix the state it claims
  to?), the global keyboard shortcuts (does the Accessibility prompt flow work, do the presets
  actually change step size audibly?), and their menu items — all of that only exists as build +
  unit-test-clean code so far, none of it has been clicked or pressed on a real running install.
  Also unverified: the two-column 10-band EQ layout (does it actually fix the menu-closing bug the
  original single-column version caused — see docs/LESSONS.md, this is a real bug report from an
  actual install, not a hypothetical), the non-flat-EQ/pan highlight on the show-more-controls
  button, the "this app is routed" indicator in the main menu, the three-way routing error message
  split (does each of the three messages actually show for its intended cause?), automatic recovery
  when a routed device is unplugged mid-route, and the new AppleScript EQ/output-device properties
  (`osascript -e 'tell application "Background Music" to get EQ band gains of application 1'` and
  similar — none of this has been run against the compiled `.sdef`, only checked to compile).
- **Verify `CATapMuted` actually mutes the routed app's normal output**, not just that the tap
  receives audio (see docs/PROCESS-TAP-ROUTING.md's Phase 1 results — this was the one thing left
  unconfirmed after the proof-of-concept, deferred to a real listening test with two apps and two
  output devices).

## Fairly quick

- Keyboard shortcuts only offer two modifier presets (Option or Control) and three step sizes
  (Fine/Normal/Coarse) — no arbitrary key rebinding. `BGMHotkeys` only ever listens for
  Up/Down-arrow, so a real rebinding UI would need to record and store an actual key code, not just
  pick from a fixed enum the way `BGMHotkeyModifierPreset`/`BGMHotkeyStepSize` do now.

## Less quick

- Per-app output routing assignments live in the menu bar app's own process (see
  docs/PROCESS-TAP-ROUTING.md's "hybrid, not a replacement" design decision) and are only restored
  for apps that are already running when Wavecraft starts or that launch later in the same session
  — an assignment for an app that was never running during that session won't be applied
  automatically even though it's still saved. Fixing this properly would mean either watching for
  *any* app launch indefinitely (not just ones with menu rows) or moving routing state into the
  driver somehow, which conflicts with the reason routing runs in user space in the first place.
- No automated tests exist for `BGMAppOutputRoutingController` or the new UI classes
  (`BGMAVM_EQBandSlider`, `BGMAVM_OutputRouteButton`) beyond what's structurally possible — see
  `BGMTapRouteTests.mm`'s own comment for why the `BGMAppUnitTests` target can't exercise anything
  that touches a real `CAHALAudioDevice`. This matches upstream's own testing gap for
  `BGMAppVolumesController`/`BGMOutputDeviceMenuSection`/`BGMPreferredOutputDevices`, none of which
  have unit tests either, but it's worth flagging rather than assuming coverage exists.
- Same testing gap applies to `BGMHotkeys` and `BGMTroubleshootMenu` — both depend on real system
  state (`AXIsProcessTrusted()`, `NSWorkspace.frontmostApplication`, `AudioObjectSetPropertyData`
  against a real `BGMDevice`, `AVCaptureDevice` authorization status) that the mocked
  `BGMAppUnitTests` target can't exercise, for the same reason `BGMTapRouteTests.mm` explains.
- Upstream's `release` job (building a signed `.pkg`) was already removed from
  `.github/workflows/build-test.yml` (see that file's own top comment and CHANGELOG.md's
  "Removed" section) — it needs an Apple Developer ID and notarization credentials this fork
  doesn't have configured. Source-build is the only distribution method right now; see the README.
