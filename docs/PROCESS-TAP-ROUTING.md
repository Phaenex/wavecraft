# Per-app output routing via CoreAudio Process Taps

## Why this exists

BGM's existing architecture (one virtual HAL device, all apps' audio summed into one buffer by
the OS before BGM ever sees it — see `BGM_Device.cpp` `kAudioServerPlugInIOOperationProcessOutput`
vs `WriteMix`) can't route individual apps to different physical output devices. `BGMPlayThrough`
has exactly one `mOutputDevice`. That's not a missing feature, it's the architecture: by the time
BGM's driver gets the mixed buffer, per-app separation is already gone.

Real per-app routing needs a different primitive: **CoreAudio Process Taps**
(`AudioHardwareCreateProcessTap`, macOS 14.2+), which captures a specific process's audio directly
rather than relying on the OS routing everything through one shared virtual device.

## Verified API surface (read directly from the SDK on this machine, not from memory)

SDK: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`

- `CoreAudio.framework/Headers/AudioHardwareTapping.h`:
  `AudioHardwareCreateProcessTap(CATapDescription*, AudioObjectID*)` — macOS 14.2+.
  `AudioHardwareDestroyProcessTap(AudioObjectID)`.
- `CoreAudio.framework/Headers/CATapDescription.h`:
  - `CATapMuteBehavior`: `CATapUnmuted` (default) / `CATapMuted` (silences the process's normal
    output — the primitive we need so a routed app doesn't also play through the default device) /
    `CATapMutedWhenTapped`.
  - `bundleIDs` property — tap by bundle ID directly. **macOS 26.0+ only.** Nick is on 26.5.1, so
    this is available, but don't assume it on an older target without checking.
  - `processRestoreEnabled` — macOS 26.0+, re-attaches the tap to a bundle ID's process across
    relaunches. Useful so a routing assignment survives quitting/reopening the app.
  - `initWithProcesses:andDeviceUID:withStream:` / `initExcludingProcesses:...` — older
    (macOS 12+), PID/AudioObjectID-based, for anywhere `bundleIDs` isn't available.
- `CoreAudio.framework/Headers/AudioHardware.h`:
  - `kAudioAggregateDeviceTapListKey` = `"taps"` — aggregate device creation dictionary key, a
    sub-tap-list.
  - `kAudioSubTapUIDKey` = `"uid"` — the tap's UID (from `kAudioTapPropertyUID`) goes here.
  - `kAudioAggregateDeviceTapAutoStartKey` = `"tapautostart"`.
  - `kAudioTapPropertyUID` / `kAudioTapPropertyDescription` / `kAudioTapPropertyFormat` — tap
    object properties, `kAudioTapClassID = 'tcls'`.

## Pipeline

1. Build a `CATapDescription` for the target app's bundle ID, `muteBehavior = CATapMuted`.
2. `AudioHardwareCreateProcessTap` → get the tap's `AudioObjectID`, read `kAudioTapPropertyUID`.
3. Create an aggregate device via the existing `kAudioAggregateDeviceTapListKey` /
   `kAudioSubTapUIDKey` dictionary keys, with the tap's UID as a sub-tap.
4. Run an IOProc against that aggregate device — this is architecturally identical to what
   `BGMPlayThrough.cpp` already does against BGM's virtual device, just a different source.
5. Apply our own volume/EQ in this same read loop (runs in `BGMApp`'s own process — user space,
   not the root-owned driver — so bugs here don't risk system audio the way a driver bug would,
   and iterating doesn't need a driver reinstall, just relaunching the app).
6. Write the processed audio to whichever physical output device the user assigned that app to,
   the same way `BGMPlayThrough` already writes to a physical device.

## Design decision: hybrid, not a replacement

Apps with no explicit routing assignment keep going through BGM's existing, tested,
driver-based per-app volume/pan (and the EQ we're adding there). Only apps explicitly assigned to
a non-default output device get pulled out via a tap, muted at the source, and re-played through
our own per-app engine. This means:

- No changes needed to the existing driver for routing to work.
- The higher-risk root-level driver code stays exactly as tested.
- The new, less-tested routing code runs in user space and can be iterated on by just relaunching
  `BGMApp` — no `sudo`, no driver reinstall, no `coreaudiod` restart — until it's solid.

## Open risk to verify empirically before building the full feature

Process taps capture another app's audio — privacy-sensitive, likely gated the same way Screen
Recording is (System Settings → Privacy & Security). This isn't documented in the framework
headers (TCC consent is enforced by `tccd` at runtime, not declared in `CoreAudio.framework`), so
don't assume either way. **Phase 1 is a minimal proof-of-concept specifically to find out**: does
`AudioHardwareCreateProcessTap` succeed for an ad-hoc-signed local build, does macOS prompt for a
new permission the first time, and where does that permission live if so.

## Phase 1 results (2026-08-12)

`tools/tap-poc/tap_poc.mm` — standalone CLI, no Xcode project needed, built directly with
`clang++ -fobjc-arc`. Supports tapping by bundle ID (macOS 26+ `CATapDescription.bundleIDs`) or by
PID (translated to an `AudioObjectID` via `kAudioHardwarePropertyTranslatePIDToProcessObject`,
using the older `CATapDescription.processes` array — works on any macOS 12+ that has the tapping
API at all, and doesn't require the target to be a bundled `.app`).

Tested against `afplay` (slowed to `-r 0.1` for a sustained ~8s tone, no bundle ID, so this
exercised the PID path) on this ad-hoc "linker-signed" build, zero extra codesigning:

- `AudioHardwareCreateProcessTap` succeeded immediately. **No TCC/permission prompt appeared, no
  hang, no new System Settings entry needed.** This was the biggest open risk in the design doc
  and it's resolved — building on this API does not need a Developer ID cert or a new privacy
  category grant, at least for this local, unsigned-except-ad-hoc case.
- Aggregate device creation via `kAudioAggregateDeviceTapListKey` / `kAudioSubTapUIDKey` worked as
  documented in the headers.
- The IOProc received real audio: 576,512 frames over 6 seconds, 573,212 of them non-silent
  (99.4%), peak `|sample|` 0.198. Not synthetic, not assumed — measured.
- **Not yet verified**: whether `CATapMuted` actually suppressed `afplay`'s normal output during
  the capture. Isolating that cleanly needs either a second tap on the real output device to
  compare against, or a human listening during the test. Deferred to Phase 2, where the full
  per-app `PlayThrough`-equivalent will make this directly audible during normal use anyway.

Conclusion: the architecture in this document is sound and buildable. Proceeding to Phase 2 (the
per-app PlayThrough engine) is justified by real, measured evidence, not just the API reading.
