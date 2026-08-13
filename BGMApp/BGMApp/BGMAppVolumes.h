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
//  BGMAppVolumes.h
//  BGMApp
//
//  Copyright © 2016, 2017 Kyle Neideck
//  Copyright © 2021 Marcus Wu
//  Copyright © 2026 TwelfthFace
//

// Local Includes
#import "BGMAppVolumesController.h"

// System Includes
#import <Cocoa/Cocoa.h>

// Forward Declarations
@class BGMAppOutputRoutingController;


#pragma clang assume_nonnull begin

@interface BGMAppVolumes : NSObject

// Subviews that need it (currently just BGMAVM_OutputRouteButton) read this instead of getting it
// through the setUpWithApp:context:controller:rowView: protocol method below, because that
// method's controller: param is a BGMAppVolumesController specifically -- see this property's use
// in BGMAVM_OutputRouteButton.
@property (nonatomic, readonly) BGMAppOutputRoutingController* outputRoutingController;

// yourAppsStack/systemAndOtherAppsStack are BGMMainPanelContentView's stacks -- see that class's
// header. Regular (non-accessory) apps' rows go in yourAppsStack; accessory/background apps' rows
// go in systemAndOtherAppsStack, which disclosureButton is disabled/enabled to match ("nothing to
// disclose" shouldn't look clickable), the same purpose the old design's "More Apps" submenu item
// being disabled when empty served.
- (id) initWithController:(BGMAppVolumesController*)inController
             yourAppsStack:(NSStackView*)inYourAppsStack
   systemAndOtherAppsStack:(NSStackView*)inSystemAndOtherAppsStack
   disclosureButton:(NSButton*)inDisclosureButton
             appVolumeView:(NSView*)inView
  outputRoutingController:(BGMAppOutputRoutingController*)inOutputRoutingController;

// Pass -1 for initialVolume or kAppPanNoValue for initialPan to leave the volume/pan at its
// default level. Pass nil for initialEQBandGains to leave the EQ bands flat (0dB); otherwise it
// must have exactly kBGMAppEQNumBands elements, in the same order as
// BGM_AppEQ::kBandCenterFreqs.
- (void) insertRowForApp:(NSRunningApplication*)app
            initialVolume:(int)volume
               initialPan:(int)pan
       initialEQBandGains:(NSArray<NSNumber*>* __nullable)gainsDB;

- (void) removeRowForApp:(NSRunningApplication*)app;

- (void) removeAllAppVolumeRows;

- (BGMAppVolumeAndPan) getVolumeAndPanForApp:(NSRunningApplication*)app;
- (void) setVolumeAndPan:(BGMAppVolumeAndPan)volumeAndPan forApp:(NSRunningApplication*)app;

// Appends a small icon to a row's app-name label when that app currently has an active
// output-routing override, so it's visible without expanding the row -- called from
// BGMMainPanel.willShowBlock (see BGMAppDelegate) each time the panel is about to be shown, so it
// picks up routes added/removed since the panel was last open. Replaces the old NSMenu-based
// design's equivalent block in -[BGMAppDelegate menuWillOpen:].
- (void) refreshRoutedIndicators;

@end

// Protocol for the UI custom classes

@protocol BGMAppVolumeMenuItemSubview <NSObject>

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
              rowView:(NSView*)rowView;

@end

// Custom classes for the UI elements in the app volume rows

@interface BGMAVM_VolumeMute: NSButton <BGMAppVolumeMenuItemSubview>

- (void) bgm_syncForVolume:(int)vol;

@end


@interface BGMAVM_AppIcon : NSImageView <BGMAppVolumeMenuItemSubview>
@end

@interface BGMAVM_AppNameLabel : NSTextField <BGMAppVolumeMenuItemSubview>
@end

@interface BGMAVM_ShowMoreControlsButton : NSButton <BGMAppVolumeMenuItemSubview>

// Re-reads the pan/EQ sliders in the same row and updates this button's appearance to indicate
// whether any of them are set to a non-default value -- the row's "extra controls" start out
// collapsed, so without this there's no way to tell they're non-default without expanding the
// row. Safe to call before the row's own siblings have their real values yet (treated as "all
// default" until it's called again after they do) -- see BGMAppVolumes.m for why this can't just
// run once from setUpWithApp:.
- (void) bgm_syncHighlightForCurrentControls;

@end

@interface BGMAVM_VolumeSlider : NSSlider <BGMAppVolumeMenuItemSubview>

- (void) setRelativeVolume:(int)relativeVolume;

@end

@interface BGMAVM_PanSlider : NSSlider <BGMAppVolumeMenuItemSubview>

- (void) setPanPosition:(int)panPosition;

@end

// One of the kBGMAppEQNumBands per-band gain sliders in an app's extra controls. Each instance is
// tagged (see the "tag" attribute in the XIB) with its band index, 0...kBGMAppEQNumBands-1, in the
// same order as BGM_AppEQ::kBandCenterFreqs (BGM_Biquad.h) -- lowest frequency first. Because the
// driver takes all bands' gains in a single property write (see
// BGMBackgroundMusicDevice::SetAppEQBandGains), moving one band's slider reads the other bands'
// current values from its siblings in the same row and sends all of them together.
@interface BGMAVM_EQBandSlider : NSSlider <BGMAppVolumeMenuItemSubview>

- (void) setGainDB:(float)gainDB;

@end

// The pop-up button in an app's extra controls used to route its audio to a different output
// device -- see BGMAppOutputRoutingController and docs/PROCESS-TAP-ROUTING.md. Its menu is empty
// until just before it's shown, when menuNeedsUpdate: asks the routing controller (reached via
// BGMAppVolumes.outputRoutingController, not the controller: param -- see that property) to
// rebuild it from the output devices currently connected. This is a plain NSPopUpButton's own
// internal menu, independent of the main panel/BGMMainPanel -- unaffected by this app's move off
// NSMenu for its main dropdown.
@interface BGMAVM_OutputRouteButton : NSPopUpButton <BGMAppVolumeMenuItemSubview, NSMenuDelegate>
@end

#pragma clang assume_nonnull end
