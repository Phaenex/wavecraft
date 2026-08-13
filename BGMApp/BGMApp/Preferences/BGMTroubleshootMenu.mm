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
//  BGMTroubleshootMenu.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "BGMTroubleshootMenu.h"

// Local Includes
#import "BGM_Types.h"
#import "BGM_Utils.h"

// PublicUtility Includes
#import "CACFArray.h"
#import "CACFDictionary.h"
#import "CACFString.h"
#import "CAException.h"

// System Includes
#import <AVFoundation/AVCaptureDevice.h>
#import <array>


#pragma clang assume_nonnull begin

@implementation BGMTroubleshootMenu {
    BGMAudioDeviceManager* audioDevices;
    BGMPreferredOutputDevices* preferredOutputDevices;
    BGMAppOutputRoutingController* outputRoutingController;
    BGMDoNotDisturb* doNotDisturb;
    BGMXPCListener* __nullable xpcListener;
}

- (instancetype) initWithPreferencesMenu:(NSMenu*)prefsMenu
                            audioDevices:(BGMAudioDeviceManager*)inAudioDevices
                 preferredOutputDevices:(BGMPreferredOutputDevices*)inPreferredOutputDevices
                outputRoutingController:(BGMAppOutputRoutingController*)inOutputRoutingController
                           doNotDisturb:(BGMDoNotDisturb*)inDoNotDisturb {
    if ((self = [super init])) {
        audioDevices = inAudioDevices;
        preferredOutputDevices = inPreferredOutputDevices;
        outputRoutingController = inOutputRoutingController;
        doNotDisturb = inDoNotDisturb;

        [self setupMenu:prefsMenu];
    }

    return self;
}

- (void) setXPCListener:(BGMXPCListener*)inXPCListener {
    xpcListener = inXPCListener;
}

#pragma mark Menu Setup

- (void) setupMenu:(NSMenu*)prefsMenu {
    [prefsMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* header = [[NSMenuItem alloc] initWithTitle:@"Troubleshoot"
                                                     action:nil
                                              keyEquivalent:@""];
    header.enabled = NO;
    [prefsMenu addItem:header];

    [self addItemWithTitle:@"Reapply Default Output Device"
                     action:@selector(reapplyDefaultOutputDevice)
                     toMenu:prefsMenu];
    [self addItemWithTitle:@"Reset All App Volumes, Pan & EQ…"
                     action:@selector(confirmResetAllAppVolumesPanAndEQ)
                     toMenu:prefsMenu];
    [self addItemWithTitle:@"Remove All Output Routing Overrides…"
                     action:@selector(confirmRemoveAllOutputOverrides)
                     toMenu:prefsMenu];
    [self addItemWithTitle:@"Reconnect to BGMXPCHelper"
                     action:@selector(reconnectXPCHelper)
                     toMenu:prefsMenu];
    [self addItemWithTitle:@"Check Microphone Permission"
                     action:@selector(checkMicrophonePermission)
                     toMenu:prefsMenu];
}

- (void) addItemWithTitle:(NSString*)title action:(SEL)action toMenu:(NSMenu*)menu {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
}

#pragma mark Reapply Default Output Device

- (void) reapplyDefaultOutputDevice {
    AudioObjectID preferred = [preferredOutputDevices findPreferredDevice];

    if (preferred == kAudioObjectUnknown) {
        [self showResultAlert:@"Couldn’t Find an Output Device"
                          text:@"No connected audio device could be used as the output device. "
                                "Check Audio MIDI Setup for what’s actually connected, then try "
                                "again."
                       success:NO];
        return;
    }

    NSError* __nullable deviceError = [audioDevices setOutputDeviceWithID:preferred
                                                          revertOnFailure:YES];
    NSError* __nullable defaultError = [audioDevices setBGMDeviceAsOSDefault];

    if (deviceError || defaultError) {
        NSError* error = BGMNN(deviceError ?: defaultError);
        [self showResultAlert:@"Couldn’t Reset the Output Device"
                          text:[NSString stringWithFormat:@"%@", error.localizedDescription]
                       success:NO];
    } else {
        [self showResultAlert:@"Output Device Reset"
                          text:@"Wavecraft is set as your system’s default device again, with "
                                "your real output device reconnected behind it. If audio was "
                                "silent before this, try playing something now."
                       success:YES];
    }
}

#pragma mark Reset All App Volumes, Pan & EQ

- (void) confirmResetAllAppVolumesPanAndEQ {
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"Reset every app’s volume, pan, and EQ?";
    alert.informativeText = @"Every app currently boosted, panned, or EQ’d away from its default "
                              "will go back to flat/centered/unboosted. This doesn’t affect your "
                              "output-routing assignments, and it won’t un-mute anything Do Not "
                              "Disturb is currently muting.";
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Reset"];

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        [self resetAllAppVolumesPanAndEQ];
    }
}

