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
# see a security warning the first time you try to open Background Music.app after this script
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

APP_DIR="Background Music.app"
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
echo " - The Wavecraft app (still shows as \"Background Music\" in Finder/Activity Monitor -- only"
echo "   this project's own branding changed, not the underlying app/driver names) gets installed"
echo "   and opened automatically once everything else is in place."
echo
echo "This install will place:"
echo " - ${APP_INSTALL_PATH}/${APP_DIR}"
echo " - ${DRIVER_INSTALL_PATH}/${DRIVER_DIR}"
echo " - a small helper service under /usr/local/libexec or /Library/Application Support"
echo " - ${LAUNCHD_PLIST}"
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

sudo rm -rf "${XPC_HELPER_INSTALL_DIR}/${XPC_HELPER_DIR}"
sudo mkdir -p "${XPC_HELPER_INSTALL_DIR}"
sudo cp -R "${XPC_HELPER_DIR}" "${XPC_HELPER_INSTALL_DIR}/"
sudo chown -R root:wheel "${XPC_HELPER_INSTALL_DIR}/${XPC_HELPER_DIR}"

# post_install.sh (bundled next to this script, not inside the .xpc -- it's a build-time script,
# not a bundle resource in the real Xcode project either) registers the launchd plist and creates
# the unprivileged user BGMXPCHelper runs as. Same script the real build uses, just invoked
# directly instead of by xcodebuild.
INSTALL_DIR="${XPC_HELPER_INSTALL_DIR}" \
EXECUTABLE_PATH="${XPC_HELPER_DIR}/Contents/MacOS/BGMXPCHelper" \
RESOURCES_PATH="${XPC_HELPER_INSTALL_DIR}/${XPC_HELPER_RESOURCES}" \
    bash post_install.sh

# 3. App.

echo "[3/3] Installing $(bold_face ${APP_DIR}) to $(bold_face ${APP_INSTALL_PATH})"

sudo rm -rf "${APP_INSTALL_PATH}/${APP_DIR}"
sudo cp -R "${APP_DIR}" "${APP_INSTALL_PATH}/"
sudo chown -R "$(whoami):admin" "${APP_INSTALL_PATH}/${APP_DIR}"

# Restart coreaudiod so it picks up the newly-installed driver.

echo "Restarting coreaudiod to load the virtual audio device."

(sudo killall coreaudiod &>/dev/null || \
    sudo launchctl kickstart -k system/com.apple.audio.coreaudiod &>/dev/null || \
    sudo launchctl kill SIGTERM system/com.apple.audio.coreaudiod &>/dev/null || \
    sudo launchctl kill TERM system/com.apple.audio.coreaudiod &>/dev/null || \
    sudo launchctl kill 15 system/com.apple.audio.coreaudiod &>/dev/null || \
    sudo launchctl kill -15 system/com.apple.audio.coreaudiod &>/dev/null || \
    (sudo launchctl unload "${COREAUDIOD_PLIST}" &>/dev/null && \
        sudo launchctl load "${COREAUDIOD_PLIST}" &>/dev/null)) && \
    sleep 5

sudo -k

# macOS's cp preserves extended attributes by default, including the "quarantine" flag this
# script's own downloaded copy of Background Music.app almost certainly has (anything downloaded
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
