# Lessons

## BGMAppUnitTests links a mocked CoreAudio HAL for the whole target, not per-test

**The trap:** wrote a real-hardware functional test for `BGMTapRoute` (create a real tap +
aggregate device, route Finder's audio to a real output device, assert it started and stopped
cleanly). It crashed instantly: `Crash: xctest at Mock_Unimplemented(char const*).
libsystem_c.dylib: abort()`. The instinct was to assume the *test* was wrong (bad device lookup,
wrong API usage) and start debugging that.

**What was actually true:** `BGMAppUnitTests` (see `BGMAppTests/UnitTests/Mocks/`) links
`Mock_CAHALAudioSystemObject.cpp` and `Mock_CAHALAudioDevice.cpp` **in place of** the real
implementations for the entire target — not opt-in per test, not something `MockAudioObjects`
layers on top of real objects. Every `CAHALAudioDevice`/`CAHALAudioSystemObject` call in any test
in this target hits the mock, including a call on a **real** `AudioObjectID` from a **real**
aggregate device just created via `AudioHardwareCreateAggregateDevice` — the mock has no idea that
ID exists and aborts rather than silently misbehaving. `BGMPlayThroughTests.mm` never hits this
because it explicitly registers everything through `MockAudioObjects::CreateMockDevice` first.

**How to apply:** before writing a test in `BGMAppUnitTests` that touches any device object
(`CAHALAudioDevice`, `CAHALAudioSystemObject`, or anything built on them like `BGMAudioDevice`),
assume it's mocked and check `BGMAppTests/UnitTests/Mocks/` for how existing tests register the
objects they need, rather than reaching for a real device by ID and finding out the hard way.
`AudioHardwareCreateProcessTap`/`AudioHardwareCreateAggregateDevice` (raw HAL entry points, not
methods on the mocked classes) aren't mocked and do create real system objects — but anything
downstream that touches them via `CAHALAudioDevice` (which `BGMPlayThrough` does extensively) will
still crash. There's currently no way to test that full pipeline inside this target; it needs
either an out-of-target harness or manual verification through actual use.

**Root cause diagnosis, not guesswork:** confirmed by reading `Mock_CAHALAudioSystemObject.cpp`'s
existence and the crash's own `Mock_Unimplemented` symbol name, not by trial and error on the test
code itself. The fix was recognizing the test was asking the wrong environment to do something it
architecturally can't, not finding a bug in the test's logic.

## Per-app EQ filter state must not live where BGM_Client gets copied

**The trap:** `BGM_ClientMap::GetClientRT` (and the rest of the existing per-client access
pattern for volume/pan) works by copying a `BGM_Client` out by value. That's fine for
`mRelativeVolume`/`mPanPosition` — plain floats, cheap and correct to copy. It is NOT fine for a
biquad EQ's delay-line state (`x1/x2/y1/y2` in `BGM_Biquad`): that state has to persist
sample-to-sample across audio callbacks, and copying it into a temporary that gets thrown away
after `GetClientRT` returns would silently reset the filter's memory on every single IO callback
(buffers are ~10ms at 48kHz). The bug this produces isn't "the EQ sounds slightly off" — it's a
periodic discontinuity at every buffer boundary, an actual audible artifact, and it would pass a
naive test that only checks "does the gain end up roughly right," because the coefficients would
still be correct even while the state resets are corrupting the audio.

**How to apply:** split *persisted parameters* (what the user set — safe to store in `BGM_Client`,
safe to copy, safe to read back via a property) from *live processing state* (delay-line memory,
anything a real-time filter needs to remember between calls — must be owned somewhere that isn't
copied every callback, e.g. directly by `BGM_Device` in a map keyed by client ID, looked up by
reference, never by value). Whenever adding real-time DSP state to a per-client system that was
built around copy-by-value access, check how existing per-client data is actually retrieved before
assuming the same pattern works for anything with persistent internal state.

**Also:** when the persisted gain value changes (user moves a slider), the filter's coefficients
need updating, which `BGM_Biquad::SetParameters` implements by resetting delay state (to avoid a
worse artifact: continuing with stale state from a different filter is a bigger discontinuity than
one deliberate, momentary reset). So the processing loop needs a change-detection check — only
call `SetParameters` for bands whose target gain actually changed since the last call — not
reapply on every callback, or the filter would never settle into steady state at all.

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

## Growing a collapsible XIB menu-item view: shift everything by the same delta

