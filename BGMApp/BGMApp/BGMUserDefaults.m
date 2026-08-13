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
//  BGMUserDefaults.m
//  BGMApp
//
//  Copyright © 2016-2019 Kyle Neideck
//

// Self Include
#import "BGMUserDefaults.h"

// Local Includes
#import "BGMHotkeys.h"
#import "BGM_Utils.h"

// System Includes
#import <Carbon/Carbon.h>  // For kVK_UpArrow/kVK_DownArrow, this feature's built-in defaults.


#pragma clang assume_nonnull begin

// Keys
static NSString* const kDefaultKeyAutoPauseMusicEnabled = @"AutoPauseMusicEnabled";
static NSString* const kDefaultKeyDoNotDisturbEnabled   = @"DoNotDisturbEnabled";
static NSString* const kDefaultKeyDoNotDisturbPriorityAppBundleID =
    @"DoNotDisturbPriorityAppBundleID";
static NSString* const kDefaultKeyDoNotDisturbMutedAppVolumes = @"DoNotDisturbMutedAppVolumes";
static NSString* const kDefaultKeySelectedMusicPlayerID = @"SelectedMusicPlayerID";
static NSString* const kDefaultKeyPreferredDeviceUIDs   = @"PreferredDeviceUIDs";
static NSString* const kDefaultKeyOutputRouteDeviceUIDs = @"OutputRouteDeviceUIDsByBundleID";
static NSString* const kDefaultKeyStatusBarIcon         = @"StatusBarIcon";
static NSString* const kDefaultKeyPauseDelayMS          = @"PauseDelayMS";
static NSString* const kDefaultKeyMaxUnpauseDelayMS     = @"MaxUnpauseDelayMS";
static NSString* const kDefaultKeyHasShownMicExplanation = @"HasShownMicrophonePermissionExplanation";
static NSString* const kDefaultKeyHotkeysEnabled        = @"HotkeysEnabled";
static NSString* const kDefaultKeyHasShownHotkeysAXExplanation =
    @"HasShownHotkeysAccessibilityExplanation";
static NSString* const kDefaultKeyHotkeyBindings        = @"HotkeyBindings";
static NSString* const kDefaultKeyHotkeyStepSize        = @"HotkeyStepSize";

// Sub-keys inside the per-action dictionaries kDefaultKeyHotkeyBindings stores.
static NSString* const kHotkeyBindingKeyCode        = @"KeyCode";
static NSString* const kHotkeyBindingModifierFlags  = @"ModifierFlags";

// Labels for Keychain Data
static NSString* const kKeychainLabelGPMDPAuthCode =
    @"app.backgroundmusic: Google Play Music Desktop Player permanent auth code";

@implementation BGMUserDefaults {
    // The defaults object wrapped by this object.
    NSUserDefaults* defaults;
    // When we're not persisting defaults, settings are stored in this dictionary instead. This
    // var should only be accessed if 'defaults' is nil.
    NSMutableDictionary<NSString*,id>* transientDefaults;
}

- (instancetype) initWithDefaults:(NSUserDefaults* __nullable)inDefaults {
    if ((self = [super init])) {
        defaults = inDefaults;

        // Register the settings defaults.
        //
        // iTunes is the default music player, but we don't set kDefaultKeySelectedMusicPlayerID
        // here so we know when it's never been set. (If it hasn't, we try using BGMDevice's
        // kAudioDeviceCustomPropertyMusicPlayerBundleID property to tell which music player should
        // be selected. See BGMMusicPlayers.)
        NSDictionary* defaultsDict = @{ 
            kDefaultKeyAutoPauseMusicEnabled: @YES,
            kDefaultKeyPauseDelayMS: @1500,
            kDefaultKeyMaxUnpauseDelayMS: @3500
        };

        if (defaults) {
            [defaults registerDefaults:defaultsDict];
        } else {
            transientDefaults = [defaultsDict mutableCopy];
        }
    }

    return self;
}

#pragma mark Selected Music Player

- (NSString* __nullable) selectedMusicPlayerID {
    return [self get:kDefaultKeySelectedMusicPlayerID];
}

