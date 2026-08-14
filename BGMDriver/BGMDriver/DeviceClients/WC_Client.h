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
//  WC_Client.h
//  BGMDriver
//
//  Copyright © 2016 Kyle Neideck
//

#ifndef __BGMDriver__BGM_Client__
#define __BGMDriver__BGM_Client__

// Local Includes
#include "WC_Biquad.h"

// PublicUtility Includes
#include "CACFString.h"

// System Includes
#include <CoreAudio/AudioServerPlugIn.h>

// STL Includes
#include <array>


#pragma clang assume_nonnull begin

//==================================================================================================
//	WC_Client
//
//  Client meaning a client (of the host) of the BGMDevice, i.e. an app registered with the HAL,
//  generally so it can do IO at some point.
//==================================================================================================

class WC_Client
{
    
public:
                                  WC_Client() = default;
                                  WC_Client(const AudioServerPlugInClientInfo* inClientInfo);
                                  ~WC_Client() = default;
                                  WC_Client(const WC_Client& inClient) { Copy(inClient); };
                                  WC_Client& operator=(const WC_Client& inClient) { Copy(inClient); return *this; }
    
private:
    void                          Copy(const WC_Client& inClient);
    
public:
    // These fields are duplicated from AudioServerPlugInClientInfo (except the mBundleID CFStringRef is
    // wrapped in a CACFString here).
    UInt32                        mClientID;
    pid_t                         mProcessID;
    Boolean                       mIsNativeEndian = true;
    CACFString                    mBundleID;
    
    // True if BGMApp has set this client as belonging to the music player app
    bool                          mIsMusicPlayer = false;
    
    // The client's volume relative to other clients. In the range [0.0, 4.0], defaults to 1.0 (unchanged).
    // mRelativeVolumeCurve is applied to this value when it's set.
    Float32                       mRelativeVolume = 1.0;
    
    // The client's pan position, in the range [-100, 100] where -100 is left and 100 is right
    SInt32                        mPanPosition = 0;

    // The client's persisted per-band EQ gains, in dB, each in [kBGMAppEQMinGainDB,
    // kBGMAppEQMaxGainDB]. Defaults to all zero (flat/unity). This is only the user-set
    // target values -- safe to copy, unlike the actual live filter state, which WC_Device
    // owns separately (in mClientEQProcessors) precisely so it doesn't get reset by a copy
    // of this class. See docs/LESSONS.md.
    std::array<Float32, WC_AppEQ::kNumBands> mEQBandGainsDB {};

};

#pragma clang assume_nonnull end

#endif /* __BGMDriver__BGM_Client__ */

