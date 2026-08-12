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
#import "BGMUserDefaults.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

typedef NS_ENUM(NSInteger, BGMHotkeyModifierPreset) {
    // Volume: Option+Up/Down. Frontmost app volume: Option+Shift+Up/Down.
    BGMHotkeyModifierPresetOption = 0,
    // Volume: Control+Up/Down. Frontmost app volume: Control+Shift+Up/Down.
    BGMHotkeyModifierPresetControl,
};

static BGMHotkeyModifierPreset const kBGMHotkeyModifierPresetMinValue = BGMHotkeyModifierPresetOption;
static BGMHotkeyModifierPreset const kBGMHotkeyModifierPresetMaxValue = BGMHotkeyModifierPresetControl;

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

// Re-registers the hotkeys with userDefaults.hotkeyModifierPreset's current value. No-op if
// hotkeys aren't currently enabled.
- (void) modifierPresetChanged;

// A human-readable description of the current keybindings, for display in the Preferences menu.
- (NSString*) currentBindingsDescription;

@end

#pragma clang assume_nonnull end