- (void) setSelectedMusicPlayerID:(NSString* __nullable)selectedMusicPlayerID {
    [self set:kDefaultKeySelectedMusicPlayerID to:selectedMusicPlayerID];
}

#pragma mark Auto-pause

- (BOOL) autoPauseMusicEnabled {
    return [self getBool:kDefaultKeyAutoPauseMusicEnabled];
}

- (void) setAutoPauseMusicEnabled:(BOOL)autoPauseMusicEnabled {
    [self setBool:kDefaultKeyAutoPauseMusicEnabled to:autoPauseMusicEnabled];
}

#pragma mark Do Not Disturb

- (BOOL) doNotDisturbEnabled {
    return [self getBool:kDefaultKeyDoNotDisturbEnabled];
}

- (void) setDoNotDisturbEnabled:(BOOL)enabled {
    [self setBool:kDefaultKeyDoNotDisturbEnabled to:enabled];
}

- (NSString* __nullable) doNotDisturbPriorityAppBundleID {
    return [self get:kDefaultKeyDoNotDisturbPriorityAppBundleID];
}

- (void) setDoNotDisturbPriorityAppBundleID:(NSString* __nullable)bundleID {
    [self set:kDefaultKeyDoNotDisturbPriorityAppBundleID to:bundleID];
}

- (NSDictionary<NSString*, NSNumber*>*) doNotDisturbMutedAppVolumes {
    NSDictionary<NSString*, NSNumber*>* __nullable volumes =
        [self get:kDefaultKeyDoNotDisturbMutedAppVolumes];
    return volumes ? BGMNN(volumes) : @{};
}

- (void) setDoNotDisturbMutedAppVolumes:(NSDictionary<NSString*, NSNumber*>*)volumes {
    [self set:kDefaultKeyDoNotDisturbMutedAppVolumes to:volumes];
}

#pragma mark Auto-pause Delays

- (NSUInteger) pauseDelayMS {
    NSInteger delay = [self getInt:kDefaultKeyPauseDelayMS or:1500];
    // Clamp to reasonable range: 0ms to 10000ms
    delay = MAX(0, MIN(10000, delay));
    return (NSUInteger)delay;
}

- (void) setPauseDelayMS:(NSUInteger)pauseDelayMS {
    // Clamp to reasonable range: 0ms to 10000ms
    NSUInteger clampedDelay = MAX(0, MIN(10000, pauseDelayMS));
    [self setInt:kDefaultKeyPauseDelayMS to:(NSInteger)clampedDelay];
}

- (NSUInteger) maxUnpauseDelayMS {
    NSInteger delay = [self getInt:kDefaultKeyMaxUnpauseDelayMS or:3500];
    // Clamp to reasonable range: 0ms to 10000ms
    delay = MAX(0, MIN(10000, delay));
    return (NSUInteger)delay;
}

- (void) setMaxUnpauseDelayMS:(NSUInteger)maxUnpauseDelayMS {
    // Clamp to reasonable range: 0ms to 10000ms
    NSUInteger clampedDelay = MAX(0, MIN(10000, maxUnpauseDelayMS));
    [self setInt:kDefaultKeyMaxUnpauseDelayMS to:(NSInteger)clampedDelay];
}

- (NSArray<NSString*>*) preferredDeviceUIDs {
    NSArray<NSString*>* __nullable uids = [self get:kDefaultKeyPreferredDeviceUIDs];
    return uids ? BGMNN(uids) : @[];
}

- (void) setPreferredDeviceUIDs:(NSArray<NSString*>*)devices {
    [self set:kDefaultKeyPreferredDeviceUIDs to:devices];
}

