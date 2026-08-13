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
//  BGMOutputDeviceMenuSection.mm
//  BGMApp
//
//  Copyright © 2016-2018, 2026 Kyle Neideck
//

// Self Include
#import "BGMOutputDeviceMenuSection.h"

// Local Includes
#import "BGM_Utils.h"
#import "BGM_Types.h"
#import "BGMAudioDevice.h"
#import "BGMMainPanelContentView.h"

// PublicUtility Includes
#import "CAAutoDisposer.h"
#import "CAHALAudioDevice.h"
#import "CAHALAudioSystemObject.h"
#import "CAPropertyAddress.h"

// STL Includes
#import <set>
#import <vector>

// System Includes
#import <objc/runtime.h>


#pragma clang assume_nonnull begin

// Associated-object key used in place of NSMenuItem.representedObject -- see the comment on
// deviceInfoForButton:/setDeviceInfo:forButton: below.
static char kDeviceInfoAssociatedObjectKey;

@implementation BGMOutputDeviceMenuSection {
    NSStackView* deviceStack;
    BGMAudioDeviceManager* audioDevices;
    BGMPreferredOutputDevices* preferredDevices;
    NSMutableArray<NSButton*>* outputDeviceButtons;
    // Called when a CoreAudio property has changed and we might need to update the list. For
    // example, when a device is connected or disconnected.
    AudioObjectPropertyListenerBlock refreshNeededListener;
    // The devices we've added refreshNeededListener to. Used to avoid adding it to a device twice
    // for the same property and to remove it from all devices in dealloc.
    std::set<BGMAudioDevice> listenedDevices_kAudioDevicePropertyDataSources;
    std::set<BGMAudioDevice> listenedDevices_kAudioDevicePropertyDataSource;
}

- (instancetype) initWithDeviceStack:(NSStackView*)inDeviceStack
                         audioDevices:(BGMAudioDeviceManager*)inAudioDevices
                     preferredDevices:(BGMPreferredOutputDevices*)inPreferredDevices {
    if ((self = [super init])) {
        deviceStack = inDeviceStack;
        audioDevices = inAudioDevices;
        preferredDevices = inPreferredDevices;
        outputDeviceButtons = [NSMutableArray new];

        [self listenForDevicesAddedOrRemoved];
        [self populateDeviceList];
    }

    return self;
}

// NSButton has no equivalent of NSMenuItem.representedObject, so this pair of helpers attaches
// the same {deviceID, dataSourceID} dictionary to a button via the Objective-C runtime's
// associated-object API instead.
- (void) setDeviceInfo:(NSDictionary*)info forButton:(NSButton*)button {
    objc_setAssociatedObject(button, &kDeviceInfoAssociatedObjectKey, info,
                              OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary* __nullable) deviceInfoForButton:(NSButton*)button {
    return objc_getAssociatedObject(button, &kDeviceInfoAssociatedObjectKey);
}

- (void) dealloc {
    // Tell CoreAudio not to call the listener block anymore. This probably isn't necessary.
    //
    // I think it's safe to do this without dispatching to the main queue because dealloc and
    // refreshNeededListener should be essentially mutually exclusive. If refreshNeededListener is
    // invoked and gets a value for weakSelf, it holds the strong ref until it returns, so dealloc
    // won't be called. If refreshNeededListener is invoked and deallocation has started, it will
    // get nil for weakSelf and just return.
    auto removeListener = [&] (CAHALAudioObject audioObject, AudioObjectPropertySelector prop) {
        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            // Check the object still exists first to reduce unnecessary error logs.
            if (CAHALAudioObject::ObjectExists(audioObject.GetObjectID())) {
                audioObject.RemovePropertyListenerBlock(CAPropertyAddress(prop),
                                                        dispatch_get_main_queue(),
                                                        refreshNeededListener);
            }
        });
    };

    // Remove the listener from each audio object we added it to.
    removeListener(CAHALAudioSystemObject(), kAudioHardwarePropertyDevices);

    for (auto device : listenedDevices_kAudioDevicePropertyDataSources) {
        removeListener(device, kAudioDevicePropertyDataSources);
    }

    for (auto device : listenedDevices_kAudioDevicePropertyDataSource) {
        removeListener(device, kAudioDevicePropertyDataSource);
    }
}

