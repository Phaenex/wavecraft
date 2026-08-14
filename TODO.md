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
- **AirPlay streaming** — investigated (2026-08-12): routing an app's audio to an AirPlay receiver
  that's *already connected* (via System Settings > Sound, same as any other output device) needs
  **no new code at all**. `BGMAudioDevice::CanBeOutputDeviceInBGMApp()`
  (`BGMApp/BGMApp/BGMAudioDevice.cpp:57-73`) has no transport-type filter — it only checks
  not-BGMDevice, not-hidden, has output channels, can-be-default — so an AirPlay device (transport
  type `kAudioDeviceTransportTypeAirPlay`, the same one `BGMOutputDeviceMenuSection.mm` already
  special-cases just to show its icon) passes the same as any physical device, and
  `BGMAppOutputRoutingController::populateMenuForButton:` (`BGMAppOutputRoutingController.mm:154`)
  lists every device that passes it — no AirPlay exclusion anywhere in that path or in
  `BGMTapRoute`/`BGMPlayThrough`, both of which talk to devices through generic CoreAudio HAL APIs
  agnostic to transport type. **Confirmed by reading the actual filter logic, not by testing real
  hardware** — still needs a real AirPlay receiver to verify audibly (add to
  docs/QA-PLAN.md's routing section: connect an AirPlay device via System Settings first, then
  route an app to it from Wavecraft's per-app pop-up and confirm audio actually plays there).
  What's still genuinely missing, and would be real new scope: **initiating** a new AirPlay
  connection Wavecraft doesn't already have — that needs actual discovery (Bonjour/mDNS browsing
  for `_raop._tcp`/`_airplay._tcp` services) and connection setup, which nothing in this codebase
  does today and isn't a routing change, it's a new client protocol implementation.

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
- **Verify multi-device output routing** (added 2026-08-12, see docs/PROCESS-TAP-ROUTING.md's
  "Phase 3"). Confirmed by reading the code that `BGMTapRoute` creates one `BGMPlayThrough` per
  output device sharing the same tap, and that switching an app's target set doesn't tear down
  outputs that didn't change — never run against real hardware. Test: route one app to two
  different output devices at once, confirm both actually play its audio simultaneously (not just
  the first one, not one glitching when the other's added/removed), then click one of the two
  already-checked devices again to remove just that one and confirm the other keeps playing
  uninterrupted.
- **Verify the keyboard-shortcut recorder actually captures keys while the Preferences menu is
  open** (added 2026-08-12, `BGMHotkeyRecorderButton`). It installs a local `NSEvent` monitor,
  which is the documented-correct way to observe events during a menu's own tracking loop — but
  NSMenu is also known to intercept some keys (arrows especially, plus Return/Escape/letters) for
  its own navigation before a subview would normally see them, and there's no way to confirm from a
  non-interactive environment which one wins. If arrow keys specifically don't get captured, that's
  a real problem since they're the most likely keys someone wants to bind (they're the built-in
  defaults). Test: open Preferences > Keyboard Shortcuts, click a record button, press an arrow key
  — does the button's title actually update to show it, or does the menu's own selection move
  instead and the button stays on "Press a key…"?
- **Verify Do Not Disturb actually mutes and restores real apps** (added 2026-08-12,
  `BGMDoNotDisturb`). Confirmed by reading `SetAppVolume`/`GetAppVolumes` usage that it calls the
  same API the volume sliders use, but never run against a real running app. Test: play audio in
  two apps, enable Do Not Disturb with one as the Priority App — confirm the other actually goes
  silent (not just that its slider visually moves), launch a third app while it's still on and
  confirm it's muted immediately, then turn Do Not Disturb off and confirm all volumes return to
  what they were before, not to a default.
- **Verify the `.pkg` installer actually walks through cleanly** (added 2026-08-12, `package.sh` +
  `pkg/`). Confirmed by direct inspection: `pkgutil --expand`/`--payload-files`/`--check-signature`
  show the right files (driver, app, XPC helper, all the install scripts), the right
  `Distribution.xml` content (title, background image, bundle-version checks), and correctly "no
  signature." Never actually opened in Installer.app — no way to confirm from here whether the
  background image renders correctly, whether the "quit Wavecraft first" check works if it's
  already running, or whether the full wizard flow (password prompt timing, auto-launch at the
  end) matches what `pkg/postinstall`'s logic assumes.