- (NSDictionary<NSString*, NSArray<NSString*>*>*) outputRouteDeviceUIDsByBundleID {
    NSDictionary* __nullable stored = [self get:kDefaultKeyOutputRouteDeviceUIDs];

    if (!stored) {
        return @{};
    }

    // Per-app output routing used to store a single UID string per bundle ID, not an array --
    // Objective-C generics are erased at runtime, so a plist saved by that older version would
    // deserialize fine as a plain NSDictionary and only fail once something calls an NSArray-only
    // method (e.g. containsObject:) on what's actually an NSString. Validate defensively and drop
    // any entry that isn't actually an array of strings, rather than propagating a value that's
    // guaranteed to crash the first real caller downstream.
    NSMutableDictionary<NSString*, NSArray<NSString*>*>* validated = [NSMutableDictionary new];

    for (NSString* bundleID in stored) {
        id __nullable value = stored[bundleID];

        if ([value isKindOfClass:[NSArray class]] &&
            [value count] > 0 &&
            [value indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL* stop) {
                #pragma unused (idx, stop)
                return ![obj isKindOfClass:[NSString class]];
            }] == NSNotFound) {
            validated[bundleID] = value;
        } else {
            NSLog(@"BGMUserDefaults::outputRouteDeviceUIDsByBundleID: Dropping malformed entry "
                   "for %@ (expected a non-empty array of strings, e.g. from a pre-multi-output "
                   "install)", bundleID);
        }
    }

    return validated;
}

- (void) setOutputRouteDeviceUIDsByBundleID:(NSDictionary<NSString*, NSArray<NSString*>*>*)uids {
    [self set:kDefaultKeyOutputRouteDeviceUIDs to:uids];
}

- (BOOL) hasShownMicrophonePermissionExplanation {
    return [self getBool:kDefaultKeyHasShownMicExplanation];
}

- (void) setHasShownMicrophonePermissionExplanation:(BOOL)hasShown {
    [self setBool:kDefaultKeyHasShownMicExplanation to:hasShown];
}

- (BOOL) hotkeysEnabled {
    return [self getBool:kDefaultKeyHotkeysEnabled];
}

- (void) setHotkeysEnabled:(BOOL)enabled {
    [self setBool:kDefaultKeyHotkeysEnabled to:enabled];
}

- (BOOL) hasShownHotkeysAccessibilityExplanation {
    return [self getBool:kDefaultKeyHasShownHotkeysAXExplanation];
}

- (void) setHasShownHotkeysAccessibilityExplanation:(BOOL)hasShown {
    [self setBool:kDefaultKeyHasShownHotkeysAXExplanation to:hasShown];
}

// The dictionary key each action's binding is stored under inside kDefaultKeyHotkeyBindings.
// Stable strings, not the enum's raw NSInteger value -- so a future reordering of BGMHotkeyAction
// doesn't silently reinterpret an already-saved binding as a different action.
static NSString* BGMHotkeyActionStorageKey(BGMHotkeyAction action) {
    switch (action) {
        case BGMHotkeyActionSystemVolumeUp:   return @"SystemVolumeUp";
        case BGMHotkeyActionSystemVolumeDown: return @"SystemVolumeDown";
        case BGMHotkeyActionAppVolumeUp:      return @"AppVolumeUp";
        case BGMHotkeyActionAppVolumeDown:    return @"AppVolumeDown";
    }

    return @"Unknown";
}

// Matches this feature's original behavior before per-action rebinding existed: Option+Up/Down
// for system volume, Option+Shift+Up/Down for the frontmost app's volume.
static BGMHotkeyBinding BGMDefaultHotkeyBinding(BGMHotkeyAction action) {
    switch (action) {
        case BGMHotkeyActionSystemVolumeUp:
            return (BGMHotkeyBinding){ kVK_UpArrow, NSEventModifierFlagOption };
        case BGMHotkeyActionSystemVolumeDown:
            return (BGMHotkeyBinding){ kVK_DownArrow, NSEventModifierFlagOption };
        case BGMHotkeyActionAppVolumeUp:
            return (BGMHotkeyBinding){
                kVK_UpArrow, NSEventModifierFlagOption | NSEventModifierFlagShift };
        case BGMHotkeyActionAppVolumeDown:
            return (BGMHotkeyBinding){
                kVK_DownArrow, NSEventModifierFlagOption | NSEventModifierFlagShift };
    }

    return kBGMHotkeyBindingUnbound;
}