- (void) listenForDevicesAddedOrRemoved {
    // Create the block that will run when a device is added or removed.
    BGMOutputDeviceMenuSection* __weak weakSelf = self;

    refreshNeededListener = ^(UInt32 inNumberAddresses,
                              const AudioObjectPropertyAddress* inAddresses) {
        #pragma unused (inNumberAddresses, inAddresses)

        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            [weakSelf populateDeviceList];
        });
    };

    // Register the listener block to be called when devices are connected or disconnected.
    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        CAHALAudioSystemObject().AddPropertyListenerBlock(
            CAPropertyAddress(kAudioHardwarePropertyDevices),
            dispatch_get_main_queue(),
            refreshNeededListener);
    });
}

- (void) populateDeviceList {
    // TODO: Technically, we should assert we're on the main queue rather than just the main thread.
    BGMAssert([NSThread isMainThread],
              "BGMOutputDeviceMenuSection::populateDeviceList called on non-main thread");

    // Remove existing buttons.
    for (NSButton* button in outputDeviceButtons) {
        DebugMsg("BGMOutputDeviceMenuSection::populateDeviceList: Removing %s",
                 button.description.UTF8String);
        // The button's container row (see BGMMainPanelContentView's rowContainerWithControl:
        // height:) is the actual arranged subview of deviceStack, not the button itself. Every
        // button still in outputDeviceButtons was added with a wrapping row and never had it
        // removed independently, so superview should always be set here.
        NSView* row = BGMNN(button.superview);
        [deviceStack removeArrangedSubview:row];
        [row removeFromSuperview];
    }

    [outputDeviceButtons removeAllObjects];

    // Add a button for each output device.
    CAHALAudioSystemObject audioSystem;
    UInt32 numDevices = audioSystem.GetNumberAudioDevices();

    if (numDevices > 0) {
        CAAutoArrayDelete<AudioObjectID> devices(numDevices);
        audioSystem.GetAudioDevices(numDevices, devices);

        for (UInt32 i = 0; i < numDevices; i++) {
            [self insertButtonsForDevice:devices[i]];
        }
    }
}

- (void) insertButtonsForDevice:(BGMAudioDevice)device {
    BOOL canBeOutputDevice = YES;
    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        canBeOutputDevice = device.CanBeOutputDeviceInBGMApp();
    });

    if (canBeOutputDevice) {
        for (NSButton* button : [self createButtonsForDevice:device]) {
            DebugMsg("BGMOutputDeviceMenuSection::insertButtonsForDevice: Inserting %s",
                     button.description.UTF8String);
            [outputDeviceButtons addObject:button];
        }

        // Add listeners to update the menu when the device's data source changes or it changes its
        // list of data sources. We do this so that, for example, when you plug headphones into the
        // built-in jack, the menu item for the built-in device will change from "Internal Speakers"
        // to "Headphones".
        if (listenedDevices_kAudioDevicePropertyDataSources.count(device) == 0) {
            BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
                device.AddPropertyListenerBlock(CAPropertyAddress(kAudioDevicePropertyDataSources,
                                                                  kAudioDevicePropertyScopeOutput),
                                                dispatch_get_main_queue(),
                                                refreshNeededListener);
                listenedDevices_kAudioDevicePropertyDataSources.insert(device);
            });
        };

        if (listenedDevices_kAudioDevicePropertyDataSource.count(device) == 0) {
            BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
                device.AddPropertyListenerBlock(CAPropertyAddress(kAudioDevicePropertyDataSource,
                                                                  kAudioDevicePropertyScopeOutput),
                                                dispatch_get_main_queue(),
                                                refreshNeededListener);
                listenedDevices_kAudioDevicePropertyDataSource.insert(device);
            });
        };
    }
}

