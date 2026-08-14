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
//  WCDoNotDisturb.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "WCDoNotDisturb.h"

// Local Includes
#import "BGM_Types.h"
#import "BGM_Utils.h"
#import "WCUserDefaults.h"

// PublicUtility Includes
#import "CACFArray.h"
#import "CACFDictionary.h"
#import "CACFString.h"

// STL Includes
#import <algorithm>


NS_ASSUME_NONNULL_BEGIN

static void* kRunningApplicationsContext = &kRunningApplicationsContext;

@implementation WCDoNotDisturb {
    WCAudioDeviceManager* audioDevices;
    WCUserDefaults* userDefaults;

    BOOL enabled;
    BOOL observingRunningApplications;

    // Bundle ID -> the volume (kAppRelativeVolumeMinRawValue...kAppRelativeVolumeMaxRawValue) to
    // restore that app to. Only contains apps this instance has actually muted -- an app that was
    // never running while enabled, or that's the priority app, never gets an entry.
    NSMutableDictionary<NSString*, NSNumber*>* mutedApps;
}

- (instancetype) initWithAudioDevices:(WCAudioDeviceManager*)inAudioDevices
                          userDefaults:(WCUserDefaults*)inUserDefaults {
    if ((self = [super init])) {
        audioDevices = inAudioDevices;
        userDefaults = inUserDefaults;
        enabled = NO;
        observingRunningApplications = NO;

        // Restore the persisted mute map (if any) BEFORE deciding whether to resume, not after --
        // if Do Not Disturb was left on and an app was already muted, applyForRunningApps: below
        // must see its real pre-mute volume already in mutedApps, or it'll capture the app's
        // *current* (already-muted) volume as if that were the original, permanently losing it.
        mutedApps = [userDefaults.doNotDisturbMutedAppVolumes mutableCopy];

        // Resume on launch if it was left on -- matches WCHotkeys's own resume-on-launch
        // behavior. Unlike hotkeys, this needs no extra permission, so there's no gate here.
        if (userDefaults.doNotDisturbEnabled) {
            [self setEnabled:YES];
        }
    }

    return self;
}

- (void) dealloc {
    [self stopObservingRunningApplications];
}

#pragma mark Enabling / Disabling

- (BOOL) isEnabled {
    return enabled;
}

- (void) setEnabled:(BOOL)shouldBeEnabled {
    if (enabled == shouldBeEnabled) {
        return;
    }

    enabled = shouldBeEnabled;
    userDefaults.doNotDisturbEnabled = shouldBeEnabled;

    if (enabled) {
        [self startObservingRunningApplications];
        [self applyForRunningApps:[NSWorkspace sharedWorkspace].runningApplications];
    } else {
        [self stopObservingRunningApplications];
        [self restoreAllMutedApps];
    }
}

#pragma mark Priority App

- (NSString* __nullable) priorityAppBundleID {
    return userDefaults.doNotDisturbPriorityAppBundleID;
}

- (void) setPriorityAppBundleID:(NSString* __nullable)bundleID {
    userDefaults.doNotDisturbPriorityAppBundleID = bundleID;

    if (enabled) {
        // Re-running the same pass that responds to app launches also correctly handles a
        // priority-app change: the previous priority app (not in mutedApps yet, since it was
        // exempted) falls into the "mute it" branch below, and the new one (probably already in
        // mutedApps from before it became the priority app) falls into the "restore it" branch.
        [self applyForRunningApps:[NSWorkspace sharedWorkspace].runningApplications];
    }
}

#pragma mark Applying Mute/Restore

// Same "which running processes actually count as an app" definition
// WCAppVolumesController::shouldBeIncludedInMenu: uses -- so Do Not Disturb never tries to mute a
// background daemon that doesn't even get its own row in the volume list, and "every app" in this
// class's behavior means the same thing it means everywhere else in the UI.
- (BOOL) shouldConsiderApp:(NSRunningApplication*)app {
    BOOL isRegularOrAccessory = (app.activationPolicy == NSApplicationActivationPolicyRegular) ||
                                 (app.activationPolicy == NSApplicationActivationPolicyAccessory);
    NSString* __nullable bundleID = app.bundleIdentifier;
    BOOL isWavecraftItself = bundleID && [BGMNN(bundleID) isEqualToString:@kBGMAppBundleID];

    return isRegularOrAccessory && bundleID && !isWavecraftItself;
}