- **Verify the new `BGMMainPanel`-based main dropdown, top to bottom.** The status-bar dropdown
  was rebuilt from scratch (2026-08-13) as a custom `NSPanel` instead of `NSMenu`, specifically to
  fix a real, confirmed bug (dragging a per-app volume slider closed the whole menu — see
  `docs/LESSONS.md`'s "NSMenu custom-view controls cannot prevent the menu closing on interaction"
  entry) and to add real structure to the per-app list ("Your Apps" vs. a collapsed
  "System & Other Apps" section). Confirmed only by clean local builds (all targets, Release
  analyzer pass, 47/47 `BGMAppUnitTests`) and code review — **none of the following has been
  clicked on a real running instance**: the panel actually opening/closing/positioning correctly
  below the status item; click-outside-to-dismiss, Esc-to-close, and losing-focus-closes-it all
  actually firing; dragging every slider type (master volume, per-app volume, pan, EQ band) no
  longer closing the panel (the specific bug this rewrite exists to fix); arrow-key nudging on a
  focused slider (newly possible, never tested); the "Your Apps"/"System & Other Apps" split and
  its disclosure toggle; the Preferences button correctly popping the (unchanged) Preferences
  `NSMenu` from inside the new panel; the panel's behavior across Space switches and full-screen
  apps; Option-clicking the status icon still revealing the Debug Logging row; and a full regression
  sweep of every other item already listed in this section, to confirm none of it silently broke
  from this structural change.
- **Verify `BGMSetupWindow` (added 2026-08-13, "Setup & Permissions" — see CHANGELOG.md).**
  Confirmed only by clean Debug+Release builds and 47/47 `BGMAppUnitTests` — **none of the
  following has been seen on a real screen**: the window actually auto-shows on a genuinely fresh
  install (not a reinstall over an existing one, which already has
  `hasShownSetupWindowOnFirstLaunch` set from a previous run and will correctly skip it — needs a
  full uninstall first to test the auto-show path honestly); the three rows' wrapped body text
  doesn't clip or overflow at the window's actual fitted size; both status badges reflect real
  permission state (not just the hardcoded `BGMSetupRowStatusNotGranted` they're constructed with
  before the first `refreshPermissionStatuses` call); clicking a row's button actually opens the
  right System Settings pane and the badge updates to "Granted" after returning to Wavecraft;
  `frameAutosaveName`'s remembered position survives a quit/relaunch; and reopening via Preferences
  → "Setup & Permissions…" shows live, not stale, status. Built specifically in response to real
  confusion this session ("installed no app is running" — the app and its status item were both
  actually running; a menu bar organizer, `Ice`, had the icon parked in a collapsed section) — the
  third row's copy is a hypothesis about what would have prevented that confusion, not something
  confirmed to actually help a confused user in the moment.
- **Verify the identity/rebrand pass (2026-08-13 — see CHANGELOG.md's "Changed" entry).** Confirmed
  structurally (the built binaries actually contain the new strings — checked with `strings`/
  `PlistBuddy` on a real compiled `.pkg`) and `BGMSetupWindowContentView`'s icon/amber-button
  header was actually rendered off-screen in both light and dark mode and looked right — but three
  things still need a real screen: (1) the system Microphone permission dialog actually says
  "Wavecraft" now, not "Background Music" — the fix (`CFBundleDisplayName`) is standard, documented
  behavior, but this exact project already had one confirmed miss in this area this session,
  so don't take it as proven until someone's actually seen the real dialog; (2) `system_profiler
  SPAudioDataType` / Sound settings / Audio MIDI Setup actually show "Wavecraft" as the device name
  after a real install, not a cached/stale name held over from before the rename; (3) the new
  `.pkg` installer's `<welcome>` pane (`pkg/welcome.txt`) actually renders legibly in Installer.app
  — confirmed the file and the `Distribution.xml` reference to it are structurally correct, but
  couldn't open Installer.app from this environment to see the real rendering (a `.pkg` `open`
  call fails with a Launch Services error from this tool context specifically, confirmed earlier
  this session; works fine when a real person runs the identical command).
