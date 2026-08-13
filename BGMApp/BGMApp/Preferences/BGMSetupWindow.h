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
//  BGMSetupWindow.h
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
#import "BGMSetupWindowContentView.h"
#import "BGMUserDefaults.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface BGMSetupWindow : NSWindow

- (instancetype) initWithUserDefaults:(BGMUserDefaults*)inUserDefaults;

// Shows the window (creating it key and frontmost, activating the app), after refreshing every
// permission row's live status. Safe to call any number of times.
- (void) show;

// Shows the window if it hasn't already been auto-shown for this exact build (see
// BGMUserDefaults.lastShownSetupWindowVersion), and records that it has. Meant to be called once,
// right after the rest of the app finishes launching -- not just on a first-ever launch, but on
// the first launch of *any* new version, since a version bump is exactly when new permission
// requirements are most likely to appear.
- (void) showOnFirstLaunchIfNeeded;

@end

#pragma clang assume_nonnull end