- (BGMHotkeyBinding) hotkeyBindingForAction:(BGMHotkeyAction)action {
    NSDictionary<NSString*, NSDictionary*>* __nullable allBindings =
        [self get:kDefaultKeyHotkeyBindings];
    NSDictionary* __nullable stored = allBindings[BGMHotkeyActionStorageKey(action)];

    if (!stored) {
        return BGMDefaultHotkeyBinding(action);
    }

    NSNumber* __nullable keyCode = stored[kHotkeyBindingKeyCode];
    NSNumber* __nullable modifierFlags = stored[kHotkeyBindingModifierFlags];

    if (!keyCode || !modifierFlags) {
        // Malformed entry (hand-edited defaults plist, or a future format change) -- fall back to
        // the built-in default rather than propagating a half-valid binding.
        NSLog(@"BGMUserDefaults::hotkeyBindingForAction: Malformed binding for action %ld, using "
               "default", (long)action);
        return BGMDefaultHotkeyBinding(action);
    }

    return (BGMHotkeyBinding){
        (unsigned short)keyCode.unsignedIntValue,
        (NSEventModifierFlags)modifierFlags.unsignedIntegerValue
    };
}

- (void) setHotkeyBinding:(BGMHotkeyBinding)binding forAction:(BGMHotkeyAction)action {
    NSMutableDictionary<NSString*, NSDictionary*>* allBindings =
        [([self get:kDefaultKeyHotkeyBindings] ?: @{}) mutableCopy];

    allBindings[BGMHotkeyActionStorageKey(action)] = @{
        kHotkeyBindingKeyCode: @(binding.keyCode),
        kHotkeyBindingModifierFlags: @(binding.modifierFlags)
    };

    [self set:kDefaultKeyHotkeyBindings to:allBindings];
}

- (NSInteger) hotkeyStepSize {
    NSInteger stepSize = [self getInt:kDefaultKeyHotkeyStepSize or:BGMHotkeyStepSizeNormal];

    // Just in case we get an invalid value somehow. (BGMHotkeys.mm also clamps this at every use
    // site before indexing into an array with it, so an invalid value here wouldn't crash -- but
    // it would silently disagree with what the Preferences menu shows as selected.)
    if ((stepSize < kBGMHotkeyStepSizeMinValue) || (stepSize > kBGMHotkeyStepSizeMaxValue)) {
        NSLog(@"BGMUserDefaults::hotkeyStepSize: Unknown BGMHotkeyStepSize: %ld", (long)stepSize);
        stepSize = BGMHotkeyStepSizeNormal;
    }

    return stepSize;
}

- (void) setHotkeyStepSize:(NSInteger)stepSize {
    [self setInt:kDefaultKeyHotkeyStepSize to:stepSize];
}

- (BGMStatusBarIcon) statusBarIcon {
    NSInteger icon = [self getInt:kDefaultKeyStatusBarIcon or:kBGMStatusBarIconDefaultValue];

    // Just in case we get an invalid value somehow.
    if ((icon < kBGMStatusBarIconMinValue) || (icon > kBGMStatusBarIconMaxValue)) {
        NSLog(@"BGMUserDefaults::statusBarIcon: Unknown BGMStatusBarIcon: %ld", (long)icon);
        icon = kBGMStatusBarIconDefaultValue;
    }

    return (BGMStatusBarIcon)icon;
}

- (void) setStatusBarIcon:(BGMStatusBarIcon)icon {
    [self setInt:kDefaultKeyStatusBarIcon to:icon];
}

#pragma mark Google Play Music Desktop Player

- (NSString* __nullable) googlePlayMusicDesktopPlayerPermanentAuthCode {
    // Try to read the permanent auth code from the user's keychain.
    NSDictionary<NSString*, NSObject*>* query = @{
        (__bridge NSString*)kSecClass: (__bridge NSString*)kSecClassGenericPassword,
        (__bridge NSString*)kSecAttrLabel: kKeychainLabelGPMDPAuthCode,
        (__bridge NSString*)kSecMatchLimit: (__bridge NSString*)kSecMatchLimitOne,
        (__bridge NSString*)kSecReturnData: @YES
    };

    CFTypeRef result = nil;
    OSStatus err = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    NSString* __nullable authCode = nil;

    // Check the return status, null check and check the type.
    if ((err == errSecSuccess) && result && (CFGetTypeID(result) == CFDataGetTypeID())) {
        // Convert it to a string.
        CFStringRef __nullable code =
                CFStringCreateFromExternalRepresentation(kCFAllocatorDefault,
                                                         result,
                                                         kCFStringEncodingUTF8);
        authCode = (__bridge_transfer NSString* __nullable)code;
    } else if (err != errSecItemNotFound) {
        NSString* __nullable errMsg =
                (__bridge_transfer NSString* __nullable)SecCopyErrorMessageString(err, nil);
        NSLog(@"Failed to read GPMDP auth code from keychain: %d, %@", err, errMsg);
    }

    // Release the data we read.
    if (result) {
        CFRelease(result);
    }

    return authCode;
}

