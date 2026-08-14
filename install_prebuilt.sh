#!/bin/bash
# vim: tw=100:

# This file is part of Background Music.
#
# Background Music is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 2 of the
# License, or (at your option) any later version.
#
# Background Music is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Background Music. If not, see <http://www.gnu.org/licenses/>.

#
# install_prebuilt.sh
#
# Copyright © 2026 Wavecraft contributors
#
# Installs a PREBUILT copy of Wavecraft (Background Music.app, Background Music Device.driver, and
# BGMXPCHelper.xpc) -- the ones sitting alongside this script, not something this script builds
# itself. This is what you get from a GitHub Release download, for people who don't have Xcode and
# don't want to build from source. If you cloned the actual source repo instead, use
# build_and_install.sh, not this script.
#
# Because these binaries weren't built on your Mac, they're not automatically trusted the way a
# local build is -- macOS marks anything downloaded from the internet with a "quarantine" flag, and
# Gatekeeper checks that flag before letting it run. Since this project doesn't have an Apple
# Developer ID to sign and notarize a release (that costs $99/year -- see README.md), you'll likely
# see a security warning the first time you try to open Wavecraft.app after this script
# installs it. See README.md's "Installing a prebuilt release" section for exactly what that
# warning looks like and how to get past it -- it's expected, not a sign anything went wrong.
#

# Safe mode
set -euo pipefail
IFS=$'\n\t'
set -o errtrace

# Go to the directory this script is in, so it finds the bundled app/driver/helper regardless of
# where it's run from.
cd "$( dirname "${BASH_SOURCE[0]}" )"

bold_face() {
    echo $(tput bold)$*$(tput sgr0)
}

error_handler() {
    echo >&2
    echo "$(tput setaf 9)ERROR$(tput sgr0): Install failed at line $1." >&2
    echo "The last command was (probably): $3" >&2
    echo "which exited with status $2." >&2
    echo >&2
    echo "If this doesn't make sense, building from source instead (see README.md's \"Build from" \
         "source\" section) gets you much more detailed error messages, since that path runs the" \
         "real build_and_install.sh." >&2
}
trap 'error_handler ${LINENO} $? "${BASH_COMMAND}"' ERR

APP_DIR="Wavecraft.app"
DRIVER_DIR="Background Music Device.driver"
XPC_HELPER_DIR="BGMXPCHelper.xpc"

APP_INSTALL_PATH="/Applications"
DRIVER_INSTALL_PATH="/Library/Audio/Plug-Ins/HAL"
LAUNCHD_PLIST="/Library/LaunchDaemons/com.bearisdriving.BGM.XPCHelper.plist"
COREAUDIOD_PLIST="/System/Library/LaunchDaemons/com.apple.audio.coreaudiod.plist"

# Make sure the prebuilt bundles are actually here -- if someone runs this script from the wrong
# directory, or a download was incomplete, fail early with a clear message instead of partway
# through the install.
for BUNDLE in "${APP_DIR}" "${DRIVER_DIR}" "${XPC_HELPER_DIR}" "post_install.sh"; do
    if [[ ! -e "${BUNDLE}" ]]; then
        echo "$(tput setaf 9)ERROR$(tput sgr0): Couldn't find \"${BUNDLE}\" next to this script." \
             >&2
        echo "Make sure you extracted the whole release zip, and are running this script from" \
             "inside the extracted folder, not after moving it elsewhere." >&2
        exit 1
    fi
done

echo "$(bold_face About to install Wavecraft) from the prebuilt files in this folder."
echo
echo "What's about to happen, and why it needs your password:"
echo " - A virtual audio device gets installed to ${DRIVER_INSTALL_PATH}/. This is what lets"
echo "   Wavecraft see (and remix) every app's audio -- macOS has no other way to do that. It only"
echo "   loads from that one system-owned path, which is why this step needs sudo; there's no"
echo "   per-user alternative."
echo " - A small helper service gets registered with launchd, to coordinate between the driver"
echo "   above and the app below."
echo " - The Wavecraft app gets installed and opened automatically once everything else is in"
echo "   place."
echo
echo "This install will place:"
echo " - ${APP_INSTALL_PATH}/${APP_DIR}"
echo " - ${DRIVER_INSTALL_PATH}/${DRIVER_DIR}"
echo " - a small helper service under /usr/local/libexec or /Library/Application Support"
echo " - ${LAUNCHD_PLIST}"
echo
echo "Partway through, coreaudiod (the system audio process) gets restarted so it picks up the"
echo "newly-installed driver -- audio will glitch briefly when that happens, so pause anything"
echo "that's playing first."
echo
echo "$(tput setaf 11)One more thing:$(tput sgr0) since these files were downloaded rather than"
echo "built on this Mac, macOS may show a security warning the first time you try to open"
echo "Wavecraft after this finishes -- that's expected, not a sign of a problem. See README.md's"
echo "\"Installing a prebuilt release\" section for exactly what to click."
echo

