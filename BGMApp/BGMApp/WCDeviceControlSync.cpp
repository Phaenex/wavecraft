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
//  WCDeviceControlSync.cpp
//  BGMApp
//
//  Copyright © 2016, 2017, 2026 Kyle Neideck
//

// Self Include
#include "WCDeviceControlSync.h"

// Local Includes
#include "BGM_Types.h"
#include "BGM_Utils.h"

// PublicUtility Includes
#include "CAPropertyAddress.h"


#pragma clang assume_nonnull begin

static const AudioObjectPropertyAddress kMutePropertyAddress =
    { kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain };

static const AudioObjectPropertyAddress kVolumePropertyAddress =
    { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain };

#pragma mark Construction/Destruction

WCDeviceControlSync::WCDeviceControlSync(AudioObjectID inBGMDevice,
                                           AudioObjectID inOutputDevice,
                                           CAHALAudioSystemObject inAudioSystem)
:
    mBGMDevice(inBGMDevice),
    mOutputDevice(inOutputDevice),
    mAudioSystem(inAudioSystem),
    mBGMDeviceControlsList(inBGMDevice)
{
}

WCDeviceControlSync::~WCDeviceControlSync()
{
    BGMLogAndSwallowExceptions("WCDeviceControlSync::~WCDeviceControlSync", [&] {
        CAMutex::Locker locker(mMutex);

        Deactivate();
    });
}

void    WCDeviceControlSync::Activate()
{
    CAMutex::Locker locker(mMutex);

    ThrowIf((mBGMDevice.GetObjectID() == kAudioObjectUnknown || mOutputDevice.GetObjectID() == kAudioObjectUnknown),
            WC_DeviceNotSetException(),
            "WCDeviceControlSync::Activate: Both the output device and BGMDevice must be set to start synchronizing their controls");

    if(!mActive)
    {
        DebugMsg("WCDeviceControlSync::Activate: Activating control sync");

        // Disable BGMDevice controls that the output device doesn't have and reenable any that were
        // disabled for the previous output device.
        //
        // Continue anyway if this fails because it's better to have extra/missing controls than to
        // be unable to use the device.
        BGMLogAndSwallowExceptionsMsg("WCDeviceControlSync::Activate", "Controls list", [&] {
            bool wasUpdated = mBGMDeviceControlsList.MatchControlsListOf(mOutputDevice);
            if(wasUpdated)
            {
                mBGMDeviceControlsList.PropagateControlListChange();
            }
        });

        // Init BGMDevice controls to match output device
        mBGMDevice.CopyVolumeFrom(mOutputDevice, kAudioObjectPropertyScopeOutput);
        mBGMDevice.CopyMuteFrom(mOutputDevice, kAudioObjectPropertyScopeOutput);

        // Register listeners for volume and mute values
        mBGMDevice.AddPropertyListener(kVolumePropertyAddress, &WCDeviceControlSync::BGMDeviceListenerProc, this);
        
        try
        {
            mBGMDevice.AddPropertyListener(kMutePropertyAddress, &WCDeviceControlSync::BGMDeviceListenerProc, this);
        }
        catch(CAException)
        {
            CATry
            mBGMDevice.RemovePropertyListener(kVolumePropertyAddress, &WCDeviceControlSync::BGMDeviceListenerProc, this);
            CACatch
            
            throw;
        }
        
        mActive = true;
    }
    else
    {
        DebugMsg("WCDeviceControlSync::Activate: Already active");
    }
}

