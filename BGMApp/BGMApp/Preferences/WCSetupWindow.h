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
//  WCSetupWindow.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  A real, titled window (not the borderless main panel) that lays out everything Wavecraft
//  needs from the system in one place -- what it is, why it's needed, whether it's currently
//  granted, and a button straight to the right System Settings pane for each. Shown once
//  automatically on a first launch, and reachable afterwards from Preferences.
//
//  This exists because the two permissions Wavecraft needs (Microphone, for the virtual audio
//  device; Accessibility, for global keyboard shortcuts) were previously only ever explained
//  reactively -- a one-time alert right before the system prompt, or an error dialog if denied.
//  There was nowhere to go back and see the whole picture at once, and nothing here at all
//  addressed the other common first-run confusion: a status bar icon that's actually running
//  (see docs/LESSONS.md) but invisible because a menu bar organizer (Bartender, Ice, Hidden Bar,
//  etc.) parked it in a collapsed section by default, which looks identical to "didn't launch."
//

// Local Includes
#import "WCSetupWindowContentView.h"
#import "WCUserDefaults.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface WCSetupWindow : NSWindow

- (instancetype) initWithUserDefaults:(WCUserDefaults*)inUserDefaults;

// Shows the window (creating it key and frontmost, activating the app), after refreshing every
// permission row's live status. Safe to call any number of times.
- (void) show;

// Shows the window if it hasn't already been auto-shown for this exact build (see
// WCUserDefaults.lastShownSetupWindowVersion), and records that it has. Meant to be called once,
// right at the start of launch -- before anything else touches a system permission -- not just on
// a first-ever launch, but on the first launch of *any* new version, since a version bump is
// exactly when new permission requirements are most likely to appear. Returns whether it actually
// showed, so a caller that would otherwise separately explain a permission (see
// WCAppDelegate::explainMicrophonePermissionIfFirstRunThenRequestAccess) can skip that redundant
// explanation when this window, which already covers it, just showed instead.
- (BOOL) showOnFirstLaunchIfNeeded;

// Called exactly once, the moment Microphone access is actually granted -- either by the user
// clicking this window's own "Grant Access" button, or by returning here (see
// applicationDidBecomeActive:) after granting it in System Settings. If access is already granted
// at the moment this is set (e.g. this window's already been through Setup in an earlier
// session), it fires immediately and synchronously from inside the setter -- callers shouldn't
// assume it only fires later, asynchronously. Lets a caller (WCAppDelegate) wait for the user to
// actually finish the permission flow themselves, at their own pace, instead of triggering the
// system permission dialog automatically the instant this window appears.
@property (nonatomic, copy, nullable) void (^microphoneAccessGrantedHandler)(void);

@end

#pragma clang assume_nonnull end
