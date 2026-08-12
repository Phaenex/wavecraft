#!/bin/bash
#
# setup.sh
#
# One-shot build + install + verify for this fork. Run this directly in a real
# Terminal window (not through an agent's proxied shell) so the sudo password
# prompt from build_and_install.sh actually has a TTY to read from.
#
# Usage: ./setup.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

bold() { echo "$(tput bold)$*$(tput sgr0)"; }
pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; }

bold "== 1/2: Build + install (this is where sudo will prompt you) =="
./build_and_install.sh

bold "== 2/2: Verify =="

OK=1

if ls "/Library/Audio/Plug-Ins/HAL/" 2>/dev/null | grep -qi background; then
    pass "Driver present in /Library/Audio/Plug-Ins/HAL/"
else
    fail "Driver not found in /Library/Audio/Plug-Ins/HAL/"
    OK=0
fi

if system_profiler SPAudioDataType 2>/dev/null | grep -qi "background music"; then
    pass "coreaudiod sees the Background Music device"
else
    fail "coreaudiod does not list a Background Music device"
    OK=0
fi

if launchctl list 2>/dev/null | grep -qi bearisdriving; then
    pass "BGMXPCHelper is registered with launchd"
else
    fail "BGMXPCHelper launchd job not found"
    OK=0
fi

if [ -d "/Applications/Background Music.app" ]; then
    pass "App installed to /Applications"
else
    fail "App not found in /Applications"
    OK=0
fi

echo
if [ "$OK" -eq 1 ]; then
    bold "All checks passed. Two things still need you:"
    echo "  1. Launch it:  open -a 'Background Music'"
    echo "  2. First run will ask for Microphone permission in System Settings —"
    echo "     approve it. It's not actually listening to your mic; macOS just"
    echo "     classifies the virtual input device that way."
    echo "  3. Set 'Background Music' as your output device (menu bar icon, or"
    echo "     System Settings > Sound > Output), then check that per-app"
    echo "     sliders in the Background Music menu actually move real volume."
else
    bold "Something didn't install cleanly — see the ✗ lines above."
    echo "Check build_and_install.log in this directory for details."
fi
