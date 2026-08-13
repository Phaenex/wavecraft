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
//  BGMAppOutputRoutingController.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "BGMAppOutputRoutingController.h"

// Local Includes
#import "BGM_Utils.h"
#import "BGMAudioDevice.h"
#import "BGMOutputDeviceDiff.h"
#import "BGMTapRoute.h"

// PublicUtility Includes
#import "CAAutoDisposer.h"
#import "CAException.h"
#import "CAHALAudioSystemObject.h"
#import "CAPropertyAddress.h"

// STL Includes
#import <algorithm>
#import <map>
#import <memory>
#import <string>
#import <vector>


#pragma clang assume_nonnull begin

@implementation BGMAppOutputRoutingController {
    BGMUserDefaults* userDefaults;

    // Only ever touched on routingQueue -- see applyRouteForBundleID:deviceUID:appName: and
    // dealloc, below. The source of truth for what's actually running;
    // userDefaults.outputRouteDeviceUIDsByBundleID (main-thread only) is the source of truth for
    // what the user asked for, which is what the UI reads so it updates immediately instead of
    // waiting on routingQueue.
    std::map<std::string, std::unique_ptr<BGMTapRoute>> routes;

    dispatch_queue_t routingQueue;

    // Notifies removeRoutesForDisconnectedDevices when any device connects/disconnects -- not
    // specific to routed devices, since kAudioHardwarePropertyDevices fires for any device, not
    // just ones this class cares about. See listenForDevicesAddedOrRemoved.
    AudioObjectPropertyListenerBlock deviceListListener;
}

- (instancetype) initWithUserDefaults:(BGMUserDefaults*)inUserDefaults {
    if ((self = [super init])) {
        userDefaults = inUserDefaults;
        routingQueue = dispatch_queue_create("BGMAppOutputRoutingController", DISPATCH_QUEUE_SERIAL);

        [self restoreRoutesForApps:[NSWorkspace sharedWorkspace].runningApplications];

        // Watch for apps launching later in the session so a persisted assignment for an app that
        // wasn't running yet at startup still gets applied once it appears.
        [[NSWorkspace sharedWorkspace] addObserver:self
                                        forKeyPath:@"runningApplications"
                                           options:NSKeyValueObservingOptionNew
                                           context:nil];

        // Watch for a routed device disconnecting mid-route -- without this, BGMTapRoute's own
        // IsAlive()/ObjectExists() checks are purely reactive (only consulted the next time
        // something else calls Start()/Stop()/Activate()), so a route to a device that's already
        // unplugged would otherwise just keep reporting IsRunning() == true indefinitely. See
        // docs/PROCESS-TAP-ROUTING.md and TODO.md's note on this gap.
        [self listenForDevicesAddedOrRemoved];
    }

    return self;
}

- (void) dealloc {
    [[NSWorkspace sharedWorkspace] removeObserver:self
                                       forKeyPath:@"runningApplications"
                                          context:nil];

    CAHALAudioSystemObject().RemovePropertyListenerBlock(
        CAPropertyAddress(kAudioHardwarePropertyDevices),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
        deviceListListener);

    // routes is "only ever touched on routingQueue" (see its declaration above), but ARC would
    // otherwise destruct it here on whatever thread drops this object's last reference, which
    // isn't guaranteed to be routingQueue. dispatch_sync so routes.clear() -- which runs each
    // BGMTapRoute's real destructor, tearing down its CoreAudio tap/aggregate device -- happens on
    // the right queue before this object (and its ivars) finish being destroyed.
    dispatch_sync(routingQueue, ^{
        routes.clear();
    });
}

#pragma mark Handling Disconnected Devices

- (void) listenForDevicesAddedOrRemoved {
    BGMAppOutputRoutingController* __weak weakSelf = self;

    deviceListListener = ^(UInt32 inNumberAddresses, const AudioObjectPropertyAddress* inAddresses) {
        #pragma unused (inNumberAddresses, inAddresses)

        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            [weakSelf removeRoutesForDisconnectedDevices];
        });
    };

    CAHALAudioSystemObject().AddPropertyListenerBlock(
        CAPropertyAddress(kAudioHardwarePropertyDevices),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
        deviceListListener);
}

