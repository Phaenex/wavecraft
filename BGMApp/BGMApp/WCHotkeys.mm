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
//  WCHotkeys.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "WCHotkeys.h"

// Local Includes
#import "BGM_Types.h"
#import "BGM_Utils.h"
#import "WCUserDefaults.h"

// PublicUtility Includes
#import "CACFArray.h"
#import "CACFDictionary.h"
#import "CACFString.h"
#import "CAException.h"

// System Includes
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>  // For kVK_* key codes and UCKeyTranslate/TIS* -- not deprecated,
                            // still the standard way AppKit apps reference virtual key codes and
                            // translate them through the current keyboard layout.
#import <algorithm>
#import <climits>


#pragma clang assume_nonnull begin

// How much each key press changes the volume by, in [0, 1] scalar terms for the system volume and
// in [kAppRelativeVolumeMinRawValue, kAppRelativeVolumeMaxRawValue] raw terms for app volume, per
// BGMHotkeyStepSize preset -- indexed by the enum's raw value.
static const float kSystemVolumeSteps[] = { 0.02f, 0.05f, 0.15f };
static const SInt32 kAppVolumeSteps[] = { 2, 5, 15 };

BGMHotkeyBinding const kBGMHotkeyBindingUnbound = { USHRT_MAX, 0 };

BOOL BGMHotkeyBindingIsUnbound(BGMHotkeyBinding binding) {
    return binding.keyCode == kBGMHotkeyBindingUnbound.keyCode;
}

BOOL BGMHotkeyBindingsEqual(BGMHotkeyBinding a, BGMHotkeyBinding b) {
    return (a.keyCode == b.keyCode) && (a.modifierFlags == b.modifierFlags);
}

// kVK_* codes below cover the keys someone would plausibly bind a volume shortcut to. There's no
// complete "key code to symbol" table in any public macOS API (the closest, UCKeyTranslate, maps
// through the current keyboard layout and can return a different string per layout, which would
// make a recorded binding's *description* layout-dependent even though the binding itself --
// matched by raw keyCode in WCHotkeys::handleKeyEvent: -- isn't), so this covers arrows, common
// navigation/media keys, and falls back to "Key <code>" for anything else rather than guessing.
static NSString* BGMKeyCodeSymbol(unsigned short keyCode) {
    switch (keyCode) {
        case kVK_UpArrow:      return @"↑";
        case kVK_DownArrow:    return @"↓";
        case kVK_LeftArrow:    return @"←";
        case kVK_RightArrow:   return @"→";
        case kVK_Space:        return @"Space";
        case kVK_Tab:          return @"⇥";
        case kVK_Return:       return @"⏎";
        case kVK_Delete:       return @"⌫";
        case kVK_Escape:       return @"⎋";
        case kVK_PageUp:       return @"Page Up";
        case kVK_PageDown:     return @"Page Down";
        case kVK_Home:         return @"Home";
        case kVK_End:          return @"End";
        case kVK_F1:  return @"F1";  case kVK_F2:  return @"F2";  case kVK_F3:  return @"F3";
        case kVK_F4:  return @"F4";  case kVK_F5:  return @"F5";  case kVK_F6:  return @"F6";
        case kVK_F7:  return @"F7";  case kVK_F8:  return @"F8";  case kVK_F9:  return @"F9";
        case kVK_F10: return @"F10"; case kVK_F11: return @"F11"; case kVK_F12: return @"F12";
        default: {
            // Printable ANSI keys (letters/digits/punctuation) -- translate through the current
            // keyboard layout so, e.g., kVK_ANSI_A shows "A" rather than "Key 0". Falls through to
            // the numeric fallback below if translation fails for any reason (non-ANSI layout,
            // dead key, etc.) rather than showing nothing.
            TISInputSourceRef __nullable source = TISCopyCurrentKeyboardLayoutInputSource();
            if (source) {
                CFDataRef __nullable layoutData =
                    (CFDataRef __nullable)TISGetInputSourceProperty(source,
                                                                     kTISPropertyUnicodeKeyLayoutData);
                if (layoutData) {
                    const UCKeyboardLayout* layout =
                        (const UCKeyboardLayout*)CFDataGetBytePtr(layoutData);
                    UInt32 deadKeyState = 0;
                    UniCharCount length = 0;
                    UniChar chars[4] = { 0 };

                    OSStatus status = UCKeyTranslate(layout,
                                                      keyCode,
                                                      kUCKeyActionDisplay,
                                                      0,
                                                      LMGetKbdType(),
                                                      kUCKeyTranslateNoDeadKeysBit,
                                                      &deadKeyState,
                                                      sizeof(chars) / sizeof(chars[0]),
                                                      &length,
                                                      chars);

                    if (status == noErr && length > 0) {
                        NSString* symbol =
                            [[NSString stringWithCharacters:chars length:length] uppercaseString];
                        CFRelease(source);
                        return symbol;
                    }
                }

                CFRelease(source);
            }

            return [NSString stringWithFormat:@"Key %u", keyCode];
        }
    }
}

