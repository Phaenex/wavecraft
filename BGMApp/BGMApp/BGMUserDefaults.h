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
//  BGMUserDefaults.h
//  BGMApp
//
//  Copyright © 2016-2019 Kyle Neideck
//
//  A simple wrapper around our use of NSUserDefaults. Used to store the preferences/state that only
//  apply to BGMApp. The others are stored by BGMDriver.
//
//  Private data will be stored in the user's keychain instead of user defaults.
//

// Local Includes
#import "BGMHotkeys.h"
#import "BGMStatusBarItem.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface BGMUserDefaults : NSObject

// If inDefaults is nil, settings are not loaded from or saved to disk, which is useful for testing.
- (instancetype) initWithDefaults:(NSUserDefaults* __nullable)inDefaults;

// The musicPlayerID (see BGMMusicPlayer.h), as a string, of the music player selected by the user.
// Must be either null or a string that can be parsed by NSUUID.
@property NSString* __nullable selectedMusicPlayerID;

@property BOOL autoPauseMusicEnabled;

// Whether Do Not Disturb (mute every app except doNotDisturbPriorityAppBundleID) is on. See
// BGMDoNotDisturb.
@property BOOL doNotDisturbEnabled;

// The one app allowed to stay audible while Do Not Disturb is on. nil means none chosen yet --
// enabling Do Not Disturb with no priority app set mutes every running app.
@property NSString* __nullable doNotDisturbPriorityAppBundleID;

// The UIDs of the output devices most recently selected by the user. The most-recently selected
// device is at index 0. See BGMPreferredOutputDevices.
@property NSArray<NSString*>* preferredDeviceUIDs;

// Per-app output routing overrides -- app bundle ID -> the UIDs of the output device(s) its audio
// should be routed to instead of BGMDevice's default output (more than one plays the same app's
// audio through every device in the array at once). Apps with no entry here aren't overridden; an
// entry's array is never empty (BGMAppOutputRoutingController removes the entry entirely instead
// of leaving an empty array). See BGMAppOutputRoutingController and BGMTapRoute.
@property NSDictionary<NSString*, NSArray<NSString*>*>* outputRouteDeviceUIDsByBundleID;

// The (type of) icon to show in the button in the status bar. (The button the user clicks to open
// BGMApp's main menu.)
@property BGMStatusBarIcon statusBarIcon;

// The auth code we're required to send when connecting to GPMDP. Stored in the keychain. Reading
// this property is thread-safe, but writing it isn't.
//
// Returns nil if no code is found or if reading fails. If writing fails, an error is logged, but no
// exception is thrown.
@property NSString* __nullable googlePlayMusicDesktopPlayerPermanentAuthCode;

// Auto-pause delay settings in milliseconds. These control how long to wait before pausing/unpausing
// music when other audio starts/stops playing.
@property NSUInteger pauseDelayMS;
@property NSUInteger maxUnpauseDelayMS;

// True once the user has seen the one-time explanation of why Wavecraft is about to ask for
// "Microphone" access (see BGMAppDelegate). Set right before that dialog is shown, not after --
// if this is somehow shown twice (e.g. the app crashes and relaunches immediately after), that's
// a much smaller problem than skipping it if it was never actually seen.
@property BOOL hasShownMicrophonePermissionExplanation;

// Whether global keyboard shortcuts (system output volume, frontmost app's volume) are enabled.
// Off by default -- unlike Microphone access, Accessibility permission (needed for global hotkeys)
// isn't required for Wavecraft's core function, so it's opt-in rather than requested at launch.
// See BGMHotkeys.
@property BOOL hotkeysEnabled;

// Same one-time-explanation pattern as hasShownMicrophonePermissionExplanation, for the
// Accessibility permission prompt hotkeys need.
@property BOOL hasShownHotkeysAccessibilityExplanation;

// The recorded key + modifier-flags combination bound to a hotkey action -- fully user-rebindable
// to any key, not limited to a fixed set of modifier presets. Returns kBGMHotkeyBindingUnbound for
// an action that's never been bound to anything (shouldn't normally happen -- every action has a
// built-in default -- but a corrupted or hand-edited defaults plist could produce it).
- (BGMHotkeyBinding) hotkeyBindingForAction:(BGMHotkeyAction)action;
- (void) setHotkeyBinding:(BGMHotkeyBinding)binding forAction:(BGMHotkeyAction)action;

// How much each hotkey press changes the volume by. See BGMHotkeys.BGMHotkeyStepSize for the
// values.
@property NSInteger hotkeyStepSize;

@end

#pragma clang assume_nonnull end