void    WCDeviceControlSync::Deactivate()
{
    CAMutex::Locker locker(mMutex);

    if(mActive)
    {
        DebugMsg("WCDeviceControlSync::Deactivate: Deactivating control sync");

        // Deregister listeners
        if(mBGMDevice.GetObjectID() != kAudioDeviceUnknown)
        {
            BGMLogAndSwallowExceptions("WCDeviceControlSync::Deactivate", [&] {
                mBGMDevice.RemovePropertyListener(kVolumePropertyAddress,
                                                  &WCDeviceControlSync::BGMDeviceListenerProc,
                                                  this);
            });

            BGMLogAndSwallowExceptions("WCDeviceControlSync::Deactivate", [&] {
                mBGMDevice.RemovePropertyListener(kMutePropertyAddress,
                                                  &WCDeviceControlSync::BGMDeviceListenerProc,
                                                  this);
            });
        }

        mActive = false;
    }
    else
    {
        DebugMsg("WCDeviceControlSync::Deactivate: Not active");
    }
}

#pragma mark Accessors

void    WCDeviceControlSync::SetDevices(AudioObjectID inBGMDevice, AudioObjectID inOutputDevice)
{
    CAMutex::Locker locker(mMutex);

    bool wasActive = mActive;

    Deactivate();

    mBGMDevice = inBGMDevice;
    mBGMDeviceControlsList.SetBGMDevice(inBGMDevice);
    mOutputDevice = inOutputDevice;
    
    if(wasActive)
    {
        Activate();
    }
}

#pragma mark Listener Procs

// static
OSStatus    WCDeviceControlSync::BGMDeviceListenerProc(AudioObjectID inObjectID, UInt32 inNumberAddresses, const AudioObjectPropertyAddress* inAddresses, void* __nullable inClientData)
{
    // refCon (reference context) is the instance that registered this listener proc.
    WCDeviceControlSync* refCon = static_cast<WCDeviceControlSync*>(inClientData);

    auto checkState = [&] {
        if(!refCon)
        {
            LogError("WCDeviceControlSync::BGMDeviceListenerProc: !refCon");
            return false;
        }

        if(!refCon->mActive ||
           (refCon->mBGMDevice.GetObjectID() == kAudioObjectUnknown) ||
           (refCon->mOutputDevice.GetObjectID() == kAudioObjectUnknown))
        {
            return false;
        }

        if(inObjectID != refCon->mBGMDevice.GetObjectID())
        {
            LogError("WCDeviceControlSync::BGMDeviceListenerProc: notified about audio object other than BGMDevice");
            return false;
        }
        
        return true;
    };

    for(int i = 0; i < inNumberAddresses; i++)
    {
        AudioObjectPropertyScope scope = inAddresses[i].mScope;
        
        switch(inAddresses[i].mSelector)
        {
            case kAudioDevicePropertyVolumeScalar:
                {
                    CAMutex::Locker locker(refCon->mMutex);

                    // Update the output device's volume. This runs on a thread CoreAudio owns, not
                    // one of BGMApp's own -- if either device's ID has gone stale (e.g. the driver
                    // was just reloaded by a coreaudiod restart while this listener was still
                    // registered against the old instance) and CopyVolumeFrom throws, there's no
                    // caller further up this stack that could catch it, so an uncaught exception
                    // here crashes the whole app instead of just failing this one update.
                    if(checkState())
                    {
                        BGMLogAndSwallowExceptions("WCDeviceControlSync::BGMDeviceListenerProc", [&] {
                            refCon->mOutputDevice.CopyVolumeFrom(refCon->mBGMDevice, scope);
                        });
                    }
                }
                break;

            case kAudioDevicePropertyMute:
                {
                    CAMutex::Locker locker(refCon->mMutex);

                    // Update the output device's mute control. Note that this also runs when you
                    // change the volume (on BGMDevice). Same reasoning as the volume case above for
                    // why this needs to swallow, not just log-and-continue by relying on a caller.
                    if(checkState())
                    {
                        BGMLogAndSwallowExceptions("WCDeviceControlSync::BGMDeviceListenerProc", [&] {
                            refCon->mOutputDevice.CopyMuteFrom(refCon->mBGMDevice, scope);
                        });
                    }
                }
                break;
        }
    }

    // "The return value [of an AudioObjectPropertyListenerProc] is currently unused and should always be 0."
    return 0;
}

#pragma clang assume_nonnull end

