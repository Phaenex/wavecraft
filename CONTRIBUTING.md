<!-- vim: set tw=120: -->

# Contributing

Thanks for reading this. Pull requests, bug reports, feature requests, and questions are all
welcome, including from non-developers.

## Issues

Update to the latest code before filing an issue — `git pull && ./build_and_install.sh` is fastest.

For bug reports about `build_and_install.sh`, include `build_and_install.log` (saved in the same
directory as the script).

It can help to include logs for bugs in Wavecraft itself. They go to syslog by default, so
Console.app can read them (search for "Wavecraft" or "BGM" — the bundle identifier and some
internal constants still start with `BGM`, so either term can turn up relevant lines). Release
builds only log errors and warnings by default. For more detail, install a debug build with
`./build_and_install.sh -d`
and include those logs instead.

If you're planning to fix or implement something yourself, say so in the issue first so we can
confirm you're on the right track before you put the work in.

## Code

The code is C++ and Objective-C (and Objective-C++ where they mix, e.g. anything with a `.mm`
extension). [DEVELOPING.md](DEVELOPING.md) has an overview of the architecture and instructions for
building/debugging — worth reading before diving into the code, though
[BGMAppDelegate.mm](BGMApp/BGMApp/BGMAppDelegate.mm) is a reasonable place to start browsing if you
prefer to learn by reading.

This fork's two additions, if you're looking for where they live:

- **Per-app EQ** — DSP in `BGMDriver/BGMDriver/DeviceClients/BGM_Biquad.*`, the device property in
  `BGMBackgroundMusicDevice::GetAppEQ`/`SetAppEQBandGains`, and the UI in
  `BGMApp/BGMApp/BGMAppVolumes.{h,m}` (`BGMAVM_EQBandSlider`).
- **Per-app output routing** — the engine in `BGMApp/BGMApp/BGMTapRoute.{h,mm}`, the controller in
  `BGMApp/BGMApp/BGMAppOutputRoutingController.{h,mm}`, and the UI in `BGMAppVolumes.{h,m}`
  (`BGMAVM_OutputRouteButton`). Read [docs/PROCESS-TAP-ROUTING.md](docs/PROCESS-TAP-ROUTING.md)
  first — the design decisions there (why routing runs in the app's own process, not the driver)
  aren't obvious from the code alone.

If you add a substantial amount of code, add a copyright notice with your name to the files you
changed. Say so in the PR if you've deliberately left one out.

## Before opening a PR

- `xcodebuild ... -only-testing:BGMAppUnitTests test` and `-only-testing:BGMDriverTests test` (see
  [CLAUDE.md](CLAUDE.md) for the exact commands) should both pass. Neither needs `sudo` or an
  installed driver.
- If you touched anything CoreAudio-device-facing, note in the PR whether you were able to test it
  against real hardware — a lot of this codebase (this fork's `BGMTapRoute` included) can't be
  exercised in the unit test targets at all, since they link mocked `CAHALAudioDevice` objects. See
  `BGMTapRouteTests.mm`'s comment for the specifics.

## Core Audio background

If you have questions about Core Audio itself, the [Core Audio mailing
list](https://lists.apple.com/archives/coreaudio-api) is useful, along with Apple's [Core Audio
Overview](https://developer.apple.com/library/mac/documentation/MusicAudio/Conceptual/CoreAudioOverview/Introduction/Introduction.html)
and [Core Audio
Glossary](https://developer.apple.com/library/mac/documentation/MusicAudio/Reference/CoreAudioGlossary/Glossary/core_audio_glossary.html).
