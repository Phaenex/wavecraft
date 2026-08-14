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
- **Per-app output routing.** Send an individual app's audio to one or more physical output
  devices, independent of everything else's output, via CoreAudio Process Taps — not possible in
  upstream's single-virtual-device architecture. See
  [docs/PROCESS-TAP-ROUTING.md](docs/PROCESS-TAP-ROUTING.md) for the full design.
  - `BGMTapRoute` (`BGMApp/BGMApp/BGMTapRoute.{h,mm}`) — the per-app tap/aggregate-device engine,
    one `BGMPlayThrough` per output device sharing the same tap (added 2026-08-12, "Phase 3" —
    originally exactly one device per route). Distinguishes macOS-too-old, target-device-vanished,
    and generic CoreAudio failures when `Start()`/`AddOutputDevice()` throw, so the error alert
    names the actual cause.
  - `BGMAppOutputRoutingController` — owns routing assignments (now per bundle ID an array of
    device UIDs, not a single one), persists them, restores them for running apps, and watches for
    a routed device disconnecting mid-route (drops just that device from the route, keeping any
    others playing and the persisted assignment so it reapplies if the device reconnects). The
    multi-output device-set reconciliation logic is extracted into `BGMComputeOutputDeviceDiff`
    (`BGMOutputDeviceDiff.{h,cpp}`) and covered by 8 unit tests — it's pure set-difference math with
    no HAL dependency, unlike the rest of this class.
  - `BGMAVM_OutputRouteButton` — the per-app output-device pop-up in the menu. Clicking a device
    toggles it into/out of the app's target set instead of replacing it, so routing to more than
    one device is a few individual clicks.
  - Routed apps are marked in the main menu (an icon appended to the app's name) so a route is
    visible without opening that app's row.
  - Requires macOS 26.0+ (`CATapDescription.processRestoreEnabled`); everything else in Wavecraft
    still targets macOS 10.13+.
- **AppleScript support for per-app EQ and output routing** — `BGMASApplication` gained
  `eqBandGains` and `outputDevices` (a list, more than one item routes to all of them at once)
  properties, alongside the existing `volume`/`pan`.
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
  the permission isn't required for the app's core function). Each of the four actions (system
  volume up/down, frontmost app volume up/down) is independently rebindable to any key + modifier
  combination via a click-to-record button (`BGMHotkeyRecorderButton`), not limited to a fixed
  Option/Control preset — conflicting bindings are rejected with an explanation. A step size
  (Fine/Normal/Coarse) still applies to all four. **Untested**: whether the record button's local
  event monitor actually captures keys — especially arrows — while it's competing with the
  Preferences menu's own tracking loop for the same events; see docs/QA-PLAN.md.
- An interactive first-run install flow — a welcome dialog explaining why Wavecraft needs
  "Microphone" access *before* the system permission prompt appears, an "Open Privacy Settings"
  button on denial, and a guided `build_and_install.sh` with a clearer preamble/epilogue about what
  the script actually does.
- [docs/QA-PLAN.md](docs/QA-PLAN.md) — an ordered checklist for verifying a fresh install actually
  works, covering every menu control and new-feature edge case, not just "does it build."
- **Do Not Disturb** (`BGMApp/BGMApp/BGMDoNotDisturb.{h,mm}`, **Preferences > Do Not Disturb**) —
  mutes every running app except one chosen "priority" app, the inverse of the existing auto-pause
  feature (which pauses one specific known music-player app; this works with any running app).
  Forces every non-priority app to `kAppRelativeVolumeMinRawValue` via the same per-app-volume API
  the volume sliders use, remembering each app's own volume to restore on disable. A newly-launched
  app while it's on gets muted immediately via an `NSWorkspace.runningApplications` KVO observer.
  Resumes automatically on next launch if left enabled.
- Two prebuilt-release install paths for people without Xcode, instead of building from source:
  - **`package.sh`** (revived and rebranded from upstream's own release pipeline, which this fork
    had left un-rebranded and unused) builds a real `.pkg` installer via `pkgbuild`/`productbuild`
    — the normal Introduction/License/Install/Summary flow any other Mac software uses, driven by
    `pkg/Distribution.xml.template` (title, background image) and `pkg/preinstall`/`pkg/postinstall`
    (installs the driver and `BGMXPCHelper`, restarts `coreaudiod`, waits for the device to actually
    appear before declaring success, then opens Wavecraft). This is the recommended path.
  - **`package_release.sh`**/`install_prebuilt.sh` build a zip containing a double-clickable
    `.command` script instead, for anyone who'd rather see exactly what's happening in a terminal
    window than click through an installer wizard.
  - Neither is signed or notarized (no paid Apple Developer ID configured for this project yet), so
    both the installer and the app it installs show a Gatekeeper warning the first time; the
    README's "Installing a prebuilt release" section explains why and exactly what to click.