**The trap:** the per-app volume menu item's "extra controls" (Pan, now also EQ and the
output-route pop-up) work by the row's `NSMenuItem.view` collapsing from a full height down to
`kAppVolumeViewInitialHeight` (20pt) via `menuItem.view.frameSize = NSMakeSize(width, 20)`, relying
on every subview's `flexibleMinY` autoresizing mask to keep it pinned to a fixed *distance from the
top* as the view shrinks. Adding new rows below the existing ones by just placing them at more
negative Y and bumping the view's declared frame height looks reasonable, but if only the new
elements' Y values are set and the existing (top-pinned) elements' Y values are left alone, their
distance-from-top changes, since that distance is `(new height) - y - subviewHeight` — everything
above the new rows shifts position.

**The fix:** pick a `Δ` (in this case 100pt, enough for 5 EQ sliders + a device pop-up), add it to
the customView's declared frame height, and add the *same* `Δ` to every existing subview's Y —
including ones that were already working (icon, name, volume slider, mute button, show-more
button, Pan slider, Pan L/R labels). This keeps `(height) - y - subviewHeight` constant for all of
them by construction, so the collapse/expand behavior needs no changes at all — new elements just
occupy the newly-available Y range below the old bottom-most element, and get pushed off-view by
the exact same runtime logic that already hides Pan on collapse.

**How to apply:** when adding rows to any view that uses this top-pinned-subviews-collapse-by-
shrinking-height pattern (springs-and-struts, not Auto Layout), never touch only the new elements'
frames. Recompute the whole block by adding one delta to the container height and to every existing
child's Y, so the invariant the collapse logic depends on (constant distance-from-top) provably
still holds instead of being re-verified by hand for each element.

## `-Wnullable-to-nonnull-conversion` is `-Werror` here, and ObjC array literals aren't static consts

**The trap:** two separate build failures while adding `BGMAppOutputRoutingController.mm` and the
`BGMAVM_EQBandSlider` tooltip labels, neither obvious from the symptom alone:

1. Passing a `__nullable`-declared local into a method expecting a non-null param — even directly
   after an `if (!x) return;` guard, or inside an `x && [x foo:y]`-style short-circuit — still
   produced `error: implicit conversion from nullable pointer ... to non-nullable pointer type
   [-Werror,-Wnullable-to-nonnull-conversion]`. Clang's flow-sensitive narrowing for this warning is
   much weaker than for e.g. `-Wnullable-to-nonnull-conversion`'s cousin diagnostics in Swift-facing
   code; don't assume an early return or a guarded `&&` is enough to silence it. Also hit on
   `NSString.UTF8String` (declared `_Nullable` in Foundation) being assigned straight into a
   `std::string`, which isn't an Objective-C object and so can't use the `BGMNN()` macro at all.
2. `static NSArray<NSString*>* const kEQBandFreqLabels = @[ @"60 Hz", ... ];` at file scope failed
   with `error: initializer element is not a compile-time constant`. A single `@"literal"` string
   is a compile-time constant in Objective-C; an `@[...]` array literal is not (it's sugar for a
   runtime `+arrayWithObjects:...:` call), so it can't initialize a file-scope `static` in a plain
   `.m` file (this would compile in Objective-C++ under different rules, but `BGMAppVolumes.m` is
   plain Objective-C).

**The fix:** for (1), use `BGMNN(expr)` (Objective-C objects) or `BGM_Utils::NN(expr)` (anything
else, e.g. `const char*`) from `BGM_Utils.h` to explicitly assert-and-cast at the exact call site
that's complaining, rather than trying to restructure control flow to satisfy the narrowing
analysis. For (2), use a plain C array (`static const char* const arr[] = {...}`) plus a
`sizeof(arr)/sizeof(arr[0])` count constant (a genuine compile-time constant), and box individual
elements with `@(arr[i])` at the point of use instead of trying to make the whole collection a
static Objective-C object.

**How to apply:** in this codebase, treat every `__nullable`-typed value as needing an explicit
`BGMNN`/`BGM_Utils::NN` at each point it's handed to something non-null-typed, regardless of how
"obviously" non-null it is by that point in the code. And never reach for an `@[]`/`@{}` literal as
a file-scope static initializer in a `.m` (only `.mm`, and even then prefer a function-local static
via `dispatch_once` or a lazy accessor over relying on C++ static-init ordering).

## A legacy `project.pbxproj` needs new files added to *every* target that compiles the referencing source, not just the "obvious" ones

