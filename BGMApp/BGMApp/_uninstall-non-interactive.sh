#!/bin/bash
# vim: tw=120:

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
# _uninstall-non-interactive.sh
#
# Copyright © 2016 Nick Jacques
# Copyright © 2016, 2017, 2021 Kyle Neideck
#
# Removes BGMApp, BGMDriver and BGMXPCHelper from the system immediately. Run by uninstall.sh and the Homebrew formula.
#

# TODO: Log commands and their output to uninstall.log, like build_and_install.sh does, rather than just sending
#       everything to /dev/null.

# TODO: Show a custom error message if the script fails, like build_and_install.sh.

# Halt on errors.
set -e

PATH=/bin:/sbin:/usr/bin:/usr/sbin; export PATH

bold=$(tput bold)
normal=$(tput sgr0)

app_path="/Applications/Wavecraft.app"
# The app itself used to install as "Background Music.app" -- still checked here (not just the
# new path above) so an install from before that rename gets fully cleaned up too. This isn't just
# a leftover-folder concern: pkgbuild's relocatable bundle handling upgrades an existing bundle
# *in place* by matching bundle ID via Launch Services, not by path, so a stale copy at this old
# path can silently keep absorbing every future install under its old name -- confirmed for real,
# see docs/LESSONS.md.
app_path_legacy="/Applications/Background Music.app"
driver_path="/Library/Audio/Plug-Ins/HAL/Background Music Device.driver"
xpc_path1="/usr/local/libexec/BGMXPCHelper.xpc"
xpc_path2="/Library/Application Support/Wavecraft/BGMXPCHelper.xpc"
# The backup install location safe_install_dir.sh uses was itself renamed alongside this app --
# still checked here (not just the new path above) so an existing install from before that rename
# still gets fully cleaned up, not just new ones.
xpc_path2_legacy="/Library/Application Support/Background Music/BGMXPCHelper.xpc"

# Check that files/directories are at most this big before we delete them, just to be safe. Note that the bundles can
# include debug symbols, e.g. if you use build_and_install.sh, which makes them a lot bigger.
max_size_mb_for_rm=30

file_paths=("${app_path}" "${app_path_legacy}" "${driver_path}" "${xpc_path1}" "${xpc_path2}" "${xpc_path2_legacy}")

bgmapp_process_name="Wavecraft"

launchd_plist_label="com.bearisdriving.BGM.XPCHelper"
launchd_plist="/Library/LaunchDaemons/${launchd_plist_label}.plist"

coreaudiod_plist="/System/Library/LaunchDaemons/com.apple.audio.coreaudiod.plist"

user_group_name="_BGMXPCHelper"

# We move files to this temp directory and then move the directory to the user's trash at the end of the script.
# Unfortunately, this means that if the user tries to use the "put back" feature the files will just go back to the
# temp directory.
trash_dir="$(mktemp -d -t UninstalledWavecraftFiles)/"

# Takes a path to a file or directory and returns false if the file/directory is larger than $max_size_mb_for_rm.
function size_check {
  local size="$(du -sm "$1" 2>/dev/null | awk '{ print $1 }')"
  [[ "${size}" =~ ^[0-9]+$ ]] && [[ "${size}" -le ${max_size_mb_for_rm} ]]
}

# Ensure that the user can use sudo. (Use `sudo true` instead of `sudo -v` because that causes a
# password prompt in Travis CI builds for some reason.)
if ! sudo true; then
  echo "ERROR: This script must be run by a user with administrator (sudo) privileges." >&2
  exit 1
fi

# Try to kill Wavecraft.app, in case it's running.
killall "${bgmapp_process_name}" &>/dev/null || true

# TODO: Use
#         mdfind kMDItemCFBundleIdentifier = "com.bearisdriving.BGM.App"
#       to offer alternatives if Wavecraft.app isn't installed to /Applications. Or we could open it with
#         open -b "com.bearisdriving.BGM.App" -- delete-yourself
#       and have Wavecraft.app delete itself and close when it gets the "delete-yourself" argument. Though
#       that wouldn't be backwards compatible.

