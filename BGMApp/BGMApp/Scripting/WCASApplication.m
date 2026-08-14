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
//  WCASApplication.m
//  BGMApp
//
//  Copyright © 2021 Marcus Wu
//  Copyright © 2021 Kyle Neideck
//

// Self Include
#import "WCASApplication.h"

// Local Includes
#import "BGM_Types.h"
#import "BGM_Utils.h"

@implementation WCASApplication {
    NSScriptObjectSpecifier* parentSpecifier;
    NSRunningApplication *application;
    WCAppVolumesController* appVolumesController;
    WCAppOutputRoutingController* outputRoutingController;
    WCAudioDeviceManager* audioDevices;
    int index;
}

- (instancetype) initWithApplication:(NSRunningApplication*)app
                          volumeController:(WCAppVolumesController*)volumeController
                  outputRoutingController:(WCAppOutputRoutingController*)routingController
                              audioDevices:(WCAudioDeviceManager*)devices
                     parentSpecifier:(NSScriptObjectSpecifier* __nullable)parent
                               index:(int)i {
    if ((self = [super init])) {
        parentSpecifier = parent;
        application = app;
        appVolumesController = volumeController;
        outputRoutingController = routingController;
        audioDevices = devices;
        index = i;
    }

    return self;
}

- (NSString*) name {
    return [NSString stringWithFormat:@"%@", [application localizedName]];
}

- (NSString*) bundleID {
    return [NSString stringWithFormat:@"%@", [application bundleIdentifier]];
}

- (int) volume {
    return [appVolumesController getVolumeAndPanForApp:application].volume;
}

- (void) setVolume:(int)vol {
    BGMAppVolumeAndPan volume = {
        .volume = vol,
        .pan = kAppPanNoValue
    };
    [appVolumesController setVolumeAndPan:volume forApp:application];
}

- (int) pan {
    return [appVolumesController getVolumeAndPanForApp:application].pan;
}

- (void) setPan:(int)pan {
    BGMAppVolumeAndPan thePan = {
        .volume = -1,
        .pan = pan
    };
    [appVolumesController setVolumeAndPan:thePan forApp:application];
}

- (NSArray<NSNumber*>* __nullable) eqBandGains {
    return [appVolumesController getEQBandGainsForApp:application];
}

- (void) setEqBandGains:(NSArray<NSNumber*>*)eqBandGains {
    [appVolumesController setEQBandGains:eqBandGains
                      forAppWithProcessID:application.processIdentifier
                                 bundleID:application.bundleIdentifier];
}

- (NSArray<WCASOutputDevice*>*) outputDevices {
    NSString* __nullable bundleID = application.bundleIdentifier;
    NSArray<NSString*>* uids =
        bundleID ?
            [outputRoutingController outputOverrideDeviceUIDsForBundleID:BGMNN(bundleID)] : @[];

    NSMutableArray<WCASOutputDevice*>* devices = [NSMutableArray arrayWithCapacity:uids.count];

    for (NSString* uid in uids) {
        AudioObjectID deviceID = [outputRoutingController findConnectedDeviceIDForUID:uid];

        if (deviceID == kAudioObjectUnknown) {
            // The route's target device isn't currently connected -- same "not there right now"
            // meaning as never having been in the override list, from a script's point of view.
            continue;
        }

        [devices addObject:[[WCASOutputDevice alloc] initWithAudioObjectID:deviceID
                                                                 audioDevices:audioDevices
                                                              parentSpecifier:parentSpecifier]];
    }

    return devices;
}

- (void) setOutputDevices:(NSArray<WCASOutputDevice*>*)outputDevices {
    NSString* __nullable bundleID = application.bundleIdentifier;

    if (!bundleID) {
        return;
    }

    NSMutableArray<NSString*>* uids = [NSMutableArray arrayWithCapacity:outputDevices.count];

    for (WCASOutputDevice* device in outputDevices) {
        if (device.uid) {
            [uids addObject:BGMNN(device.uid)];
        }
    }

    [outputRoutingController setOutputOverrideDeviceUIDs:uids
                                       forAppWithBundleID:BGMNN(bundleID)
                                                  appName:application.localizedName];
}

- (NSScriptObjectSpecifier* __nullable) objectSpecifier {
    NSScriptClassDescription* parentClassDescription = [parentSpecifier keyClassDescription];
    return [[NSNameSpecifier alloc] initWithContainerClassDescription:parentClassDescription
                                                   containerSpecifier:parentSpecifier
                                                                  key:@"applications"
                                                                 name:self.name];
}

@end
