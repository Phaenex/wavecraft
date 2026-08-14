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
//  WCOutputDeviceDiff.cpp
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#include "WCOutputDeviceDiff.h"

// STL Includes
#include <algorithm>


static bool Contains(const std::vector<AudioObjectID>& inDevices, AudioObjectID inDevice)
{
    return std::find(inDevices.begin(), inDevices.end(), inDevice) != inDevices.end();
}

WCOutputDeviceDiff BGMComputeOutputDeviceDiff(const std::vector<AudioObjectID>& inCurrentDevices,
                                                const std::vector<AudioObjectID>& inDesiredDevices)
{
    WCOutputDeviceDiff diff;

    for (AudioObjectID current : inCurrentDevices)
    {
        if (!Contains(inDesiredDevices, current) && !Contains(diff.toRemove, current))
        {
            diff.toRemove.push_back(current);
        }
    }

    for (AudioObjectID desired : inDesiredDevices)
    {
        if (!Contains(inCurrentDevices, desired) && !Contains(diff.toAdd, desired))
        {
            diff.toAdd.push_back(desired);
        }
    }

    return diff;
}
