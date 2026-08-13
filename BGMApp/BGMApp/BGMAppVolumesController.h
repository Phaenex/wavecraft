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
//  BGMAppVolumesController.h
//  BGMApp
//
//  Copyright © 2017 Kyle Neideck
//  Copyright © 2021 Marcus Wu
//

// Local Includes
#import "BGMAudioDeviceManager.h"

// System Includes
#import <Cocoa/Cocoa.h>

// Forward Declarations
@class BGMAppOutputRoutingController;


#pragma clang assume_nonnull begin

typedef struct BGMAppVolumeAndPan {
    int volume;
    int pan;
} BGMAppVolumeAndPan;

@interface BGMAppVolumesController : NSObject

// yourAppsStack/systemAndOtherAppsStack/disclosureButton are BGMMainPanelContentView's -- see
// BGMAppVolumes.h for how they're used.
- (id) initWithYourAppsStack:(NSStackView*)yourAppsStack
       systemAndOtherAppsStack:(NSStackView*)systemAndOtherAppsStack
              disclosureButton:(NSButton*)disclosureButton
                 appVolumeView:(NSView*)view
                  audioDevices:(BGMAudioDeviceManager*)audioDevices
       outputRoutingController:(BGMAppOutputRoutingController*)outputRoutingController;

// See BGMBackgroundMusicDevice::SetAppVolume.
- (void)  setVolume:(SInt32)volume
forAppWithProcessID:(pid_t)processID
           bundleID:(NSString* __nullable)bundleID;

// See BGMBackgroundMusicDevice::SetPanVolume.
- (void) setPanPosition:(SInt32)pan
    forAppWithProcessID:(pid_t)processID
               bundleID:(NSString* __nullable)bundleID;

// gainsDB must have exactly kBGMAppEQNumBands elements. See
// BGMBackgroundMusicDevice::SetAppEQBandGains.
- (void) setEQBandGains:(NSArray<NSNumber*>*)gainsDB
    forAppWithProcessID:(pid_t)processID
               bundleID:(NSString* __nullable)bundleID;

// Returns nil if the device doesn't have EQ gains stored for app (i.e. it's still flat/0dB on
// every band). Reads a fresh snapshot from the driver on every call -- unlike setEQBandGains:...,
// not meant to be called from a hot path (e.g. don't poll this from a UI update loop).
- (NSArray<NSNumber*>* __nullable) getEQBandGainsForApp:(NSRunningApplication*)app;

- (BGMAppVolumeAndPan) getVolumeAndPanForApp:(NSRunningApplication *)app;
- (void) setVolumeAndPan:(BGMAppVolumeAndPan)volumeAndPan forApp:(NSRunningApplication*)app;

// See BGMAppVolumes.refreshRoutedIndicators.
- (void) refreshRoutedIndicators;

@end

#pragma clang assume_nonnull end

