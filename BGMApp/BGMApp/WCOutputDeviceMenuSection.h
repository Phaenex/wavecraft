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
//  WCOutputDeviceMenuSection.h
//  BGMApp
//
//  Copyright © 2016, 2018 Kyle Neideck
//

// Local Includes
#import "WCAudioDeviceManager.h"
#import "WCPreferredOutputDevices.h"

// System Includes
#import <AppKit/AppKit.h>


#pragma clang assume_nonnull begin

@interface WCOutputDeviceMenuSection : NSObject

// deviceStack is a vertical NSStackView (WCMainPanelContentView.outputDeviceStack) that this
// class adds/removes one button per output device (or per data source, for devices with more than
// one) to, keeping it in sync as devices connect/disconnect.
- (instancetype) initWithDeviceStack:(NSStackView*)deviceStack
                         audioDevices:(WCAudioDeviceManager*)inAudioDevices
                     preferredDevices:(WCPreferredOutputDevices*)inPreferredDevices;

// To be called when BGMApp has been set to use a different output device. For example, when a new
// device is connected and WCPreferredOutputDevices decides BGMApp should switch to it.
- (void) outputDeviceDidChange;

@end

#pragma clang assume_nonnull end

