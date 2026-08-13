<!-- vim: set tw=120: -->

# QA plan — first real install

Nothing in this file has been run yet. It exists so that the moment Wavecraft is actually
installed (`./build_and_install.sh`, the one step that needs a human at a terminal — see
CLAUDE.md), there's a concrete, ordered plan to execute instead of improvising, and so gaps are
tracked instead of silently skipped. Check items off (or file them as known issues in
[TODO.md](../TODO.md)) as they're actually verified — don't mark anything done from reading the
code, only from watching it happen.

Once installed, the right way to execute the "click every state" sections is a Sonnet subagent
doing find-and-fix with real screenshots (`screencapture`, since this is native macOS menu bar UI,
not a browser) — not eyeballing the code and assuming it's fine.

## 0. Install sanity (do first, blocks everything else)

- [ ] `./build_and_install.sh` completes without error
- [ ] `system_profiler SPAudioDataType` shows the Wavecraft/Background Music device
- [ ] `launchctl print system/com.bearisdriving.BGM.XPCHelper | grep "state = running"` — **not**
      plain `launchctl list` (see docs/TROUBLESHOOTING.md for why that gives a false negative)
- [ ] `ps aux | grep "Background Music"` shows the app running
- [ ] Menu bar shows the new four-bar icon, not the old three-ring one — if it's still the old one,
      the install picked up a stale build; re-run the script
- [ ] First-run explanation dialog appears *before* the system Microphone prompt, reads clearly,
      and clicking Continue actually triggers the real system permission prompt next
- [ ] Granting Microphone access completes launch without crashing (this is also where the
      `kAudioObjectPropertyCustomPropertyInfoList` crash fix gets its first real test — confirm the
      per-app menu populates for every running app, not just that the app stays open)
- [ ] Denying Microphone access shows the error dialog with a working **Open Privacy Settings**
      button that jumps to the right System Settings pane, then quits cleanly
- [ ] Quit and relaunch Wavecraft a second time — the first-run explanation should **not** show
      again, and access should be requested (and already granted) silently
- [ ] `tools/verify-icons.py` passes (checks pixel dimensions of `AppIcon.appiconset` against
      `Contents.json`)

## 1. Critical path — the three headline features actually work

This is the minimum bar before claiming any of this session's work "works," not just "builds."

- [ ] **Per-app volume**: pick a currently-playing app, drag its slider down — audibly quieter.
      Drag to max — audibly louder than system volume alone. Mute button silences it; unmute
      restores the exact prior level.