NSString* BGMHotkeyBindingDescription(BGMHotkeyBinding binding) {
    if (BGMHotkeyBindingIsUnbound(binding)) {
        return @"Click to Record";
    }

    NSMutableString* description = [NSMutableString new];

    // Fixed display order matches how macOS itself always orders modifier symbols.
    if (binding.modifierFlags & NSEventModifierFlagControl) { [description appendString:@"⌃"]; }
    if (binding.modifierFlags & NSEventModifierFlagOption)  { [description appendString:@"⌥"]; }
    if (binding.modifierFlags & NSEventModifierFlagShift)   { [description appendString:@"⇧"]; }
    if (binding.modifierFlags & NSEventModifierFlagCommand) { [description appendString:@"⌘"]; }

    [description appendString:BGMKeyCodeSymbol(binding.keyCode)];

    return description;
}

NSString* BGMHotkeyActionDisplayName(BGMHotkeyAction action) {
    switch (action) {
        case BGMHotkeyActionSystemVolumeUp:   return @"System Volume Up";
        case BGMHotkeyActionSystemVolumeDown: return @"System Volume Down";
        case BGMHotkeyActionAppVolumeUp:      return @"Frontmost App Volume Up";
        case BGMHotkeyActionAppVolumeDown:    return @"Frontmost App Volume Down";
    }

    return @"Unknown Shortcut";
}

@implementation WCHotkeys {
    WCAudioDeviceManager* audioDevices;
    WCUserDefaults* userDefaults;
    id __nullable eventMonitor;
}

- (instancetype) initWithAudioDevices:(WCAudioDeviceManager*)inAudioDevices
                          userDefaults:(WCUserDefaults*)inUserDefaults {
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

- (void) bindingsChanged {
    // The global monitor below listens for every key-down system-wide and filters by binding
    // inside handleKeyEvent:, which reads userDefaults live -- so a changed binding takes effect
    // on its own, without needing to re-register the monitor. Restarting anyway (when hotkeys are
    // actually running) is defensive, not load-bearing: it guards against a future change to
    // startMonitoring that captures binding state at registration time instead of reading it live.
    if (userDefaults.hotkeysEnabled && AXIsProcessTrusted()) {
        [self stopMonitoring];
        [self startMonitoring];
    }
}

#pragma mark Monitoring

- (void) startMonitoring {
    [self stopMonitoring];  // Replace any existing monitor rather than stacking a second one.

    // Apple doesn't document (in the header or otherwise) which thread this handler block runs
    // on -- unlike addLocalMonitorForEventsMatchingMask:, which is synchronous on the calling
    // thread, the global monitor is commonly observed running off the main thread. handleKeyEvent:
    // touches WCUserDefaults, NSWorkspace, and CoreAudio HAL property calls, none of which are
    // documented as safe from an arbitrary background thread the way they'd be from the main
    // thread -- so dispatch back to main rather than assume.
    eventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                            handler:^(NSEvent* event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleKeyEvent:event];
        });
    }];
}