// Drops (but doesn't un-persist) just the disconnected device from any app's target set that
// includes it, leaving any other still-connected targets for that app untouched. The persisted
// assignment in userDefaults survives, so it's reapplied automatically if the device reconnects
// later -- the same restoration path restoreRoutesForApps: already uses for apps that weren't
// running yet, applied here to a device that wasn't connected yet instead.
- (void) removeRoutesForDisconnectedDevices {
    // outputRouteDeviceUIDsByBundleID is documented main-thread-only (see its call sites elsewhere
    // in this class); the property listener block runs on a background queue, so hop to the main
    // thread before reading it.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary<NSString*, NSArray<NSString*>*>* assignments =
            self->userDefaults.outputRouteDeviceUIDsByBundleID;

        for (NSString* bundleID in assignments) {
            NSArray<NSString*>* deviceUIDs = assignments[bundleID];
            NSMutableArray<NSString*>* stillConnected = [deviceUIDs mutableCopy];
            BOOL anyRemoved = NO;

            for (NSString* deviceUID in deviceUIDs) {
                if ([self findConnectedDeviceIDForUID:deviceUID] == kAudioObjectUnknown) {
                    DebugMsg("BGMAppOutputRoutingController::removeRoutesForDisconnectedDevices: "
                             "Device %s for %s is no longer connected -- dropping it from the "
                             "route, leaving %lu other target(s) untouched",
                             deviceUID.UTF8String,
                             bundleID.UTF8String,
                             (unsigned long)(deviceUIDs.count - 1));
                    [stillConnected removeObject:deviceUID];
                    anyRemoved = YES;
                }
            }

            if (anyRemoved) {
                [self setOutputOverrideDeviceUIDs:stillConnected
                                forAppWithBundleID:bundleID
                                           appName:nil];
            }
        }
    });
}

#pragma mark Menu

- (void) populateMenuForButton:(NSPopUpButton*)popUpButton forBundleID:(NSString*)bundleID {
    NSAssert([NSThread isMainThread],
             @"populateMenuForButton:forBundleID: is not thread safe");

    NSMenu* menu = popUpButton.menu;
    [menu removeAllItems];

    NSArray<NSString*>* currentUIDs = userDefaults.outputRouteDeviceUIDsByBundleID[bundleID] ?: @[];

    NSMenuItem* defaultItem = [[NSMenuItem alloc] initWithTitle:@"Default"
                                                          action:nil
                                                   keyEquivalent:@""];
    defaultItem.state = (currentUIDs.count == 0) ? NSOnState : NSOffState;
    [menu addItem:defaultItem];

    CAHALAudioSystemObject audioSystem;
    UInt32 numDevices = audioSystem.GetNumberAudioDevices();

    if (numDevices == 0) {
        return;
    }

    CAAutoArrayDelete<AudioObjectID> devices(numDevices);
    audioSystem.GetAudioDevices(numDevices, devices);

    for (UInt32 i = 0; i < numDevices; i++) {
        BGMAudioDevice device(devices[i]);
        BOOL canBeOutputDevice = NO;

        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            canBeOutputDevice = device.CanBeOutputDeviceInBGMApp();
        });

        if (!canBeOutputDevice) {
            continue;
        }

        NSString* __nullable name = nil;
        NSString* __nullable uid = nil;

        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            name = (__bridge_transfer NSString* __nullable)device.CopyName();
            uid = (__bridge_transfer NSString* __nullable)device.CopyDeviceUID();
        });

        if (!name || !uid) {
            continue;
        }

        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:BGMNN(name)
                                                        action:nil
                                                 keyEquivalent:@""];
        item.representedObject = uid;
        item.state = [currentUIDs containsObject:BGMNN(uid)] ? NSOnState : NSOffState;
        [menu addItem:item];
    }
}

#pragma mark Selecting a Device

- (void) userToggledDeviceUID:(NSString*)deviceUID
             forAppWithBundleID:(NSString*)bundleID
                        appName:(NSString* __nullable)appName {
    NSAssert([NSThread isMainThread], @"userToggledDeviceUID:forAppWithBundleID:appName: is not thread safe");

    NSMutableArray<NSString*>* uids =
        [(userDefaults.outputRouteDeviceUIDsByBundleID[bundleID] ?: @[]) mutableCopy];

    if ([uids containsObject:deviceUID]) {
        [uids removeObject:deviceUID];
    } else {
        [uids addObject:deviceUID];
    }

    [self setOutputOverrideDeviceUIDs:uids forAppWithBundleID:bundleID appName:appName];
}

- (void) userSelectedDefaultForAppWithBundleID:(NSString*)bundleID
                                        appName:(NSString* __nullable)appName {
    NSAssert([NSThread isMainThread],
             @"userSelectedDefaultForAppWithBundleID:appName: is not thread safe");

    [self setOutputOverrideDeviceUIDs:@[] forAppWithBundleID:bundleID appName:appName];
}

