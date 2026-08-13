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
//  BGMDoNotDisturb.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  Mutes every running app's audio except one chosen "priority" app -- the inverse of
//  BGMAutoPauseMusic (which pauses one specific, known music-player app when anything else plays).
//  Do Not Disturb works on any running app, not just the fixed set of supported music players,
//  since the point is "let ME choose what's allowed to make noise," not "protect my music."
//
//  Unlike BGMAutoPauseMusic, this doesn't send an app-level pause/unpause command -- it works
//  entirely through BGMDevice's existing per-app volume property (the same one the volume sliders
//  use), forcing every non-priority app to kAppRelativeVolumeMinRawValue and restoring each app's
//  own volume from before Do Not Disturb was turned on when it turns back off or that app becomes
//  the priority app.
//

// Local Includes
#import "BGMAudioDeviceManager.h"

// System Includes
#import <Cocoa/Cocoa.h>

@class BGMUserDefaults;


NS_ASSUME_NONNULL_BEGIN

@interface BGMDoNotDisturb : NSObject

- (instancetype) initWithAudioDevices:(BGMAudioDeviceManager*)audioDevices
                          userDefaults:(BGMUserDefaults*)userDefaults;

@property (nonatomic, readonly) BOOL isEnabled;

// Muting/restoring app volumes can throw (the same CoreAudio HAL calls BGMHotkeys/BGMAppVolumes
// use elsewhere) -- exceptions are logged and swallowed internally (BGM_Utils::
// LogAndSwallowExceptions, matching this codebase's existing convention for UI-triggered HAL
// calls), so this never throws, but a request can partially fail silently for an individual app.
- (void) setEnabled:(BOOL)enabled;

// The one app allowed to stay audible while enabled. Changing this while already enabled
// immediately re-applies: the previous priority app (if any) gets muted like everything else, and
// the new one gets its pre-Do-Not-Disturb volume restored. nil mutes every running app.
@property (nonatomic, readonly, nullable) NSString* priorityAppBundleID;
- (void) setPriorityAppBundleID:(NSString* __nullable)bundleID;

// True if bundleID is currently muted by Do Not Disturb (i.e. this instance is the reason its
// volume is at kAppRelativeVolumeMinRawValue right now). For callers that need to avoid clobbering
// a Do Not Disturb mute -- see BGMTroubleshootMenu's "Reset All App Volumes, Pan & EQ", which skips
// muted apps rather than un-muting them out from under Do Not Disturb with no warning.
- (BOOL) isMutingBundleID:(NSString*)bundleID;

@end

NS_ASSUME_NONNULL_END
