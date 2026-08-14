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
//  WCAppVolumesController.h
//  BGMApp
//
//  Copyright © 2017 Kyle Neideck
//  Copyright © 2021 Marcus Wu
//

// Local Includes
#import "WCAudioDeviceManager.h"

// System Includes
#import <Cocoa/Cocoa.h>

// Forward Declarations
@class WCAppOutputRoutingController;


#pragma clang assume_nonnull begin

typedef struct BGMAppVolumeAndPan {
    int volume;
    int pan;
} BGMAppVolumeAndPan;

@interface WCAppVolumesController : NSObject

// yourAppsStack/systemAndOtherAppsStack/disclosureButton are WCMainPanelContentView's -- see
// WCAppVolumes.h for how they're used.
- (id) initWithYourAppsStack:(NSStackView*)yourAppsStack
       systemAndOtherAppsStack:(NSStackView*)systemAndOtherAppsStack
              disclosureButton:(NSButton*)disclosureButton
                 appVolumeView:(NSView*)view
                  audioDevices:(WCAudioDeviceManager*)audioDevices
       outputRoutingController:(WCAppOutputRoutingController*)outputRoutingController;

// See WCBackgroundMusicDevice::SetAppVolume.
- (void)  setVolume:(SInt32)volume
forAppWithProcessID:(pid_t)processID
           bundleID:(NSString* __nullable)bundleID;

// See WCBackgroundMusicDevice::SetPanVolume.
- (void) setPanPosition:(SInt32)pan
    forAppWithProcessID:(pid_t)processID
               bundleID:(NSString* __nullable)bundleID;

// gainsDB must have exactly kBGMAppEQNumBands elements. See
// WCBackgroundMusicDevice::SetAppEQBandGains.
- (void) setEQBandGains:(NSArray<NSNumber*>*)gainsDB
    forAppWithProcessID:(pid_t)processID
               bundleID:(NSString* __nullable)bundleID;

// Returns nil if the device doesn't have EQ gains stored for app (i.e. it's still flat/0dB on
// every band). Reads a fresh snapshot from the driver on every call -- unlike setEQBandGains:...,
// not meant to be called from a hot path (e.g. don't poll this from a UI update loop).
- (NSArray<NSNumber*>* __nullable) getEQBandGainsForApp:(NSRunningApplication*)app;

- (BGMAppVolumeAndPan) getVolumeAndPanForApp:(NSRunningApplication *)app;
- (void) setVolumeAndPan:(BGMAppVolumeAndPan)volumeAndPan forApp:(NSRunningApplication*)app;

// See WCAppVolumes.refreshRoutedIndicators.
- (void) refreshRoutedIndicators;

@end

#pragma clang assume_nonnull end

