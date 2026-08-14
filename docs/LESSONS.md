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

## A device-wide crash on first real install: two functions that must agree on a count, silently didn't

**Symptom:** the very first real install of the per-app EQ work crashed `BGMApp` on launch, every
time, non-deterministically-looking from the outside (it happened deep inside a KVO callback for
`NSWorkspace.runningApplications`, which made it *look* like a race condition or an app-launch
timing bug). The crash log's own stack-walk was actively misleading: symbolicating the Release
binary's addresses by hand pointed at unrelated functions (`BGMAppDelegate menuWillOpen:`,
`BGMAVM_PanSlider setUpWithApp:...`, `BGMOutputDeviceMenuSection dealloc`) that don't call each
other and had nothing to do with the real cause. **Don't trust hand-symbolicated addresses from an
optimized Release binary as ground truth** — they can look plausible and still be wrong.

**What actually found it:** relaunching the crashing binary directly from Terminal (rather than via
LaunchServices) to capture live stderr, which printed the one thing that mattered:
`Uncaught CAException. Error code: 'who?' (2003332927)` --
`kAudioHardwareUnknownPropertyError`. That pointed at a specific property being unrecognized, not a
vague crash. From there, reading `BGM_Device.cpp`'s three dispatch points for
`kAudioObjectPropertyCustomPropertyInfoList` (the list a HAL client uses to discover which custom
properties a plugin supports) found it: `Device_GetPropertyData` had grown to fill in 8 entries
when `kAudioDeviceCustomPropertyAppEQ` was added as the 8th custom property in an earlier session,
but `Device_GetPropertyDataSize` for the *same selector* was still hardcoded to `sizeof(...) * 7`.
A well-behaved caller sizes its buffer from the size query, gets a 7-property-sized buffer, and
`Device_GetPropertyData`'s own clamp (`inDataSize / sizeof(...)`) then silently agrees with that
undersized buffer and returns only 7 entries -- so the property discovery list never lies loudly,
it just quietly omits whatever was added after the count went stale. `AudioObjectGetPropertyData`
for `kAudioDeviceCustomPropertyAppEQ` directly then fails with "unknown property," even though the
driver's own `Device_GetPropertyData`/`Device_HasProperty`/`Device_IsPropertySettable` all handle
that selector correctly in isolation -- the bug was never in the property's own dispatch case, it
was in a *different* property (the meta-property that lists all the others) undercounting.

Root cause, not just the symptom: this was **only reachable with a real HAL round-trip** --
`BGMDriverTests` mocks nothing about `BGM_Device` itself (it's tested directly, not through a mock
HAL), but every existing test called `Device_GetPropertyData`/`Device_GetPropertyDataSize`
independently for the properties it cared about, never through the *discovery* path
(`kAudioObjectPropertyCustomPropertyInfoList`) the way a real generic HAL client actually finds out
what properties exist. 22/22 driver tests passed the entire time this bug existed.