# Remove the files defined in file_paths
for path in "${file_paths[@]}"; do
  if [ -e "${path}" ]; then
    if size_check "${path}"; then
      echo "Moving \"${path}\" to the trash."
      sudo mv -f "${path}" "${trash_dir}" &>/dev/null
    else
      echo "Error: Refusing to delete \"${path}\" because it was much larger than expected." >&2
    fi
  fi
done

echo "Removing Wavecraft launchd service."
sudo launchctl list | grep "${launchd_plist_label}" >/dev/null && \
  (sudo launchctl bootout system "${launchd_plist}" &>/dev/null || \
    # Try older versions of the command in case the user has an old version of launchctl.
    sudo launchctl unbootstrap system "${launchd_plist}" &>/dev/null || \
    sudo launchctl unload "${launchd_plist}" >/dev/null) || \
  echo "  Service does not exist."

echo "Removing Wavecraft launchd service configuration file."
if [ -e "${launchd_plist}" ]; then
  sudo mv -f "${launchd_plist}" "${trash_dir}"
fi

# Be paranoid about user_group_name because we really don't want to delete every user account.
if ! [[ -z ${user_group_name} ]] && [[ "${user_group_name}" != "" ]]; then
  echo "Removing Wavecraft user."
  dscl . -read /Users/"${user_group_name}" &>/dev/null && \
    sudo dscl . -delete /Users/"${user_group_name}" 1>/dev/null || \
    echo "  User does not exist."

  echo "Removing Wavecraft group."
  dscl . -read /Groups/"${user_group_name}" &>/dev/null && \
    sudo dscl . -delete /Groups/"${user_group_name}" 1>/dev/null || \
    echo "  Group does not exist."
else
  echo "Warning: could not delete the Wavecraft user/group due to an internal error in $0." >&2
fi

# Without this, a later reinstall's first launch can show stale results for both permissions --
# confirmed for real this session: an old grant/denial decision survives an uninstall (TCC data is
# keyed by bundle ID, stored completely separately from the app bundle on disk, and isn't touched
# by deleting it) and gets misread against whatever's reinstalled next, showing a permission as
# already decided when the user never actually made that choice for the new install. Not silenced
# with `&>/dev/null` -- tccutil can fail for reasons worth actually seeing (e.g. whatever's running
# this script not having the standing to modify TCC's database at all), and a hidden failure here
# is worse than a visible one: it would look identical to success while quietly not doing anything.
# Still `|| true` on each -- a courtesy reset shouldn't abort the rest of the uninstall if it fails.
echo "Resetting Wavecraft's Microphone and Accessibility permissions."
bundle_id="com.bearisdriving.BGM.App"
tccutil reset Microphone "${bundle_id}" || echo "  (tccutil reset Microphone failed -- see above)"
tccutil reset Accessibility "${bundle_id}" || echo "  (tccutil reset Accessibility failed -- see above)"

# We're done removing files, so now actually move trash_dir into the trash. And if that fails, just delete it normally.
osascript -e 'tell application id "com.apple.finder"
                move the POSIX file "'"${trash_dir}"'" to trash
              end tell' >/dev/null 2>&1 \
  || rm -rf "${trash_dir}" \
  || true

echo "Restarting Core Audio."
# Wait a little because moving files to the trash plays a short sound.
sleep 2
# The extra or-clauses are fallback versions of the command that restarts coreaudiod. Apparently some of these commands 
# don't work with older versions of launchctl, so I figure there's no harm in trying a bunch of different ways until
# one works.
(sudo launchctl kickstart -k system/com.apple.audio.coreaudiod &>/dev/null || \
  sudo killall coreaudiod &>/dev/null || \
  sudo launchctl kill SIGTERM system/com.apple.audio.coreaudiod &>/dev/null || \
  sudo launchctl kill TERM system/com.apple.audio.coreaudiod &>/dev/null || \
  sudo launchctl kill 15 system/com.apple.audio.coreaudiod &>/dev/null || \
  sudo launchctl kill -15 system/com.apple.audio.coreaudiod &>/dev/null || \
  (sudo launchctl unload "${coreaudiod_plist}" &>/dev/null && \
    sudo launchctl load "${coreaudiod_plist}" &>/dev/null))

echo "..."
sleep 3

# TODO: What if they only have one audio device?
echo ""
echo "${bold}Done! Toggle your audio output device in the Sound section of System Settings to finish" \
     "uninstalling. (Or just restart your computer.)${normal}"