- (NSArray<NSButton*>*) createButtonsForDevice:(CAHALAudioDevice)device {
    // We fill this array with a button for each output device (or each data source for each device) on
    // the system.
    NSMutableArray<NSButton*>* items = [NSMutableArray new];

    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeOutput;
    UInt32 channel = kAudioObjectPropertyElementMain;
    
    // If the device has data sources, create a menu item for each. Otherwise, create a single menu item
    // for the device. This way the menu items' titles will be, for example, "Internal Speakers" rather
    // than "Built-in Output".
    //
    // TODO: Handle data destinations as well? I don't have (or know of) any hardware with them.
    // TODO: Use the current data source's name when the control isn't settable, but only add one menu item.
    UInt32 numDataSources = 0;

    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        if (device.HasDataSourceControl(scope, channel) &&
                device.DataSourceControlIsSettable(scope, channel)) {
            numDataSources = device.GetNumberAvailableDataSources(scope, channel);
        }
    });
    
    if (numDataSources > 0) {
        std::vector<UInt32> dataSourceIDs(numDataSources);
        // This call updates numDataSources to the real number of IDs it added to our array.
        device.GetAvailableDataSources(scope, channel, numDataSources, dataSourceIDs.data());
        
        for (UInt32 i = 0; i < numDataSources; i++) {
            DebugMsg("BGMOutputDeviceMenuSection::createButtonsForDevice: "
                     "Creating button. %s%u %s%u",
                     "Device ID:", device.GetObjectID(),
                     ", Data source ID:", dataSourceIDs[i]);

            BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, "(DS)", [&] {
                NSString* dataSourceName =
                    CFBridgingRelease(device.CopyDataSourceNameForID(scope, channel, dataSourceIDs[i]));
                NSString* deviceName = CFBridgingRelease(device.CopyName());

                [items addObject:[self createButtonForDevice:device
                                                 dataSourceID:@(dataSourceIDs[i])
                                                        title:dataSourceName
                                                      toolTip:deviceName]];
            });
        }
    } else {
        DebugMsg("BGMOutputDeviceMenuSection::createButtonsForDevice: Creating button. %s%u",
                 "Device ID:", device.GetObjectID());

        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            [items addObject:[self createButtonForDevice:device
                                             dataSourceID:nil
                                                    title:CFBridgingRelease(device.CopyName())
                                                  toolTip:nil]];
        });
    }

    return items;
}

// Returns the button itself -- button.superview is its row container (see
// BGMMainPanelContentView.rowContainerWithControl:height:), which is what actually gets added to
// deviceStack.
- (NSButton*) createButtonForDevice:(CAHALAudioDevice)device
                        dataSourceID:(NSNumber* __nullable)dataSourceID
                               title:(NSString* __nullable)title
                             toolTip:(NSString* __nullable)toolTip {
    // If we don't have a title, use the tool-tip text instead.
    if (!title) {
        title = (toolTip ? toolTip : @"");
    }

    // Indented one level to match the old menu's indentationLevel=1 for device rows, relative to
    // the "Output Device" section header above them.
    NSButton* button = [NSButton buttonWithTitle:[@"    " stringByAppendingString:BGMNN(title)]
                                            target:self
                                            action:@selector(outputDeviceButtonClicked:)];
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.alignment = NSTextAlignmentLeft;
    button.buttonType = NSButtonTypeSwitch;
    button.translatesAutoresizingMaskIntoConstraints = NO;

    // Add the AirPlay icon to the labels of AirPlay devices.
    //
    // TODO: Test this with real hardware that supports AirPlay. (I don't have any.)
    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        if (device.GetTransportType() == kAudioDeviceTransportTypeAirPlay) {
            NSImage* airplayIcon = [NSImage imageNamed:@"AirPlayIcon"];

            // Make the icon a "template image" so it gets drawn colour-inverted when it's
            // highlighted or the system is in dark mode.
            [airplayIcon setTemplate:YES];
            button.image = airplayIcon;
            button.imagePosition = NSImageLeft;
        }
    });

    // The button should show as selected if it's for the current output device. If the device has
    // data sources, only the button for the current data source should be selected.
    BOOL isSelected =
        [audioDevices isOutputDevice:device.GetObjectID()] &&
            (!dataSourceID || [audioDevices isOutputDataSource:[dataSourceID unsignedIntValue]]);

    button.state = (isSelected ? NSControlStateValueOn : NSControlStateValueOff);
    button.toolTip = toolTip;

    [self setDeviceInfo:@{ @"deviceID": @(device.GetObjectID()),
                          @"dataSourceID": dataSourceID ? BGMNN(dataSourceID) : [NSNull null] }
              forButton:button];

    if (@available(macOS 10.10, *)) {
        // Used for UI tests.
        button.accessibilityIdentifier = @"output-device";
    }

    // Add the row to deviceStack immediately, in the same call that creates it -- an NSView's
    // superview backreference is unretained, so if this button's wrapping row were left
    // unattached to any view hierarchy even briefly, nothing would keep it alive and it (and this
    // button along with it) could be deallocated before the caller ever uses it.
    NSView* row = [BGMMainPanelContentView rowContainerWithControl:button height:kBGMMainPanelRowHeight];
    [deviceStack addArrangedSubview:row];

    return button;
}

