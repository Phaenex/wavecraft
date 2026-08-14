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
//  WCTapRoute.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "WCTapRoute.h"

// Local Includes
#import "BGM_Utils.h"

// PublicUtility Includes
#import "CAException.h"
#import "CACFArray.h"

// System Includes
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <Foundation/Foundation.h>

// STL Includes
#import <algorithm>


WCTapRoute::WCTapRoute(CACFString inAppBundleID)
:
    mAppBundleID(inAppBundleID)
{
    ThrowIf(!mAppBundleID.IsValid(),
            CAException(kAudioHardwareIllegalOperationError),
            "WCTapRoute::WCTapRoute: Invalid bundle ID");
}

WCTapRoute::~WCTapRoute()
{
    BGMLogAndSwallowExceptionsMsg("WCTapRoute::~WCTapRoute", "Stop", [&]() {
        Stop();
    });
}

void    WCTapRoute::Start()
{
    if(mRunning)
    {
        return;
    }

    CreateTapAndAggregateDevice();
    mRunning = true;
}

void    WCTapRoute::AddOutputDevice(BGMAudioDevice inOutputDevice)
{
    if(!mRunning)
    {
        Throw(CAException(kAudioHardwareIllegalOperationError));
    }

    if(HasOutputDevice(inOutputDevice))
    {
        return;
    }

    Output output { inOutputDevice, nullptr };

    try
    {
        output.playThrough = std::unique_ptr<WCPlayThrough>(
                new WCPlayThrough(BGMAudioDevice(mAggregateDeviceID), inOutputDevice));
        output.playThrough->SetRequireBGMDeviceInput(false);
        output.playThrough->Activate();
        output.playThrough->Start();

        mOutputs.push_back(std::move(output));
    }
    catch(const CAException& e)
    {
        // Only this one device's WCPlayThrough is affected -- mOutputs isn't touched until the
        // push_back above, which never runs if we get here, so any other already-running outputs
        // are untouched and keep playing.
        //
        // Check inOutputDevice directly rather than trusting the OSStatus we happened to get back:
        // kAudioHardwareBadDeviceError/kAudioHardwareIllegalOperationError are both reused for
        // unrelated reasons elsewhere in WCPlayThrough, so they aren't a reliable signal on their
        // own that the device actually vanished -- see the comment on AddOutputDevice() in the
        // header.
        if (!OutputDeviceIsAlive(inOutputDevice))
        {
            throw CAException(kOutputDeviceVanished);
        }

        throw;
    }
}

void    WCTapRoute::RemoveOutputDevice(BGMAudioDevice inOutputDevice) noexcept
{
    auto it = std::find_if(mOutputs.begin(), mOutputs.end(), [&](const Output& output) {
        return output.device.GetObjectID() == inOutputDevice.GetObjectID();
    });

    if(it != mOutputs.end())
    {
        // ~WCPlayThrough calls Deactivate(), which stops it -- destroying the unique_ptr (via
        // erase) is enough to stop that one output without touching any others.
        mOutputs.erase(it);
    }
}

bool    WCTapRoute::HasOutputDevice(BGMAudioDevice inOutputDevice) const noexcept
{
    return std::any_of(mOutputs.begin(), mOutputs.end(), [&](const Output& output) {
        return output.device.GetObjectID() == inOutputDevice.GetObjectID();
    });
}

std::vector<BGMAudioDevice>    WCTapRoute::GetOutputDevices() const
{
    std::vector<BGMAudioDevice> devices;
    devices.reserve(mOutputs.size());

    for(const Output& output : mOutputs)
    {
        devices.push_back(output.device);
    }

    return devices;
}

bool    WCTapRoute::OutputDeviceIsAlive(const BGMAudioDevice& inDevice) noexcept
{
    // CAHALAudioObject::ObjectExists is safe to call on an ID that's already gone -- it just
    // returns false. CAHALAudioDevice::IsAlive() isn't: it does a real HAL property fetch, which
    // throws if the object doesn't exist at all, so it's only safe to call once ObjectExists has
    // already confirmed the object is there to ask.
    if (!CAHALAudioObject::ObjectExists(inDevice.GetObjectID()))
    {
        return false;
    }

    try
    {
        return inDevice.IsAlive();
    }
    catch (...)
    {
        // Treat "couldn't even ask" as "not alive" -- this method exists specifically to decide
        // whether a failure looks like a vanished device, and a device that can't answer a basic
        // liveness query already looks exactly like one that vanished.
        return false;
    }
}

