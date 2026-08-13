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
//  BGMPreferencesMenu.h
//  BGMApp
//
//  Copyright © 2016, 2018, 2019 Kyle Neideck
//
//  Handles the preferences menu UI. The user's preference changes are often passed directly to the driver rather
//  than to other BGMApp classes.
//

// Local Includes
#import "BGMAppOutputRoutingController.h"
#import "BGMAudioDeviceManager.h"
#import "BGMDoNotDisturb.h"
#import "BGMHotkeys.h"
#import "BGMHotkeyRecorderButton.h"
#import "BGMMusicPlayers.h"
#import "BGMPreferredOutputDevices.h"
#import "BGMStatusBarItem.h"
#import "BGMTroubleshootMenu.h"
#import "BGMUserDefaults.h"
#import "BGMXPCListener.h"

// System Includes
#import <Cocoa/Cocoa.h>


NS_ASSUME_NONNULL_BEGIN

@interface BGMPreferencesMenu : NSObject <BGMHotkeyRecorderButtonDelegate, NSMenuDelegate>

// The Preferences NSMenu itself -- extracted from inBGMMenu's XIB-defined structure at init, but
// never shown as part of inBGMMenu (which the main panel replaced -- see BGMMainPanel's header).
// The caller pops this menu up directly (e.g. via
// [NSMenu popUpMenuPositioningItem:atLocation:inView:]) when the user clicks a "Preferences…"
// button in the panel.
@property (nonatomic, readonly) NSMenu* menu;

- (id) initWithBGMMenu:(NSMenu*)inBGMMenu
          audioDevices:(BGMAudioDeviceManager*)inAudioDevices
          musicPlayers:(BGMMusicPlayers*)inMusicPlayers
         statusBarItem:(BGMStatusBarItem*)inStatusBarItem
            aboutPanel:(NSPanel*)inAboutPanel
 aboutPanelLicenseView:(NSTextView*)inAboutPanelLicenseView
          userDefaults:(BGMUserDefaults*)inUserDefaults
preferredOutputDevices:(BGMPreferredOutputDevices*)inPreferredOutputDevices
outputRoutingController:(BGMAppOutputRoutingController*)inOutputRoutingController
               hotkeys:(BGMHotkeys*)inHotkeys
          doNotDisturb:(BGMDoNotDisturb*)inDoNotDisturb;

// BGMXPCListener isn't constructed yet when this class is -- see BGMTroubleshootMenu's header for
// why this is a separate, later call instead of an initializer param.
- (void) setXPCListener:(BGMXPCListener*)xpcListener;

@end

NS_ASSUME_NONNULL_END