- (void) setOutputOverrideDeviceUIDs:(NSArray<NSString*>*)deviceUIDs
                    forAppWithBundleID:(NSString*)bundleID
                               appName:(NSString* __nullable)appName {
    NSAssert([NSThread isMainThread],
             @"setOutputOverrideDeviceUIDs:forAppWithBundleID:appName: is not thread safe");

    // Update the persisted assignment immediately, so the UI (checkmarks, hasOutputOverride...)
    // reflects the user's choice right away, even though actually starting/stopping the route
    // happens asynchronously below.
    NSMutableDictionary<NSString*, NSArray<NSString*>*>* assignments =
        [userDefaults.outputRouteDeviceUIDsByBundleID mutableCopy];

    if (deviceUIDs.count > 0) {
        assignments[bundleID] = deviceUIDs;
    } else {
        [assignments removeObjectForKey:bundleID];
    }

    userDefaults.outputRouteDeviceUIDsByBundleID = assignments;

    [self applyRouteAsyncForBundleID:bundleID deviceUIDs:deviceUIDs appName:appName];
}

- (BOOL) hasOutputOverrideForBundleID:(NSString*)bundleID {
    return userDefaults.outputRouteDeviceUIDsByBundleID[bundleID].count > 0;
}

- (NSArray<NSString*>*) outputOverrideDeviceUIDsForBundleID:(NSString*)bundleID {
    return userDefaults.outputRouteDeviceUIDsByBundleID[bundleID] ?: @[];
}

- (void) removeAllOutputOverrides {
    NSAssert([NSThread isMainThread], @"removeAllOutputOverrides is not thread safe");

    // Snapshot the keys first -- setOutputOverrideDeviceUIDs:forAppWithBundleID:appName: below
    // replaces userDefaults.outputRouteDeviceUIDsByBundleID with a new dictionary each call, so
    // iterating a separately-captured array here is safe against mutating the thing we're
    // iterating.
    NSArray<NSString*>* bundleIDs = userDefaults.outputRouteDeviceUIDsByBundleID.allKeys;

    for (NSString* bundleID in bundleIDs) {
        [self setOutputOverrideDeviceUIDs:@[] forAppWithBundleID:bundleID appName:nil];
    }
}

#pragma mark Restoring Persisted Routes

- (void) restoreRoutesForApps:(NSArray<NSRunningApplication*>*)apps {
    NSDictionary<NSString*, NSArray<NSString*>*>* assignments =
        userDefaults.outputRouteDeviceUIDsByBundleID;

    if (assignments.count == 0) {
        return;
    }

    for (NSRunningApplication* app in apps) {
        NSString* __nullable bundleID = app.bundleIdentifier;
        NSArray<NSString*>* __nullable uids = bundleID ? assignments[BGMNN(bundleID)] : nil;

        if (bundleID && uids.count > 0) {
            DebugMsg("BGMAppOutputRoutingController::restoreRoutesForApps: "
                     "Restoring route for %s -> %s",
                     bundleID.UTF8String,
                     uids.description.UTF8String);
            [self applyRouteAsyncForBundleID:BGMNN(bundleID)
                                    deviceUIDs:BGMNN(uids)
                                      appName:app.localizedName];
        }
    }
}

#pragma mark KVO

- (void) observeValueForKeyPath:(NSString* __nullable)keyPath
                       ofObject:(id __nullable)object
                         change:(NSDictionary* __nullable)change
                        context:(void* __nullable)context {
    #pragma unused (object, context)

    if (keyPath && change && [keyPath isEqualToString:@"runningApplications"]) {
        NSArray<NSRunningApplication*>* __nullable newApps = change[NSKeyValueChangeNewKey];
        int changeKind = [change[NSKeyValueChangeKindKey] intValue];

        // Only newly-appeared apps can have a persisted-but-not-yet-applied assignment. Apps
        // quitting is deliberately ignored here -- see this class's header comment and
        // BGMTapRoute's processRestoreEnabled: a route is meant to keep waiting for its app to
        // come back, not stop when it quits.
        if (newApps &&
            (changeKind == NSKeyValueChangeInsertion ||
             changeKind == NSKeyValueChangeReplacement ||
             changeKind == NSKeyValueChangeSetting)) {
            [self restoreRoutesForApps:BGMNN(newApps)];
        }
    }
}

#pragma mark Routing (routingQueue only)

