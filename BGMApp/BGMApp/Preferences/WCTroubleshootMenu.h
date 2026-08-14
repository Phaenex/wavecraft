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
//  WCTroubleshootMenu.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  Clickable diagnostics that actually run and fix the failure modes that are realistic to hit
//  while using Wavecraft, right from the Preferences menu -- not just documentation telling the
//  user to do it themselves. Everything here operates in user space, through APIs the app already
//  has as a running, permitted process; nothing here attempts (or can attempt) anything that needs
//  sudo -- that's still a real terminal and ./build_and_install.sh, same as it's always been.
//

// Local Includes
#import "WCAppOutputRoutingController.h"
#import "WCAudioDeviceManager.h"
#import "WCDoNotDisturb.h"
#import "WCPreferredOutputDevices.h"
#import "WCXPCListener.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface WCTroubleshootMenu : NSObject

- (instancetype) initWithPreferencesMenu:(NSMenu*)prefsMenu
                            audioDevices:(WCAudioDeviceManager*)audioDevices
                 preferredOutputDevices:(WCPreferredOutputDevices*)preferredOutputDevices
                outputRoutingController:(WCAppOutputRoutingController*)outputRoutingController
                           doNotDisturb:(WCDoNotDisturb*)doNotDisturb;

// WCXPCListener isn't constructed yet when this class is (see WCAppDelegate's launch sequence),
// so it's handed over later instead of through the initializer. The "Reconnect to BGMXPCHelper"
// troubleshooter is a no-op with a clear message if this hasn't been called yet.
- (void) setXPCListener:(WCXPCListener*)xpcListener;

@end

#pragma clang assume_nonnull end