**The trap:** added `BGMAppOutputRoutingController.h/.mm` to the `Background Music` (app) and
`BGMAppUnitTests` targets — the same two targets `BGMTapRoute.h/.mm` already belonged to, which
seemed like the complete, correct set by precedent. The build failed at the *link* step for a
third target, `BGMAppUITests`, with `Undefined symbols ... "_OBJC_CLASS_$_BGMAppOutputRoutingController",
referenced from: ... in BGMAppDelegate.o`.

**What was actually true:** `BGMAppUITests` (a `com.apple.product-type.bundle.ui-testing` target)
independently lists `BGMAppDelegate.mm` in its own Compile Sources build phase — it compiles the
app delegate itself, not just launching the built `Background Music.app` and driving it via
Accessibility APIs the way UI tests are often assumed to work. So the instant `BGMAppDelegate.mm`
started referencing a new class (to wire up the routing controller), every target that separately
compiles `BGMAppDelegate.mm` needed that new class's `.mm` linked in too — and transitively,
`BGMTapRoute.h/.mm` as well, since `BGMAppOutputRoutingController.mm` references it and `BGMTapRoute`
had never been added to `BGMAppUITests` either (it was never needed there before, since nothing
`BGMAppUITests` compiled referenced it).

**How to apply:** before assuming "these two targets" is the complete set for a new file, check
target membership of the file whose *import* is changing (here, `BGMAppDelegate.mm`), not just the
file that's new — `proj.targets.select { |t| t.source_build_phase.files.any? { |f|
f.file_ref&.path == "BGMAppDelegate.mm" } }` via the `xcodeproj` Ruby gem lists every target that
needs the new symbol. When a link fails with an undefined `_OBJC_CLASS_$_X` referenced from a file
that isn't `X` itself, the fix is target membership, not code.

## Hand-editing `project.pbxproj`: use the `xcodeproj` Ruby gem, not text edits

**Context:** this project's `.xcodeproj` uses the legacy explicit-file-reference format (every
source file needs a `PBXFileReference` + one `PBXBuildFile` per target it's compiled in + a listing
in the right `PBXGroup` and `PBXSourcesBuildPhase`), not Xcode's newer synchronized-folder groups.
Adding a new file by hand-editing the XML-adjacent plist text risks malformed UUID references or
missed listings that don't fail cleanly (Xcode silently ignores an orphaned `PBXFileReference` with
no corresponding `PBXBuildFile`, so a broken addition can look fine until the file's symbols are
actually needed).

**How to apply:** the `xcodeproj` gem (already installed via `gem list -i xcodeproj`, ships with
CocoaPods tooling that's common on machines with Xcode) does this correctly:
`group.new_reference(fname)` for the file reference, then `target.source_build_phase
.add_file_reference(fref)` per target. It also diffs cleanly — `git diff --stat` on this project's
`project.pbxproj` showed exactly the expected new lines (file ref + build file entries + group/
phase listings) with zero reordering or reformatting of unrelated content, which is worth
confirming after every automated edit to this file since a full reformat would make the diff
unreviewable.

## Renaming a Claude-Code-tracked project directory orphans its memory and settings

**The trap:** asked to rename this project's directory to fit a naming scheme, the obvious move is
just `mv`. But Claude Code keys a project's memory, conversation history, and (per this machine's
sandbox policy) its permission/settings allowlist by the project's *exact filesystem path* —
visible directly in this session's own memory directory,
`~/.claude/projects/-Users-damato-Projects-mac-volume-mixer/memory/`, and in the sandbox's
`denyWithinAllow` list, which hardcodes paths like
`/Users/damato/Projects/mac-volume-mixer/.claude/settings.local.json`.

**What actually happens on rename:** none of that is renamed or migrated automatically. A `mv` to a
new path means Claude Code treats the new location as an unconnected project going forward — this
project's existing memory files, past conversation history, and any project-specific settings tied
to the old path are orphaned, not carried over. The `mv` itself is safe for the repo (git doesn't
care about its containing directory's name, and an already-open shell's cwd follows the rename via
inode rather than breaking, though any *other* shell or tool holding the old path string as text
will fail until it re-resolves).

**How to apply:** before renaming any project directory, surface this consequence explicitly and
let the user decide, rather than treating "rename the folder" as a purely mechanical filesystem
operation — the two options (rename and accept the history split, or keep the path and rebrand only
in-repo naming/docs) have very different costs and only the user can weigh them.