- (void) applyRouteAsyncForBundleID:(NSString*)bundleID
                          deviceUIDs:(NSArray<NSString*>*)deviceUIDs
                            appName:(NSString* __nullable)appName {
    BGMAppOutputRoutingController* __weak weakSelf = self;

    dispatch_async(routingQueue, ^{
        [weakSelf applyRouteForBundleID:bundleID deviceUIDs:deviceUIDs appName:appName];
    });
}

- (void) applyRouteForBundleID:(NSString*)bundleID
                     deviceUIDs:(NSArray<NSString*>*)deviceUIDs
                        appName:(NSString* __nullable)appName {
    std::string key = BGM_Utils::NN(bundleID.UTF8String);

    if (deviceUIDs.count == 0) {
        // Back to Default -- tear down the whole route. BGMTapRoute::~BGMTapRoute calls Stop(),
        // which unmutes the app and destroys the tap.
        routes.erase(key);
        return;
    }

    // Resolve every requested UID to a connected device up front. One that isn't connected gets
    // its own error and is skipped, rather than blocking every other requested device in the same
    // set from being routed.
    std::vector<AudioObjectID> desiredDeviceIDs;

    for (NSString* uid in deviceUIDs) {
        AudioObjectID deviceID = [self findConnectedDeviceIDForUID:uid];

        if (deviceID == kAudioObjectUnknown) {
            DebugMsg("BGMAppOutputRoutingController::applyRouteForBundleID: "
                     "Device %s isn't connected",
                     uid.UTF8String);
            [self showRoutingErrorForAppName:appName
                                       reason:[NSString stringWithFormat:
                                                   @"“%@” isn't connected.", uid]];
        } else {
            desiredDeviceIDs.push_back(deviceID);
        }
    }

    if (desiredDeviceIDs.empty()) {
        // Every requested device failed to resolve -- nothing left to route to.
        routes.erase(key);
        [self reconcilePersistedAssignmentForBundleID:bundleID key:key];
        return;
    }

    auto it = routes.find(key);
    BGMTapRoute* __nullable route = nullptr;

    if (it == routes.end()) {
        // No existing route for this app -- create the tap fresh, with no outputs yet.
        try {
            // BGMTapRoute retains this for its lifetime (see its header), so give it a CACFString
            // that actually owns a CFRetain -- the bridge cast below transfers the one this
            // method's ARC-owned bundleID would otherwise have kept.
            CACFString ownedBundleID((__bridge_retained CFStringRef)bundleID);
            auto newRoute = std::unique_ptr<BGMTapRoute>(new BGMTapRoute(ownedBundleID));
            newRoute->Start();
            route = newRoute.get();
            routes[key] = std::move(newRoute);
        } catch (const CAException& e) {
            [self showRoutingErrorForAppName:appName reason:[self reasonForTapRouteException:e]];
            [self reconcilePersistedAssignmentForBundleID:bundleID key:key];
            return;
        } catch (...) {
            LogError("BGMAppOutputRoutingController::applyRouteForBundleID: "
                     "Unknown exception starting tap for %s",
                     bundleID.UTF8String);
            [self showRoutingErrorForAppName:appName reason:@"An unknown error occurred."];
            [self reconcilePersistedAssignmentForBundleID:bundleID key:key];
            return;
        }
    } else {
        route = it->second.get();
    }

    // Reconcile this route's actual output devices with the desired set -- remove ones no longer
    // wanted, add ones that are new. BGMComputeOutputDeviceDiff (pure decision logic, unit tested
    // in BGMOutputDeviceDiffTests.mm) deliberately leaves an output alone if it's already correct,
    // so e.g. switching the target set from {A, B} to {A, C} doesn't glitch A's audio by tearing
    // its BGMPlayThrough down and immediately back up for no reason.
    std::vector<AudioObjectID> currentDeviceIDs;
    for (const BGMAudioDevice& current : route->GetOutputDevices()) {
        currentDeviceIDs.push_back(current.GetObjectID());
    }

    BGMOutputDeviceDiff diff = BGMComputeOutputDeviceDiff(currentDeviceIDs, desiredDeviceIDs);

    for (AudioObjectID deviceID : diff.toRemove) {
        route->RemoveOutputDevice(BGMAudioDevice(deviceID));
    }

    for (AudioObjectID deviceID : diff.toAdd) {
        try {
            route->AddOutputDevice(BGMAudioDevice(deviceID));
        } catch (const CAException& e) {
            [self showRoutingErrorForAppName:appName reason:[self reasonForTapRouteException:e]];
        } catch (...) {
            LogError("BGMAppOutputRoutingController::applyRouteForBundleID: "
                     "Unknown exception adding an output device for %s",
                     bundleID.UTF8String);
            [self showRoutingErrorForAppName:appName reason:@"An unknown error occurred."];
        }
    }

    // If every output ended up failing to add (e.g. every requested device vanished between
    // resolving its UID above and actually adding it), the route would otherwise be left running
    // with zero outputs -- harmless (still tapping/muting the app for nothing) but pointless.
    if (route->GetOutputDevices().empty()) {
        routes.erase(key);
    }

    [self reconcilePersistedAssignmentForBundleID:bundleID key:key];
}

