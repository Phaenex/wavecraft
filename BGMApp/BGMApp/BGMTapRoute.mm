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
//  BGMTapRoute.mm
//  BGMApp
//
//  Copyright © 2026 mac-volume-mixer contributors
//

// Self Include
#import "BGMTapRoute.h"

// Local Includes
#import "BGM_Utils.h"

// PublicUtility Includes
#import "CAException.h"
#import "CACFArray.h"

// System Includes
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <Foundation/Foundation.h>


BGMTapRoute::BGMTapRoute(CACFString inAppBundleID, BGMAudioDevice inOutputDevice)
:
    mAppBundleID(inAppBundleID),
    mOutputDevice(inOutputDevice)
{
    ThrowIf(!mAppBundleID.IsValid(),
            CAException(kAudioHardwareIllegalOperationError),
            "BGMTapRoute::BGMTapRoute: Invalid bundle ID");
}

BGMTapRoute::~BGMTapRoute()
{
    BGMLogAndSwallowExceptionsMsg("BGMTapRoute::~BGMTapRoute", "Stop", [&]() {
        Stop();
    });
}

void    BGMTapRoute::Start()
{
    if(mRunning)
    {
        return;
    }

    try
    {
        CreateTapAndAggregateDevice();

        mPlayThrough = std::unique_ptr<BGMPlayThrough>(
                new BGMPlayThrough(BGMAudioDevice(mAggregateDeviceID), mOutputDevice));
        mPlayThrough->SetRequireBGMDeviceInput(false);
        mPlayThrough->Activate();
        mPlayThrough->Start();

        mRunning = true;
    }
    catch(...)
    {
        // Clean up whatever actually got created before rethrowing, so a caller that catches
        // this and gives up doesn't leak the tap/aggregate device or leave the app muted.
        mPlayThrough = nullptr;
        DestroyTapAndAggregateDevice();
        throw;
    }
}

void    BGMTapRoute::Stop()
{
    // BGMPlayThrough's own destructor calls Deactivate(), which stops it -- see
    // BGMPlayThrough::~BGMPlayThrough. Resetting here is enough to stop the audio bridge.
    mPlayThrough = nullptr;

    DestroyTapAndAggregateDevice();

    mRunning = false;
}

void    BGMTapRoute::CreateTapAndAggregateDevice()
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
            description.name = [NSString stringWithFormat:@"mac-volume-mixer route: %@",
                                                            (__bridge NSString*)mAppBundleID.GetCFString()];

            AudioObjectID tapID = kAudioObjectUnknown;
            OSStatus status = AudioHardwareCreateProcessTap(description, &tapID);
            ThrowIf(status != noErr,
                    CAException(status),
                    "BGMTapRoute::CreateTapAndAggregateDevice: AudioHardwareCreateProcessTap "
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
                    "BGMTapRoute::CreateTapAndAggregateDevice: could not get tap UID");

            NSDictionary* subTap = @{ @(kAudioSubTapUIDKey) : (__bridge NSString*)tapUID };
            NSDictionary* aggregateDict = @{
                @(kAudioAggregateDeviceNameKey) :
                        [NSString stringWithFormat:@"mac-volume-mixer route aggregate: %@",
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
                    "BGMTapRoute::CreateTapAndAggregateDevice: "
                    "AudioHardwareCreateAggregateDevice failed");
            mAggregateDeviceID = aggregateDeviceID;
        }
    }
    else
    {
        Throw(CAException(kAudioHardwareUnsupportedOperationError));
    }
}

void    BGMTapRoute::DestroyTapAndAggregateDevice() noexcept
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