- (void) resetAllAppVolumesPanAndEQ {
    try {
        NSUInteger resetCount = 0;
        resetCount += [self resetAllAppVolumesAndPan];
        resetCount += [self resetAllAppEQ];

        if (resetCount == 0) {
            [self showResultAlert:@"Nothing to Reset"
                              text:@"No app currently has a non-default volume, pan, or EQ set."
                           success:YES];
        } else {
            [self showResultAlert:@"Reset"
                              text:[NSString stringWithFormat:
                                        @"Reset %lu app audio setting%@ back to default.",
                                        (unsigned long)resetCount, resetCount == 1 ? @"" : @"s"]
                           success:YES];
        }
    } catch (const CAException& e) {
        [self showResultAlert:@"Couldn’t Reset Everything"
                          text:[NSString stringWithFormat:@"CoreAudio error %d.",
                                                           static_cast<int>(e.GetError())]
                       success:NO];
    }
}

// Returns the number of clients whose volume/pan were actually reset -- doesn't include any app
// this method skipped because Do Not Disturb is currently muting it (see the loop body).
- (NSUInteger) resetAllAppVolumesAndPan {
    CACFArray volumes(audioDevices.bgmDevice.GetAppVolumes(), false);
    UInt32 count = volumes.GetNumberItems();

    // Halfway between kAppRelativeVolumeMinRawValue and kAppRelativeVolumeMaxRawValue -- the same
    // "unity gain" raw value BGMAVM_VolumeMute restores to and BGMAVM_VolumeSlider snaps to. 0 is
    // the centered/default pan position.
    const SInt32 kDefaultVolume = (kAppRelativeVolumeMinRawValue + kAppRelativeVolumeMaxRawValue) / 2;
    const SInt32 kDefaultPan = 0;

    NSUInteger resetCount = 0;

    for (UInt32 i = 0; i < count; i++) {
        CACFDictionary entry(false);
        volumes.GetCACFDictionary(i, entry);

        // A Do Not Disturb-muted app's volume is at kAppRelativeVolumeMinRawValue, which makes it
        // "non-default" by the same test that includes any other boosted/cut app here -- but
        // resetting it would silently un-mute an app Do Not Disturb is actively suppressing,
        // without Do Not Disturb's own state (which app it's muting) ever finding out, so the
        // mismatch would persist until Do Not Disturb is toggled off or the app relaunches. Skip
        // it instead; the confirmation alert already tells the user Do Not Disturb-muted apps
        // aren't touched here.
        CACFString bundleID;
        bundleID.DontAllowRelease();
        entry.GetCACFString(CFSTR(kBGMAppVolumesKey_BundleID), bundleID);

        if (bundleID.IsValid() &&
            [doNotDisturb isMutingBundleID:(__bridge NSString*)bundleID.GetCFString()]) {
            continue;
        }

        [self setVolume:kDefaultVolume pan:kDefaultPan forClientEntry:entry];
        resetCount++;
    }

    return resetCount;
}

- (NSUInteger) resetAllAppEQ {
    CACFArray eq(audioDevices.bgmDevice.GetAppEQ(), false);
    UInt32 count = eq.GetNumberItems();

    std::array<Float32, kBGMAppEQNumBands> flatGains {};
    flatGains.fill(0.0f);

    for (UInt32 i = 0; i < count; i++) {
        CACFDictionary entry(false);
        eq.GetCACFDictionary(i, entry);

        pid_t pid = -1;
        entry.GetSInt32(CFSTR(kBGMAppEQKey_ProcessID), pid);

        CACFString bundleID;
        bundleID.DontAllowRelease();
        entry.GetCACFString(CFSTR(kBGMAppEQKey_BundleID), bundleID);

        audioDevices.bgmDevice.SetAppEQBandGains(flatGains, pid,
                                                 bundleID.IsValid() ? bundleID.GetCFString()
                                                                     : nullptr);
    }

    return count;
}

