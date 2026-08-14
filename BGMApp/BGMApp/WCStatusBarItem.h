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
//  WCStatusBarItem.h
//  BGMApp
//
//  Copyright © 2019, 2020 Kyle Neideck
//
//  The button in the system status bar (the bar with volume, battery, clock, etc.) to show the main
//  menu for the app. These are called "menu bar extras" in the Human Interface Guidelines.
//

// Local Includes
#import "WCAudioDeviceManager.h"
#import "WCDebugLoggingMenuItem.h"
#import "WCMainPanel.h"

// System Includes
#import <Cocoa/Cocoa.h>

// Forward Declarations
@class WCUserDefaults;


#pragma clang assume_nonnull begin

typedef NS_ENUM(NSInteger, BGMStatusBarIcon) {
    BGMWavecraftStatusBarIcon = 0,
    BGMVolumeStatusBarIcon
};

static BGMStatusBarIcon const kBGMStatusBarIconMinValue     = BGMWavecraftStatusBarIcon;
static BGMStatusBarIcon const kBGMStatusBarIconMaxValue     = BGMVolumeStatusBarIcon;
static BGMStatusBarIcon const kBGMStatusBarIconDefaultValue = BGMWavecraftStatusBarIcon;

@interface WCStatusBarItem : NSObject

- (instancetype) initWithPanel:(WCMainPanel*)panel
                  audioDevices:(WCAudioDeviceManager*)devices
                  userDefaults:(WCUserDefaults*)defaults;

// Set this to BGMWavecraftStatusBarIcon to change the icon to the Wavecraft logo (four bars,
// replaced the upstream project's fermata-shaped icon here -- see docs/LESSONS.md for why: it
// read as a microphone/recording icon at status-bar size, which is exactly the wrong impression
// for an app that needs "microphone" permission for an unrelated reason).
//
// Set this to BGMVolumeStatusBarIcon to change the icon to a volume icon. This icon has the
// advantage of indicating the volume level, but we can't make it the default because it looks the
// same as the icon for the macOS volume status bar item.
@property BGMStatusBarIcon icon;

// If the user holds down the option key when they click the status bar icon, this menu item will be
// shown in the main menu.
- (void) setDebugLoggingMenuItem:(WCDebugLoggingMenuItem*)menuItem;

@end

#pragma clang assume_nonnull end

