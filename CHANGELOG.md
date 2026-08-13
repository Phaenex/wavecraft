<!-- vim: set tw=120: -->

# Changelog

This documents Wavecraft's changes on top of the upstream [Background
Music](https://github.com/kyleneideck/BackgroundMusic) v0.5.0 base it was forked from. It doesn't
duplicate upstream's own history — see [upstream's
releases](https://github.com/kyleneideck/BackgroundMusic/releases) for that.

## Unreleased

### Added

- **Per-app EQ.** A 10-band equalizer (the standard ISO octave-band spread — 31/62/125/250/500Hz/
  1/2/4/8/16kHz, ±12dB) per running app, alongside the existing volume/pan controls. Started as 5
  bands and grew to 10 in the same "Unreleased" window — see the `Changed` section below.
  - Driver: DSP core (`BGMDriver/BGMDriver/DeviceClients/BGM_Biquad.*`), the
    `kAudioDeviceCustomPropertyAppEQ` device property, and real-time application in
    `BGM_Device::ApplyClientEQ`.
  - App: `BGMAVM_EQBandSlider` in `BGMApp/BGMApp/BGMAppVolumes.{h,m}`, wired to
    `BGMBackgroundMusicDevice::SetAppEQBandGains`/`GetAppEQ`. The show-more-controls arrow
    highlights when an app has non-default EQ or pan set.
- **Per-app output routing.** Send an individual app's audio to a different physical output device
  than everything else, via CoreAudio Process Taps — not possible in upstream's single-virtual-
  device architecture. See [docs/PROCESS-TAP-ROUTING.md](docs/PROCESS-TAP-ROUTING.md) for the full
  design.
  - `BGMTapRoute` (`BGMApp/BGMApp/BGMTapRoute.{h,mm}`) — the per-app tap/aggregate-device/
    `BGMPlayThrough` engine. Distinguishes macOS-too-old, target-device-vanished, and generic
    CoreAudio failures when `Start()` throws, so the error alert names the actual cause.
  - `BGMAppOutputRoutingController` — owns routing assignments, persists them, restores them for
    running apps, and now watches for the routed device disconnecting mid-route (clears the route,
    keeps the persisted assignment so it reapplies if the device reconnects).
  - `BGMAVM_OutputRouteButton` — the per-app output-device pop-up in the menu.
  - Routed apps are marked in the main menu (an icon appended to the app's name) so a route is
    visible without opening that app's row.
  - Requires macOS 26.0+ (`CATapDescription.processRestoreEnabled`); everything else in Wavecraft
    still targets macOS 10.13+.
- **AppleScript support for per-app EQ and output routing** — `BGMASApplication` gained
  `eqBandGains` and `outputDevice` properties, alongside the existing `volume`/`pan`.
- Native Apple Silicon (`arm64`) build from source — the reason this fork exists at all. Upstream's
  official release binary runs under Rosetta on Apple Silicon
  ([issue #395](https://github.com/kyleneideck/BackgroundMusic/issues/395)); building from source
  with a current Xcode does not have this problem.
- A monochrome menu-bar status icon and custom app icon, replacing upstream's Fermata mark — see
  [docs/LESSONS.md](docs/LESSONS.md) for why (the original read as a microphone/recording icon at
  status-bar size).
- **In-app troubleshooters** (`BGMApp/BGMApp/Preferences/BGMTroubleshootMenu.{h,mm}`,
  **Preferences > Troubleshoot**) — five one-click fixes for the most common stuck states: reapply
  the default output device, reset every app's volume/pan/EQ to flat, clear every output-routing
  override, reconnect to `BGMXPCHelper`, and jump to the Microphone privacy pane.
- **Global keyboard shortcuts** (`BGMApp/BGMApp/BGMHotkeys.{h,mm}`, **Preferences > Keyboard
  Shortcuts**) — adjust system volume or the frontmost app's volume without opening the menu. Off
  by default (needs Accessibility permission, requested with its own one-time explanation since
  the permission isn't required for the app's core function). Customizable: a modifier preset
  (Option or Control) and a step size (Fine/Normal/Coarse).
- An interactive first-run install flow — a welcome dialog explaining why Wavecraft needs
  "Microphone" access *before* the system permission prompt appears, an "Open Privacy Settings"
  button on denial, and a guided `build_and_install.sh` with a clearer preamble/epilogue about what
  the script actually does.
- [docs/QA-PLAN.md](docs/QA-PLAN.md) — an ordered checklist for verifying a fresh install actually
  works, covering every menu control and new-feature edge case, not just "does it build."

### Changed

- `BGMPlayThrough` generalized to accept a non-`BGMDevice` input (`SetRequireBGMDeviceInput`), so
  `BGMTapRoute` can reuse its ring-buffer/clock-sync engine instead of reimplementing it.
- Per-app EQ grew from 5 bands (60Hz/250Hz/1kHz/4kHz/12kHz) to 10 (the standard ISO octave-band
  spread) — `BGM_AppEQ::kNumBands`/`kBandCenterFreqs` (`BGM_Biquad.h`) and `kBGMAppEQNumBands`
  (`SharedSource/BGM_Types.h`), plus 5 more slider/label pairs added to `MainMenu.xib`.

### Fixed

- A device-wide crash on first real install: `Device_GetPropertyDataSize`'s case for
  `kAudioObjectPropertyCustomPropertyInfoList` had gone stale at 7 entries after
  `kAudioDeviceCustomPropertyAppEQ` became the 8th custom property, silently making AppEQ
  undiscoverable via property introspection and crashing `BGMApp` on launch. See
  [docs/LESSONS.md](docs/LESSONS.md)'s "device-wide crash on first real install" entry.
- A data race in the real-time audio driver: `BGM_Device::DoIOOperation`'s `ProcessOutput` case
  called `ApplyClientEQ`/`ApplyClientRelativeVolume` after the mutex guarding
  `mClientEQProcessors` had already gone out of scope, racing unsynchronized against
  `AddClient`/`RemoveClient` on another thread. See [docs/LESSONS.md](docs/LESSONS.md).

### Removed

- The project's own signed `.pkg` release pipeline (`.github/workflows/build-test.yml`'s upstream
  `release` job) — this fork has no Apple Developer ID or notarization credentials configured.
  Source-build is the only supported install path for now; see the README.
