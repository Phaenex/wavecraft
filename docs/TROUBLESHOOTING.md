# Troubleshooting

Every entry here is something that actually happened while building this fork, not a
hypothetical. If you hit something not listed here, add it once you've fixed it — that's the
whole point of this file. See also `docs/LESSONS.md` for the *why* behind non-obvious decisions,
and `docs/PROCESS-TAP-ROUTING.md` for anything specific to per-app output routing.

## Build

### `-Werror` fails on `implicit conversion changes signedness`

This project treats `-Wsign-conversion` as an error. Any `int` used to index a `std::array` (or
anything with a `size_t`-based `operator[]`) will fail. Use `size_t` for indices/channel numbers
throughout, not `int`, and cast explicitly at the one or two places you can't avoid an `int` (loop
bounds coming from a `constexpr int` count, for example).

### Linker error: `Undefined symbols ... referenced from ...` for a `static constexpr` member

This project's `CLANG_CXX_LANGUAGE_STANDARD` is `c++0x` (C++11), confirmed by grepping
`project.pbxproj` — don't assume C++17 just because the syntax compiles. C++17 made
`static constexpr` class data members implicitly `inline`; C++11 didn't, so anything that
ODR-uses one (a range-based `for` loop over it, binding a reference to it) needs an explicit
out-of-class definition in a `.cpp` file:

```cpp
constexpr std::array<double, MyClass::kSize> MyClass::kMyArray;
```

### A new `.h`/`.cpp` file compiles from the command line but Xcode doesn't see it / tests don't link against it

New files aren't picked up automatically — Xcode needs an explicit file reference in
`project.pbxproj`. **Never hand-edit `project.pbxproj`** — it's a fragile, easy-to-corrupt format.
Use the `xcodeproj` Ruby gem instead (already installed on this machine, `gem list xcodeproj`
confirms it):

```ruby
require "xcodeproj"
proj = Xcodeproj::Project.open("BGMDriver/BGMDriver.xcodeproj")
group = proj.main_group.find_subpath("BGMDriver/DeviceClients", false)
ref = group.new_reference("MyNewFile.cpp")
proj.targets.find { |t| t.name == "Background Music Device" }.source_build_phase.add_file_reference(ref)
proj.save
```

Add the same file to `BGMDriverTests`' Sources phase too if the test target needs to compile it
directly (check with `t.source_build_phase.files.any? { |f| f.file_ref&.path == "SomeExistingFile.cpp" }`
against a file you know the target already compiles, to see whether that target recompiles driver
sources directly rather than linking a binary).

## Install

### `sudo: a terminal is required to read the password`

`./build_and_install.sh` (or the `setup.sh` wrapper) needs `sudo` to install the driver into
`/Library/Audio/Plug-Ins/HAL/` and reload `coreaudiod`. This **must** be run directly in a real
Terminal window — not through an agent's proxied/non-interactive shell, which has no TTY for the
password prompt to read from and will fail exactly this way (confirmed empirically, see
`docs/LESSONS.md`). Run:

```
cd /Users/damato/Projects/wavecraft && ./setup.sh
```

### Verifying an install actually worked

Don't trust "the script exited 0" alone. Check all four signs of a real install:

```bash
ls "/Library/Audio/Plug-Ins/HAL/" | grep -i background          # driver file present
system_profiler SPAudioDataType | grep -i "background music"    # coreaudiod actually loaded it
launchctl print system/com.bearisdriving.BGM.XPCHelper | grep "state = running"  # NOT `launchctl list` -- see below
ls "/Applications/Wavecraft.app"                          # app installed
```

**`launchctl list` (no `sudo`) cannot see root-owned system `LaunchDaemon`s** — it only shows the
calling user's launchd domain. Checking the XPC helper with plain `launchctl list` gives a false
negative even when the helper is actually running. Use `launchctl print system/<label>` instead,
which doesn't need `sudo` either and actually reports the daemon's real state.

## Icons

### Icon doesn't update in Finder/Dock after a rebuild

The installed app in `/Applications` is a copy, not a symlink — rebuilding in Xcode doesn't touch
it. After changing icon assets:

```bash
rsync -a --delete "$(xcodebuild -workspace BGM.xcworkspace -scheme 'Wavecraft' -configuration Release -showBuildSettings | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')/Wavecraft.app/" "/Applications/Wavecraft.app/"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "/Applications/Wavecraft.app"
```

This doesn't need `sudo` — `build_and_install.sh` already `chown`s the installed app to your user.
If Finder still shows the old icon after that, it's an icon cache issue, not a real problem:
`killall Finder Dock` forces a refresh, but that's disruptive (closes/resets Finder windows and the
Dock), so only do it if the icon still looks wrong after the steps above and you actually need to
confirm visually.

### `DeviceIcon.icns` (shown in Audio MIDI Setup / System Settings → Sound) still shows the old icon

That file lives inside the root-owned driver bundle at
`/Library/Audio/Plug-Ins/HAL/Background Music Device.driver/`. Unlike the app icon, there's no
user-writable shortcut — it needs a real `./setup.sh` reinstall (`sudo`) to take effect.

### Verifying icon assets are actually correct, not just present

`tools/verify-icons.py` measures every `AppIcon.appiconset` PNG's real pixel dimensions against
what `Contents.json` declares (rather than trusting the filename or a generation script), and
round-trips `DeviceIcon.icns` through `iconutil` to confirm it contains real image data. Run it
after regenerating any icon:

```bash
python3 tools/verify-icons.py
```

## Process Taps (per-app output routing)

### `AudioHardwareCreateProcessTap` fails

Check the `OSStatus` printed — `tools/tap-poc/tap_poc.mm` decodes it to a four-character code
where possible. If it looks like an authorization failure, check System Settings → Privacy &
Security for a permission category related to audio capture (likely grouped near Screen & System
Audio Recording, since taps capture another process's audio). This did **not** happen in this
project's own testing (an ad-hoc "Sign to Run Locally" build worked immediately, no prompt), so if
it happens now, something about the environment changed — don't assume it's expected.

### Testing a tap without needing GUI automation permissions

Don't drive a GUI app via AppleScript/`osascript` to generate test audio unless you specifically
need to test a bundle-ID-based tap — `osascript` controlling another app needs "Automation"
permission granted per-target-app in System Settings, and if it's not already granted, the command
hangs waiting on a permission dialog it can't get an answer to (confirmed: cost real time this
session). Prefer a plain background process instead (`afplay`, no bundle ID, no automation
permission needed at all) with `CATapDescription.processes` (PID-based tapping, translated via
`kAudioHardwarePropertyTranslatePIDToProcessObject`) rather than `CATapDescription.bundleIDs`.

## Screenshots / visual verification

`screencapture` fails with `could not create image from display` (or `could not create image from
rect`) when the calling process doesn't have Screen Recording permission — this is a real macOS
security gate, not a bug, and can't be granted by any command run from here. If a change needs
visual confirmation and `screencapture` fails this way, that confirmation needs to happen by a
human looking at the actual screen, not by a script.
