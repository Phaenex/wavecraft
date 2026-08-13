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

## Phase 2: the routing engine and UI (2026-08-12)

`BGMApp/BGMApp/BGMTapRoute.{h,mm}` is the per-app engine this doc predicted: a `CATapDescription`
with `bundleIDs` + `muteBehavior = CATapMuted`, wrapped in a private aggregate device, driving a
`BGMPlayThrough` (generalized in the same change to accept a non-`BGMDevice` input via
`SetRequireBGMDeviceInput(false)`, so the already-proven ring-buffer/clock-sync code is reused
rather than reimplemented) that writes to whichever physical device the user picked. `Start()`/
`Stop()` clean up whatever actually got created, even on a partial failure.

One addition beyond the original design: `CATapDescription.processRestoreEnabled = YES`. Without
it, a tap only lives as long as the process that owned the bundle ID at `Start()` time -- quit and
reopen the routed app and routing would silently stop working until the user reselected it in the
UI. With it (macOS 26.0+, same gate as `bundleIDs`), the tap reattaches to whichever process
currently owns the bundle ID, so an assignment survives the target app being quit and relaunched.

`BGMAppOutputRoutingController` (`BGMApp/BGMApp/BGMAppOutputRoutingController.{h,mm}`) owns the
bundle-ID → `BGMTapRoute` map and is the thing the UI actually talks to:

- Each app's menu item has a `BGMAVM_OutputRouteButton` pop-up (`BGMApp/BGMApp/BGMAppVolumes.{h,m}`)
  listing "Default" plus every output device `BGMOutputDeviceMenuSection` would offer BGMApp's own
  output, rebuilt fresh from `CAHALAudioSystemObject` every time it's about to open
  (`NSMenuDelegate.menuNeedsUpdate:`), so it can't go stale between a device being plugged in and
  the button being clicked.
- Starting/stopping a route runs on the controller's own serial background queue --
  `BGMPlayThrough::Start()` blocks waiting for IO, the same way `BGMAudioDeviceManager`'s own
  `startPlayThroughSync` does, and that can't happen on the main thread without hanging the menu.
- Assignments persist in `BGMUserDefaults.outputRouteDeviceUIDsByBundleID` (bundle ID → device
  UID, matched back to a connected `AudioObjectID` the same way `BGMPreferredOutputDevices` matches
  its preferred-device list) and are restored for apps that are running whenever
  `NSWorkspace.runningApplications` reports them -- both at `BGMApp` launch and later in the
  session, so an assignment for an app that wasn't open yet at launch still gets applied once it
  starts.

**What Phase 2 does not cover**: the `CATapMuted` question flagged as open at the end of Phase 1
(does muting the source app's normal output actually work) is still unverified by anything other
than reading the header's documented behavior -- confirming it needs `./build_and_install.sh` (the
one step that always needs a human) and a real listening test with two apps and two output
devices. Nothing here has been run against real hardware yet; what's verified so far is that the
whole thing builds clean and the driver-side `BGM_BiquadTests`/`BGM_ClientsTests`,
`BGMAppUnitTests`'s `BGMTapRouteTests`, and the full BGMApp/BGMDriver/BGMXPCHelper build all pass
-- see the "Build & test" section in `CLAUDE.md`.

## Phase 3: multiple output devices per route (2026-08-12)

TODO.md's "Feature parity" list flagged this as needing real design work, not a simple hookup --
`BGMTapRoute` originally hard-coded exactly one output device (and one `BGMPlayThrough`) per tap.

**The key fact that makes this tractable without a second tap per output**: a CoreAudio device
supports multiple independent `IOProcID`s reading its captured audio simultaneously -- the same
mechanism that lets several apps record from one microphone at once. The tap/aggregate device is
the expensive, per-app resource (it's what actually mutes the source app and captures its audio);
the *output* side is "just" a `BGMPlayThrough` writing that same captured audio to one physical
device. So `BGMTapRoute` now owns a `std::vector` of `{device, BGMPlayThrough}` pairs all reading
from the *same* aggregate input device, instead of exactly one. `Start()` creates the tap and
mutes the app but plays through nothing yet; `AddOutputDevice()`/`RemoveOutputDevice()` manage the
output list independently, so adding a second device to an already-running route doesn't tear down
and recreate the tap (which would mean a moment of the app's audio not being muted, then muted
again) -- it just adds one more `BGMPlayThrough` sharing the existing capture.

`BGMAppOutputRoutingController` changed from "one device UID per bundle ID" to "an array of device
UIDs per bundle ID" throughout: `BGMUserDefaults.outputRouteDeviceUIDsByBundleID` is now
`NSDictionary<NSString*, NSArray<NSString*>*>*` (an empty/missing array means Default, matching the
old nil-means-Default convention). `applyRouteForBundleID:deviceUIDs:appName:` *diffs* the desired
device set against a route's actual current outputs (`BGMTapRoute::GetOutputDevices()`) rather than
tearing the whole route down and rebuilding it on every change -- switching from `{A, B}` to
`{A, C}` only touches `B` and `C`, leaving `A`'s `BGMPlayThrough` running untouched, so its audio
doesn't glitch for no reason.

**UI decision, deliberately conservative**: the per-app output-device pop-up
(`BGMAVM_OutputRouteButton`) still uses the plain `NSPopUpButton`-driven "click a device, menu
closes" interaction it already had -- clicking now *toggles* that device in the target set instead
of replacing it, so selecting more than one device is several individual clicks (reopen the
pop-up, pick the next one), not a single persistent multi-select gesture. A "stays open, check
several boxes at once" checklist would need custom-view menu items with their own click handling
that doesn't dismiss the menu -- exactly the category of AppKit menu interaction that caused the
per-app EQ's real menu-closing bug this same session (see docs/LESSONS.md), and which isn't
confirmed fixed yet. Reusing the existing, already-built click-and-close interaction avoids
stacking a second unverified menu-interaction risk on top of the first. Revisit this once the
two-column EQ fix (or lack thereof) is actually confirmed against a real running menu.

AppleScript's per-app `output device` property became `output devices` (a list) --
`BGMASApplication.outputDevices`/`setOutputDevices:` replace the old singular
`outputDevice`/`setOutputDevice:`. `BGMApp.sdef`'s `pRte` property code is unchanged (same
underlying property, now list-typed) so existing compiled `.sdef` references to it by code aren't
broken, only the name/cocoa-key changed.

**Nothing about the underlying mechanism (mute behavior, `processRestoreEnabled`, tap creation)
changed** -- multi-output only affects the output side. The same Phase 2 caveat still applies in
full: `CATapMuted` is still unverified against real hardware, and now so is the specific multi-
output claim that two devices really do play the same audio simultaneously without one glitching
the other. See TODO.md's "Needs a human" section.
