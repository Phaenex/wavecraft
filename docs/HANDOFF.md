# Handoff — 2026-08-14

Written at the end of a long session that: (1) finished the Wavecraft identity/rebrand sweep,
(2) verified and fixed real bugs in the new Setup & Permissions window, (3) found and fixed real
install-pipeline bugs (`.pkg` installing to the wrong path, an indefinite install hang, missing
TCC cleanup, a `tput` crash in the uninstaller), and (4) audited and fixed real layout bugs in the
new `NSPanel`-based main dropdown. Everything below is either **confirmed with direct evidence**
or **explicitly marked as not yet confirmed** — see [LESSONS.md](LESSONS.md) for the full story
behind each fix if you need it, and [TODO.md](../TODO.md) for the complete, blow-by-blow list this
file is distilled from.

## Where things stand right now

- **Currently installed**: `/Applications/Wavecraft.app`, running (confirmed via `ps` at time of
  writing), built from commit `8346926`.
- **Latest commit on `master`**: `7222557` — two commits ahead of what's installed
  (`19aa511` tccutil-output-visibility, `7222557` the `tput` crash fix). Neither of those two
  affects the installed app itself, only the uninstall scripts run from this source tree, so
  there's no urgency to reinstall just for them.
- **The one `.pkg` that exists right now**: `Wavecraft-0.5.0-SNAPSHOT-8346926/Wavecraft-0.5.0-SNAPSHOT-8346926.unsigned.pkg`.
  Rebuild with `./package.sh` if you want one built from the latest commit — cheap, no `sudo`
  needed, takes a couple minutes.

## Correct commands (get these wrong and you'll waste time — happened twice tonight)

```bash
cd /Users/damato/Projects/wavecraft

# Uninstall -- NEVER prefix this with sudo. The script elevates internally where it needs to.
# Running the whole thing as root breaks tput under some terminal emulators (confirmed: Ghostty)
# and produces no useful error, just a dead script and no output.
./uninstall.sh

# Build a fresh .pkg from the current commit (no sudo needed):
./package.sh

# Install -- opens Installer.app, which prompts for your password itself when it needs to:
open "Wavecraft-0.5.0-SNAPSHOT-<commit>/Wavecraft-0.5.0-SNAPSHOT-<commit>.unsigned.pkg"
```

Don't test against ad-hoc debug builds (`build_and_install.sh -b -d` launched directly) for
anything permission-related — confirmed multiple times tonight that this causes real, confusing
cross-talk with the real install (different on-disk builds share the same bundle ID, so TCC and
`NSUserDefaults` state bleeds between them). If you do need a throwaway test build for something
UI-only (not permissions), launch it with `--args --no-persistent-data` so it can't pollute the
real app's `NSUserDefaults` domain.

## Fixed and verified with real evidence tonight (screenshots, `ps`, reproduced failures)

- App bundle rename fallout: `Background Music.app` → `Wavecraft.app` install path,
  `ORGANIZATIONNAME`, `package_release.sh`, stale comments. Multiple full-tree sweeps, all clean.
- Setup window: premature Microphone permission dialog (fired before the user clicked anything),
  window landing at screen origin `(0,0)` instead of centered, window too small/cramped.
- `.pkg` installing into the old `Background Music.app` folder instead of creating
  `Wavecraft.app` (root cause: `BundleIsRelocatable: true`, fixed by turning it off).
- `pkg/postinstall` hanging indefinitely on `./ListInputDevices` (a `AVCaptureDevice` call that
  can wait forever on a TCC decision with no UI context to resolve it) — now hard-timed-out at 5s.
- `uninstall.sh` dying on `tput: unknown terminal "xterm-ghostty"` when run with `sudo`.
- `tccutil reset` now runs as part of every uninstall — confirmed working via real "Successfully
  reset" output, not just added and assumed.
- Main panel: master output volume row rendering on top of the Auto-pause row (wrong fixed-height
  container for a 47pt view).
- Main panel: "Your Apps" list had no scroll view and no height cap at all (unlike the `NSMenu` it
  replaced) — found via a direct code audit, not a user report. Fixed with a capped scroll view.

## NOT yet verified — needs a human, in priority order

1. **The main panel itself has never actually been clicked on the current, fully-fixed build.**
   Specifically unverified: does the volume-row overlap fix actually look right now; does the
   scrollable apps list actually scroll and cap correctly with your real app count; does dragging
   any slider (master volume, per-app, pan, EQ band) still avoid closing the panel (the original
   bug the whole `NSPanel` rewrite exists to fix); does the Preferences button correctly pop its
   menu from inside the panel; Space-switching and full-screen-app behavior.
2. **Setup window didn't visibly appear after the most recent fresh install**, even though the
   evidence (`LastShownSetupWindowVersion` correctly recorded) shows the code path to show it did
   run. Leading theory: `Installer.app`'s own post-install "Summary" page focus-grab is winning a
   race against the new window's own activation. Not confirmed. See TODO.md's matching entry for
   the full detail and what to check next.
3. **The "Setup window closes right after granting Microphone" report from earlier tonight** is
   still unresolved — never cleanly reproduced against the real installed app specifically (the
   report happened while a debug test build and the real app were both in play). Leading
   hypothesis: a modal "Error connecting to BGMXPCHelper" alert firing at exactly that moment,
   which would only happen if BGMXPCHelper isn't actually reachable. Needs a clean repro.
4. **Accessibility badge live-update**: does it actually flip to "✓ Granted" immediately after
   clicking "Grant Access" and completing the real AXIsProcessTrustedWithOptions flow, now that
   `tccutil reset` genuinely clears old state first?
5. Everything else already catalogued in TODO.md's "Needs a human" section — real audio routing,
   per-app EQ, Do Not Disturb, the keyboard-shortcut recorder, multi-device output routing, etc.
   None of that was touched tonight; it was already unverified before this session and still is.

## Suggested next session's first move

Fresh `./uninstall.sh` (no sudo) → fresh `open` on a freshly-built `.pkg` → **don't touch
anything** until the Setup window either appears or doesn't, so item 2 above gets a clean,
unambiguous answer before anything else. Then walk both permission rows through a real grant
cycle, checking badges update live. Then, only once permissions are confirmed clean, open the
main panel and go through item 1's checklist — that's the one nobody has actually clicked yet on
this final build.
