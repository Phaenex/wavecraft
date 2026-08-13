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
//  Routes one app's audio to one or more physical output devices at once, independent of
//  BGMDevice/the system default output. This is the feature BGM's original virtual-HAL-device
//  architecture can't do at all -- see docs/PROCESS-TAP-ROUTING.md for why, and docs/LESSONS.md
//  for what Phase 1's proof-of-concept (tools/tap-poc/) already confirmed empirically about this
//  API.
//
//  Mechanism: a CoreAudio Process Tap captures the target app's audio directly and mutes its
//  normal output (CATapMuted). The tap is wrapped in a private aggregate device, which is then
//  used as the input side of one BGMPlayThrough instance PER output device (generalized in this
//  same change to allow a non-BGMDevice input -- see SetRequireBGMDeviceInput). CoreAudio devices
//  support multiple independent IOProcs reading the same captured audio simultaneously (the same
//  way several apps can record from one microphone at once), so N output devices means N
//  BGMPlayThrough instances sharing the one tap/aggregate device as their common input -- the tap
//  itself, the expensive per-app resource, is created once regardless of how many outputs are
//  attached to it. So the actual real-time audio bridging reuses BGMPlayThrough's already-proven
//  ring-buffer/clock-sync engine, once per output; this class is only responsible for the
//  tap/aggregate-device lifecycle and the set of BGMPlayThrough instances around it.
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
#include <vector>


#pragma clang assume_nonnull begin

class BGMTapRoute
{

public:
    /*!
     @param inAppBundleID The bundle ID of the app to route. Retained for the lifetime of this
                          object.
     */
    explicit            BGMTapRoute(CACFString inAppBundleID);
    ~BGMTapRoute();

    BGMTapRoute(const BGMTapRoute&) = delete;
    BGMTapRoute& operator=(const BGMTapRoute&) = delete;

    /*!
     Creates the tap and aggregate device, and mutes the app's normal output. Doesn't play the
     app's audio anywhere yet -- call AddOutputDevice() afterwards for each device it should play
     through. If this object is already running, does nothing.

     @throws CAException If creating the tap or aggregate device fails. The exception's GetError()
                         is kMacOSTooOld if this system doesn't support
                         CATapDescription.processRestoreEnabled, or the raw OSStatus CoreAudio
                         itself returned for any other failure.
     */
    void                Start();

    // Distinguishable causes for a Start()/AddOutputDevice() failure -- see their doc comments.
    // Picked as arbitrary values outside the OSStatus range CoreAudio itself uses for
    // FourCharCode-style error constants, the same way BGMPlayThrough::kDeviceNotStarting is.
    static const OSStatus kMacOSTooOld = 200;
    static const OSStatus kOutputDeviceVanished = 201;

    /*!
     Starts playing this route's audio through inOutputDevice as well as whatever it was already
     playing through. Must be called after Start(). No-op if inOutputDevice is already one of this
     route's output devices.

     @throws CAException If BGMPlayThrough fails to activate/start for this device. Only this one
                         device's output is affected -- any devices already playing keep playing.
                         GetError() is kOutputDeviceVanished if inOutputDevice is no longer alive by
                         the time this throws (checked directly, not inferred from whichever
                         ambiguous CoreAudio error happened to come back -- see BGMTapRoute.mm), or
                         the raw OSStatus CoreAudio itself returned for any other failure.
     */
    void                AddOutputDevice(BGMAudioDevice inOutputDevice);

    /*!
     Stops playing this route's audio through inOutputDevice, leaving any other output devices
     unaffected. No-op if inOutputDevice isn't one of this route's current output devices. Safe to
     call even if this route isn't running at all.
     */
    void                RemoveOutputDevice(BGMAudioDevice inOutputDevice) noexcept;

    /*!
     @return True if inOutputDevice is currently one of this route's output devices.
     */
    bool                HasOutputDevice(BGMAudioDevice inOutputDevice) const noexcept;

    /*!
     @return This route's current output devices, in the order they were added.
     */
    std::vector<BGMAudioDevice>    GetOutputDevices() const;

    /*!
     Stops routing to every output device, unmutes the app's normal output, and destroys the tap
     and aggregate device. Safe to call even if Start() was never called, or if it failed partway
     through -- only tears down whatever actually got created. Safe to call more than once.
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
    static bool         OutputDeviceIsAlive(const BGMAudioDevice& inDevice) noexcept;

    struct Output
    {
        BGMAudioDevice                      device;
        std::unique_ptr<BGMPlayThrough>     playThrough;
    };

    CACFString                          mAppBundleID;

    AudioObjectID                       mTapID { kAudioObjectUnknown };
    AudioObjectID                       mAggregateDeviceID { kAudioObjectUnknown };

    std::vector<Output>                 mOutputs;

    bool                                mRunning { false };

};

#pragma clang assume_nonnull end

#endif /* BGMApp__BGMTapRoute */
