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
# package_release.sh
#
# Copyright © 2026 Wavecraft contributors
#
# Builds Release copies of the driver, XPC helper, and app (without installing them -- just
# `build_and_install.sh -b`) and packages them, plus install_prebuilt.sh and its dependencies, into
# a zip anyone can download and run without needing Xcode. This is what gets attached to a GitHub
# Release -- see README.md's "Installing a prebuilt release" section for what the person on the
# other end experiences.
#
# Usage: ./package_release.sh [version]
#   version defaults to today's date (YYYY-MM-DD) if not given.
#

set -euo pipefail
IFS=$'\n\t'

cd "$( dirname "${BASH_SOURCE[0]}" )"

VERSION="${1:-$(date +%Y-%m-%d)}"
STAGING_DIR="release-staging/Wavecraft-${VERSION}"
OUTPUT_ZIP="Wavecraft-${VERSION}-macOS.zip"

APP_BUILD_PATH="BGMApp/build/Release/Background Music.app"
XPC_BUILD_PATH="BGMApp/build/Release/BGMXPCHelper.xpc"
DRIVER_BUILD_PATH="BGMDriver/build/Release/Background Music Device.driver"

echo "Building Release copies of the driver, XPC helper, and app (not installing)..."
./build_and_install.sh -b

for PRODUCT in "${APP_BUILD_PATH}" "${XPC_BUILD_PATH}" "${DRIVER_BUILD_PATH}"; do
    if [[ ! -e "${PRODUCT}" ]]; then
        echo "ERROR: Expected build product missing: ${PRODUCT}" >&2
        echo "build_and_install.sh -b should have created this. Check its output above." >&2
        exit 1
    fi
done

echo
echo "Staging release contents in ${STAGING_DIR}..."
rm -rf "release-staging"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_BUILD_PATH}" "${STAGING_DIR}/"
cp -R "${XPC_BUILD_PATH}" "${STAGING_DIR}/"
cp -R "${DRIVER_BUILD_PATH}" "${STAGING_DIR}/"

# Strip debug symbols -- ~10MB of dSYM data nobody downloading a release build needs, only useful
# for symbolicating crash reports during development (where the real build products, not this
# packaged copy, already have it).
find "${STAGING_DIR}" -iname "*.dSYM" -exec rm -rf {} + 2>/dev/null || true
cp "BGMApp/BGMXPCHelper/post_install.sh" "${STAGING_DIR}/"
# Renamed to .command so it's actually double-clickable in Finder -- a plain .sh file just opens in
# a text editor by default, which defeats the entire point of a no-terminal-typing install path.
cp "install_prebuilt.sh" "${STAGING_DIR}/Install Wavecraft.command"
chmod +x "${STAGING_DIR}/Install Wavecraft.command" "${STAGING_DIR}/post_install.sh"

cat > "${STAGING_DIR}/README.txt" << 'EOF'
Wavecraft -- a free, native per-app audio mixer for macOS
https://github.com/Phaenex/wavecraft

TO INSTALL:
    Double-click "Install Wavecraft.command". It'll explain what it's doing and ask for
    your Mac password partway through (needed to install the audio driver).

You'll likely see a macOS security warning the first time you try to open either this
installer or Wavecraft itself -- that's expected, not a sign anything is broken. It happens
because this was downloaded rather than built on your Mac, and this project doesn't have a
paid Apple Developer ID to sign around that yet. Full explanation and exactly what to click:
https://github.com/Phaenex/wavecraft#installing-a-prebuilt-release-what-the-warning-means

Full docs: https://github.com/Phaenex/wavecraft/blob/main/docs/GUIDE.md
Something wrong? https://github.com/Phaenex/wavecraft/blob/main/docs/TROUBLESHOOTING.md
EOF

echo "Zipping..."
(cd release-staging && zip -rq -X "../${OUTPUT_ZIP}" "Wavecraft-${VERSION}")
rm -rf "release-staging"

echo
echo "Done: $(pwd)/${OUTPUT_ZIP} ($(du -h "${OUTPUT_ZIP}" | cut -f1))"
echo "Contents:"
unzip -l "${OUTPUT_ZIP}"
