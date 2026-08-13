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
//  BGMAppOutputRoutingController.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  Owns the per-app output-device routing assignments -- see BGMTapRoute and
//  docs/PROCESS-TAP-ROUTING.md for the mechanism and why it exists. There's at most one
//  BGMTapRoute per app that's been explicitly routed to a non-default output device; apps with no
//  assignment keep using BGMDevice's normal per-app playthrough, unaffected by this class.
//
//  Assignments are persisted (bundle ID -> output device UID) in BGMUserDefaults so they survive
//  Wavecraft restarting. Restoring a persisted assignment only happens for apps that are actually
//  running (there's no menu row, and so no way to show or change the assignment, for an app that
//  isn't) -- this class watches NSWorkspace's list of running apps itself and restores a route as
//  soon as a matching app appears, whether that's at startup or later in the session.
//
//  Starting/stopping a route can block (BGMTapRoute::Start() waits for IO to start, the same way
//  BGMAudioDeviceManager::startPlayThroughSync does), so this class does that work on its own
//  serial background queue, never the main thread.

// Local Includes
#import "BGMUserDefaults.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface BGMAppOutputRoutingController : NSObject

- (instancetype) initWithUserDefaults:(BGMUserDefaults*)userDefaults;

// Rebuilds popUpButton's menu with "Default" plus one item per output device currently connected
// (the same devices BGMOutputDeviceMenuSection would offer as BGMApp's own output), marking
// whichever one matches this app's current routing (or "Default" if it has none). Call right
// before the button's menu is shown -- see BGMAVM_OutputRouteButton's menuNeedsUpdate:. Safe to
// call often; it doesn't touch anything but the button passed in.
- (void) populateMenuForButton:(NSPopUpButton*)popUpButton
                    forBundleID:(NSString*)bundleID;

// Called when the user picks an item from an app's output-device pop-up button. Persists the new
// assignment immediately (so the UI reflects it right away), then starts or stops the underlying
// route asynchronously, showing an error alert if that fails. Pass nil for deviceUID for
// "Default" (i.e. remove any override and let the app go back through BGMDevice as normal).
- (void) userSelectedDeviceUID:(NSString* __nullable)deviceUID
             forAppWithBundleID:(NSString*)bundleID
                        appName:(NSString* __nullable)appName;

// True if bundleID currently has a persisted output-device override. Reflects the user's most
// recent choice immediately; the underlying route may still be starting/stopping asynchronously
// to catch up to it.
- (BOOL) hasOutputOverrideForBundleID:(NSString*)bundleID;

// The UID of the device bundleID's audio is currently routed to, or nil if it has no override
// (i.e. it's using the default output). Same underlying value hasOutputOverrideForBundleID: checks
// for nil-ness -- exposed as its own accessor for callers (AppleScript support) that need the
// actual UID, not just whether one exists.
- (NSString* __nullable) outputOverrideDeviceUIDForBundleID:(NSString*)bundleID;

// Removes every current output-device override, returning all routed apps to Wavecraft's normal
// default-output path. For the "Remove All Output Routing Overrides" troubleshooter -- a panic
// button for the newest, least-tested feature in the app, in case a route gets stuck.
- (void) removeAllOutputOverrides;

// The AudioObjectID of the currently-connected device with the given UID, or kAudioObjectUnknown
// if no connected device has it. Exposed publicly (this class already needs to resolve UIDs to
// live devices for its own popup) so AppleScript support can resolve a UID to a real device object
// without duplicating this lookup.
- (AudioObjectID) findConnectedDeviceIDForUID:(NSString*)uid;

@end

#pragma clang assume_nonnull end
