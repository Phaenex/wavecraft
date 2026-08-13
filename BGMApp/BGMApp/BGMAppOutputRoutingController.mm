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
#import "BGMTapRoute.h"

// PublicUtility Includes
#import "CAAutoDisposer.h"
#import "CAException.h"
#import "CAHALAudioSystemObject.h"
#import "CAPropertyAddress.h"

// STL Includes
#import <map>
#import <memory>
#import <string>


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

// Tears down (but doesn't un-persist) any route whose target device is no longer connected. The
// persisted assignment in userDefaults survives, so it's reapplied automatically if the device
// reconnects later -- the same restoration path restoreRoutesForApps: already uses for apps that
// weren't running yet, applied here to a device that wasn't connected yet instead.
- (void) removeRoutesForDisconnectedDevices {
    // outputRouteDeviceUIDsByBundleID is documented main-thread-only (see its call sites elsewhere
    // in this class); the property listener block runs on a background queue, so hop to the main
    // thread before reading it.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary<NSString*, NSString*>* assignments = self->userDefaults.outputRouteDeviceUIDsByBundleID;

        for (NSString* bundleID in assignments) {
            NSString* deviceUID = assignments[bundleID];

            if ([self findConnectedDeviceIDForUID:deviceUID] == kAudioObjectUnknown) {
                DebugMsg("BGMAppOutputRoutingController::removeRoutesForDisconnectedDevices: "
                         "Device %s for %s is no longer connected -- clearing its route",
                         deviceUID.UTF8String,
                         bundleID.UTF8String);
                [self applyRouteAsyncForBundleID:bundleID deviceUID:nil appName:nil];
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

    NSString* __nullable currentUID = userDefaults.outputRouteDeviceUIDsByBundleID[bundleID];

    NSMenuItem* defaultItem = [[NSMenuItem alloc] initWithTitle:@"Default"
                                                          action:nil
                                                   keyEquivalent:@""];
    defaultItem.state = currentUID ? NSOffState : NSOnState;
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
        item.state =
            (currentUID && [uid isEqualToString:BGMNN(currentUID)]) ? NSOnState : NSOffState;
        [menu addItem:item];
    }
}

#pragma mark Selecting a Device

- (void) userSelectedDeviceUID:(NSString* __nullable)deviceUID
             forAppWithBundleID:(NSString*)bundleID
                        appName:(NSString* __nullable)appName {
    NSAssert([NSThread isMainThread],
             @"userSelectedDeviceUID:forAppWithBundleID:appName: is not thread safe");

    // Update the persisted assignment immediately, so the UI (checkmarks, hasOutputOverride...)
    // reflects the user's choice right away, even though actually starting/stopping the route
    // happens asynchronously below.
    NSMutableDictionary<NSString*, NSString*>* assignments =
        [userDefaults.outputRouteDeviceUIDsByBundleID mutableCopy];

    if (deviceUID) {
        assignments[bundleID] = deviceUID;
    } else {
        [assignments removeObjectForKey:bundleID];
    }

    userDefaults.outputRouteDeviceUIDsByBundleID = assignments;

    [self applyRouteAsyncForBundleID:bundleID deviceUID:deviceUID appName:appName];
}

- (BOOL) hasOutputOverrideForBundleID:(NSString*)bundleID {
    return userDefaults.outputRouteDeviceUIDsByBundleID[bundleID] != nil;
}

- (NSString* __nullable) outputOverrideDeviceUIDForBundleID:(NSString*)bundleID {
    return userDefaults.outputRouteDeviceUIDsByBundleID[bundleID];
}

- (void) removeAllOutputOverrides {
    NSAssert([NSThread isMainThread], @"removeAllOutputOverrides is not thread safe");

    // Snapshot the keys first -- userSelectedDeviceUID:forAppWithBundleID:appName: below replaces
    // userDefaults.outputRouteDeviceUIDsByBundleID with a new dictionary each call, so iterating a
    // separately-captured array here is safe against mutating the thing we're iterating.
    NSArray<NSString*>* bundleIDs = userDefaults.outputRouteDeviceUIDsByBundleID.allKeys;

    for (NSString* bundleID in bundleIDs) {
        [self userSelectedDeviceUID:nil forAppWithBundleID:bundleID appName:nil];
    }
}

#pragma mark Restoring Persisted Routes

- (void) restoreRoutesForApps:(NSArray<NSRunningApplication*>*)apps {
    NSDictionary<NSString*, NSString*>* assignments = userDefaults.outputRouteDeviceUIDsByBundleID;

    if (assignments.count == 0) {
        return;
    }

    for (NSRunningApplication* app in apps) {
        NSString* __nullable bundleID = app.bundleIdentifier;
        NSString* __nullable uid = bundleID ? assignments[BGMNN(bundleID)] : nil;

        if (bundleID && uid) {
            DebugMsg("BGMAppOutputRoutingController::restoreRoutesForApps: "
                     "Restoring route for %s -> %s",
                     bundleID.UTF8String,
                     uid.UTF8String);
            [self applyRouteAsyncForBundleID:BGMNN(bundleID)
                                    deviceUID:uid
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
                          deviceUID:(NSString* __nullable)deviceUID
                            appName:(NSString* __nullable)appName {
    BGMAppOutputRoutingController* __weak weakSelf = self;

    dispatch_async(routingQueue, ^{
        [weakSelf applyRouteForBundleID:bundleID deviceUID:deviceUID appName:appName];
    });
}

- (void) applyRouteForBundleID:(NSString*)bundleID
                      deviceUID:(NSString* __nullable)deviceUID
                        appName:(NSString* __nullable)appName {
    std::string key = BGM_Utils::NN(bundleID.UTF8String);

    // Stop and remove any existing route for this app first -- whether we're switching to a
    // different device or going back to Default, there's never more than one route per bundle ID.
    // BGMTapRoute::~BGMTapRoute calls Stop(), which unmutes the app and tears down the tap.
    routes.erase(key);

    if (!deviceUID) {
        return;
    }

    AudioObjectID deviceID = [self findConnectedDeviceIDForUID:BGMNN(deviceUID)];

    if (deviceID == kAudioObjectUnknown) {
        DebugMsg("BGMAppOutputRoutingController::applyRouteForBundleID: "
                 "Device %s isn't connected",
                 deviceUID.UTF8String);
        [self showRoutingErrorForAppName:appName reason:@"That output device isn't connected."];
        return;
    }

    try {
        // BGMTapRoute retains this for its lifetime (see its header), so give it a CACFString
        // that actually owns a CFRetain -- the bridge cast below transfers the one this method's
        // ARC-owned bundleID would otherwise have kept.
        CACFString ownedBundleID((__bridge_retained CFStringRef)bundleID);
        auto route =
            std::unique_ptr<BGMTapRoute>(new BGMTapRoute(ownedBundleID, BGMAudioDevice(deviceID)));
        route->Start();
        routes[key] = std::move(route);
    } catch (const CAException& e) {
        LogError("BGMAppOutputRoutingController::applyRouteForBundleID: CAException %d",
                 static_cast<int>(e.GetError()));

        // BGMTapRoute::Start() distinguishes these two specific causes from a generic CoreAudio
        // failure -- see its header comment. Only the fallback case is actually about a raw
        // OSStatus; the other two have a real, specific explanation to show instead of a code.
        NSString* reason;
        if (e.GetError() == BGMTapRoute::kMacOSTooOld) {
            reason = @"Per-app output routing needs macOS 26 or later.";
        } else if (e.GetError() == BGMTapRoute::kOutputDeviceVanished) {
            reason = @"That output device disconnected before routing could start.";
        } else {
            reason = [NSString stringWithFormat:@"CoreAudio error %d.",
                                                  static_cast<int>(e.GetError())];
        }

        [self showRoutingErrorForAppName:appName reason:reason];
    } catch (...) {
        LogError("BGMAppOutputRoutingController::applyRouteForBundleID: Unknown exception");
        [self showRoutingErrorForAppName:appName reason:@"An unknown error occurred."];
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
