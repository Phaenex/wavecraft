# Lessons

## An "open Tahoe compatibility bug" turned out to be a known, unrelated limitation

**Symptom:** [Issue #856](https://github.com/kyleneideck/BackgroundMusic/issues/856), "severe
audio choppiness" on macOS 26 (Tahoe), filed against v0.4.3, framed as possibly needing PR #852.
Read only the issue title and first-pass research would have (and initially did) flagged this as
a live, unresolved OS-compatibility risk worth worrying about before building.

**Root cause:** The reporter's output device was an 8-channel DisplayPort monitor. Background
Music has only ever supported 2-channel (stereo) output — documented in its own README under
Known Issues. Nothing to do with Tahoe.

**The fix that actually mattered:** reading the full comment thread, not just the title. The
maintainer asked one clarifying question ("do you get distortion on built-in speakers?"), the
reporter checked `system_profiler SPAudioDataType`, found 8 channels, and the issue was closed as
a known limitation within two comments. Total cost if we'd skipped this: would have gone into the
build expecting to need a Tahoe-specific patch that doesn't exist and doesn't need to.

**How to apply:** before treating a GitHub issue title as evidence of a current bug, read to the
last comment. Titles often get filed with an initial hypothesis ("possibly a Tahoe regression")
that gets falsified by the end of the thread.

## A large "official-looking" fix PR was half rejected by the maintainer for looking unverified

**Symptom:** [PR #852](https://github.com/kyleneideck/BackgroundMusic/pull/852), "Tahoe compat,"
open since April 2026, 10 commits, 915 additions, titled like the authoritative fix for Tahoe
issues. Easy to assume the right move is "apply this whole diff."

**What was actually true:** the maintainer had already reviewed it and cherry-picked six of the
ten commits — the narrow, verifiable ones (browser/Whale helper audio-routing bundle-ID fixes) —
directly into master weeks before we cloned. Those are already in the `v0.5.0` we forked from; no
patching needed. The remaining four commits (a large "aggregate device / shutdown stability"
change and two signing-script changes) are still unmerged, and the maintainer's own review comment
directly asks the PR author "What was the human involvement in writing the patch?" after noting he
could only skim it — a maintainer calling out suspected unreviewed AI-generated code in his own
project. That part correctly never landed.

**How to apply:** never treat an open PR as "the fix" without reading its review thread first.
Check `git log --all --grep '<commit message from the PR>'` against the target branch — a
maintainer may have already taken the good parts and left the rest for a reason worth reading.

## `sudo` inside a HAL driver install script cannot be scripted around, and shouldn't be

**Symptom:** `build_and_install.sh` needs `sudo` to copy the driver into
`/Library/Audio/Plug-Ins/HAL/` and reload `coreaudiod`. Running it non-interactively fails with
`sudo: a terminal is required to read the password; either use the -S option to read from standard
input or configure an askpass helper`.

**Why this isn't a bug to fix:** `coreaudiod` is a root daemon; CoreAudio HAL plugins are only
loaded from that one system-owned path, there's no per-user equivalent. Confirmed by testing the
script directly rather than assuming — see the CoreAudio HAL loading model, not a fixable script
limitation. An agent has no legitimate way past this that doesn't involve either handling the
user's actual login password (never do this) or weakening `sudo` itself (e.g. a `NOPASSWD` sudoers
entry — also never do this without being explicitly asked, and even then it's a standing security
downgrade, not a one-time convenience).

**How to apply:** any project that installs a privileged macOS driver/daemon has exactly one step
that needs a human at a real terminal. Design the rest of the workflow (build, test, verify) to be
fully autonomous so that step is the only thing blocking "done."