- (void) setGooglePlayMusicDesktopPlayerPermanentAuthCode:(NSString* __nullable)authCode {
    if (authCode) {
        // Convert it to an NSData so we can store it in the user's keychain.
        NSData* authCodeData = [authCode dataUsingEncoding:NSUTF8StringEncoding];

        // Delete the old code if necessary. (There's an update function, but this takes less code.)
        if (self.googlePlayMusicDesktopPlayerPermanentAuthCode) {
            [self deleteGPMDPPermanentAuthCode];
        }

        // Store the code.
        [self addGPMDPPermanentAuthCode:authCodeData];
    } else {
        [self deleteGPMDPPermanentAuthCode];
    }
}

- (void) addGPMDPPermanentAuthCode:(NSData*)authCodeData {
    NSDictionary<NSString*, NSObject*>* attributes = @{
        (__bridge NSString*)kSecClass: (__bridge NSString*)kSecClassGenericPassword,
        (__bridge NSString*)kSecAttrLabel: kKeychainLabelGPMDPAuthCode,
        (__bridge NSString*)kSecValueData: authCodeData
    };

    OSStatus err = SecItemAdd((__bridge CFDictionaryRef)attributes, nil);

    // Just log an error if it failed.
    if (err != errSecSuccess) {
        NSString* errMsg = (__bridge_transfer NSString*)SecCopyErrorMessageString(err, nil);
        NSLog(@"Failed to store GPMDP auth code in keychain: %d, %@", err, errMsg);
    }
}

- (void) deleteGPMDPPermanentAuthCode {
    NSDictionary<NSString*, NSObject*>* query = @{
        (__bridge NSString*)kSecClass: (__bridge NSString*)kSecClassGenericPassword,
        (__bridge NSString*)kSecAttrLabel: kKeychainLabelGPMDPAuthCode
    };

    OSStatus err = SecItemDelete((__bridge CFDictionaryRef)query);

    // Just log an error if it failed.
    if (err != errSecSuccess) {
        NSString* errMsg = (__bridge_transfer NSString*)SecCopyErrorMessageString(err, nil);
        NSLog(@"Failed to delete GPMDP auth code from keychain: %d, %@", err, errMsg);
    }
}

#pragma mark General Accessors

- (id __nullable) get:(NSString*)key {
    return defaults ? [defaults objectForKey:key] : transientDefaults[key];
}

- (void) set:(NSString*)key to:(NSObject<NSCopying,NSSecureCoding>* __nullable)value {
    if (defaults) {
        [defaults setObject:value forKey:key];
    } else {
        transientDefaults[key] = value;
    }
}

// TODO: This method should have a default value param.
- (BOOL) getBool:(NSString*)key {
    return defaults ? [defaults boolForKey:key] : [transientDefaults[key] boolValue];
}

- (void) setBool:(NSString*)key to:(BOOL)value {
    if (defaults) {
        [defaults setBool:value forKey:key];
    } else {
        transientDefaults[key] = @(value);
    }
}

- (NSInteger) getInt:(NSString*)key or:(NSInteger)valueIfNil
{
    if (defaults) {
        if ([defaults objectForKey:key]) {
            return [defaults integerForKey:key];
        } else {
            return valueIfNil;
        }
    } else {
        if (transientDefaults[key]) {
            return [transientDefaults[key] intValue];
        } else {
            return valueIfNil;
        }
    }
}

- (void) setInt:(NSString*)key to:(NSInteger)value {
    if (defaults) {
        [defaults setInteger:value forKey:key];
    } else {
        transientDefaults[key] = @(value);
    }
}

@end

#pragma clang assume_nonnull end