// Called by BGMAudioDeviceManager to tell us a different device has been set as the output device.
- (void) outputDeviceDidChange {
    BGMOutputDeviceMenuSection* __weak weakSelf = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            [weakSelf populateDeviceList];
        });
    });
}

- (void) outputDeviceButtonClicked:(NSButton*)button {
    DebugMsg("BGMOutputDeviceMenuSection::outputDeviceButtonClicked: '%s' button clicked",
             [button.title UTF8String]);

    // Make sure the button is actually for an output device.
    if (![outputDeviceButtons containsObject:button]) {
        return;
    }

    NSDictionary* __nullable deviceInfo = [self deviceInfoForButton:button];

    if (!deviceInfo) {
        return;
    }

    // Change to the new output device.
    AudioDeviceID newDeviceID = [deviceInfo[@"deviceID"] unsignedIntValue];
    id newDataSourceID = deviceInfo[@"dataSourceID"];

    BOOL changingDevice = ![audioDevices isOutputDevice:newDeviceID];
    BOOL changingDataSource =
        (newDataSourceID != [NSNull null]) &&
            ![audioDevices isOutputDataSource:[newDataSourceID unsignedIntValue]];

    if (changingDevice || changingDataSource) {
        NSString* deviceName =
            button.toolTip ?
                [NSString stringWithFormat:@"%@ (%@)", button.title, button.toolTip] :
                button.title;

        if (changingDevice) {
            // Add the new output device to the list of preferred devices.
            [preferredDevices userChangedOutputDeviceTo:newDeviceID];
        }

        // Dispatched because it usually blocks. (Note that we're using
        // DISPATCH_QUEUE_PRIORITY_HIGH, which is the second highest priority.)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self changeToOutputDevice:newDeviceID
                         newDataSource:newDataSourceID
                            deviceName:deviceName];
        });
    }
}

- (void) changeToOutputDevice:(AudioDeviceID)deviceID
                newDataSource:(id)dataSourceID
                   deviceName:(NSString*)deviceName {
    NSError* __nullable error;
    
    if (dataSourceID == [NSNull null]) {
        error = [audioDevices setOutputDeviceWithID:deviceID revertOnFailure:YES];
    } else {
        error = [audioDevices setOutputDeviceWithID:deviceID
                                       dataSourceID:[dataSourceID unsignedIntValue]
                                    revertOnFailure:YES];
    }
    
    if (error) {
        // Couldn't change the output device, so show a warning. (No need to change the menu
        // selection back because it gets repopulated every time it's opened.)
        
        // NSAlerts should only be shown on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"Failed to set output device: %@", deviceName);
            
            NSAlert* alert = [NSAlert new];
            
            alert.messageText =
                [NSString stringWithFormat:@"Failed to set %@ as the output device.", deviceName];
            alert.informativeText = @"This is probably a bug. Feel free to report it.";
            
            [alert runModal];
        });
    }
}

@end

#pragma clang assume_nonnull end