- [ ] **Per-app EQ**: pick a playing app with sustained tone content (music, not silence), expand
      its row, drag the 31Hz band to -12dB — audible bass cut on *that app only*, not on anything
      else playing simultaneously. Drag +12dB on 4kHz — audible presence boost. Confirm all 10
      bands are visible and correctly labeled, laid out as two clean columns (31/62/125/250/500Hz
      on the left, 1/2/4/8/16kHz on the right), not clipped or overlapping. **Also confirm clicking
      or dragging any slider — main volume, pan, or any EQ band — never closes the menu or
      collapses the row** (a real bug reported against the original single-column 10-band layout,
      most likely caused by the taller row pushing the menu into needing to scroll; the two-column
      redesign keeps the row at its original height specifically to avoid this, but needs a real
      check with several apps' rows expanded at once, not just one). Return all 10 bands to 0 —
      audio returns to how it sounded before touching EQ (this is the actual claim from
      `BGM_BiquadTests::testZeroGainIsExactUnity`; verify it holds for real audio, not just the
      unit test's synthetic signal).
- [ ] **Per-app output routing**: with two output devices connected (e.g. built-in speakers +
      headphones/AirPods), route one playing app to the non-default device via its pop-up. Confirm:
      - Audio from the routed app comes out the *new* device
      - Audio from every other app still comes out the *original* default device
      - The routed app's audio does **not** also play through the original device (this is
        `CATapMuted`, flagged as unverified since Phase 1 of docs/PROCESS-TAP-ROUTING.md — this is
        the first real chance to confirm it)
      - Selecting "Default" again sends it back to the normal path audibly

## 2. Full menu sweep

Every control, once, confirming it does what the code says it does:

- [ ] Output volume slider (top of menu) changes system output level
- [ ] System sounds slider changes UI/alert sound volume independent of app volumes
- [ ] Per-app pan slider audibly shifts an app's stereo image left/right
- [ ] "Show more controls" arrow expands/collapses correctly, rotates direction, and the row's
      height changes without clipping any control
- [ ] Output Device list shows every connected device, correctly checkmarks the current one, and
      switching updates system audio with no dropout beyond the expected brief glitch
- [ ] AirPlay device (if available) shows its icon in the device list
- [ ] "More Apps" submenu correctly bins background/accessory apps separately from regular ones
- [ ] Preferences → Status Bar Icon: switching to the volume-meter icon changes the menu bar glyph
      and reflects actual volume level; switching back restores the four-bar icon
- [ ] Preferences → auto-pause: selecting each supported music player
      (Music/Spotify/VLC/VOX/Decibel/Hermes/Swinsian/GPMDP that's actually installed) and
      confirming play/pause actually triggers auto-pause when other audio starts/stops
- [ ] Preferences → pause delay / max unpause delay sliders visibly change and the setting
      persists (quit and reopen Preferences to confirm)
- [ ] About panel opens, shows correct version/license text, closes cleanly
- [ ] Option-click on the status bar icon reveals the hidden debug logging menu item; toggling it
      changes logging verbosity in Console.app
- [ ] Quit reverts the system default output device to what it was before Wavecraft launched

## 3. New-feature edge cases

- [ ] EQ: rapid slider dragging produces no clicks/pops (tests the change-detection gate in
      `BGM_Biquad::SetAllBandGainsDB` — it should only call `SetParameters`, which resets filter
      state, for bands whose value actually changed)
- [ ] EQ: an app with non-flat EQ set quits and relaunches — does the driver still have the old
      gains for that bundle ID, and does the menu show them correctly on the new process, including
      the show-more-controls arrow's highlight (confirm it's on immediately on the freshly-created
      row, not just after touching a slider)
- [ ] EQ/Pan: the show-more-controls arrow highlights when either has a non-default value and
      returns to normal when both are back to default, both at row-creation time (restored from a
      previous session) and live while dragging a slider with the row already open
- [ ] Routing: the routed app's name in the main menu shows the route indicator icon immediately
      after picking a device, and it disappears immediately after picking "Default" or using
      "Remove All Output Routing Overrides" — check both with the menu already open (does it update
      without closing and reopening?) and freshly opened
- [ ] Routing: unplug the device an app is currently routed to, while it's routed — confirm the
      route clears automatically (audio falls back to the default output, not silence) within a few
      seconds, the persisted assignment is still there (not lost), and reconnecting the device and
      reselecting it from the pop-up restores the route
- [ ] Routing: quit and relaunch the *routed app* (not Wavecraft) — audio should still be routed
      correctly afterward, unattended (this is the actual point of `processRestoreEnabled`)
- [ ] Routing: quit and relaunch *Wavecraft itself* — the assignment should be gone from the
      running state (by design, see TODO.md's known limitation) but still show as persisted next
      time that app's row exists — confirm the UI doesn't lie about which one is true
- [ ] Routing: on a system below macOS 26 (if one's available to test on), confirm the pop-up
      shows the specific "Per-app output routing needs macOS 26 or later" message (`BGMTapRoute::
      kMacOSTooOld`), not a generic/confusing CoreAudio error code
- [ ] Routing: route two different apps to two different non-default devices simultaneously —
      confirm neither route interferes with the other or with the default-output apps
- [ ] AppleScript: from Script Editor, get and set `volume`, `pan`, `EQ band gains`, and
      `output device` of a running app via `tell application "Background Music"` — confirm each
      round-trips correctly and that setting `output device` actually starts a route (audible, and
      visible via the new route indicator) the same as using the pop-up would

## 4. Regression check against upstream behavior

Nothing in this fork should have made stock Background Music functionality worse:

- [ ] Recording system audio via QuickTime (select Wavecraft/"Background Music" as input device)
      still works
- [ ] An aggregate device combining a real mic + the Wavecraft device still records both
- [ ] Volume above 50% still clips as documented (confirms nothing changed the known clipping
      behavior unexpectedly)
- [ ] If a genuinely multichannel (>2 channel) output device is available, confirm the documented
      2-channel-only limitation still reproduces the same way, not some new failure mode

## 5. Troubleshooting paths (the app's own error handling)

- [ ] Rename/remove the driver and launch the app — get the "could not find the virtual audio
      device" dialog with correct instructions, not a crash
- [ ] Force BGMXPCHelper to not be running and launch the app — get the XPC connection error
      dialog, app still partially functional per its own degraded-mode design
- [ ] Trigger a failed output-device change (e.g. by disconnecting a device mid-switch) — confirm
      the error alert and revert-on-failure behavior described in `BGMAudioDeviceManager`

## 6. In-app troubleshooters, keyboard shortcuts, and customization (added 2026-08-12)

None of this has run against a real install either — same rule as everything else on this page.

- [ ] Preferences → Troubleshoot → **Reapply Default Output Device**: change your system default
      output to something other than Wavecraft, then run this — confirm it switches back without
      needing System Settings
- [ ] Preferences → Troubleshoot → **Reset All App Volumes, Pan & EQ**: set a non-default
      volume/pan/EQ on at least one app, run this (confirm the alert), confirm every app's controls
      visibly return to their defaults and the audio matches
- [ ] Preferences → Troubleshoot → **Remove All Output Routing Overrides**: route at least one app to a
      non-default device, run this (confirm the alert), confirm the app's audio returns to the
      default output and its pop-up shows "Default" again
- [ ] Preferences → Troubleshoot → **Reconnect to BGMXPCHelper**: kill `BGMXPCHelper` manually, run
      this, confirm the app recovers connection without requiring a full relaunch
- [ ] Preferences → Troubleshoot → **Check Microphone Permission**: with permission denied, confirm
      this jumps to the correct System Settings pane (`x-apple.systempreferences:` URL scheme
      actually resolves on this macOS version, not just in theory)
- [ ] Preferences → Keyboard Shortcuts → **Enable Keyboard Shortcuts** with Accessibility not yet
      granted: confirm the one-time explanation dialog appears before the system Accessibility
      prompt, and that toggling the switch off and back on after granting access actually starts
      monitoring (there's no completion callback for this permission — confirm the documented
      "toggle it again" workaround is actually necessary and actually works)
- [ ] Keyboard Shortcuts: with shortcuts enabled and Option as the modifier, confirm ⌥↑/⌥↓ change
      system volume and ⌥⇧↑/⌥⇧↓ change the frontmost app's volume — audibly, not just that the
      sliders move
- [ ] Keyboard Shortcuts: switch to Control as the modifier, confirm the old Option binding stops
      working and the new Control one works immediately (no re-enable needed)
- [ ] Keyboard Shortcuts: switch between Fine/Normal/Coarse step sizes and confirm each press
      changes volume by a visibly different amount, matching the description text shown in the
      menu
- [ ] Keyboard Shortcuts: confirm the shortcuts don't fire while Wavecraft itself is the frontmost
      app (there's no reason to adjust "the frontmost app's volume" when that app is Wavecraft) and
      don't interfere with the same key combination in another app that also uses it

## Reporting back

For each item: pass/fail, and for fails, exactly what happened (error text, screenshot, or
Console.app log excerpt) — not "didn't work." Anything that fails goes in TODO.md's "Needs a
human" or a new dedicated section, not silently dropped.
