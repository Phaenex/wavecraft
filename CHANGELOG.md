<!-- vim: set tw=120: -->

# Changelog

This documents Wavecraft's changes on top of the upstream [Background
Music](https://github.com/kyleneideck/BackgroundMusic) v0.5.0 base it was forked from. It doesn't
duplicate upstream's own history — see [upstream's
releases](https://github.com/kyleneideck/BackgroundMusic/releases) for that.

## Unreleased

### Added

- **Per-app EQ.** A 5-band equalizer (60Hz/250Hz/1kHz/4kHz/12kHz, ±12dB) per running app, alongside
  the existing volume/pan controls.
  - Driver: DSP core (`BGMDriver/BGMDriver/DeviceClients/BGM_Biquad.*`), the
    `kAudioDeviceCustomPropertyAppEQ` device property, and real-time application in
    `BGM_Device::ApplyClientEQ`.
  - App: `BGMAVM_EQBandSlider` in `BGMApp/BGMApp/BGMAppVolumes.{h,m}`, wired to
    `BGMBackgroundMusicDevice::SetAppEQBandGains`/`GetAppEQ`.
- **Per-app output routing.** Send an individual app's audio to a different physical output device
  than everything else, via CoreAudio Process Taps — not possible in upstream's single-virtual-
  device architecture. See [docs/PROCESS-TAP-ROUTING.md](docs/PROCESS-TAP-ROUTING.md) for the full
  design.
  - `BGMTapRoute` (`BGMApp/BGMApp/BGMTapRoute.{h,mm}`) — the per-app tap/aggregate-device/
    `BGMPlayThrough` engine.
  - `BGMAppOutputRoutingController` — owns routing assignments, persists them, and restores them
    for running apps.
  - `BGMAVM_OutputRouteButton` — the per-app output-device pop-up in the menu.
  - Requires macOS 26.0+ (`CATapDescription.processRestoreEnabled`); everything else in Wavecraft
    still targets macOS 10.13+.
- Native Apple Silicon (`arm64`) build from source — the reason this fork exists at all. Upstream's
  official release binary runs under Rosetta on Apple Silicon
  ([issue #395](https://github.com/kyleneideck/BackgroundMusic/issues/395)); building from source
  with a current Xcode does not have this problem.
- A monochrome menu-bar status icon and custom app icon, replacing upstream's Fermata mark — see
  [docs/LESSONS.md](docs/LESSONS.md) for why (the original read as a microphone/recording icon at
  status-bar size).

### Changed

- `BGMPlayThrough` generalized to accept a non-`BGMDevice` input (`SetRequireBGMDeviceInput`), so
  `BGMTapRoute` can reuse its ring-buffer/clock-sync engine instead of reimplementing it.

### Removed

- The project's own signed `.pkg` release pipeline (`.github/workflows/build-test.yml`'s upstream
  `release` job) — this fork has no Apple Developer ID or notarization credentials configured.
  Source-build is the only supported install path for now; see the README.