- (void) setVolume:(SInt32)volume pan:(SInt32)pan forClientEntry:(const CACFDictionary&)entry {
    pid_t pid = -1;
    entry.GetSInt32(CFSTR(kBGMAppVolumesKey_ProcessID), pid);

    CACFString bundleID;
    bundleID.DontAllowRelease();
    entry.GetCACFString(CFSTR(kBGMAppVolumesKey_BundleID), bundleID);

    CFStringRef __nullable bundleIDRef = bundleID.IsValid() ? bundleID.GetCFString() : nullptr;

    audioDevices.bgmDevice.SetAppVolume(volume, pid, bundleIDRef);
    audioDevices.bgmDevice.SetAppPanPosition(pan, pid, bundleIDRef);
}

#pragma mark Remove All Output Routing Overrides

- (void) confirmRemoveAllOutputOverrides {
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"Remove every output-routing override?";
    alert.informativeText = @"Every app currently routed to a non-default output device will go "
                              "back through Wavecraft’s normal output path.";
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Remove All"];

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        [outputRoutingController removeAllOutputOverrides];
        [self showResultAlert:@"Routing Overrides Removed"
                          text:@"Every app is back on Wavecraft’s normal default-output path."
                       success:YES];
    }
}

#pragma mark Reconnect to BGMXPCHelper

- (void) reconnectXPCHelper {
    if (!xpcListener) {
        [self showResultAlert:@"Not Ready Yet"
                          text:@"Wavecraft hasn’t finished starting up yet — try again in a few "
                                "seconds."
                       success:NO];
        return;
    }

    [xpcListener initHelperConnection];

    [self showResultAlert:@"Reconnecting"
                      text:@"Asked Wavecraft to re-establish its connection to BGMXPCHelper. This "
                            "also happens automatically in the background if the connection ever "
                            "drops, so you may not have needed this."
                   success:YES];
}

#pragma mark Check Microphone Permission

- (void) checkMicrophonePermission {
    if (@available(macOS 10.14, *)) {
        AVAuthorizationStatus status =
            [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];

        if (status == AVAuthorizationStatusAuthorized) {
            [self showResultAlert:@"Microphone Access Granted"
                              text:@"Wavecraft has the permission it needs. (It doesn’t actually "
                                    "listen to your microphone — see the README for why it needs "
                                    "this permission at all.)"
                           success:YES];
            return;
        }

        NSAlert* alert = [NSAlert new];
        alert.messageText = @"Microphone Access Not Granted";
        alert.informativeText = @"Wavecraft can’t capture your system’s audio without this. Grant "
                                  "it in System Settings > Privacy & Security > Microphone, then "
                                  "reopen Wavecraft.";
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Open Privacy Settings"];

        if ([alert runModal] != NSAlertFirstButtonReturn) {
            [self openSysPrefsMicrophonePrivacy];
        }
    } else {
        [self showResultAlert:@"Not Needed on This macOS Version"
                          text:@"Versions of macOS before 10.14 don’t require this permission for "
                                "virtual audio input devices."
                       success:YES];
    }
}

- (void) openSysPrefsMicrophonePrivacy {
    NSURL* __nullable url = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"];

    BOOL opened = url && [[NSWorkspace sharedWorkspace] openURL:BGMNN(url)];

    if (!opened) {
        NSLog(@"BGMTroubleshootMenu::openSysPrefsMicrophonePrivacy: "
              "Failed to open System Settings");
    }
}

#pragma mark Result Alert

- (void) showResultAlert:(NSString*)title text:(NSString*)text success:(BOOL)success {
    NSAlert* alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = text;
    alert.alertStyle = success ? NSAlertStyleInformational : NSAlertStyleCritical;
    [alert runModal];
}

@end

#pragma clang assume_nonnull end
