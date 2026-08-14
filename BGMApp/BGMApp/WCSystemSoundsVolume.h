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
//  WCSystemSoundsVolume.h
//  BGMApp
//
//  Copyright © 2017 Kyle Neideck
//
//  The menu item with the volume slider that controls system-related sounds. The slider is used to
//  set the volume of the instance of BGMDevice that system sounds are played on, i.e. the audio
//  device returned by WCBackgroundMusicDevice::GetUISoundsBGMDeviceInstance.
//
//  System sounds are any sounds played using the audio device macOS is set to use as the device
//  "for system related sound from the alert sound to digital call progress". See
//  kAudioHardwarePropertyDefaultSystemOutputDevice in AudioHardware.h. They can be played by any
//  app, though most apps use systemsoundserverd to play their system sounds, which means BGMDriver
//  can't tell which app is actually playing the sounds.
//

// Local Includes
#import "BGMAudioDevice.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface WCSystemSoundsVolume : NSObject

// The volume level of uiSoundsDevice will be used to set the slider's initial position and will be
// updated when the user moves the slider. view and slider are the UI elements from MainMenu.xib.
- (instancetype) initWithUISoundsDevice:(BGMAudioDevice)uiSoundsDevice
                                   view:(NSView*)view
                                 slider:(NSSlider*)slider;

// The row's view, added as an arranged subview of WCMainPanel's row stack by whoever constructs
// this object.
@property (readonly) NSView* view;

@end

#pragma clang assume_nonnull end

