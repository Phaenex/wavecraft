// This file is part of Background Music.
//
// Background Music is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation, either version 2 of the
// License, or (at your option) any later version.
//
// Background Music is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Background Music. If not, see <http://www.gnu.org/licenses/>.

//
//  WCOutputDeviceDiff.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  Pure decision logic for WCAppOutputRoutingController's multi-device reconciliation, pulled out
//  of applyRouteForBundleID:deviceUIDs:appName: specifically so it can be unit tested without a
//  real WCTapRoute/CoreAudio tap -- unlike almost everything else this class touches, computing
//  which devices to add/remove has no HAL dependency at all, so there's no reason for it to share
//  WCTapRouteTests.mm's "construction/validation only" limitation.
//

#ifndef BGMApp__BGMOutputDeviceDiff
#define BGMApp__BGMOutputDeviceDiff

// System Includes
#include <CoreAudio/CoreAudio.h>
#include <vector>


struct WCOutputDeviceDiff
{
    std::vector<AudioObjectID> toRemove;
    std::vector<AudioObjectID> toAdd;
};

/*!
 Given a route's current output devices and the set it should have, returns which devices need to
 be removed (in inCurrentDevices but not inDesiredDevices) and which need to be added (in
 inDesiredDevices but not inCurrentDevices). A device present in both is left out of both lists
 entirely -- the point of this function is telling a caller exactly what to change, not
 re-describing the whole desired state, so an already-correct output is never touched. Duplicate
 IDs within either input are treated as one logical device; neither returned list ever contains a
 duplicate, regardless of duplicates in the input.
 */
WCOutputDeviceDiff BGMComputeOutputDeviceDiff(const std::vector<AudioObjectID>& inCurrentDevices,
                                                const std::vector<AudioObjectID>& inDesiredDevices);

#endif /* BGMApp__BGMOutputDeviceDiff */
