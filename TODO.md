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

- **More EQ bands.** Currently 5 (60Hz/250Hz/1kHz/4kHz/12kHz); SoundSource has 10, Sound Control has
  10 or 31. The driver side (`BGM_AppEQ`/`BGM_Biquad`) is already built to take an arbitrary band
  count — `kBGMAppEQNumBands` and `kBandCenterFreqs` just need to grow, and
  `BGM_ClientEQProcessors`' per-client storage cost scales linearly with it. The real cost is the
  UI: 5 sliders already needed a real XIB layout exercise (see docs/LESSONS.md) to fit in the
  per-app menu row; 10+ needs an actual layout decision (a wider row? A separate EQ window per app?
  Two columns?), not just repeating the same pattern more times.
- **Keyboard shortcuts** for volume (system boost and/or frontmost app) — already on upstream's own
  TODO list, unrelated to this fork's features specifically.
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
    than the 5-10 range above, so this and "more EQ bands" aren't fully independent.
- **Audio Unit (AU) plugin hosting per app** — let users insert their own AU effects in an app's
  real-time audio path, not just the built-in EQ. This is new real-time-safe architecture, not an
  extension of the existing EQ code — AU plugins aren't guaranteed real-time safe themselves, so
  hosting them from `BGM_Device`'s IO thread (which has hard real-time constraints — see
  DEVELOPING.md's "Real-time Constraints" section) needs real design work, not just a hookup.
- **AirPlay streaming** — SoundSource can stream to AirPlay receivers. Not something Background
  Music's architecture does anywhere today; would need real investigation into whether it fits the
  existing output-device model at all or needs its own path.

None of this is started. If you want to tackle one, open an issue first so effort doesn't overlap,
and check whether the driver side or the UI side is the actual bottleneck before assuming — for the
EQ band count in particular, it's the UI, not the DSP.

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
- **Verify `CATapMuted` actually mutes the routed app's normal output**, not just that the tap
  receives audio (see docs/PROCESS-TAP-ROUTING.md's Phase 1 results — this was the one thing left
  unconfirmed after the proof-of-concept, deferred to a real listening test with two apps and two
  output devices).

## Fairly quick

- Per-app EQ has no visual indicator (e.g. a highlighted "show more controls" arrow) for whether an
  app currently has non-flat EQ set, the same gap that already exists for pan (see the TODO comment
  on `BGMAVM_ShowMoreControlsButton::setUpWithApp:` in `BGMApp/BGMApp/BGMAppVolumes.m`).
- The output-routing pop-up's error alert (shown when `BGMTapRoute::Start()` throws) doesn't
  distinguish "macOS is too old" from "the device disappeared between selecting it and starting the
  route" from a genuine CoreAudio failure — it shows the same generic message with the raw
  `OSStatus` for all three. Worth splitting once we know from real use which of these actually
  happens.
- No AppleScript/`osascript` support for the new EQ or routing controls (the existing per-app
  volume/pan AppleScript support in `BGMApp/BGMApp/Scripting/BGMASApplication.m` wasn't extended).

## Less quick

- Per-app output routing assignments live in the menu bar app's own process (see
  docs/PROCESS-TAP-ROUTING.md's "hybrid, not a replacement" design decision) and are only restored
  for apps that are already running when Wavecraft starts or that launch later in the same session
  — an assignment for an app that was never running during that session won't be applied
  automatically even though it's still saved. Fixing this properly would mean either watching for
  *any* app launch indefinitely (not just ones with menu rows) or moving routing state into the
  driver somehow, which conflicts with the reason routing runs in user space in the first place.
- No UI affordance shows *which* apps currently have an output-route override active without
  opening each app's row individually — a summary view (or just a badge on the menu bar icon) would
  help once there's more than one or two routed apps at a time.
- No automated tests exist for `BGMAppOutputRoutingController` or the new UI classes
  (`BGMAVM_EQBandSlider`, `BGMAVM_OutputRouteButton`) beyond what's structurally possible — see
  `BGMTapRouteTests.mm`'s own comment for why the `BGMAppUnitTests` target can't exercise anything
  that touches a real `CAHALAudioDevice`. This matches upstream's own testing gap for
  `BGMAppVolumesController`/`BGMOutputDeviceMenuSection`/`BGMPreferredOutputDevices`, none of which
  have unit tests either, but it's worth flagging rather than assuming coverage exists.
- `.github/workflows/build-test-release.yml`'s release job (building a signed `.pkg`) isn't
  something this fork can run — it needs an Apple Developer ID and notarization credentials we
  don't have configured. Source-build is the only distribution method right now; see the README.
