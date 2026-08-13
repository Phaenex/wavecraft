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
//  BGMHotkeys.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  Global keyboard shortcuts for the system output volume and the frontmost app's volume -- from
//  upstream Background Music's own TODO.md wishlist. Off by default: unlike Microphone access,
//  the Accessibility permission this needs isn't required for Wavecraft's core function, so it's
//  opt-in from Preferences rather than requested at launch.
//
//  Accessibility trust has no live "permission granted" callback the way AVCaptureDevice's
//  microphone request does -- macOS only lets the user grant it by checking a box in System
//  Settings, and there's no notification when they do. So turning hotkeys on when trust hasn't
//  been granted yet shows the system prompt and asks the user to toggle the switch again after
//  granting it, rather than pretending this can complete automatically.

// Local Includes
#import "BGMAudioDeviceManager.h"

// System Includes
#import <Cocoa/Cocoa.h>

// BGMUserDefaults.h imports this header (to declare hotkeyBindingForAction:/setHotkeyBinding:
// forAction:, which need BGMHotkeyBinding/BGMHotkeyAction's real definitions, not just a pointer
// type), so importing it back here would be circular. This header only ever uses BGMUserDefaults
// as a pointer type, so a forward declaration is enough -- BGMHotkeys.mm imports the real header.
@class BGMUserDefaults;


#pragma clang assume_nonnull begin

// Which action a recorded key binding triggers. Each is independently rebindable to any key +
// modifier-flags combination -- unlike the old fixed Option/Control preset, these aren't limited
// to Up/Down arrow keys either.
typedef NS_ENUM(NSInteger, BGMHotkeyAction) {
    BGMHotkeyActionSystemVolumeUp = 0,
    BGMHotkeyActionSystemVolumeDown,
    BGMHotkeyActionAppVolumeUp,
    BGMHotkeyActionAppVolumeDown,
};

static BGMHotkeyAction const kBGMHotkeyActionMinValue = BGMHotkeyActionSystemVolumeUp;
static BGMHotkeyAction const kBGMHotkeyActionMaxValue = BGMHotkeyActionAppVolumeDown;
static NSInteger const kBGMHotkeyActionCount = 4;

// A single recorded key + modifier-flags combination. keyCode is an NSEvent.keyCode value (a
// virtual key code, e.g. kVK_UpArrow); modifierFlags is always pre-masked to
// NSEventModifierFlagDeviceIndependentFlagsMask so comparisons don't have to mask on every use.
// kBGMHotkeyBindingUnbound (keyCode == USHRT_MAX) means "no key recorded for this action" -- 0 is
// a real key code (kVK_ANSI_A), so it can't double as the sentinel.
typedef struct {
    unsigned short keyCode;
    NSEventModifierFlags modifierFlags;
} BGMHotkeyBinding;

extern BGMHotkeyBinding const kBGMHotkeyBindingUnbound;

BOOL BGMHotkeyBindingIsUnbound(BGMHotkeyBinding binding);
BOOL BGMHotkeyBindingsEqual(BGMHotkeyBinding a, BGMHotkeyBinding b);

// e.g. "⌥↑", "⌃⇧↓", or "Click to Record" for kBGMHotkeyBindingUnbound.
NSString* BGMHotkeyBindingDescription(BGMHotkeyBinding binding);

// e.g. "System Volume Up".
NSString* BGMHotkeyActionDisplayName(BGMHotkeyAction action);

typedef NS_ENUM(NSInteger, BGMHotkeyStepSize) {
    BGMHotkeyStepSizeFine = 0,     // 2% system volume, 2 raw units of app volume per press
    BGMHotkeyStepSizeNormal = 1,   // 5% / 5 raw units -- the default
    BGMHotkeyStepSizeCoarse = 2,   // 15% / 15 raw units
};

static BGMHotkeyStepSize const kBGMHotkeyStepSizeMinValue = BGMHotkeyStepSizeFine;
static BGMHotkeyStepSize const kBGMHotkeyStepSizeMaxValue = BGMHotkeyStepSizeCoarse;

@interface BGMHotkeys : NSObject

- (instancetype) initWithAudioDevices:(BGMAudioDeviceManager*)audioDevices
                          userDefaults:(BGMUserDefaults*)userDefaults;

// Turns global keyboard shortcuts on/off and persists the choice to
// userDefaults.hotkeysEnabled. If turning on and Accessibility trust hasn't been granted yet,
// shows a one-time explanation (see the header comment on this class for why this can't just
// complete automatically) and leaves hotkeysEnabled set to the requested value, but doesn't
// actually start monitoring until trust is confirmed -- call this again (e.g. by toggling the
// menu item off and back on) after granting it in System Settings.
- (void) setEnabled:(BOOL)enabled;

- (BOOL) isEnabled;

// Records that a binding changed in userDefaults so any cached state gets refreshed. Safe to call
// whether or not hotkeys are currently enabled.
- (void) bindingsChanged;

// A human-readable description of the current keybindings, for display in the Preferences menu.
- (NSString*) currentBindingsDescription;

@end

#pragma clang assume_nonnull end