- **Verify the `BGM` -> `WC` class/file rename (2026-08-13) with a real install.** Confirmed by
  clean Release and Debug builds of both the app and the driver, zero new warnings or analyzer
  issues, 24/24 `BGMDriverTests` and 47/47 `BGMAppUnitTests` passing (identical counts to before
  the rename), and an explicit whole-tree scan confirming zero remaining references to any of the
  107 renamed names. Not run against real audio on a real install — the driver side specifically
  (`WC_Device`, `WC_PlugIn`, etc.) is a pure rename with no logic changes, so the risk is low, but
  "the unit tests pass" and "audio actually plays correctly through a freshly rebuilt driver" are
  different claims, and this session already has one example (docs/LESSONS.md's device-wide crash
  entry) of a defect that unit tests didn't catch but a real install did.

## Fairly quick

None open right now — the last item here (arbitrary keyboard-shortcut rebinding) shipped
2026-08-12; see the "Needs a human" entry above for what's still unverified about it.

- A **Debug**-configuration build (`xcodebuild ... -configuration Debug build`, 2026-08-13) surfaced
  3 static analyzer findings that a Release build doesn't run into (this project's
  `RUN_CLANG_STATIC_ANALYZER` setting differs per configuration, so Debug is the only config that's
  actually exercised this): `BGMStatusBarItem.mm:307`, `BGMDoNotDisturb.mm:172`, and
  `BGMASApplication.m:136`, all `NullPassedToNonnull`/`NilArg`. All three are the analyzer failing
  to trace nullability through `BGM_Utils.h`'s `BGMNN()` macro (assert-and-cast, used pervasively
  across this codebase precisely because Clang's flow-sensitive nullability checks don't work
  reliably in this project's build configuration — see docs/LESSONS.md and this session's earlier
  `-Wnullable-to-nonnull-conversion` fixes) — not real bugs, and none are in code touched this
  session. Left as-is rather than "fixed" by adding redundant nil-checks the macro already
  guarantees are unreachable; flagged here so a future Debug-config analyzer run doesn't
  re-investigate the same 3 findings from scratch.

## Less quick

- **Docs still reference old `BGM`-prefixed class names** after the 2026-08-13 `BGM` -> `WC`
  rename (see CHANGELOG.md) — the rename itself was deliberately scoped to source code only, not
  prose (rewriting every class-name mention across every doc in the same pass as a system-critical
  driver rename would have been real scope creep). Rough count at rename time:
  `docs/PROCESS-TAP-ROUTING.md` (29), `TODO.md` itself (38, including entries below this one),
  `docs/QA-PLAN.md` (9), `docs/TROUBLESHOOTING.md` (3), `README.md` and `docs/GUIDE.md` (1 each).
  Also out of scope in the code rename itself, and larger/riskier than the class rename was: free
  functions, macros, and `#define` constants still carrying the old `BGM` prefix (`BGMNN()`,
  `BGMAppEQKey_BundleID`, etc.) — some of these are literal dictionary/XPC keys where the string
  *value*, not just the symbol name, may matter, so this needs more care than a straightforward
  rename, not just more time.
- Per-app output routing assignments live in the menu bar app's own process (see
  docs/PROCESS-TAP-ROUTING.md's "hybrid, not a replacement" design decision) and are only restored
  for apps that are already running when Wavecraft starts or that launch later in the same session
  — an assignment for an app that was never running during that session won't be applied
  automatically even though it's still saved. Fixing this properly would mean either watching for
  *any* app launch indefinitely (not just ones with menu rows) or moving routing state into the
  driver somehow, which conflicts with the reason routing runs in user space in the first place.