**The fix:** corrected the stale `7` to `8`, then replaced both hardcoded numbers (the size query's
`* 8` and the data-fill clamp's `> 8`) with one shared `#define kNumCustomProperties 8` in
`BGM_Device.h`, so the two call sites structurally can't drift apart the same way again when a 9th
property gets added later. Added `BGM_DeviceTests::testCustomPropertyInfoListSizeMatchesActualEntryCount`,
which fetches the list with a deliberately oversized buffer (so `Device_GetPropertyData`'s own
clamp can't hide an undercount from the test the way it hides one from a well-behaved real caller),
asserts the size query and the actual fill agree, and asserts every known custom-property selector
is actually present in the list. Verified red-then-green: reverted the fix, watched the new test
fail, reapplied it, watched it pass -- see the global rule about not trusting a new check until it's
been shown capable of failing.

**How to apply:** any time a HAL/driver-style API has a "how many things exist" query and a
separate "give me the things" call, treat them as one invariant with two call sites, not two
independent numbers -- define the count once and reference it from both, and write a test that
exercises the *discovery* path specifically (oversized buffer, checking the size query and the
actual fill agree), not just each individual property in isolation. A mocked or narrowly-scoped
unit test suite passing 100% is not evidence that a real end-to-end round trip works -- it's
evidence that the paths the tests actually exercise work. The first real install is a genuinely
different test than any mock, and finding out only there is expected, not a sign the tests were bad
-- the response is adding the coverage that specific gap revealed, not distrusting testing in
general.

## A comment that asserts a locking invariant isn't the same as code that provides it -- second occurrence

**The trap:** a full-project audit specifically went looking for more instances of the pattern
that caused the property-discovery crash above (two things that must agree on an invariant,
silently didn't) and found a live one: `BGM_Device::ApplyClientEQ`'s own comment said its
`mClientEQProcessors.find()` call was "guarded by the same `mIOMutex` its caller already holds" --
and `BGM_Device.h`'s comment on the member said the same thing. Both comments were wrong. The
actual caller, `DoIOOperation`'s `ProcessOutput` case, only held `mIOMutex` for a scoped inner
block covering `mAudibleState.UpdateWithClientIO(...)` -- the lock had already gone out of scope
by the time `ApplyClientEQ`/`ApplyClientRelativeVolume` ran. `AddClient`/`RemoveClient` genuinely
do take `mIOMutex` around inserting/erasing from that same `std::map`, from a different thread --
so the real effect was an unsynchronized `find()` racing a concurrent `insert`/`erase` on the same
map's internal tree, a real data race with crash potential inside `coreaudiod`.

**Confirmed, not assumed:** reverting the fix and running a concurrency stress test (four reader
threads hammering the `ProcessOutput` path, four writer threads churning distinct client IDs
through `AddClient`/`RemoveClient`) reproduced a real `SIGABRT` crash 3/3 times, every time in well
under a second (`BGM_DeviceTests::
testConcurrentAddRemoveClientDuringProcessOutputDoesNotCorruptEQProcessorMap`). With the fix (the
whole `mIOMutex` scope widened to cover both calls, plus a lock-free `std::atomic<Float64>` cache
of the sample rate so `ApplyClientEQ` doesn't have to take `mStateMutex` inside `mIOMutex` -- which
would've reintroduced an AB-BA deadlock against `AddClient`/`RemoveClient`/`Deactivate`, which all
take `mStateMutex` before `mIOMutex`), the same test passed clean 3/3 times. Passing tests before
the fix (51/51, the count reported at the top of this project's session) said nothing about this --
none of them exercised concurrent `AddClient`/`RemoveClient` against active `ApplyClientEQ` calls.

**How to apply:** a comment describing a locking invariant is a *claim*, not a *guarantee* -- when
auditing concurrency-sensitive code (anything touching a real-time IO thread, anything with a
mutex-guarded shared structure), read the actual call site's lock scope directly rather than
trusting what a nearby comment says it is, especially when that comment was written at the same
time as the code it's describing (both are equally likely to encode the same wrong assumption).
This is now the second time this exact shape has caused a real bug in this project -- worth
treating as a standing category to re-check whenever new code touches a shared structure that both
a real-time thread and a background thread access, not just a one-off fix.

## Verifying an install means checking the app process is alive, not just its supporting services

**The trap:** after the first `./build_and_install.sh` run, checked that the driver showed up in
`system_profiler`, that the XPC helper reported `state = running`, and declared the install
verified. All of that was true, and the app had still crashed on launch -- `ps aux` for
"Background Music" only showed the driver's `coreaudiod` host process and the XPC helper, not the
app itself, which was missed on the first pass because the check was "does anything relevant show
up in ps aux" rather than specifically confirming the foreground app's own process.

**How to apply:** verifying an install of a multi-component system (driver + helper + app here)
means checking *every* component individually reached a running state, not just the ones that are
easiest to check or that infrastructure-level tools (`system_profiler`, `launchctl`) surface by
default. `pgrep -fl` (or equivalent) for the actual app binary's path, specifically, before calling
an install verified -- and check `~/Library/Logs/DiagnosticReports/` for a crash report matching
the install's timestamp if the process isn't there, rather than assuming it just hasn't launched
yet.

## `bold_face`'s bare-word args break on apostrophes, silently swallowing the rest of the script

**The trap:** added `echo "$(bold_face What's next):"` to `build_and_install.sh` and `bash -n`
immediately failed with `unexpected EOF while looking for matching `'`` pointing at the *last* line
of an 887-line file, nowhere near the actual mistake. `bold_face()` is `echo $(tput
bold)$*$(tput sgr0)` -- it takes its argument as bare, unquoted words via `$*`, which means
`$(bold_face What's next)` hands the apostrophe in "What's" to the shell as an *unquoted* character
inside a command substitution, not as literal text inside a string. The shell opens a single-quoted
string right there and keeps consuming every character after it, across the rest of the file,
looking for a closing `'` that doesn't exist -- which is exactly why the reported error location was
useless for finding the actual problem.

**How to apply:** every existing `bold_face` call in this script already avoids contractions and
apostrophes (`"About to install Background Music"`, `"Building Background Music..."`) -- that's not
a coincidence, it's the actual constraint this function's implementation imposes. Don't put an
apostrophe in anything passed to `bold_face`; rephrase instead ("What happens next", not "What's
next"). More generally: after editing a shell script, `bash -n` before considering the edit done,
not just before running it for real -- it's a full parse with zero side effects, cheap enough to run
after every edit, and a syntax error's *reported* line number can be arbitrarily far from the actual
mistake when an unterminated quote is involved.

## `xcodebuild test` under the sandbox fails on DerivedData permissions, not on the code

**The trap:** running `xcodebuild ... test` sandboxed produced a wall of `CoreSimulatorService
connection became invalid`, `Operation not permitted` on `.xcresult`/`.xcactivitylog` paths inside
`~/Library/Developer/Xcode/DerivedData/...`, and finally `Couldn't create workspace arena folder`,
ending in `** TEST FAILED **` / `Testing cancelled because the build failed`. Nothing about that
output mentions the sandbox, so the obvious first read is "the build is broken" or "Xcode's
simulator service is down" -- neither is true.

**What was actually true:** `~/Library/Developer/Xcode/DerivedData` isn't on this session's sandbox
write allowlist, so every artifact `xcodebuild` needs to create there (the arena folder, the
`.xcresult` bundle, build/activity logs) gets denied. `xcodebuild` doesn't fail fast on the first
denial -- it logs each one as a `CoreSimulatorService`/`IDETestOperationsObserverDebug`/`DVTAssertions`
warning and keeps limping forward until it finally can't create the top-level workspace arena
folder at all, which is the error that actually surfaces as the build failure. The CoreSimulator
noise is a downstream symptom of the same permission denial, not a separate problem -- this project
never touches the iOS Simulator (`-destination 'platform=macOS'` only).

**How to apply:** any `xcodebuild ... test` invocation (not just `build`) needs
`dangerouslyDisableSandbox: true` on this machine, the same as install commands -- this is the same
class of trap as the `gh auth status` keychain issue already learned this session (a sandboxed
command that fails for permission reasons unrelated to the actual task, producing noisy but
misleading output). Recognize the shape early: `Operation not permitted` on a path under
`~/Library/...`, or `Couldn't create workspace arena folder`, means retry unsandboxed immediately
rather than debugging the build itself. Plain `xcodebuild ... build` (no `test`) doesn't hit this,
since it doesn't need `.xcresult`/test-session directories -- only the `test` action does.

## `iconutil` also needs to run unsandboxed -- same trap, third occurrence this project

**The trap:** `tools/generate-icons.py --out-dir <scratch>` generated all 7 AppIcon PNGs
correctly, then failed at the `.icns` step with nothing more specific than `Failed to generate
ICNS.` and a non-zero exit from `iconutil -c icns ...` -- no permission-denied text, no path
mentioned, nothing that looks like a sandbox artifact on its face.

**What was actually true:** retrying the exact same command with the sandbox disabled succeeded
immediately and produced a valid `.icns` that round-tripped through `iconutil -c iconset` back to
10 real PNGs. `iconutil` is CoreAudio-adjacent in this repo's toolchain only by coincidence -- the
actual pattern is the same one already learned twice this session (`gh auth status`,
`xcodebuild ... test`): a macOS system tool that touches something outside this session's sandbox
write/read allowlist (here, whatever scratch/plist state `iconutil` needs on its own, not
necessarily the `--out-dir` path itself, since the AppIcon PNGs it doesn't need wrote there fine)
fails with output that gives no hint the sandbox is the cause.

**How to apply:** the growing list of tools that need `dangerouslyDisableSandbox: true` on this
machine isn't really a list of unrelated one-offs -- it's one recurring shape: *any* macOS system
CLI tool (not just build tools) can be denied by the sandbox in ways that produce generic,
misleading errors with no "Operation not permitted" text to grep for. When a system tool
(`iconutil`, `codesign`, `sips`, anything under `/usr/bin` or a `.app`'s own CLI) fails with a
vague, non-specific error and the *logic* around the call looks correct, retry unsandboxed before
spending time debugging the code that invoked it.

## `xcodebuild build`'s static analyzer only runs for Release, not the Debug test builds already being run

**The trap:** a new `menuWillOpen:` code path (`BGMAppDelegate.mm`) passed a possibly-nil local
`NSTextField*` into a new helper method whose parameter wasn't marked nullable. Every verification
run up to that point -- `-only-testing:BGMAppUnitTests test` (Debug), repeated many times across
this session -- built and passed clean, 28/28, with zero warnings. The problem only surfaced on the
next plain `-configuration Release build`, as `** BUILD SUCCEEDED **` followed by a separate,
easy-to-miss line: `The following commands produced analyzer issues: AnalyzeShallow
BGMAppDelegate.mm`.

**What was actually true:** Xcode's static analyzer (`clang --analyze`, deeper flow-sensitive
nullability/nil-flow checking than the ordinary compiler's `-Wnullable-to-nonnull-conversion`) runs
as part of the Release build's `AnalyzeShallow` step but is **not** part of the Debug/test
invocations this project runs constantly for fast iteration. So a real nil-flow defect can pass
every `BGMAppUnitTests test` run in a session and only show up the first time a Release build
actually happens -- which, in this project's rhythm, is often the *last* verification step before
declaring something done, not an early one.

**How to apply:** `-only-testing:... test` (Debug) is necessary but not sufficient verification for
this codebase -- always run the three plain `-configuration Release build` commands too (already
part of this project's standard verification sequence) and specifically grep the output for
`produced analyzer issues`, not just `BUILD SUCCEEDED`/`BUILD FAILED`, since an analyzer finding
doesn't fail the build or show up in the pass/fail summary line. `** BUILD SUCCEEDED **` on its own
is not proof there's nothing to fix.

## A real-world bug report (menu closes on slider click) traced to a row-height regression, not a click-handling bug

**Symptom:** the first actual real-world use of the 10-band per-app EQ -- the user, not a test --
reported that clicking *any* volume/pan/EQ slider inside an expanded app row made "the menu close
or disappear," across multiple apps, not one specific control. The instinctive place to look is the
slider's own click handling (`BGMAVM_VolumeSlider`/`BGMAVM_EQBandSlider`, `mouseDown:`/target-action
wiring) since that's the code that changed most recently and directly touches the reported symptom.

**What was actually true, as far as it could be diagnosed without a live running menu bar app (no
way to interact with a real NSMenu from this environment):** the per-app EQ shipped as a single
column of 10 bands, which grew the expanded row's custom view from 147pt to 222pt -- a 51% height
increase. NSMenu has a documented, well-known interaction: once a menu (or a scrollable region
within it) needs to scroll to show all its content, custom `NSMenuItem` views can lose mouse
tracking mid-drag, because AppKit's own scroll-handling machinery competes with the view's tracking
loop for the same mouse-down/mouse-dragged events -- a click that starts on a slider can register as
"outside the menu item" partway through and dismiss the whole menu, which matches the reported
symptom (any slider, any app, only when the row/menu was tall) far better than a per-control bug
would (which would affect one slider type, not all of them uniformly).

**How this was actually resolved:** not by reproducing the bug (impossible from this environment)
but by removing the suspected trigger -- redesigning the layout from one column of 10 bands back to
two columns of 5, restoring the original 147pt row height entirely (see "Growing a collapsible XIB
menu-item view: shift everything by the same delta" above for the layout mechanics), so the
menu never needs the taller scrolling state that's believed to cause the lost tracking. This is
explicitly a **theory-driven mitigation, not a confirmed fix** -- it was never verified against a
live menu, only against static XIB geometry (no overlaps, everything in bounds) and the mechanism's
plausibility. TODO.md and docs/QA-PLAN.md both carry this as an open, unverified item until the user
actually reinstalls and clicks a slider on a real running instance.

**How to apply:** when a bug report describes symptoms that are broad and environmental ("any
control, any row, only sometimes") rather than narrow and specific to one code path, consider
whether a recent *layout* change (something that alters container size, triggers scrolling, or
changes view hierarchy depth) is the actual cause before assuming the most recently touched
*interaction* code is at fault -- especially for AppKit constructs like NSMenu with known, documented
interactions between built-in scrolling and custom-view mouse tracking. When a live target can't be
interacted with directly to confirm a theory, say so explicitly rather than presenting a plausible
mitigation as a verified fix.

## A row-type check based on subview count silently rotted into 100% dead code

**The trap:** `BGMAppDelegate.mm`'s `menuWillOpen:` told an app-volume row apart from the System
Sounds row by counting `menuItem.view.subviews.count` (7 vs. 3) and branching on it to drive a
routed-app indicator and an alignment tweak. It compiled clean, every test suite passed, and
nothing about running the app would obviously break -- the branch just silently never matched
either count anymore, after earlier layout changes added/removed subviews, so both code paths it
guarded were dead. No warning, no test failure, no crash: the feature just quietly did nothing.

**What was actually true:** a `.count == N` check against a view hierarchy is not an identity
check, it's a coincidence that happens to hold on the day it's written and breaks the moment
*anything* changes that view's subview count for an unrelated reason (new label, new button, a
XIB edit made for cosmetic reasons). Nothing enforces the invariant, and nothing detects when it
silently stops holding.

**How to apply:** never identify "which kind of row is this" (or any similar case-detection) by
counting or measuring incidental structure (subview count, view frame, tag ordering by position).
Use an actual identity marker set deliberately for that purpose -- here,
`NSMenuItem.representedObject` holding the real `NSRunningApplication`, and a direct object
comparison (`menuItem.view == self.systemSoundsView`) for the one-off row. When reviewing older
code for this project's audits, grep for `.count ==`/`.count >` comparisons feeding a branch and
check whether the count is actually guaranteed by something, or just happened to be true when
written.

## `NSMenuItem.enabled` does not disable a custom-view menu item's own controls

**The trap:** `BGMPreferencesMenu.mm`'s `updateHotkeyMenuItemStates` set `.enabled = NO` on the
wrapping `NSMenuItem` for the four hotkey-recorder rows and three step-size rows when hotkeys were
turned off, expecting AppKit to grey them out and block clicks the way it does for plain
text-title menu items.

**What was actually true:** for a custom-view `NSMenuItem` (`.view` set to something like
`BGMHotkeyRecorderButton`, an `NSButton` subclass), `NSMenuItem.enabled` only affects the item's
own highlight/selection behavior in the menu -- it does **nothing** to the custom view's own
interactivity. The subview is a real, independently-enabled control; it stayed fully clickable
(and looked normal, not greyed out) regardless of the wrapping item's `.enabled` state. This is
undocumented behavior a reader has to already know rather than something the API surface warns
about.

**How to apply:** for any custom-view `NSMenuItem`, disabling it means setting `.enabled` (or the
equivalent) directly on the custom view/control itself, not on the wrapping `NSMenuItem` -- treat
`NSMenuItem.enabled` as a no-op for interactivity whenever `.view` is set, and grep this project's
other custom-view menu items (`BGMAVM_VolumeSlider`, `BGMAVM_EQBandSlider`,
`BGMAVM_OutputRouteButton`, etc.) for the same assumption before trusting any of their disabled
states.

## `$?` after a negated `if !` condition reads the wrong exit code

**The trap:** `pkg/postinstall`'s first draft of the `ListInputDevices` failure path was
`if ! input_device_list="$(./ListInputDevices 2>&1)"; then log "...(exit $?)..."`. Inside that
`then` branch, `$?` was always `0` -- looked plausible, ran without an obvious crash, and would
have silently logged the wrong exit code for every real failure.

**What was actually true:** `$?` reflects the exit status of the *last command executed*, which
inside an `if ! cmd; then` branch is the negated test of `cmd` succeeding as evaluated by `if`
itself -- not `cmd`'s own exit code. By the time the `then` block runs, the original status is
already gone.

**How to apply:** to both branch on a command's failure and report its real exit code, run the
command as a plain (non-negated) statement first, capture `$?` into a variable on the very next
line, then branch on that variable: `out="$(cmd)"; status=$?; if [[ $status -ne 0 ]]; then ...`.
Never combine `!`-negation with a later `$?` read in the same construct.

## A property listener on a CoreAudio-owned thread crashed because it was the one call site that didn't swallow exceptions

**The trap:** `BGMDeviceControlSync::BGMDeviceListenerProc` -- a property-change callback CoreAudio
invokes on its own thread, not one of this app's -- called `mOutputDevice.CopyVolumeFrom`/
`CopyMuteFrom` directly, no try/catch, no `BGMLogAndSwallowExceptions`. Every *other* CoreAudio call
in the same class already had that protection. This one didn't, and nothing caught it until a real
install crashed with an uncaught `CAException` (confirmed via a real crash report, `terminating due
to uncaught exception of type CAException`, not inferred from reading the code).

**What was actually true:** the crash was reachable in an entirely ordinary way -- a previous
install's app process survived a driver reload (see the next entry) and kept a stale device object
reference from before it. The first CoreAudio call against that stale reference threw, and because
it happened on a thread CoreAudio owns rather than one this app controls, there was no outer
handler anywhere in the call stack to catch it before it reached `std::terminate`.

**How to apply:** a call site being "just like the other five in this file" isn't itself protection
-- check each one actually has the same guard, don't assume consistency from proximity. This is
also a second, independent argument for why swallowing exceptions on any thread CoreAudio invokes
directly (a property listener, an IO callback) isn't optional the way it might look "safer to be
strict" on an app's own thread: there's no caller further up able to do anything about it.

## An already-running app process survived a coreaudiod restart and crashed on stale state

**The trap:** re-running `build_and_install.sh`/the `.pkg` installer while a previous install's app
was still running left that old process alive straight through the driver swap and `coreaudiod`
restart -- the scripts copied the new driver into place and restarted the daemon, but never quit
the already-running app first.

**What was actually true, confirmed on a real reinstall cycle:** the surviving old process kept
CoreAudio object references (a device ID, in this case) from *before* the reload. Those references
went stale the moment the driver actually reloaded, and the first attempt to use one (dragging the
master volume slider) crashed the app via the uncaught-exception bug in the previous entry. The
fresh, newly-installed binary never even got a chance to run -- `open`/`launchctl asuser open` on
an already-running app just refocuses the existing (old, stale) process instead of starting a new
one, so the crash looked at first like "nothing happened" rather than "the wrong process crashed."

**How to apply:** both scripts now quit any already-running copy of the app (via AppleScript
`tell application ... to quit`, reached through `launchctl asuser` in `pkg/postinstall` since that
script runs as root) before restarting `coreaudiod`, guaranteeing the process that comes back up
afterward is running the just-installed binary against the just-reloaded driver, not a stale
survivor of the previous one. Any future install/reinstall script that swaps out a driver or daemon
the app holds live references to needs the same "quit first" step, not just "copy the new files and
restart the service."

## `NSMenu` custom-view controls cannot prevent the menu closing on interaction

**The trap:** the per-app volume slider closed the whole menu the instant the user dragged it.
The first fix attempted was a custom `mouseDown:` override (`BGMTrackSliderWithoutLosingMenuFocus`)
that bypassed `NSSlider`'s own tracking loop and pumped `-nextEventMatchingMask:` directly, on the
theory that `NSMenu`'s own tracking was racing against the slider's and sometimes winning mid-drag.

**What was actually true, confirmed via direct `NSLog` instrumentation on a real install, not
theorized:** the custom tracking loop worked *correctly* -- it ran to completion, all iterations,
ending on a real `mouseUp`. The menu still closed anyway, about 13ms after that `mouseUp`
returned. The close wasn't a race the slider's own code could win or lose; it happens at `NSMenu`'s
level, triggered by the same physical mouse-up event the slider's tracking loop also observed, and
nothing a custom view does with that event changes whether `NSMenu` treats it as "an interaction
finished here, so close." Apple's own "Views in Menu Items" documentation confirms the ceiling
directly: a custom `NSMenuItem` view receives mouse events, but has no supported way to prevent
menu dismissal on mouse-up, and receives no keyboard events at all. An unrelated, similarly-scoped
app (MonitorControl, brightness/volume sliders in an `NSMenu` dropdown) has filed, still-open
GitHub issues describing the identical failure mode in production (#1724, #1611).

**The fix:** there wasn't a control-level one. The `NSMenu`-based main dropdown was replaced
entirely with a custom `NSPanel` (`BGMMainPanel`) -- borderless, `.nonactivatingPanel`,
`canBecomeKeyWindow` overridden `YES`, dismissed via a global mouse-down monitor instead of
`NSMenu`'s automatic behavior. Once hosted in a real window, the `BGMTrackSliderWithoutLosingMenuFocus`
workaround was itself removed -- plain `[super mouseDown:]` behaves correctly there, and, as a
side effect neither the old `NSMenu` design nor the workaround ever provided, arrow-key nudging on
a focused slider now works too. Reference recipe: `jordanbaird/Ice`'s `IceBarPanel`/
`MenuBarSearchPanel` (a real, shipping open-source menu-bar app solving the identical problem).

**How to apply:** any future interactive custom view hosted in an `NSMenuItem.view` in this
codebase (Preferences still has two: the Auto-pause Delay sliders and the `BGMHotkeyRecorderButton`
controls, both flagged in `TODO.md` as a follow-up, not yet moved) has this same architectural
ceiling. Don't chase a reported "the menu closes/doesn't respond right" bug against one of those as
if it were a bug in that specific control -- it isn't fixable there, only by moving the control out
of `NSMenu` entirely.

## A sandboxed shell blocked `xcodebuild`'s own writes, and looked like a compile error

**The trap:** running `./package.sh` (which shells out to `xcodebuild ... archive` for all three
targets) failed on the very first `clean` step, with `xcodebuild: error: "Background Music Device"
couldn't be removed because you don't have permission to access it` and a top-level message that
just said "A build command failed. Probably a compilation error." Nothing in the diff had changed
anything build-related.

**What was actually true:** the shell this ran in was sandboxed, and `xcodebuild` needs to write
outside the project directory for reasons that have nothing to do with the actual build -- `~/Library/
Developer/Xcode/DerivedData/.../Logs/Build/*.xcactivitylog`, `~/Library/Logs/CoreSimulator/...`, and
a `.xcresult` bundle under `$TMPDIR`. Every one of those writes came back `Operation not permitted`,
and losing the DerivedData log write was enough to make the `clean` action itself report failure,
which cascaded into "the build failed" even though not one line of project code had been touched.
The `pgrep`/`ps` calls `build_and_install.sh` uses for its cosmetic progress-spinner also failed
under the same restriction (`pgrep: Cannot get process list`, `/bin/ps: Operation not permitted`),
but those are non-fatal by design (guarded by `disable_error_handling`) -- they're noise, not the
actual failure, and would have been a red herring if chased first.

**Fix:** re-ran with the sandbox disabled for that one command. Build succeeded immediately, same
source tree, zero code changes.

**How to apply:** any `xcodebuild` invocation -- not just this project's, any Xcode project -- needs
write access outside its own directory (DerivedData, CoreSimulator logs, `$TMPDIR` result bundles)
purely to run at all, independent of whether the build itself would succeed. When an `xcodebuild`
failure's actual error text is `Operation not permitted` on a path under `~/Library/...` or
`$TMPDIR`, that's the sandbox, not the code -- don't start bisecting recent commits for a
compile-error root cause before checking whether the failure is even about compilation.

## `command | tee logfile` in the background hides the command's real exit status

**The trap:** the first packaging attempt was launched as `./package.sh 2>&1 | tee run.log` in the
background. The task-completion notification reported "completed (exit code 0)" -- which, read on
its own, looks like a clean pass and was almost taken as one without opening the log.

**What was actually true:** the exit code surfaced from a `cmd | tee file` pipeline (in a shell
without `set -o pipefail`, which the calling context here didn't have) is `tee`'s exit status, not
`package.sh`'s. `tee` itself always exits 0 as long as it can write its log file, regardless of
whether the command feeding it failed. The build had actually failed (see the entry above) --
"exit code 0" was true of `tee`, not of the build.

**How to apply:** never read a background command's reported exit code as the final word when the
command was piped through `tee` (or anything else) without `pipefail`. Either add `set -o pipefail`
before piping, capture the real exit code explicitly (`cmd; ec=$?; ... | tee log; exit $ec` or
`${PIPESTATUS[0]}` in bash), or -- simplest, and what actually caught this -- read the log's tail
for the tool's own pass/fail banner instead of trusting the wrapper's exit code alone.

## `CFBundleDisplayName`, not `CFBundleName`, is what TCC permission dialogs show

**The trap:** `BGMSetupWindow` was built to explain, among other things, exactly why macOS is
about to show a Microphone permission dialog. But the dialog itself still said `"Background
Music.app" would like to access the Microphone` -- a real screenshot from an actual install, not
a hypothetical -- even after `docs/LESSONS.md`'s prior entries about this session's rearchitecture
had shipped. The instinct was to assume this needed some deeper fix in how the permission request
was triggered.

**What was actually true:** the dialog was reading `CFBundleName`, which was `$(PRODUCT_NAME)` =
"Background Music" -- the literal Xcode target name, unrelated to what this fork calls itself
anywhere else. `CFBundleDisplayName` is the separate key macOS actually prefers for this exact
text (Finder, Activity Monitor, and TCC/system permission dialogs all read it first, falling back
to `CFBundleName` only if it's absent) -- confirmed via a real, documented instance of the same
bug in an unrelated project (Claude Code's own CLI hit this from a missing/misconfigured
`CFBundleDisplayName`, GitHub issue #27322). Setting it doesn't touch `CFBundleName`, the bundle
identifier, the `.app` folder name, or anything else scripts/docs depend on -- it's a purely
additive key with no coupling to the technical plumbing.

**How to apply:** any time an app's user-visible name needs to differ from its internal
target/bundle name (a rebrand, a fork, a white-label build), reach for `CFBundleDisplayName`
first, not a `PRODUCT_NAME`/bundle-identifier rename. The latter is a much bigger, riskier change
(breaks existing installs' TCC grants, requires updating every script/doc with a hardcoded path)
for the same visible result.

**Follow-up, 2026-08-14:** the same class of bug hit Accessibility too, on a real `.pkg` install,
independent of the Microphone fix above -- System Settings' Accessibility list showed the
permission row under the stale name `"Background Music.app"`, and toggling it ON had no effect on
`WCSetupWindow`'s live status check (`AXIsProcessTrustedWithOptions`), which kept reading "Not
Granted." Unlike the Microphone case, this isn't just a display-name cache -- this project is
unsigned (ad-hoc-signed only, no paid Developer ID), and ad-hoc signatures are derived from the
actual binary bytes, so two builds of the exact same bundle ID with different code between them
get different signatures. TCC's identity check for some services goes beyond the bundle ID string
alone, so a grant (or a stale not-yet-decided entry) recorded against one build's signature isn't
reliably honored for a later rebuild, even though `com.bearisdriving.BGM.App` never changed. The
app-side code (`updateAccessibilityRow`, the button's `AXIsProcessTrustedWithOptions` call) had no
bug -- both matched Apple's documented usage exactly. The only real fix is the same one-liner as
before, `tccutil reset Accessibility com.bearisdriving.BGM.App`, run by a human. **How to apply:**
for any unsigned/ad-hoc-signed app under active development, expect *every* TCC-gated permission
(not just the one that broke once) to be able to leave stale or mismatched entries behind after
enough rebuilds across a session -- don't treat the Microphone fix as having closed this class of
bug, since each service (Microphone, Accessibility, Camera, etc.) keeps its own independent TCC
state and can go stale on its own schedule. A real Developer ID + consistent code signing would
remove this whole failure class; until then, `tccutil reset <Service> <bundle-id>` is the expected,
recurring unblock during development, not a one-time fix.

## An isolated off-screen `NSView` render needs its own background before dark mode "works"

**The trap:** verifying `BGMSetupWindowContentView`'s new dark-mode-adaptive header/buttons meant
rendering it off-screen to a PNG rather than guessing (per this project's own render-and-look
standard) -- a standalone harness was built that compiles the real source file directly, forces
`NSAppearanceNameDarkAqua`, and calls `cacheDisplayInRect:toBitmapImageRep:`. The first render came
back with every `labelColor`/`secondaryLabelColor` text field completely invisible in dark mode --
title, subtitle, every row's title and body text, all gone. Read at face value, that looks like a
real color-resolution bug in the shipped code.

**What was actually true:** it wasn't a code bug at all. Setting `view.appearance` positions the
view for dark mode but doesn't push it as the *drawing-time* current appearance that dynamic
`NSColor`s resolve against inside `drawRect:` -- fixed by wrapping the render in
`[appearance performAsCurrentDrawingAppearance:^{ ... }]` instead, which *is* documented for
exactly this. That alone didn't fix it either: the text was very likely rendering correctly as
white, just invisible against a transparent canvas that PNG export flattens to white. A real
`NSWindow` supplies an opaque background to its content view for free; an isolated off-screen view
rendered in complete isolation has none, so nothing was actually wrong with the production code --
only with the harness testing it in a way the real deployment never would be.

**How to apply:** when building an off-screen rendering harness for any AppKit view that isn't
hosted in a real window, two things are required for a faithful test, not one:
`performAsCurrentDrawingAppearance:` to make dynamic colors actually resolve for the target
appearance, *and* an explicit opaque background layer (`wantsLayer = YES` +
`layer.backgroundColor = NSColor.windowBackgroundColor.CGColor`, or whichever background color the
real host window would actually provide) so text rendered in that color is visible against
something. Missing either one produces a result that looks like a real bug in the code under test
but is actually purely an artifact of the harness -- worth ruling out explicitly (as was done here,
by adding the missing piece and confirming the *same* unmodified source then rendered correctly)
before concluding the production code is actually broken.

## An unquoted `$(cat file-list)` silently truncated a 256-file mechanical rename

**The trap:** renaming the codebase's internal `BGM` class prefix to `WC` (see the commit itself,
"Rename the internal BGM class/file prefix to WC") meant running one Perl script across 256 files,
invoked as `perl script.pl map.tsv $(cat files_to_rename.txt)`. The script logged 114 "changed:"
lines and exited 0 -- read at face value, that looked like a clean, complete run, and very nearly
was reported as done on that basis (see the earlier `tee`/`pipefail` entry in this file for why
"exited 0" alone was already flagged as insufficient evidence this same session).

**What was actually true:** this project has a directory with a space in its name (`BGMApp/BGMApp/
Music Players/`). The unquoted `$(cat files_to_rename.txt)` let the shell word-split every path
under it into two bogus arguments before Perl ever saw them. The very first one Perl tried to
`open()` doesn't exist, so it `die`d immediately -- and Perl's `die` aborts the whole process, not
just that one iteration. Every file later in the argument list -- 21 file pairs across `Music
Players/`, `Preferences/`, and `Scripting/`, roughly 40 files -- silently never got touched. Worse,
a *separate* pass (`git mv`, driven by a different, unaffected file list built from the rename map
rather than the crashed run) had already renamed those exact files' *names* to the new prefix --
so the failure mode wasn't "these files still have their old name," which would have been obvious
on sight, but "these files have their new name and their old, wrong content," which is invisible
without actually opening them. The first correctness check written to catch this reused the
*original* (pre-`git mv`) file list and silently skipped every file it couldn't find at its old
path anymore -- concluding "only 4 files missed" when the real number was over 40, because it was
checking against a snapshot of the world that had already moved on.

**How to apply:** never pass a file list to a command via unquoted `$(cat ...)` or unquoted
`$(find ...)` -- one path with a space anywhere in the tree corrupts the whole argument list from
that point on, and a script that `die`s (or just errors) on the first bad argument won't even
signal that everything after it was skipped. Use `xargs -0` with a NUL-delimited list, a `while
IFS= read -r` loop, or a shell array (`mapfile`/`readarray` in bash; a `while read` loop building
an array in zsh, which has no `mapfile` builtin -- confirmed the hard way mid-fix here). Separately:
when verifying a bulk mechanical change, always re-scan the *current* state of the tree (`git
ls-files` at the moment of checking), never a *snapshot* file list captured before the change ran
-- a snapshot check that silently treats "file not found" as "already handled, skip it" will hide
exactly this failure mode, since the file moving out from under the old path is indistinguishable,
from that check's perspective, from success.

## A file whose name doesn't exactly match its class needs its own rename rule

**The trap:** the same rename above matched file names to class names by exact basename equality
(`BGMAppDelegate.h` -> a class named exactly `BGMAppDelegate` -> renamed to `WCAppDelegate.h`).
One category file, `BGMAppDelegate+AppleScript.{h,mm}` (an Objective-C category extending
`BGMAppDelegate`, not a class named `BGMAppDelegate+AppleScript`), doesn't exactly match any single
class name, so the exact-match file-rename pass correctly, silently left it alone -- while the
separate, independent *content* rename (which operates on whole-token matches anywhere in a file,
not on file names at all) still correctly rewrote `BGMAppDelegate` to `WCAppDelegate` everywhere
it appeared inside that file, including inside its own `#import "BGMAppDelegate+AppleScript.h"`
line, producing `#import "WCAppDelegate+AppleScript.h"` -- a reference to a file that, until this
was caught by an actual build's "file not found" compile error, didn't exist under that name.

**How to apply:** a rename pass split into "rename files that exactly match a renamed symbol" and
"rename the symbol wherever it's referenced in content" will always miss files whose name is a
*compound* of a renamed symbol plus something else (a category, a suffix, a variant) -- the content
half doesn't know about file names, and the file half only matches whole names. `grep` for the
renamed symbol as a *prefix* of any remaining file name (not just an exact match) after the main
pass, to catch these before a build does.

## A rename's own build-config plist can be invisible to every search except an actual build

**The trap:** renaming the app itself (`Background Music.app` -> `Wavecraft.app`, via the Xcode
target's `PRODUCT_NAME`) meant finding and fixing every script/doc that hardcoded the old path or
scheme name -- done thoroughly, including three separate full-tree greps at different points that
each caught something the previous one missed (AppleScript `tell application` targets, `ps`/
`killall` process-name checks, a device-detection check with no fallback that would have hard-failed
every future install). After all of that, `package.sh` was run end-to-end anyway, on the assumption
it would just confirm what already looked complete.

**What was actually true:** `pkg/pkgbuild.plist` -- the property list `pkgbuild --component-plist`
reads to know where each bundle actually lives inside the package root
(`RootRelativeBundlePath = Applications/Background Music.app`) -- still had the old path, and none
of the greps had caught it. Not because it was hard to find (`grep -rl "Background Music.app"`
would have caught it in under a second), but because it was never *looked for* -- every search this
pass ran was built from "where would the old name show up in scripts/docs/comments," a mental model
built by reading the .sh/.md/.mm surface area, and a `.plist` consumed only by `pkgbuild` itself
sits outside that model entirely. Left unfixed, this wouldn't have errored -- `pkgbuild` would have
either silently packaged nothing at that path or failed with a `pkgbuild` error unrelated-looking to
the actual rename, discovered only by someone building a release, possibly much later than this
session.

**How to apply:** for any rename with real build/install tooling behind it, enumerate every file
`pkgbuild`/`productbuild`/the build system actually *reads paths from* (component plists, entitlements,
`Info.plist` templates, provisioning-adjacent config) as its own explicit checklist item, separate
from "grep the scripts and docs for the old string" -- these files are easy to forget precisely
because they're rarely opened by hand and don't show up in a mental model built from the
human-facing surface area. Then actually run the full downstream pipeline (not just build the
renamed target) before calling a rename like this complete -- `package.sh` end-to-end is what
surfaced this, not a broader or smarter grep.

## A "shown first" onboarding window still lost the race to an unconditional call right after it

**The trap:** `WCAppDelegate::applicationDidFinishLaunching` called `[setupWindow
showOnFirstLaunchIfNeeded]` *before* touching any system permission -- specifically to fix an
earlier, real bug where the permission dialog appeared before the user had a chance to read the
explanation. That looked like the fix. But two lines later, in the very same method, `if
(showedSetupWindow) { ... [self requestMicrophoneAccess]; }` called the real
`AVCaptureDevice requestAccessForMediaType:` request *itself*, unconditionally, the instant the
window had been ordered onto screen -- not when the user clicked its own "Grant Access" button.
Ordering the window first didn't help, because a second, independent code path also fired the
same real request immediately after, racing the user's ability to even read the window before the
system dialog appeared on top of it. Caught only by actually launching the built app and
screenshotting it -- clean builds and 47/47 unit tests never touch this, since nothing in the
suite drives a real `applicationDidFinishLaunching` and watches what system UI shows up.

**What was actually true:** "shown before" and "the user decided" are different claims. The
window being visually in front doesn't mean nothing downstream can still race ahead of the user's
own input -- the reordering fixed the *visual* race (window paints before the dialog) but not the
*causal* one (something other than the user's own click still triggers the dialog). The tell was
in the app-delegate comment itself: "the Setup window's own Microphone row already ... has a
button that does the exact same thing" -- true, but the code right below it called that same
action from the delegate too, not just from the button.

**How to apply:** when a UI element exists specifically so the user can trigger a consequential
action (a permission request, a payment, a send) at their own pace, grep for every other call site
of that same underlying action and confirm none of them can fire on a path that doesn't go through
a real user click -- "the button also does this" is not evidence nothing else does. The fix here
was a completion-handler property on the window (`microphoneAccessGrantedHandler`), set once by
the delegate and fired only from the window's own permission-status-refresh logic (which itself
only runs after a button click or returning from System Settings) -- moving the *decision* of
when the underlying call happens fully inside the component the user actually interacts with,
not just the ordering of two independent call sites.

## `NSWindow.frameAutosaveName`, set before the first layout pass, autosaves a frame nobody chose

**The trap:** `WCSetupWindow`'s initializer set `self.frameAutosaveName = @"WCSetupWindow"`
immediately (with a comment explaining the intent: remember where the user leaves the window),
then called `buildRows` and `sizeToFitContent`, which resized the window from its initial
`NSZeroRect` to its real fitted size via `setContentSize:`, then attempted
`[self setFrameUsingName:...]` to restore any previously saved position, falling back to
`[self center]` if none existed. On a genuinely first-ever launch (no prior saved frame), this
should have centered the window. Confirmed by direct screenshot on a real screen: it did not --
the window landed pinned to the screen's bottom-left corner, `(0, 0)`, every time.

**What was actually true:** `frameAutosaveName` isn't just a name to pass to
`setFrameUsingName:` later -- setting it turns on automatic save-on-move/resize immediately, for
the rest of the window's life. Since it was set *before* `sizeToFitContent` ran,
`setContentSize:`'s own resize (from zero to the real fitted size) was itself auto-saved to
`defaults` right then -- capturing the window's frame at whatever origin it happened to have
straight out of construction, `(0, 0)`, before anyone had ever positioned it. Moments later in the
same method, `setFrameUsingName:` read that value straight back and "restored" it -- a
self-fulfilling restore of a frame nobody, ever, actually chose. `restored` came back `YES` on
every single first launch, so the `center` fallback never ran. Confirmed with temporary `NSLog`
instrumentation around every step (`setContentSize:`, `setFrameUsingName:`, the centering call)
before writing the real fix -- guessing from reading the code alone pointed at `-center`'s
screen-association behavior, which was the wrong layer entirely.

**How to apply:** don't set `frameAutosaveName` until *after* a window's initial position for
this show has already been resolved one way or another (restored from a real prior session, or
explicitly positioned) -- setting it any earlier makes every layout-time resize during
construction eligible for auto-save, including ones that happened before the window was ever
shown to anyone. If restoration needs to happen during that same initial layout (as it does here,
to check for a real saved frame from an *earlier* session), read/write the autosave name as a
private string constant during that phase, and only assign it to the live `frameAutosaveName`
property once positioning is finished. When a saved position looks suspicious (an origin at
exactly `(0, 0)`, or any window that's "somewhere, technically" but never where a user would
expect), suspect the autosave timing before suspecting the centering call itself -- confirm with
`NSLog` around the actual sequence of calls rather than reasoning about `NSWindow` behavior from
memory, since positioning APIs like `-center` have real, non-obvious dependencies on window
visibility state that aren't fully documented.

## A relocatable pkg component upgrades an old-named bundle in place, silently, forever

**The trap:** the app itself was renamed on disk this session (`Background Music.app` ->
`Wavecraft.app`, see the earlier "Rename the app itself" entries), and `pkg/pkgbuild.plist` was
fixed to point at the new path (`RootRelativeBundlePath = Applications/Wavecraft.app`) -- verified
correct, re-checked, confirmed present in the built `.pkg`. A real, fresh `.pkg` install still
produced an app running from `/Applications/Background Music.app`, the *old* path -- confirmed via
`ps -p <pid> -o command` showing the literal old path, not a hypothesis. Every individual piece of
the rename looked right in isolation.

**What was actually true:** `pkgbuild.plist`'s app component was also marked
`BundleIsRelocatable: true` with `BundleOverwriteAction: upgrade` -- correct, ordinary behavior
for handling a user who's moved the app before installing an update (Launch Services finds the
existing install *by bundle ID*, not by the path in the component plist, and upgrades it in
place). But a leftover `/Applications/Background Music.app` from *before this session's rename*
was still sitting on disk, sharing the unchanged bundle identifier `com.bearisdriving.BGM.App`.
`pkgbuild`'s relocatable-upgrade logic found that old bundle by ID, and upgraded its *contents* in
place -- new executable, new `CFBundleShortVersionString`, everything inside correctly reporting
"Wavecraft" -- while leaving the enclosing folder under its old name, because "upgrade in place"
means exactly that: it never moves or renames the folder itself. `/Applications/Wavecraft.app`
was never created at all. `pkg/postinstall`'s own launch step (`open -b com.bearisdriving.BGM.App`)
then correctly found and launched that same bundle -- at the old path -- and its own header
comment had *already predicted this exact failure mode* ("TODO: If they have multiple copies of
BGMApp, this might open one of the old ones"), written by the original project author years before
this session's rename made it newly relevant.

**A second, compounding bug rode along with this one:** ad-hoc debug testing earlier the same
session (`open BGMApp/build/Debug/Wavecraft.app` directly, to verify an unrelated UI fix) used the
real, standard `NSUserDefaults` domain for `com.bearisdriving.BGM.App` -- the *same* domain the
real `.pkg` install reads from, since defaults are keyed by bundle ID, not by which copy of the
binary happens to be running. That test session recorded `LastShownSetupWindowVersion` and
`HasShownMicrophonePermissionExplanation` against the exact version string the next real `.pkg`
build also produced (same commit, same `set-version.sh` output) -- so when the user's real install
launched, `WCSetupWindow::showOnFirstLaunchIfNeeded` saw a version match and skipped the window
entirely, falling through to the older, less-explained permission-request path, which *also* saw
its "already explained" flag set from testing and skipped straight to the real system dialog with
no explanation at all. Two independent bugs (a stale bundle, and stale shared defaults) combined
to reproduce exactly the symptom the whole `WCSetupWindow` rearchitecture existed to prevent.

**How to apply:**
- Any time a `pkgbuild` component is `BundleIsRelocatable` + `BundleOverwriteAction: upgrade`
  (the normal, correct choice for handling user-moved installs), a rename of that bundle's on-disk
  name needs an explicit, one-time migration step -- a `preinstall` script that finds any existing
  bundle with the *old* name and the *same* bundle ID, and removes it before the main payload
  installs, so relocatable-upgrade has nothing stale to "helpfully" reuse. Fixed here by adding
  exactly that to `pkg/preinstall`. The uninstaller needed the identical fix (`_uninstall-non-
  interactive.sh`'s `file_paths` array) so a plain uninstall without a following reinstall also
  fully cleans up -- the same "check both the new and legacy path" pattern already used for the
  XPC helper's backup install dir, just not yet extended to the app bundle itself.
- Never test a rebuilt app by launching it directly against the *real* `NSUserDefaults` domain a
  production install shares -- pass `--no-persistent-data` (already implemented, see
  `WCAppDelegate::createUserDefaults` and `kOptNoPersistentData`) for any ad-hoc launch of a build
  sharing a real app's bundle ID, so test-only state never contaminates what a real install reads.
  Confirmed after the fact by reading the exact polluted keys back out of the shared domain.
- When a fix is verified only by reading code/config that looks correct, and a live symptom still
  reproduces, suspect a *second*, unrelated mechanism before re-reading the same fix again --
  `ps -p <pid> -o command` (the actual running executable's real path, not an assumption about
  where it "should" be) is what actually broke this open.

**Follow-up, same day: the `preinstall`-only fix above did not actually work.** A second real
install, with that fix confirmed present in the built `.pkg` (`pkgutil --expand-full`, not
assumed), *still* landed at the old `/Applications/Background Music.app` path -- confirmed again
via `ps`, and via the folder's own modification time matching the install that had just run (so
`preinstall` almost certainly did remove it, and Installer's own relocatable-component placement
logic then recreated a folder at that same old path anyway). The likely mechanism: Installer
resolves a relocatable component's actual install location during its own planning phase, via
Launch Services' bundle-ID registration -- a cache, not a live filesystem check -- which may be
consulted before `preinstall` runs, or may simply not reflect a deletion that happens moments
before the payload write. Either way, a `preinstall`-side cleanup cannot reliably win a race
against that resolution. **The actual fix: stop the app component from being relocatable at all**
(`BundleIsRelocatable: false` in `pkg/pkgbuild.plist`, matching what the driver component already
correctly used) -- this removes Launch-Services-based location resolution from the picture
entirely, forcing installation at the literal `RootRelativeBundlePath` every time, with nothing
left to race. The `preinstall` cleanup step stays (now genuinely effective, since there's no
placement ambiguity for it to lose to) so a leftover old-named copy doesn't sit there as a
confusing duplicate. `pkg/postinstall`'s app-launch step was also reordered to try the explicit
install path *before* bundle-ID lookup (previously the other way around, specifically written to
cooperate with the relocatable behavior that no longer exists) -- bundle-ID lookup can still
resolve to any bundle sharing that ID, explicit path cannot.

**How to apply, revised:** don't trust that a `preinstall`/`postinstall` script can out-race or
override a `pkgbuild` component-plist placement decision (`BundleIsRelocatable`,
`BundleHasStrictIdentifier`) -- those keys control *where Installer decides to put something*,
which can be resolved before, or independently of, when scripts run. If a component's install
location must be deterministic (a fixed path, not "wherever a same-bundle-ID app happens to already
be registered"), set that directly in the component plist, don't try to steer it from a script.
Reserve script-side cleanup for genuinely orthogonal jobs (removing an old *duplicate*, not
un-recreating one) once the placement mechanism can't fight back against them.

## `AVCaptureDevice` device-discovery APIs can hang indefinitely when run as root, unsandboxed

**The trap:** `pkg/postinstall`'s device-verification loop (confirming the driver actually loaded
before declaring the install done) calls a small helper, `./ListInputDevices`
(`pkg/ListInputDevices.swift`), as a fallback for `system_profiler SPAudioDataType` not working on
CI. It uses `AVCaptureDevice.DiscoverySession`/`.devices(for:)` and had worked fine in every prior
test this session. On a real install, the whole install hung -- not slow, genuinely stuck --
confirmed via `ps`: `./ListInputDevices` still running after 6+ minutes, when a normal call
completes in milliseconds. The existing code only handled the helper *failing* (non-zero exit),
not *hanging* -- there was no timeout at all.

**What was actually true:** `postinstall` scripts run as root, invoked from a temporary,
ephemerally-signed sandbox location (`/tmp/PKInstallSandbox.*/Scripts/...`) with no real app bundle
and no `NSMicrophoneUsageDescription`. `AVCaptureDevice`'s discovery APIs appear to depend on a TCC
authorization decision under those conditions -- one that has no UI context to ever resolve in
(no windowed app, no bundle identity to prompt on behalf of, running as root) -- and simply wait
forever rather than failing fast or erroring out. This is exactly the class of thing `docs/
LESSONS.md` already warned about with `AVCaptureDevice`/microphone permission timing earlier this
session, just hitting a completely different call site: a plain CLI enumeration call, not a
user-facing permission request, can be subject to the same TCC machinery and hang the same way.

**How to apply:** any call into a TCC-gated framework (`AVFoundation`, `CoreLocation`,
`Contacts`, etc.) from a process that isn't a normal, windowed, properly-bundled app -- a root
install script, a headless CLI tool, anything running from a temp/ephemeral bundle -- should be
treated as capable of hanging indefinitely, not just failing. Wrap it with an actual timeout,
always, even (especially) if it "always worked in testing" -- a hang like this is exactly the kind
of thing that only shows up on a real install, on a real machine, never in a dev loop where the
calling context (a real signed app, already TCC-authorized from prior testing) is different enough
to not trigger it. macOS ships no `timeout(1)`/`gtimeout` by default, so the portable fix is a
plain background-job-plus-watchdog loop (fixed here: `pkg/postinstall`'s new
`run_list_input_devices` function) -- tested directly against a deliberately hanging fake binary
before trusting it (confirmed timeout at the intended bound, confirmed zero leftover processes) and
against a fast-succeeding one (confirmed real output still passes through), not just read and
assumed correct. The first version of that test also caught a second real bug in the timeout
wrapper itself: killing only the immediate child PID left a grandchild process orphaned and still
running when the child forked before hanging -- fixed by also killing children of the watched PID,
not just the PID itself, before trusting the wrapper as done.

## A ported XIB view forced into a fixed-height row container just overflows, doesn't shrink

**The trap:** the `NSMenu` -> `NSPanel` rearchitecture (see the earlier "NSMenu custom-view
controls" entry) ported several existing XIB view templates -- `outputVolumeView`,
`systemSoundsView`, `appVolumeView` -- into the new panel's `NSStackView` rows, each wrapped via a
shared `rowContainerWithControl:height:kBGMMainPanelRowHeight` helper (a fixed 22pt, matching a
flat single-line menu-item row). Builds and unit tests stayed clean throughout -- nothing about
this is checkable without actually looking at the rendered result. The first real look at the
panel (a user screenshot) showed the Auto-pause row and the master output volume row rendering on
top of each other, badly overlapping.

**What was actually true:** `outputVolumeView` (checked directly in the XIB source) is 47pt tall
by design -- a label positioned above the slider, not a single-line row. `systemSoundsView` is
only 16pt, which is why *that* row looked fine in the same screenshot despite using the identical
`kBGMMainPanelRowHeight` call -- it happened to fit inside 22pt with room to spare, the same code
path just didn't happen to be visibly broken for it. `rowContainerWithControl:height:` constrains
the *container*, not the inner view -- centering a 47pt view inside a 22pt box doesn't scale or
clip it, it just lets roughly 12.5pt of it hang off each edge, overlapping whatever's next to it in
the stack. No layout warning, no crash, no test failure -- constraints are satisfied; the box is
exactly 22pt, precisely as instructed. It just doesn't look right.

**How to apply:** when porting a fixed-size view (especially one designed for a different
container, like an `NSMenuItem`'s auto-sizing row) into a new fixed-height wrapper, the wrapper's
height needs to come from *that view's own actual size*, not a shared constant chosen for a
different kind of row. Read it directly off the view (`view.frame.size.height`, for a
`fixedFrame="YES"` XIB view whose frame is already its designed size once loaded) rather than
introducing a second hardcoded number that has to be kept in sync by hand. More generally: a
`NSStackView`/Auto Layout row that's the wrong height doesn't fail loudly -- it satisfies every
constraint and still overlaps its neighbor, because centering and fixed-size wrapping don't imply
clipping. This class of bug is invisible to `xcodebuild`, invisible to unit tests, and only ever
shows up in a real screenshot -- exactly why the standing rule here is to actually look at new UI
on a real screen before calling it done, not just confirm it compiles.

## Replacing NSMenu with NSStackView silently dropped NSMenu's free scrolling

**The trap:** the whole point of the `NSMenu` -> `NSPanel` rearchitecture (see the "NSMenu
custom-view controls" entry) was fixing real, confirmed bugs -- and it did. But nobody asked "what
did `NSMenu` do for free that a plain `NSStackView` doesn't?" until being told directly to keep
digging rather than call the fix-and-ship cycle done after one reported bug (the row-height
overlap, previous entry) got fixed. `NSMenu` automatically scrolls when its items don't fit the
screen -- scroll arrows appear at the top/bottom, standard, invisible behavior nobody thinks about
because it always works. `WCMainPanelContentView`'s "Your Apps" list -- one row per running app
producing audio, completely unbounded -- was a plain `NSStackView` added directly to the panel's
outer stack, sized purely by `fittingSize`, with no scroll view and no cap anywhere. Same for
`WCMainPanel`'s positioning: it computed a Y coordinate from content height with no floor, meaning
a tall enough panel would compute a position that put part of itself below the visible screen.

**What was actually true:** this wasn't a corner case. A user with a working desktop -- browser,
editor, terminal, chat client, a few background apps -- routinely has 8-10+ things producing or
capable of producing audio, which is exactly the population a per-app volume mixer exists to
serve. Every one of them gets a row. Nothing in the build, the unit tests, or even the first real
screenshot (which happened to be taken with a normal number of apps open) would ever surface this
-- it only shows up once someone's app count crosses whatever their specific screen height allows,
silently, with no error and no visual glitch at the boundary -- rows past the edge just aren't
reachable, and there's no scrollbar to notice is missing because there was never one there to look
for.

**How to apply:** when replacing a system control (`NSMenu`, `NSTableView`, anything with decades
of accumulated free behavior) with a custom-built equivalent, explicitly enumerate what the
original provided beyond its headline behavior -- keyboard navigation, accessibility, scrolling,
overflow handling, whatever isn't the *reason* for the replacement -- and check each one, not just
the specific thing the replacement was built to fix. A rewrite naturally gets scrutinized for
whether it fixed the target bug; it does not naturally get scrutinized for what it silently
stopped doing. Fixed here: the apps section wrapped in its own `NSScrollView` with a capped height
(recomputed before every show, since rows are added/removed live as apps launch and quit -- a
static one-time measurement would go stale), plus a defensive floor on the panel's Y position so
even content taller than the cap accounts for can't push it below the visible screen.

## `sudo whole-script.sh` instead of "run normally, it `sudo`s internally" breaks `tput`, silently

**The trap:** `uninstall.sh` was invoked as `sudo ./uninstall.sh` (told to the user this way,
repeatedly, across the same session that had *already* independently identified this exact
mistake once before and apparently didn't stick). Running it produced a single line --
`tput: unknown terminal "xterm-ghostty"` -- and returned straight to the prompt. No confirmation
prompt, no file-removal messages, nothing. Looked like the script silently did nothing.

**What was actually true:** `uninstall.sh` line 33 (before this fix) was `bold=$(tput bold)`,
followed immediately by `set -e`'s effect: a failing command substitution used as a bare
assignment aborts the whole script right there (confirmed directly: a minimal repro script with
`x=$(false)` under `set -e` dies at that exact line, while the identical failing command used
*inline* inside a larger string, like `echo "$(false)text"`, does not -- `set -e` only watches the
outer command's own exit status in that case, not substitutions embedded within it). `tput`
failed specifically because the script was run as root (`sudo ./uninstall.sh` runs the *entire*
script, including this line, as root from the start) -- and a custom terminal emulator's terminfo
entry (Ghostty ships `xterm-ghostty`, not a stock entry) is typically only reachable through the
*invoking user's* environment, not root's default one. The user never even saw
`uninstall.sh`'s own "this script is not intended to be run as root" warning, because that check
is a few lines *after* the `tput` line that was already fatal by the time execution would have
reached it.

**How to apply:**
- When a script documents its own correct invocation ("run it normally, it escalates internally
  where needed"), don't override that with an assumption that "just prefix sudo, it's safer" --
  running the whole thing as root can change its behavior in ways that have nothing to do with
  privilege, and this project's own uninstall/build scripts explicitly warn about exactly this.
  This was flagged once already earlier the same session and recommended again anyway -- worth
  actually checking a script's own header/warnings before restating a usage instruction, not
  relying on memory of having checked it once.
- `VAR=$(cmd)` and `echo "$(cmd)more text"` are **not equally dangerous** under `set -e` -- only
  the bare-assignment form aborts the script on failure; a substitution embedded in a larger
  command does not. Verified directly with a minimal repro before trusting this distinction,
  rather than assuming it from general `set -e` folklore (which is inconsistent enough across
  shells and Bash versions that "verified locally" beats "recalled").
- Any `VAR=$(tput ...)` used purely for cosmetic formatting (bold, color) should never be allowed
  to abort a whole script -- `VAR=$(tput ... 2>/dev/null || true)` degrades to an unstyled string
  instead of killing the run. Fixed in `uninstall.sh` and `_uninstall-non-interactive.sh`, the only
  two places this bare-assignment form actually existed -- checked directly (`grep` for the exact
  `VAR=$(tput` pattern), not assumed: `build_and_install.sh`/`install_prebuilt.sh`/`setup.sh` all
  use `tput` exclusively inline inside larger `echo` strings, the already-safe form, so they were
  never actually at risk from this specific interaction despite calling `tput` far more often.
- Verified the fix, not just read it: reproduced the *exact* reported error message
  (`tput: unknown terminal "xterm-ghostty"`, exit 3) by forcing `TERMINFO` to a nonexistent path
  against the old pattern, confirmed the new pattern survives the identical forced failure and
  reaches the line after it with empty (not erroring) fallback values.
