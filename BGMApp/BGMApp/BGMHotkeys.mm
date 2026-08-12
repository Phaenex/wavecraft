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
//  BGMHotkeys.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "BGMHotkeys.h"

// Local Includes
#import "BGM_Types.h"
#import "BGM_Utils.h"

// PublicUtility Includes
#import "CACFArray.h"
#import "CACFDictionary.h"
#import "CACFString.h"
#import "CAException.h"

// System Includes
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>  // For kVK_UpArrow/kVK_DownArrow only -- not deprecated, still the
                            // standard way AppKit apps reference virtual key codes.
#import <algorithm>


#pragma clang assume_nonnull begin

// How much each key press changes the volume by, in [0, 1] scalar terms for the system volume and
// in [kAppRelativeVolumeMinRawValue, kAppRelativeVolumeMaxRawValue] raw terms for app volume, per
// BGMHotkeyStepSize preset -- indexed by the enum's raw value.
static const float kSystemVolumeSteps[] = { 0.02f, 0.05f, 0.15f };
static const SInt32 kAppVolumeSteps[] = { 2, 5, 15 };

@implementation BGMHotkeys {
    BGMAudioDeviceManager* audioDevices;
    BGMUserDefaults* userDefaults;
    id __nullable eventMonitor;
}

- (instancetype) initWithAudioDevices:(BGMAudioDeviceManager*)inAudioDevices
                          userDefaults:(BGMUserDefaults*)inUserDefaults {
    if ((self = [super init])) {
        audioDevices = inAudioDevices;
        userDefaults = inUserDefaults;

        // Only actually start monitoring if hotkeys were left enabled from a previous run *and*
        // Accessibility trust is already granted -- don't re-prompt just because the app relaunched.
        if (userDefaults.hotkeysEnabled && AXIsProcessTrusted()) {
            [self startMonitoring];
        }
    }

    return self;
}

- (void) dealloc {
    [self stopMonitoring];
}

#pragma mark Enabling / Disabling

- (BOOL) isEnabled {
    return userDefaults.hotkeysEnabled;
}

- (void) setEnabled:(BOOL)enabled {
    userDefaults.hotkeysEnabled = enabled;

    if (!enabled) {
        [self stopMonitoring];
        return;
    }

    if (AXIsProcessTrusted()) {
        [self startMonitoring];
        return;
    }

    // Not trusted yet. Explain why, once, before the system's own Accessibility prompt appears --
    // it just says "Wavecraft would like to control this computer using accessibility features",
    // which is alarming out of context for a volume-mixer app.
    if (!userDefaults.hasShownHotkeysAccessibilityExplanation) {
        userDefaults.hasShownHotkeysAccessibilityExplanation = YES;

        NSAlert* explanation = [NSAlert new];
        explanation.messageText = @"Wavecraft needs “Accessibility” access for keyboard shortcuts";
        explanation.informativeText =
            @"macOS requires Accessibility permission for any app that listens for keyboard "
             "shortcuts while it isn’t the active app — that’s the only way global shortcuts "
             "work. Wavecraft only uses this to detect the specific volume shortcuts below; it "
             "doesn’t log or act on anything else you type.\n\nClick Continue, then check the "
             "box for Wavecraft in the System Settings window that opens. Come back here and "
             "turn shortcuts on again afterwards — macOS doesn’t tell apps when this has been "
             "granted, so Wavecraft can’t detect it automatically.";
        [explanation addButtonWithTitle:@"Continue"];
        [explanation runModal];
    }

    // This call itself triggers the system prompt (and, on first grant, adds Wavecraft to the
    // Accessibility list) when the prompt option is true.
    NSDictionary* options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    // Deliberately not starting the monitor here -- AXIsProcessTrustedWithOptions returns
    // immediately, before the user has had a chance to grant anything in the window it just
    // opened. hotkeysEnabled stays YES (set above) so the next call to this method -- e.g. the
    // user toggling the menu item off and back on, or the next app launch -- picks it up once
    // trust is actually granted.
}

- (void) modifierPresetChanged {
    if (userDefaults.hotkeysEnabled && AXIsProcessTrusted()) {
        [self stopMonitoring];
        [self startMonitoring];
    }
}

#pragma mark Monitoring

- (void) startMonitoring {
    [self stopMonitoring];  // Replace any existing monitor rather than stacking a second one.

    eventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                            handler:^(NSEvent* event) {
        [self handleKeyEvent:event];
    }];
}

- (void) stopMonitoring {
    if (eventMonitor) {
        [NSEvent removeMonitor:BGMNN(eventMonitor)];
        eventMonitor = nil;
    }
}