- (void) stopMonitoring {
    if (eventMonitor) {
        [NSEvent removeMonitor:BGMNN(eventMonitor)];
        eventMonitor = nil;
    }
}

- (void) handleKeyEvent:(NSEvent*)event {
    // Never fire while Wavecraft itself is the frontmost app -- "adjust the frontmost app's
    // volume" has no sensible meaning when that app is Wavecraft, and there's no reason to
    // hijack a key combination from whatever's actually in front, including Wavecraft's own
    // menu/preferences UI (e.g. an arrow key used to navigate a menu).
    if ([NSRunningApplication currentApplication].isActive) {
        return;
    }

    BGMHotkeyBinding pressed = {
        event.keyCode,
        event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask
    };

    if (BGMHotkeyBindingIsUnbound(pressed)) {
        return;
    }

    BGMHotkeyAction action;
    if (BGMHotkeyBindingsEqual(pressed, [userDefaults hotkeyBindingForAction:BGMHotkeyActionSystemVolumeUp])) {
        action = BGMHotkeyActionSystemVolumeUp;
    } else if (BGMHotkeyBindingsEqual(pressed, [userDefaults hotkeyBindingForAction:BGMHotkeyActionSystemVolumeDown])) {
        action = BGMHotkeyActionSystemVolumeDown;
    } else if (BGMHotkeyBindingsEqual(pressed, [userDefaults hotkeyBindingForAction:BGMHotkeyActionAppVolumeUp])) {
        action = BGMHotkeyActionAppVolumeUp;
    } else if (BGMHotkeyBindingsEqual(pressed, [userDefaults hotkeyBindingForAction:BGMHotkeyActionAppVolumeDown])) {
        action = BGMHotkeyActionAppVolumeDown;
    } else {
        return;
    }

    NSInteger stepIndex = std::min(static_cast<NSInteger>(kBGMHotkeyStepSizeMaxValue),
                                    std::max(static_cast<NSInteger>(kBGMHotkeyStepSizeMinValue),
                                             userDefaults.hotkeyStepSize));

    switch (action) {
        case BGMHotkeyActionSystemVolumeUp:
            [self adjustSystemVolumeBy:kSystemVolumeSteps[stepIndex]];
            break;
        case BGMHotkeyActionSystemVolumeDown:
            [self adjustSystemVolumeBy:-kSystemVolumeSteps[stepIndex]];
            break;
        case BGMHotkeyActionAppVolumeUp:
            [self adjustFrontmostAppVolumeBy:kAppVolumeSteps[stepIndex]];
            break;
        case BGMHotkeyActionAppVolumeDown:
            [self adjustFrontmostAppVolumeBy:-kAppVolumeSteps[stepIndex]];
            break;
    }
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
// WCTroubleshootMenu::resetAllAppVolumesAndPan's comment on that value.
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
    NSArray<NSString*>* stepNames = @[ @"fine", @"normal", @"coarse" ];
    NSInteger stepIndex = std::min(static_cast<NSInteger>(kBGMHotkeyStepSizeMaxValue),
                                    std::max(static_cast<NSInteger>(kBGMHotkeyStepSizeMinValue),
                                             userDefaults.hotkeyStepSize));

    NSString* systemUp = BGMHotkeyBindingDescription([userDefaults hotkeyBindingForAction:BGMHotkeyActionSystemVolumeUp]);
    NSString* systemDown = BGMHotkeyBindingDescription([userDefaults hotkeyBindingForAction:BGMHotkeyActionSystemVolumeDown]);
    NSString* appUp = BGMHotkeyBindingDescription([userDefaults hotkeyBindingForAction:BGMHotkeyActionAppVolumeUp]);
    NSString* appDown = BGMHotkeyBindingDescription([userDefaults hotkeyBindingForAction:BGMHotkeyActionAppVolumeDown]);

    return [NSString stringWithFormat:
                @"System Volume: %@ / %@, Frontmost App: %@ / %@ (%@ steps)",
                systemUp, systemDown, appUp, appDown,
                stepNames[static_cast<NSUInteger>(stepIndex)]];
}

@end

#pragma clang assume_nonnull end