void    WCTapRoute::Stop()
{
    // Each WCPlayThrough's own destructor calls Deactivate(), which stops it -- clearing here is
    // enough to stop every output's audio bridge.
    mOutputs.clear();

    DestroyTapAndAggregateDevice();

    mRunning = false;
}

void    WCTapRoute::CreateTapAndAggregateDevice()
{
    // This project's deployment target (10.13) is far below what per-app output routing needs.
    // CATapDescription.bundleIDs specifically requires macOS 26.0 (AudioHardwareCreateProcessTap
    // itself only needs 14.2, but bundleIDs -- rather than PID/AudioObjectID-based tapping -- is
    // what this class uses, matching the modern, simpler approach confirmed in Phase 1's
    // proof-of-concept). Gate on the strictest requirement and fail clearly on older systems
    // instead of letting the compiler's availability checking block the whole build.
    if (__builtin_available(macOS 26.0, *))
    {
        @autoreleasepool
        {
            CATapDescription* description = [[CATapDescription alloc] init];
            description.bundleIDs = @[ (__bridge NSString*)mAppBundleID.GetCFString() ];
            description.exclusive = NO;
            description.mono = NO;
            description.mixdown = YES;
            description.privateTap = YES;
            description.muteBehavior = CATapMuted;
            // Without this, the tap stops delivering audio for good once the app process that
            // owned it at Start() time exits -- quitting and reopening the routed app would
            // silently break routing until the user reselects it. processRestoreEnabled makes the
            // tap reattach to whichever process currently owns the bundle ID, so a routing
            // assignment survives the app being quit and relaunched. Same macOS 26.0+ gate as
            // description.bundleIDs above -- see docs/PROCESS-TAP-ROUTING.md.
            description.processRestoreEnabled = YES;
            description.name = [NSString stringWithFormat:@"Wavecraft route: %@",
                                                            (__bridge NSString*)mAppBundleID.GetCFString()];

            AudioObjectID tapID = kAudioObjectUnknown;
            OSStatus status = AudioHardwareCreateProcessTap(description, &tapID);
            ThrowIf(status != noErr,
                    CAException(status),
                    "WCTapRoute::CreateTapAndAggregateDevice: AudioHardwareCreateProcessTap "
                    "failed");
            mTapID = tapID;

            CFStringRef tapUID = nullptr;
            UInt32 uidSize = sizeof(tapUID);
            AudioObjectPropertyAddress uidAddr = {
                kAudioTapPropertyUID, kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            status = AudioObjectGetPropertyData(mTapID, &uidAddr, 0, nullptr, &uidSize, &tapUID);
            ThrowIf(status != noErr || tapUID == nullptr,
                    CAException(status),
                    "WCTapRoute::CreateTapAndAggregateDevice: could not get tap UID");

            NSDictionary* subTap = @{ @(kAudioSubTapUIDKey) : (__bridge NSString*)tapUID };
            NSDictionary* aggregateDict = @{
                @(kAudioAggregateDeviceNameKey) :
                        [NSString stringWithFormat:@"Wavecraft route aggregate: %@",
                                                    (__bridge NSString*)mAppBundleID.GetCFString()],
                @(kAudioAggregateDeviceUIDKey) : [[NSUUID UUID] UUIDString],
                @(kAudioAggregateDeviceIsPrivateKey) : @YES,
                @(kAudioAggregateDeviceTapAutoStartKey) : @YES,
                @(kAudioAggregateDeviceTapListKey) : @[ subTap ],
            };

            AudioObjectID aggregateDeviceID = kAudioObjectUnknown;
            status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)aggregateDict,
                                                          &aggregateDeviceID);
            CFRelease(tapUID);

            ThrowIf(status != noErr,
                    CAException(status),
                    "WCTapRoute::CreateTapAndAggregateDevice: "
                    "AudioHardwareCreateAggregateDevice failed");
            mAggregateDeviceID = aggregateDeviceID;
        }
    }
    else
    {
        Throw(CAException(kMacOSTooOld));
    }
}

void    WCTapRoute::DestroyTapAndAggregateDevice() noexcept
{
    if(mAggregateDeviceID != kAudioObjectUnknown)
    {
        AudioHardwareDestroyAggregateDevice(mAggregateDeviceID);
        mAggregateDeviceID = kAudioObjectUnknown;
    }

    if (__builtin_available(macOS 14.2, *))
    {
        if(mTapID != kAudioObjectUnknown)
        {
            AudioHardwareDestroyProcessTap(mTapID);
            mTapID = kAudioObjectUnknown;
        }
    }
}
