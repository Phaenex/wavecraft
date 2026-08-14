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
  (`osascript -e 'tell application "Wavecraft" to get EQ band gains of application 1'` and
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
- **Verify `WCSetupWindow` (added 2026-08-13, "Setup & Permissions" — see CHANGELOG.md).**
  Update 2026-08-14: a real install-free Debug launch (built via `./build_and_install.sh -b -d`,
  run directly from `BGMApp/build/Debug/Wavecraft.app` without installing the driver, so no sudo
  needed) surfaced two real bugs, both fixed and both confirmed with real screenshots on a real
  screen after the fix — see docs/LESSONS.md's two new entries for the full writeup: (1) the
  system Microphone permission dialog was firing automatically the instant the window appeared,
  racing the user's ability to even read it, because `WCAppDelegate` called
  `requestMicrophoneAccess` itself right after showing the window instead of waiting for the
  window's own "Grant Access" button — fixed with a `microphoneAccessGrantedHandler` completion
  block the window fires only from its own button-click/permission-refresh path; (2) the window
  was landing pinned to the screen's bottom-left corner `(0, 0)` on every first-ever show, not
  centered, because `frameAutosaveName` was set before the window's initial layout pass, causing
  its own `setContentSize:` resize to auto-save a never-positioned frame that `setFrameUsingName:`
  then immediately "restored" — fixed by deferring `frameAutosaveName` until after the window's
  initial position is actually resolved. Now confirmed on a real screen: the window auto-shows on
  first launch, is genuinely centered, no system dialog appears before a button click, and both
  status badges correctly show "Not Granted" on fresh state with no visible text clipping.
  Update 2026-08-14, later the same day: the user's own real `.pkg` install (not a Debug test run)
  confirmed the microphone completion-handler fix works end to end with a live, first-ever grant,
  not just the already-granted-at-set-time path — the badge correctly showed "✓ Granted" after
  clicking through the real system dialog. Also confirmed real, user-reported feedback that the
  window read as too small/cramped (460pt wide, 11pt body text) — widened to 560pt with larger
  fonts throughout (title 24pt, row titles 16pt, body 14pt, regular-sized buttons instead of
  small) and reconfirmed readable via screenshot after rebuilding.
  **Still not seen on a real screen**: `frameAutosaveName`'s remembered position surviving a
  quit/relaunch *after* the user has actually moved the window (only the fresh-launch/no-saved-
  frame path was tested); and reopening via Preferences → "Setup & Permissions…" shows live, not
  stale, status. Built specifically in response to real confusion this session ("installed no app
  is running" — the app and its status item were both actually running; a menu bar organizer,
  `Ice`, had the icon parked in a collapsed section) — independently reconfirmed 2026-08-14 that
  `Ice` is still running on this dev machine and still does exactly this, so the third row's copy
  addresses a real, currently-reproducible condition on this machine, though whether the copy
  itself actually resolves a real user's confusion in the moment is still unconfirmed.
- **Accessibility permission shows under a stale "Background Music.app" entry in System
  Settings, and toggling it does nothing for the real app** (found 2026-08-14 on the user's real
  `.pkg` install). **Update, same day, root cause now confirmed** (see docs/LESSONS.md's
  "relocatable pkg component" entry): `/Applications/Background Music.app` was never actually
  replaced by any install this session — `pkg/pkgbuild.plist`'s relocatable-bundle handling kept
  upgrading its *contents* in place under its old folder name, every single install, because it
  matches by bundle ID (via Launch Services) rather than by path. Since it's the exact same bundle
  that's existed (never deleted, just repeatedly overwritten) since before this session's rename,
  TCC's cached display name for it — the same caching mechanism as the already-documented
  `CFBundleDisplayName` Microphone bug — is stale for every permission service checked against it,
  not just Microphone. No code bug in `updateAccessibilityRow`/`AXIsProcessTrustedWithOptions`.
  **Second update, same day**: the `pkg/preinstall`-only fix above did *not* actually work — a
  second real install still landed at the old path, confirmed again via `ps`. Root cause revised
  (see docs/LESSONS.md's follow-up on the same entry): `BundleIsRelocatable: true` on the app
  component means Installer resolves the real install location via Launch Services' bundle-ID
  registration during its own planning, which a `preinstall`-side deletion can't reliably race
  against. Real fix: `BundleIsRelocatable: false` in `pkg/pkgbuild.plist` (matching what the driver
  component already used), removing bundle-ID-based placement entirely so the component always
  installs at the literal path. `pkg/postinstall`'s launch step also reordered to try the explicit
  path before bundle-ID lookup. **Still needs, after the next real install** (now genuinely
  untested — this exact combination has never been run for real): (1) confirm the app actually
  ends up at `/Applications/Wavecraft.app` this time (`ps -p <pid> -o command`, not just
  Installer.app's success screen, and not just "it opened" since a stale copy opening looks
  identical from the outside); (2) confirm the old `/Applications/Background Music.app` is
  actually gone afterward; (3) `tccutil reset Accessibility com.bearisdriving.BGM.App` (and
  possibly Microphone too, to fully clear old records), run by a human; (4) confirm both badges
  reflect a live grant afterward.
- **`BGMAppUITests` fails locally, 3/3 tests, all with `Element StatusItem ... is not hittable`**
  (found 2026-08-14 running `xcodebuild test` on the `Wavecraft` scheme, which runs both
  `BGMAppUnitTests` and `BGMAppUITests` — `BGMAppUnitTests` itself is unaffected, 47/47 still
  pass). Root cause confirmed directly: `Ice` (a menu bar organizer, already running on this dev
  machine) collapses Wavecraft's status item into its hidden section, same as the real user
  confusion `WCSetupWindow`'s third row exists for — the failing element's reported frame
  (`x = -4180`) matches Ice's off-screen-park convention exactly. Not a regression from anything
  changed 2026-08-14 (neither of that day's fixes touch `WCStatusBarItem` or status-item
  visibility) — but also not independently confirmed to have been passing *before* that day's
  changes, since no baseline run was captured first. Needs: (1) confirm on a machine without a
  menu bar organizer running (or with Ice's "keep visible" list including Wavecraft) that this
  suite passes cleanly, to fully rule out a real regression; (2) decide whether CI should guard
  against exactly this (a runner with a menu bar organizer installed would hit the identical
  failure) — e.g. detecting a running menu bar organizer and skipping/xfailing rather than a hard
  failure.
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
- **Verify `Wavecraft.app` (2026-08-13) with a real install and real clicks, not just a build.**
  Confirmed structurally: `package.sh` end to end produced a `.pkg` whose payload is genuinely at
  `Applications/Wavecraft.app` (checked via `pkgutil --expand-full`, not assumed), the executable
  inside is named `Wavecraft`, `CFBundleIdentifier` is unchanged, and every `-scheme`/`tell
  application`/`ps` reference this pass could find was updated and re-verified with a fresh
  full-tree grep. What that can't confirm: that a real install actually opens without a Gatekeeper
  surprise specific to the new name, that AppleScript scripts (`docs/GUIDE.md`'s examples,
  `BGMAppUITests.mm` if it's ever actually run — it's skipped on GitHub Actions) really do address
  "Wavecraft" successfully rather than silently failing to find the app, and that
  `_uninstall-non-interactive.sh`'s dual-path check (new `Wavecraft` fallback dir, old `Background
  Music` one) actually cleans up an install that used the *old* fallback path — that specific case
  needs an install made before this rename to test against, which doesn't exist on this machine.

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
