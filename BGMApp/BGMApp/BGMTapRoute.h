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
//  BGMTapRoute.h
//  BGMApp
//
//  Routes one app's audio to a specific physical output device, independent of BGMDevice/the
//  system default output. This is the feature BGM's original virtual-HAL-device architecture
//  can't do at all -- see docs/PROCESS-TAP-ROUTING.md for why, and docs/LESSONS.md for what
//  Phase 1's proof-of-concept (tools/tap-poc/) already confirmed empirically about this API.
//
//  Mechanism: a CoreAudio Process Tap captures the target app's audio directly and mutes its
//  normal output (CATapMuted). The tap is wrapped in a private aggregate device, which is then
//  used as the input side of a BGMPlayThrough instance (generalized in this same change to allow
//  a non-BGMDevice input -- see SetRequireBGMDeviceInput) writing to the chosen physical output
//  device. So the actual real-time audio bridging reuses BGMPlayThrough's already-proven
//  ring-buffer/clock-sync engine; this class is only responsible for the tap/aggregate-device
//  lifecycle around it.
//

#ifndef BGMApp__BGMTapRoute
#define BGMApp__BGMTapRoute

// Local Includes
#include "BGMAudioDevice.h"
#include "BGMPlayThrough.h"

// PublicUtility Includes
#include "CACFString.h"

// System Includes
#include <CoreAudio/CoreAudio.h>
#include <memory>


#pragma clang assume_nonnull begin

class BGMTapRoute
{

public:
    /*!
     @param inAppBundleID The bundle ID of the app to route. Retained for the lifetime of this
                          object.
     @param inOutputDevice The physical device to play the app's audio through.
     */
    BGMTapRoute(CACFString inAppBundleID, BGMAudioDevice inOutputDevice);
    ~BGMTapRoute();

    BGMTapRoute(const BGMTapRoute&) = delete;
    BGMTapRoute& operator=(const BGMTapRoute&) = delete;

    /*!
     Creates the tap and aggregate device, mutes the app's normal output, and starts playing its
     audio through the output device given to the constructor. If this object is already running,
     does nothing.

     @throws CAException If creating the tap or aggregate device fails, or if BGMPlayThrough fails
                         to activate/start. Safe to call Stop() (or just destroy this object) after
                         a failed Start() -- cleans up whatever was actually created. The exception's
                         GetError() is kMacOSTooOld if this system doesn't support
                         CATapDescription.processRestoreEnabled, kOutputDeviceVanished if the output
                         device given to the constructor is no longer alive by the time this throws
                         (checked directly, not inferred from whichever ambiguous CoreAudio error
                         happened to come back -- see BGMTapRoute.mm), or the raw OSStatus CoreAudio
                         itself returned for any other failure.
     */
    void                Start();

    // Distinguishable causes for a Start() failure -- see its doc comment above. Picked as
    // arbitrary values outside the OSStatus range CoreAudio itself uses for FourCharCode-style
    // error constants, the same way BGMPlayThrough::kDeviceNotStarting is.
    static const OSStatus kMacOSTooOld = 200;
    static const OSStatus kOutputDeviceVanished = 201;

    /*!
     Stops routing, unmutes the app's normal output, and destroys the tap and aggregate device.
     Safe to call even if Start() was never called, or if it failed partway through -- only tears
     down whatever actually got created. Safe to call more than once.
     */
    void                Stop();

    bool                IsRunning() const { return mRunning; }

    /*!
     @return The bundle ID this route was constructed with.
     */
    CACFString          GetAppBundleID() const { return mAppBundleID; }

private:
    void                CreateTapAndAggregateDevice();
    void                DestroyTapAndAggregateDevice() noexcept;
    bool                OutputDeviceIsAlive() const noexcept;

    CACFString                          mAppBundleID;
    BGMAudioDevice                      mOutputDevice;

    AudioObjectID                       mTapID { kAudioObjectUnknown };
    AudioObjectID                       mAggregateDeviceID { kAudioObjectUnknown };

    std::unique_ptr<BGMPlayThrough>     mPlayThrough;

    bool                                mRunning { false };

};

#pragma clang assume_nonnull end

#endif /* BGMApp__BGMTapRoute */