- (void) handleKeyEvent:(NSEvent*)event {
    NSEventModifierFlags flags =
        event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;

    NSEventModifierFlags volumeModifier = [self currentVolumeModifierFlags];
    NSEventModifierFlags appVolumeModifier = volumeModifier | NSEventModifierFlagShift;

    if (event.keyCode != kVK_UpArrow && event.keyCode != kVK_DownArrow) {
        return;
    }

    BOOL increase = (event.keyCode == kVK_UpArrow);

    NSInteger stepIndex = std::min(static_cast<NSInteger>(kBGMHotkeyStepSizeMaxValue),
                                    std::max(static_cast<NSInteger>(kBGMHotkeyStepSizeMinValue),
                                             userDefaults.hotkeyStepSize));

    if (flags == appVolumeModifier) {
        // Check the more specific (Shift-inclusive) combination first -- it's a superset of the
        // plain volume modifier's flags, so checking volumeModifier first would shadow this one.
        SInt32 step = kAppVolumeSteps[stepIndex];
        [self adjustFrontmostAppVolumeBy:(increase ? step : -step)];
    } else if (flags == volumeModifier) {
        float step = kSystemVolumeSteps[stepIndex];
        [self adjustSystemVolumeBy:(increase ? step : -step)];
    }
}

- (NSEventModifierFlags) currentVolumeModifierFlags {
    return (userDefaults.hotkeyModifierPreset == BGMHotkeyModifierPresetControl) ?
        NSEventModifierFlagControl : NSEventModifierFlagOption;
}

#pragma mark Actions

- (void) adjustSystemVolumeBy:(float)delta {
    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        AudioObjectPropertyScope scope = kAudioDevicePropertyScopeOutput;
        UInt32 channel = kAudioObjectPropertyElementMain;

        if (!audioDevices.bgmDevice.HasSettableMainVolume(scope)) {
            return;
        }

        Float32 current = audioDevices.bgmDevice.GetVolumeControlScalarValue(scope, channel);
        Float32 newValue = std::min(1.0f, std::max(0.0f, current + delta));

        audioDevices.bgmDevice.SetVolumeControlScalarValue(scope, channel, newValue);
    });
}

- (void) adjustFrontmostAppVolumeBy:(SInt32)delta {
    NSRunningApplication* __nullable frontmostApp =
        [NSWorkspace sharedWorkspace].frontmostApplication;

    if (!frontmostApp || [frontmostApp.bundleIdentifier isEqualToString:@kBGMAppBundleID]) {
        return;
    }

    NSRunningApplication* nonNullFrontmostApp = BGMNN(frontmostApp);

    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        SInt32 current = [self currentVolumeForApp:nonNullFrontmostApp];
        SInt32 newValue = std::min(static_cast<SInt32>(kAppRelativeVolumeMaxRawValue),
                                    std::max(static_cast<SInt32>(kAppRelativeVolumeMinRawValue),
                                             current + delta));

        audioDevices.bgmDevice.SetAppVolume(
            newValue,
            nonNullFrontmostApp.processIdentifier,
            (__bridge CFStringRef __nullable)nonNullFrontmostApp.bundleIdentifier);
    });
}

// Defaults to the same "unity gain" raw value the volume-reset troubleshooter and the mute button
// restore to if this app has no non-default volume currently set -- see
// BGMTroubleshootMenu::resetAllAppVolumesAndPan's comment on that value.
- (SInt32) currentVolumeForApp:(NSRunningApplication*)app {
    const SInt32 kDefaultVolume = (kAppRelativeVolumeMinRawValue + kAppRelativeVolumeMaxRawValue) / 2;

    CACFArray volumes(audioDevices.bgmDevice.GetAppVolumes(), false);
    UInt32 count = volumes.GetNumberItems();

    for (UInt32 i = 0; i < count; i++) {
        CACFDictionary entry(false);
        volumes.GetCACFDictionary(i, entry);

        pid_t pid = -1;
        entry.GetSInt32(CFSTR(kBGMAppVolumesKey_ProcessID), pid);

        CACFString bundleID;
        bundleID.DontAllowRelease();
        entry.GetCACFString(CFSTR(kBGMAppVolumesKey_BundleID), bundleID);

        BOOL pidMatches = (app.processIdentifier == pid);
        BOOL bundleIDMatches =
            bundleID.IsValid() &&
            [app.bundleIdentifier isEqualToString:(__bridge NSString*)bundleID.GetCFString()];

        if (pidMatches || bundleIDMatches) {
            SInt32 volume = kDefaultVolume;
            entry.GetSInt32(CFSTR(kBGMAppVolumesKey_RelativeVolume), volume);
            return volume;
        }
    }

    return kDefaultVolume;
}

#pragma mark Display

- (NSString*) currentBindingsDescription {
    NSString* modifier =
        (userDefaults.hotkeyModifierPreset == BGMHotkeyModifierPresetControl) ? @"⌃" : @"⌥";

    NSArray<NSString*>* stepNames = @[ @"fine", @"normal", @"coarse" ];
    NSInteger stepIndex = std::min(static_cast<NSInteger>(kBGMHotkeyStepSizeMaxValue),
                                    std::max(static_cast<NSInteger>(kBGMHotkeyStepSizeMinValue),
                                             userDefaults.hotkeyStepSize));

    return [NSString stringWithFormat:
                @"%@↑/↓ System Volume, %@⇧↑/↓ Frontmost App Volume (%@ steps)",
                modifier, modifier, stepNames[static_cast<NSUInteger>(stepIndex)]];
}

@end

#pragma clang assume_nonnull end
