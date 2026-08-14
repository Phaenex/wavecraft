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
//  WCAppOutputRoutingController.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  Owns the per-app output-device routing assignments -- see WCTapRoute and
//  docs/PROCESS-TAP-ROUTING.md for the mechanism and why it exists. There's at most one
//  WCTapRoute per app that's been explicitly routed to one or more non-default output devices
//  (WCTapRoute itself supports playing through several devices at once from a single tap -- see
//  its header); apps with no assignment keep using BGMDevice's normal per-app playthrough,
//  unaffected by this class.
//
//  Assignments are persisted (bundle ID -> output device UID) in WCUserDefaults so they survive
//  Wavecraft restarting. Restoring a persisted assignment only happens for apps that are actually
//  running (there's no menu row, and so no way to show or change the assignment, for an app that
//  isn't) -- this class watches NSWorkspace's list of running apps itself and restores a route as
//  soon as a matching app appears, whether that's at startup or later in the session.
//
//  Starting/stopping a route can block (WCTapRoute::Start() waits for IO to start, the same way
//  WCAudioDeviceManager::startPlayThroughSync does), so this class does that work on its own
//  serial background queue, never the main thread.

// Local Includes
#import "WCUserDefaults.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface WCAppOutputRoutingController : NSObject

- (instancetype) initWithUserDefaults:(WCUserDefaults*)userDefaults;

// Rebuilds popUpButton's menu with "Default" plus one item per output device currently connected
// (the same devices WCOutputDeviceMenuSection would offer as BGMApp's own output), checkmarking
// every device that's currently one of this app's targets (or "Default" alone if it has none).
// Call right before the button's menu is shown -- see WCAVM_OutputRouteButton's menuNeedsUpdate:.
// Safe to call often; it doesn't touch anything but the button passed in.
- (void) populateMenuForButton:(NSPopUpButton*)popUpButton
                    forBundleID:(NSString*)bundleID;

// Called when the user clicks a device in an app's output-device pop-up button. Adds deviceUID to
// the app's set of target devices if it wasn't already one (so the app's audio now also plays
// through it, alongside any others already selected), or removes it if it was (so that device
// stops, leaving any others playing). Persists the new set immediately (so the UI reflects it
// right away), then reconciles the underlying route asynchronously, showing an error alert if
// that fails.
- (void) userToggledDeviceUID:(NSString*)deviceUID
             forAppWithBundleID:(NSString*)bundleID
                        appName:(NSString* __nullable)appName;

// Called when the user clicks "Default" in an app's output-device pop-up button. Clears every
// target device for that app at once, back to using BGMDevice's normal default-output path.
- (void) userSelectedDefaultForAppWithBundleID:(NSString*)bundleID
                                        appName:(NSString* __nullable)appName;

// Replaces bundleID's entire set of target output devices at once -- the primitive
// userToggledDeviceUID:/userSelectedDefaultForAppWithBundleID: and AppleScript support
// (WCASApplication's outputDevices property) all funnel through, rather than each maintaining
// their own copy of the add/remove/persist logic. An empty array means "no override" (Default).
- (void) setOutputOverrideDeviceUIDs:(NSArray<NSString*>*)deviceUIDs
                    forAppWithBundleID:(NSString*)bundleID
                               appName:(NSString* __nullable)appName;

// True if bundleID currently has at least one persisted output-device override. Reflects the
// user's most recent choice immediately; the underlying route may still be starting/stopping
// asynchronously to catch up to it.
- (BOOL) hasOutputOverrideForBundleID:(NSString*)bundleID;

// The UIDs of the devices bundleID's audio is currently routed to -- empty if it has no override
// (i.e. it's using the default output). Same underlying value hasOutputOverrideForBundleID: checks
// for emptiness -- exposed as its own accessor for callers (AppleScript support) that need the
// actual UIDs, not just whether any exist.
- (NSArray<NSString*>*) outputOverrideDeviceUIDsForBundleID:(NSString*)bundleID;

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