// Writes the route's actual, real device set back to userDefaults.outputRouteDeviceUIDsByBundleID
// -- the request written there when the user made their selection (see
// setOutputOverrideDeviceUIDs:forAppWithBundleID:appName:) is optimistic, and any failure above
// (a device that disconnected, a CoreAudio error) can leave it disagreeing with what's actually
// routed. Without this, the per-app pop-up would keep showing a device checked as routed even
// though its BGMTapRoute output never actually started, with no way to notice short of "Remove
// All Output Routing Overrides" -- which also clears every other app's legitimate routes.
- (void) reconcilePersistedAssignmentForBundleID:(NSString*)bundleID key:(const std::string&)key {
    NSMutableArray<NSString*>* actualDeviceUIDs = [NSMutableArray new];

    auto it = routes.find(key);
    if (it != routes.end()) {
        for (const BGMAudioDevice& device : it->second->GetOutputDevices()) {
            NSString* __nullable uid = nil;

            BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
                uid = (__bridge_transfer NSString* __nullable)device.CopyDeviceUID();
            });

            if (uid) {
                [actualDeviceUIDs addObject:BGMNN(uid)];
            }
        }
    }

    BGMAppOutputRoutingController* __weak weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        BGMAppOutputRoutingController* __strong strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        NSMutableDictionary<NSString*, NSArray<NSString*>*>* assignments =
            [strongSelf->userDefaults.outputRouteDeviceUIDsByBundleID mutableCopy];

        if (actualDeviceUIDs.count > 0) {
            assignments[bundleID] = actualDeviceUIDs;
        } else {
            [assignments removeObjectForKey:bundleID];
        }

        strongSelf->userDefaults.outputRouteDeviceUIDsByBundleID = assignments;
    });
}

// BGMTapRoute::Start()/AddOutputDevice() distinguish these two specific causes from a generic
// CoreAudio failure -- see BGMTapRoute.h. Only the fallback case is actually about a raw OSStatus;
// the other two have a real, specific explanation to show instead of a code.
- (NSString*) reasonForTapRouteException:(const CAException&)e {
    LogError("BGMAppOutputRoutingController: CAException %d", static_cast<int>(e.GetError()));

    if (e.GetError() == BGMTapRoute::kMacOSTooOld) {
        return @"Per-app output routing needs macOS 26 or later.";
    } else if (e.GetError() == BGMTapRoute::kOutputDeviceVanished) {
        return @"That output device disconnected before routing could start.";
    } else {
        return [NSString stringWithFormat:@"CoreAudio error %d.", static_cast<int>(e.GetError())];
    }
}

- (AudioObjectID) findConnectedDeviceIDForUID:(NSString*)uid {
    CAHALAudioSystemObject audioSystem;
    UInt32 numDevices = audioSystem.GetNumberAudioDevices();

    if (numDevices == 0) {
        return kAudioObjectUnknown;
    }

    CAAutoArrayDelete<AudioObjectID> devices(numDevices);
    audioSystem.GetAudioDevices(numDevices, devices);

    for (UInt32 i = 0; i < numDevices; i++) {
        NSString* __nullable deviceUID = nil;

        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            deviceUID = (__bridge_transfer NSString* __nullable)BGMAudioDevice(devices[i]).CopyDeviceUID();
        });

        if ([deviceUID isEqualToString:uid]) {
            return devices[i];
        }
    }

    return kAudioObjectUnknown;
}

- (void) showRoutingErrorForAppName:(NSString* __nullable)appName reason:(NSString*)reason {
    NSString* name = appName ? BGMNN(appName) : @"this app";

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [NSAlert new];
        alert.messageText = [NSString stringWithFormat:@"Failed to route %@'s audio.", name];
        alert.informativeText = reason;
        [alert runModal];
    });
}

@end

#pragma clang assume_nonnull end