- **A "Setup & Permissions" window** (`BGMSetupWindow`) listing everything Wavecraft needs from the
  system in one place — Microphone access (required, for the virtual audio device), Accessibility
  access (optional, only for global keyboard shortcuts), and a tip about menu bar organizer apps
  (Bartender, Ice, Hidden Bar, etc.) potentially hiding a newly-installed icon in a collapsed
  section, which looks identical to "didn't launch" but isn't — the exact confusion that motivated
  adding this row, hit for real on this session's own test install. Each permission row shows live
  granted/not-granted status (refreshed on open and again when Wavecraft regains focus, e.g. after
  returning from System Settings) and a button that does the actual thing for its current state —
  triggers the real system permission request when it's never been asked, or deep-links to the
  right Privacy & Security pane once it has been and was declined (asking again after a decline
  doesn't re-prompt, so those need to be different actions, not just different labels). Shown
  automatically before anything else touches a system permission, the first time each new version
  launches — not gated on a one-time "ever shown" flag, so a version bump (including, for now,
  every distinct rebuild) shows it again, since that's exactly when new requirements are most
  likely to appear. Also reachable anytime from Preferences → "Setup & Permissions…". Has its own
  visual identity — the app icon, a "Welcome to Wavecraft" header, and the same amber accent color
  as the README's own graphics on its action buttons — rather than looking like a generic system
  dialog. Previously all of this was only ever explained reactively — a one-time alert right before
  the system prompt, or an error dialog on denial — with nowhere to go back and see the whole
  picture, and nothing anywhere addressed the menu-bar-visibility confusion at all.
- **A `<welcome>` pane in the `.pkg` installer.** `Distribution.xml.template` previously only had
  `<background>`/`<license>`, so Installer.app's Introduction page showed no branded content at
  all — it went straight to Destination Select. Now explains what Wavecraft is, exactly what the
  installer sets up, and what to expect (an admin password prompt, a brief audio interruption from
  the `coreaudiod` restart, the new Setup & Permissions window right after).

### Changed

- **"Wavecraft" is now the name macOS itself shows, not just the docs.** Every system-facing name
  was still literally "Background Music" — the exact text in Finder, Activity Monitor, and the
  system Microphone permission dialog itself. `CFBundleDisplayName` (the key TCC/system dialogs
  actually read) is now set to "Wavecraft" on the app and "Wavecraft Helper" on the XPC helper; the
  Microphone/Apple-Events permission-prompt body text, the About panel's header and copyright, and
  the project/issue-tracker/contributors URLs baked into error dialogs (previously pointing at
  upstream's repo, meaning bug reports from Wavecraft users would have gone to the wrong tracker)
  all follow. The CoreAudio device's own display name — what shows in System Settings > Sound and
  Audio MIDI Setup, arguably the single most-seen piece of identity in the whole app — is now
  "Wavecraft" too (`WC_Device.h`'s `kDeviceName`). Deliberately unchanged: the bundle identifiers
  (`com.bearisdriving.BGM.*`), the `.app` folder/executable name, and the device's persistent UID
  (`kBGMDeviceUID`) — renaming any of those would make macOS treat existing installs as a different
  app (losing granted permissions) for no user-visible benefit. See CLAUDE.md's "Verifying after
  install" section for why its own troubleshooting commands now intentionally grep for two
  different names on adjacent lines.
- **The `BGM` class/file prefix throughout the codebase is now `WC`** (`BGMAppDelegate` ->
  `WCAppDelegate`, `BGM_Device` -> `WC_Device`, and 105 others) — the code's own internal identity
  now matches "Wavecraft" the same way the user-facing strings above do. Scoped deliberately to
  class/protocol/struct names and the files matching them, not the much larger (and in places
  riskier — some are literal dictionary/XPC keys where the string value, not just the symbol name,
  matters) surface of free functions, macros, and `#define` constants still carrying the old
  prefix; not the bundle identifiers, launchd/XPC service labels, Xcode scheme/workspace names, or
  the device UID string values, all left alone for the same "everything else references this exact
  string" reasons as the identity work above. See docs/LESSONS.md for two real bugs caught and
  fixed during the rename itself (a silently-truncated bulk edit from an unquoted file-list
  substitution, and a category file's compound name slipping past exact-match file renaming).
- `BGMPlayThrough` generalized to accept a non-`BGMDevice` input (`SetRequireBGMDeviceInput`), so
  `BGMTapRoute` can reuse its ring-buffer/clock-sync engine instead of reimplementing it.
- Per-app EQ grew from 5 bands (60Hz/250Hz/1kHz/4kHz/12kHz) to 10 (the standard ISO octave-band
  spread) — `BGM_AppEQ::kNumBands`/`kBandCenterFreqs` (`BGM_Biquad.h`) and `kBGMAppEQNumBands`
  (`SharedSource/BGM_Types.h`), plus 5 more slider/label pairs added to `MainMenu.xib`.
- The 10-band EQ's layout, from one column of 10 to two columns of 5, restoring the expanded row to
  its original height. A real install reported that clicking any slider in an expanded app row
  closed the whole menu; the working theory at the time (unconfirmed) was that the single-column
  layout's 51% taller row pushed the menu into needing to scroll. That turned out not to be the
  real cause — see the main dropdown rearchitecture below, which found and fixed the actual
  underlying issue (an `NSMenu` limitation, not a row-height/scrolling one). The two-column layout
  itself is still worth keeping on its own merits.
- **The main status-bar dropdown is now a custom window (`BGMMainPanel`), not an `NSMenu`.** Built
  to fix a real, confirmed bug (see Fixed, below) and to add actual structure to the per-app list:
  a "Your Apps" section (regular apps, always visible) and a collapsed "System & Other Apps"
  section (System Sounds + accessory/background apps), instead of one flat undifferentiated list.
  All the existing per-app controls (mute, volume, pan, EQ, output routing), the master volume/
  System Sounds sliders, and the Output Device list moved into it essentially unchanged. Preferences
  stays exactly as it was — a real `NSMenu`, now popped up from a button in the new panel instead of
  being a native submenu of the retired dropdown — since none of its content shares the interaction
  risk that motivated replacing the *main* dropdown specifically (two exceptions noted in
  `TODO.md`). See [docs/LESSONS.md](docs/LESSONS.md).

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
- An uncaught-exception crash confirmed on a real install: `BGMDeviceControlSync`'s property
  listener (`BGMDeviceListenerProc`, invoked on a CoreAudio-owned thread) called
  `CopyVolumeFrom`/`CopyMuteFrom` with no exception handling, unlike every other CoreAudio call
  site in the same class. Reachable whenever a previous install's app process survives a driver
  reload (see the next entry) and its cached device object goes stale — now wrapped in
  `BGMLogAndSwallowExceptions`, matching its siblings.
- `build_and_install.sh`/`pkg/postinstall` didn't quit an already-running copy of the app before
  restarting `coreaudiod` and swapping in the new driver. The old process survived the swap, kept a
  now-stale CoreAudio object reference from before the reload, and crashed (see the entry above)
  the next time something touched it — confirmed via a real reinstall cycle. Both scripts now quit
  the running app first.
- The bug the main dropdown rearchitecture (above) exists to fix: dragging the per-app volume
  slider closed the whole menu. Confirmed via direct `NSLog` instrumentation on a real install that
  this wasn't a lost-tracking race (an earlier custom `mouseDown:` workaround ran to completion
  correctly every time) — `NSMenu` closes itself on any interaction's mouse-up regardless of what a
  custom view does with that event, a real AppKit ceiling with no per-control fix, independently
  confirmed by an unrelated app (MonitorControl) hitting the identical failure mode in production.
  See [docs/LESSONS.md](docs/LESSONS.md).
- A full-project pass over the main menu, Preferences, both installers, and the troubleshooting
  tooling, prompted by "what does someone actually see the moment they click this" rather than
  feature-by-feature testing:
  - `install_prebuilt.sh` called `post_install.sh` in a way that made every prebuilt install fail
    100% of the time — the script's third positional arg (where it finds the resources to copy)
    was never actually passed, only set as an env var `post_install.sh` doesn't read. Also
    Gatekeeper-unblocks the installed XPC helper (daemons are silently blocked on macOS 14+, no
    click-through dialog like GUI apps get) and replaces a flat `sleep 5` after the `coreaudiod`
    restart with a real poll for the device reappearing.
  - `pkg/postinstall` had a bare `# TODO: Fail the install and show an error message if this
    fails` with no actual check on the main install step — it now fails loudly (GUI alert +
    non-zero exit) instead of silently continuing.
  - The main menu's routed-app indicator (an icon next to a routed app's name) and a related
    alignment tweak were dead code — `menuWillOpen:` told rows apart by subview count, which no
    longer matched either row type after earlier layout changes. Replaced with a real identity
    check (`NSRunningApplication` in `representedObject`).
  - Do Not Disturb's muted-apps set didn't survive an app relaunch, and Troubleshoot's "Reset All
    App Volumes, Pan & EQ" would silently un-mute anything Do Not Disturb was actively muting —
    persisted the mute set and taught the reset to skip DND-owned apps.
  - The per-app output-routing pop-up rendered as normal, clickable UI on macOS < 26 even though
    the underlying engine requires 26+ (it just silently didn't work) — now gated with the same
    `@available` check `BGMTapRoute` itself uses, disabled with an explanatory tooltip below 26.
    Also: a route that failed left the UI still showing the requested device instead of
    reconciling back to what's actually running.
  - The Preferences hotkey-recorder buttons and step-size rows didn't actually disable when
    hotkeys were turned off — `NSMenuItem.enabled` doesn't propagate to a custom-view menu item's
    own control, so they stayed clickable while looking disabled. See
    [docs/LESSONS.md](docs/LESSONS.md).
  - Leftover "Background Music" branding in a few accessibility labels/menu items, a dead
    permanently-disabled button on the System Sounds row, and a couple of XIB layout overlaps.

### Removed

- The project's own signed `.pkg` release pipeline (`.github/workflows/build-test.yml`'s upstream
  `release` job) — this fork has no Apple Developer ID or notarization credentials configured.
  Source-build is the only supported install path for now; see the README.
