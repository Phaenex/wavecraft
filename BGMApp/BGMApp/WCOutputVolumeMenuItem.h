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
//  WCOutputVolumeMenuItem.h
//  BGMApp
//
//  Copyright © 2017 Kyle Neideck
//

// Local Includes
#import "WCAudioDeviceManager.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface WCOutputVolumeMenuItem : NSObject

// A row with a slider for controlling the volume of the output device, hosted in WCMainPanel.
// Similar to the one in macOS's Volume menu extra.
//
// view, slider and deviceLabel are the UI elements from MainMenu.xib.
- (instancetype) initWithAudioDevices:(WCAudioDeviceManager*)devices
                                 view:(NSView*)view
                               slider:(NSSlider*)slider
                          deviceLabel:(NSTextField*)label;

// The row's view, added as an arranged subview of WCMainPanel's row stack by whoever constructs
// this object.
@property (nonatomic, readonly) NSView* view;

- (void) outputDeviceDidChange;

@end

#pragma clang assume_nonnull end