- No automated tests exist for `BGMAppOutputRoutingController`, `BGMDoNotDisturb`, or the newer UI
  classes (`BGMAVM_EQBandSlider`, `BGMAVM_OutputRouteButton`, `BGMHotkeyRecorderButton`) beyond what
  BGMTapRouteTests.mm's own comment says is structurally possible — checked directly (2026-08-12) by
  reading `Mock_CAHALAudioObject.cpp`'s `GetPropertyData`/`SetPropertyData` switch statements rather
  than assuming: they implement a small fixed set of selectors (music-player bundle ID, a couple of
  device properties) and hit `Mock_Unimplemented()` (which aborts the test process) for anything
  else, including every app-volume/main-volume-control property `BGMHotkeys`, `BGMDoNotDisturb`, and
  `BGMTroubleshootMenu` actually call. So this genuinely can't be worked around by writing a test
  the usual way — confirmed, not just assumed. This matches upstream's own testing gap for
  `BGMAppVolumesController`/`BGMOutputDeviceMenuSection`/`BGMPreferredOutputDevices`, none of which
  have unit tests either, but it's worth flagging rather than assuming coverage exists.
  - **One piece of this did get extracted and covered**: `BGMAppOutputRoutingController`'s
    multi-output device-set reconciliation (added 2026-08-12, alongside multi-output routing) was
    pulled out into `BGMComputeOutputDeviceDiff` (`BGMOutputDeviceDiff.{h,cpp}`) specifically
    because it's pure `std::vector<AudioObjectID>` set-difference logic with no HAL dependency at
    all — unlike the *action* of actually adding/removing a `BGMTapRoute` output, which still needs
    real hardware. 8 tests in `BGMOutputDeviceDiffTests.mm` cover it fully. Same technique (find the
    pure-logic slice of an otherwise-untestable class, extract it, test that) is worth trying again
    if a similar seam turns up in `BGMTroubleshootMenu` or elsewhere — most of what those classes do
    is genuinely HAL-bound, but not necessarily all of it.
- Same testing gap applies to `BGMHotkeys` and `BGMTroubleshootMenu` — both depend on real system
  state (`AXIsProcessTrusted()`, `NSWorkspace.frontmostApplication`, `AudioObjectSetPropertyData`
  against a real `BGMDevice`, `AVCaptureDevice` authorization status) that the mocked
  `BGMAppUnitTests` target can't exercise, for the same reason `BGMTapRouteTests.mm` explains.
- Upstream's `release` job (building a *signed* `.pkg` in CI) was already removed from
  `.github/workflows/build-test.yml` (see that file's own top comment and CHANGELOG.md's
  "Removed" section) — it needs an Apple Developer ID and notarization credentials this fork
  doesn't have configured. `package.sh` (revived and rebranded 2026-08-12, see CHANGELOG.md) builds
  the same *unsigned* `.pkg` locally, run by hand rather than in CI — attaching one to a GitHub
  Release today means running `./package.sh` locally and uploading the resulting
  `Wavecraft-<version>/Wavecraft-<version>.unsigned.pkg` by hand. Re-adding a CI job that does this
  automatically on a tag push would be a reasonable follow-up, but wasn't built now: it can't be
  verified without an actual GitHub Actions run, and getting a broken workflow file merged silently
  (only failing the next time someone tags a release) is worse than not having the automation yet.
- **Preferences still has two controls in the same interaction-risk class** the main dropdown's
  rewrite (2026-08-13, see `docs/LESSONS.md`) fixed everywhere else: the two Auto-pause Delay
  sliders and the four `BGMHotkeyRecorderButton` keyboard-recording buttons, both still hosted as
  custom `NSMenuItem` views in the (unchanged, still-`NSMenu`-based) Preferences submenu. Neither
  has ever been confirmed to actually exhibit the closing-on-interaction bug — this isn't a known
  regression, just an unclosed risk — but given the main dropdown's identical symptom turned out to
  be a real, unfixable-at-the-control-level `NSMenu` ceiling, both should be treated as suspect
  until verified on a real install. If confirmed, the fix is the same one already proven out for the
  main dropdown: move them into a small `NSPanel`-based panel of their own (or into `BGMMainPanel`
  itself, behind the Preferences button) rather than attempting another per-control workaround.