- (void) applyForRunningApps:(NSArray<NSRunningApplication*>*)apps {
    NSMutableSet<NSString*>* runningBundleIDs = [NSMutableSet new];

    for (NSRunningApplication* app in apps) {
        if ([self shouldConsiderApp:app]) {
            [runningBundleIDs addObject:BGMNN(app.bundleIdentifier)];
        }
    }

    // Drop any app that quit while muted -- if it relaunches, it gets treated as a fresh app
    // below (a fresh volume snapshot, muted again), rather than silently skipped because a stale
    // bundle ID was still sitting in the map from its previous run.
    for (NSString* bundleID in [mutedApps.allKeys copy]) {
        if (![runningBundleIDs containsObject:bundleID]) {
            [mutedApps removeObjectForKey:bundleID];
        }
    }

    NSString* __nullable priorityBundleID = userDefaults.doNotDisturbPriorityAppBundleID;

    for (NSRunningApplication* app in apps) {
        if (![self shouldConsiderApp:app]) {
            continue;
        }

        NSString* bundleID = BGMNN(app.bundleIdentifier);

        BOOL isPriorityApp = priorityBundleID && [bundleID isEqualToString:BGMNN(priorityBundleID)];

        if (isPriorityApp) {
            [self restoreAppIfMuted:bundleID];
        } else if (!mutedApps[bundleID]) {
            [self muteApp:app];
        }
    }

    [self persistMutedApps];
}

- (void) muteApp:(NSRunningApplication*)app {
    NSString* bundleID = BGMNN(app.bundleIdentifier);

    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        SInt32 currentVolume = [self currentVolumeForBundleID:bundleID];
        mutedApps[bundleID] = @(currentVolume);

        audioDevices.bgmDevice.SetAppVolume(kAppRelativeVolumeMinRawValue,
                                             app.processIdentifier,
                                             (__bridge CFStringRef)bundleID);
    });
}

- (void) restoreAppIfMuted:(NSString*)bundleID {
    NSNumber* __nullable savedVolume = mutedApps[bundleID];

    if (!savedVolume) {
        return;
    }

    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        // PID omitted (-1) -- the app may have relaunched with a different PID since it was
        // muted, but SetAppVolume matches by bundle ID too, and BGMDevice's per-client volume
        // storage is keyed primarily by bundle ID for exactly this reason.
        audioDevices.bgmDevice.SetAppVolume(savedVolume.intValue, -1, (__bridge CFStringRef)bundleID);
    });

    [mutedApps removeObjectForKey:bundleID];
}

- (void) restoreAllMutedApps {
    // Snapshot first -- restoreAppIfMuted: mutates mutedApps, which would corrupt an in-progress
    // fast-enumeration over the same dictionary.
    NSArray<NSString*>* bundleIDs = mutedApps.allKeys;

    for (NSString* bundleID in bundleIDs) {
        [self restoreAppIfMuted:bundleID];
    }

    [self persistMutedApps];
}

- (void) persistMutedApps {
    userDefaults.doNotDisturbMutedAppVolumes = [mutedApps copy];
}

- (BOOL) isMutingBundleID:(NSString*)bundleID {
    return mutedApps[bundleID] != nil;
}

// Same fallback default (unity gain, the midpoint of the raw volume range) WCHotkeys and
// WCTroubleshootMenu use for an app with no recorded volume yet.
- (SInt32) currentVolumeForBundleID:(NSString*)bundleID {
    const SInt32 kDefaultVolume = (kAppRelativeVolumeMinRawValue + kAppRelativeVolumeMaxRawValue) / 2;

    CACFArray volumes(audioDevices.bgmDevice.GetAppVolumes(), false);
    UInt32 count = volumes.GetNumberItems();

    for (UInt32 i = 0; i < count; i++) {
        CACFDictionary entry(false);
        volumes.GetCACFDictionary(i, entry);

        CACFString entryBundleID;
        entryBundleID.DontAllowRelease();
        entry.GetCACFString(CFSTR(kBGMAppVolumesKey_BundleID), entryBundleID);

        if (entryBundleID.IsValid() &&
            [bundleID isEqualToString:(__bridge NSString*)entryBundleID.GetCFString()]) {
            SInt32 volume = kDefaultVolume;
            entry.GetSInt32(CFSTR(kBGMAppVolumesKey_RelativeVolume), volume);
            return volume;
        }
    }

    return kDefaultVolume;
}

#pragma mark Watching for New Apps

- (void) startObservingRunningApplications {
    if (observingRunningApplications) {
        return;
    }

    [[NSWorkspace sharedWorkspace] addObserver:self
                                     forKeyPath:@"runningApplications"
                                        options:0
                                        context:kRunningApplicationsContext];
    observingRunningApplications = YES;
}

- (void) stopObservingRunningApplications {
    if (!observingRunningApplications) {
        return;
    }

    [[NSWorkspace sharedWorkspace] removeObserver:self
                                        forKeyPath:@"runningApplications"
                                           context:kRunningApplicationsContext];
    observingRunningApplications = NO;
}

- (void) observeValueForKeyPath:(NSString* __nullable)keyPath
                        ofObject:(id __nullable)object
                          change:(NSDictionary* __nullable)change
                         context:(void* __nullable)context {
    if (context == kRunningApplicationsContext) {
        // A newly-launched app needs muting immediately, not whenever the next unrelated event
        // happens to run applyForRunningApps: again -- otherwise a few seconds of an unmuted app
        // is exactly the interruption Do Not Disturb exists to prevent.
        if (enabled) {
            [self applyForRunningApps:[NSWorkspace sharedWorkspace].runningApplications];
        }
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end

NS_ASSUME_NONNULL_END