read -p "Continue (y/N)? " CONTINUE_INSTALLATION
if [[ "${CONTINUE_INSTALLATION}" != "y" ]] && [[ "${CONTINUE_INSTALLATION}" != "Y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

if ! sudo -v; then
    echo "$(tput setaf 9)ERROR$(tput sgr0): This script must be run by a user with administrator" \
         "(sudo) privileges." >&2
    exit 1
fi
echo

# 1. Driver.

echo "[1/3] Installing the virtual audio device $(bold_face ${DRIVER_DIR}) to" \
     "$(bold_face ${DRIVER_INSTALL_PATH})"

sudo rm -rf "${DRIVER_INSTALL_PATH}/${DRIVER_DIR}"
sudo cp -R "${DRIVER_DIR}" "${DRIVER_INSTALL_PATH}/"
sudo chown -R root:wheel "${DRIVER_INSTALL_PATH}/${DRIVER_DIR}"

# 2. XPC helper.

echo "[2/3] Installing $(bold_face ${XPC_HELPER_DIR})"

# Find a safe install location the same way the real build does -- reuses the actual logic
# (already bundled inside the .xpc as a resource, not something this script reimplements).
XPC_HELPER_RESOURCES="${XPC_HELPER_DIR}/Contents/Resources"
XPC_HELPER_INSTALL_DIR="$(bash "${XPC_HELPER_RESOURCES}/safe_install_dir.sh" -y)"

# safe_install_dir.sh -y silently falls back to an unsafe directory (rather than prompting) if
# neither of its normal candidates checks out -- rare (only if /usr/local/libexec and
# /Library/Application Support are both already in a bad state, e.g. some Homebrew setups), but
# since -y means it won't ask, check it ourselves and at least warn instead of installing a
# privileged helper into an insecure location with zero indication. pkg/postinstall's GUI
# installer path does this same second check via an alert; this is the terminal equivalent.
if [[ "$(bash "${XPC_HELPER_RESOURCES}/safe_install_dir.sh" "${XPC_HELPER_INSTALL_DIR}")" != "1" ]]; then
    echo
    echo "$(tput setaf 11)WARNING$(tput sgr0): ${XPC_HELPER_INSTALL_DIR} (and all of its parent"
    echo "directories) should be owned by 'root', with the group 'wheel', and have permissions 755"
    echo "(rwxr-xr-x) for it to be safe to install a privileged helper there -- this Mac's copy"
    echo "isn't set up that way. Wavecraft will still work if you continue, but this is worth fixing"
    echo "(check ownership/permissions on that path and its parents)."
    echo
fi

sudo rm -rf "${XPC_HELPER_INSTALL_DIR}/${XPC_HELPER_DIR}"
sudo mkdir -p "${XPC_HELPER_INSTALL_DIR}"
sudo cp -R "${XPC_HELPER_DIR}" "${XPC_HELPER_INSTALL_DIR}/"
sudo chown -R root:wheel "${XPC_HELPER_INSTALL_DIR}/${XPC_HELPER_DIR}"

# Since macOS 14.0, a quarantined launchd daemon (as opposed to a GUI app) just gets silently
# blocked by Gatekeeper with no dialog to click through -- there's no right-click-Open or System
# Settings entry for a background daemon the way there is for Wavecraft.app below. Strip it
# explicitly, matching pkg/postinstall's handling of this exact bundle.
sudo xattr -dr com.apple.quarantine "${XPC_HELPER_INSTALL_DIR}/${XPC_HELPER_DIR}" 2>/dev/null || true

# post_install.sh (bundled next to this script, not inside the .xpc -- it's a build-time script,
# not a bundle resource in the real Xcode project either) registers the launchd plist and creates
# the unprivileged user BGMXPCHelper runs as. Same script the real build uses, just invoked
# directly instead of by xcodebuild.
#
# Positional args, not env vars: post_install.sh only falls back to reading INSTALL_DIR/
# EXECUTABLE_PATH from the environment when $1/$2 are empty, but its fallback for $3 specifically
# checks Xcode-only build variables (TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH) instead
# of a RESOURCES_PATH env var -- those don't exist outside an actual xcodebuild invocation, so
# setting RESOURCES_PATH alone here would always fail with "Environment variable TARGET_BUILD_DIR
# was not set." Positional args ($1=INSTALL_DIR, $2=EXECUTABLE_PATH, $3=RESOURCES_PATH, per
# post_install.sh's own argument parsing) sidestep that fallback entirely and are what it actually
# reads, whether called this way or by xcodebuild's Run Script phase.
bash post_install.sh \
    "${XPC_HELPER_INSTALL_DIR}" \
    "${XPC_HELPER_DIR}/Contents/MacOS/BGMXPCHelper" \
    "${XPC_HELPER_INSTALL_DIR}/${XPC_HELPER_RESOURCES}"

# 3. App.

echo "[3/3] Installing $(bold_face ${APP_DIR}) to $(bold_face ${APP_INSTALL_PATH})"

sudo rm -rf "${APP_INSTALL_PATH}/${APP_DIR}"
sudo cp -R "${APP_DIR}" "${APP_INSTALL_PATH}/"
sudo chown -R "$(whoami):admin" "${APP_INSTALL_PATH}/${APP_DIR}"

# Restart coreaudiod so it picks up the newly-installed driver.

echo "Restarting coreaudiod to load the virtual audio device."

RESTARTED_COREAUDIOD=0
(sudo killall coreaudiod &>/dev/null || \
    sudo launchctl kickstart -k system/com.apple.audio.coreaudiod &>/dev/null || \
    sudo launchctl kill SIGTERM system/com.apple.audio.coreaudiod &>/dev/null || \
    sudo launchctl kill TERM system/com.apple.audio.coreaudiod &>/dev/null || \
    sudo launchctl kill 15 system/com.apple.audio.coreaudiod &>/dev/null || \
    sudo launchctl kill -15 system/com.apple.audio.coreaudiod &>/dev/null || \
    (sudo launchctl unload "${COREAUDIOD_PLIST}" &>/dev/null && \
        sudo launchctl load "${COREAUDIOD_PLIST}" &>/dev/null)) && \
    RESTARTED_COREAUDIOD=1

if [[ "${RESTARTED_COREAUDIOD}" -ne 1 ]]; then
    echo "$(tput setaf 11)WARNING$(tput sgr0): couldn't restart coreaudiod through any of the" \
         "usual methods -- the driver is installed, but it may not actually be loaded until you" \
         "restart this Mac." >&2
fi

# Don't just sleep and hope -- actually confirm the device came up before calling this done, the
# same way pkg/postinstall (the .pkg installer's equivalent step) does. A silent failure here
# would otherwise look identical to a successful install from this script's own output.
echo "Confirming the virtual audio device is available."
DEVICE_FOUND=0
for ATTEMPT in 1 2 3 4 5; do
    if system_profiler SPAudioDataType 2>/dev/null | grep -q "Wavecraft"; then
        DEVICE_FOUND=1
        break
    fi
    if [[ "${ATTEMPT}" -lt 5 ]]; then
        sleep 3
    fi
done

if [[ "${DEVICE_FOUND}" -ne 1 ]]; then
    echo "$(tput setaf 9)ERROR$(tput sgr0): The virtual audio device never showed up in" \
         "system_profiler after restarting coreaudiod. The driver and helper are installed, but" \
         "something's preventing coreaudiod from actually loading it." >&2
    echo "Try restarting your Mac, then check with: system_profiler SPAudioDataType | grep -A5" \
         "'Wavecraft'" >&2
    exit 1
fi

sudo -k

# macOS's cp preserves extended attributes by default, including the "quarantine" flag this
# script's own downloaded copy of Wavecraft.app almost certainly has (anything downloaded
# via a browser gets one) -- so the installed copy likely carries it too, and Gatekeeper is likely
# to block this `open` the first time. Don't rely on `open`'s exit status to detect that: its
# behavior around Gatekeeper blocks isn't consistent across macOS versions (older versions return
# nonzero and macOS shows a dialog with an "Open" button right in it; some newer versions return 0
# while silently refusing to launch, requiring System Settings instead). Always show the guidance
# below rather than only conditionally.
echo "Opening Wavecraft."
open "${APP_INSTALL_PATH}/${APP_DIR}" &>/dev/null || true

echo
echo "Done."
echo
echo "$(bold_face What happens next):"
echo "If a security dialog appeared just now (\"Apple could not verify...\" or similar) -- or"
echo "nothing visibly opened -- that's the expected Gatekeeper warning mentioned earlier, not a"
echo "sign anything went wrong. Depending on your macOS version, one of these will get you past"
echo "it (both are one-time, you won't see this again after):"
echo "  1. Open Finder, go to Applications, right-click \"${APP_DIR}\", choose Open, then click"
echo "     Open again on the dialog that appears."
echo "  2. If that doesn't show an Open option: System Settings > Privacy & Security, scroll down"
echo "     to the message about \"${APP_DIR}\" being blocked, and click Open Anyway."
echo
echo "Once it's actually open:"
echo " - You should see a dialog asking to allow \"Microphone\" access -- click Continue on the"
echo "   explanation, then Allow on the actual system prompt. If you miss it or click Don't"
echo "   Allow, Wavecraft will show you a button that jumps straight to the right Privacy &"
echo "   Security setting."
echo " - Once that's granted, look for the Wavecraft icon (four bars) in your menu bar -- that's"
echo "   where every control lives: per-app volume, per-app EQ, per-app output routing, and the"
echo "   output device picker."
echo " - Full walkthrough of every control: docs/GUIDE.md, if you have the source repo, or"
echo "   https://github.com/Phaenex/wavecraft/blob/main/docs/GUIDE.md online."
echo " - Something not working right: docs/TROUBLESHOOTING.md, or"
echo "   https://github.com/Phaenex/wavecraft/blob/main/docs/TROUBLESHOOTING.md online."
