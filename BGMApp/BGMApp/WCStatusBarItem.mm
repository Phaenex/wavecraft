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
//  WCStatusBarItem.m
//  BGMApp
//
//  Copyright © 2019, 2020, 2026 Kyle Neideck
//

// Self Include
#import "WCStatusBarItem.h"

// Local Includes
#import "BGM_Utils.h"
#import "WCUserDefaults.h"
#import "WCVolumeChangeListener.h"


#pragma clang assume_nonnull begin

static CGFloat const kStatusBarIconPadding                = 0.25;
static CGFloat const kVolumeIconAdditionalVerticalPadding = 0.075;

@implementation WCStatusBarItem
{
    WCAudioDeviceManager* audioDevices;

    // User settings and data.
    WCUserDefaults* userDefaults;

    NSImage* wavecraftIcon;
    NSImage* volumeIcon0SoundWaves;
    NSImage* volumeIcon1SoundWave;
    NSImage* volumeIcon2SoundWaves;
    NSImage* volumeIcon3SoundWaves;

    NSStatusItem* statusBarItem;
    WCMainPanel* mainPanel;
    WCDebugLoggingMenuItem* debugLoggingMenuItem;

    WCVolumeChangeListener* volumeChangeListener;

    BGMStatusBarIcon _icon;
}

#pragma mark Initialisation

- (instancetype) initWithPanel:(WCMainPanel*)panel
                  audioDevices:(WCAudioDeviceManager*)devices
                  userDefaults:(WCUserDefaults*)defaults {
    if ((self = [super init])) {
        statusBarItem =
                [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

        mainPanel = panel;
        audioDevices = devices;
        userDefaults = defaults;

        // Initialise the icons.
        [self initIcons];

        // Set the initial icon.
        self.icon = userDefaults.statusBarIcon;

        // Clicking the button toggles the main panel -- there's no automatic "menu" wiring to do
        // here any more (see WCMainPanel's header for why this app moved off NSMenu for its main
        // dropdown), so this is the one place that has to explicitly open/close it.
        if ([WCStatusBarItem buttonAvailable]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
            statusBarItem.button.target = self;
            statusBarItem.button.action = @selector(statusBarButtonClicked:);

            // Set the accessibility label to "Wavecraft". (We intentionally don't set a
            // title or a tooltip.)
            statusBarItem.button.accessibilityLabel =
                    [NSRunningApplication currentApplication].localizedName;
#pragma clang diagnostic pop
        }

        // Update the icon when BGMDevice's volume changes.
        WCStatusBarItem* __weak weakSelf = self;
        volumeChangeListener = new WCVolumeChangeListener(audioDevices.bgmDevice, [=] {
            [weakSelf bgmDeviceVolumeDidChange];
        });
    }

    return self;
}

- (void) dealloc {
    delete volumeChangeListener;
}

- (void) initIcons {
    // Load the icons.
    wavecraftIcon = [NSImage imageNamed:@"WavecraftIcon"];
    if (@available(macOS 11.0, *)) {
        volumeIcon0SoundWaves = [NSImage imageWithSystemSymbolName:@"speaker.fill" accessibilityDescription:nil];
        volumeIcon1SoundWave = [NSImage imageWithSystemSymbolName:@"speaker.wave.1.fill" accessibilityDescription:nil];
        volumeIcon2SoundWaves = [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill" accessibilityDescription:nil];
        volumeIcon3SoundWaves = [NSImage imageWithSystemSymbolName:@"speaker.wave.3.fill" accessibilityDescription:nil];
    } else {
        volumeIcon0SoundWaves = [NSImage imageNamed:@"Volume0"];
        volumeIcon1SoundWave = [NSImage imageNamed:@"Volume1"];
        volumeIcon2SoundWaves = [NSImage imageNamed:@"Volume2"];
        volumeIcon3SoundWaves = [NSImage imageNamed:@"Volume3"];
    }

    // Set the icons' sizes based on the menu bar's own thickness (a stable constant, e.g. 22pt --
    // not the status item's button frame. This runs immediately after the item is created, before
    // it's ever actually been laid out, so button.frame.size.height can still be 0 at this exact
    // moment; sizing the icon off that would resize it to literally 0x0 pixels -- present, but
    // genuinely invisible, independent of when the image gets assigned. Confirmed against a real
    // install (see docs/LESSONS.md) after fixing a separate, also-real timing bug in setIcon: below
    // didn't make the icon appear on its own.
    CGFloat heightMinusPadding =
        [NSStatusBar systemStatusBar].thickness * (1 - kStatusBarIconPadding);

    // The Wavecraft icon has equal width and height.
    [wavecraftIcon setSize:NSMakeSize(heightMinusPadding, heightMinusPadding)];

    // The volume icons are all the same width and height.
    CGFloat volumeIconWidthToHeightRatio =
            volumeIcon0SoundWaves.size.width / volumeIcon0SoundWaves.size.height;
    CGFloat volumeIconWidth = heightMinusPadding * volumeIconWidthToHeightRatio;
    CGFloat volumeIconHeight = heightMinusPadding * (1 - kVolumeIconAdditionalVerticalPadding);

    [volumeIcon0SoundWaves setSize:NSMakeSize(volumeIconWidth, volumeIconHeight)];
    [volumeIcon1SoundWave setSize:NSMakeSize(volumeIconWidth, volumeIconHeight)];
    [volumeIcon2SoundWaves setSize:NSMakeSize(volumeIconWidth, volumeIconHeight)];
    [volumeIcon3SoundWaves setSize:NSMakeSize(volumeIconWidth, volumeIconHeight)];

    // Make the icons "template images" so they get drawn colour-inverted when they're highlighted
    // or the system is in dark mode.
    [wavecraftIcon setTemplate:YES];
    [volumeIcon0SoundWaves setTemplate:YES];
    [volumeIcon1SoundWave setTemplate:YES];
    [volumeIcon2SoundWaves setTemplate:YES];
    [volumeIcon3SoundWaves setTemplate:YES];
}

#pragma mark Accessors

+ (BOOL) buttonAvailable {
    // NSStatusItem doesn't have the "button" property on OS X 10.9.
    return (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_10);
}

- (void) setImage:(NSImage*)image {
    if ([WCStatusBarItem buttonAvailable]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        statusBarItem.button.image = image;
#pragma clang diagnostic pop
    } else {
        statusBarItem.image = image;
    }
}

- (BGMStatusBarIcon) icon {
    return _icon;
}

- (void) setIcon:(BGMStatusBarIcon)icon {
    _icon = icon;

    // Save the setting.
    userDefaults.statusBarIcon = self.icon;

    // Change the icon (i.e. the image). Must run on the main thread because it changes the UI --
    // but only actually dispatch when we're not already there. Unconditionally dispatching, even
    // from the main thread, defers the update to the next run loop turn instead of running it
    // inline. This setter's very first call comes from initWithMenu:, already on the main thread
    // during app launch -- when that call went through the deferred path, NSStatusItem's initial
    // layout pass ran before the image was ever set, computed a zero width, and never
    // recalculated it once the image did land a moment later: a real, "visible" NSStatusItem with
    // no icon and no width, permanently invisible in the actual menu bar. Confirmed against a real
    // install via diagnostic logging (button.image was still nil immediately after this call
    // returned) -- see docs/LESSONS.md.
    void (^updateIcon)(void) = ^{
        if (_icon == BGMWavecraftStatusBarIcon) {
            [self setImage:wavecraftIcon];

            // If the icon was greyed out, change it back.
            if ([WCStatusBarItem buttonAvailable]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
                statusBarItem.button.appearsDisabled = NO;
#pragma clang diagnostic pop
            }
        } else {
            BGMAssert((_icon == BGMVolumeStatusBarIcon), "Unknown icon in enum");

            [self updateVolumeStatusBarIcon];
        }
    };

    if ([NSThread isMainThread]) {
        updateIcon();
    } else {
        dispatch_async(dispatch_get_main_queue(), updateIcon);
    }
}

#pragma mark Volume Icon

- (void) bgmDeviceVolumeDidChange {
    if (self.icon == BGMVolumeStatusBarIcon) {
        [self updateVolumeStatusBarIcon];
    }
}

// Should only be called on the main thread because it calls UI functions.
- (void) updateVolumeStatusBarIcon {
    BGMAssert([[NSThread currentThread] isMainThread],
              "updateVolumeStatusBarIcon called on non-main thread.");
    BGMAssert((self.icon == BGMVolumeStatusBarIcon), "Volume status bar icon not enabled");

    BGMAudioDevice bgmDevice = [audioDevices bgmDevice];

    // BGMDevice should never return an error for these calls, so we just swallow any exceptions and
    // give up.
    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        AudioObjectPropertyScope scope = kAudioObjectPropertyScopeOutput;
        AudioObjectPropertyElement element = kAudioObjectPropertyElementMain;

        BOOL hasVolume = bgmDevice.HasVolumeControl(scope, element);

        // Show the button as greyed out if BGMDevice doesn't have a volume control (which means the
        // output device doesn't have one).
        if ([WCStatusBarItem buttonAvailable]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
            statusBarItem.button.appearsDisabled = !hasVolume;
#pragma clang diagnostic pop
        }

        if (hasVolume) {
            if (bgmDevice.HasMuteControl(scope, element) &&
                    bgmDevice.GetMuteControlValue(scope, element)) {
                // The device is muted, so use the zero waves icon.
                [self setImage:volumeIcon0SoundWaves];
            } else {
                // Set the icon to reflect the device's volume.
                double volume = bgmDevice.GetVolumeControlScalarValue(scope, element);

                // These values match the macOS volume status bar item, except for the first one. I
                // don't know why, but at a very low volume macOS will show the zero waves icon even
                // though the sound is still audible.
                if (volume == 0.05) {
                    [self setImage:volumeIcon0SoundWaves];
                } else if (volume < 0.33) {
                    [self setImage:volumeIcon1SoundWave];
                } else if (volume < 0.66) {
                    [self setImage:volumeIcon2SoundWaves];
                } else {
                    [self setImage:volumeIcon3SoundWaves];
                }
            }
        } else {
            // Always use the full-volume icon when the device has no volume control.
            [self setImage:volumeIcon3SoundWaves];
        }
    });

    DebugMsg("WCStatusBarItem::updateVolumeStatusBarIcon: Set icon to %s",
             statusBarItem.image.name.UTF8String);
}

#pragma mark Button Click

- (void) statusBarButtonClicked:(id)sender {
    #pragma unused (sender)

    NSEvent* __nullable event = NSApp.currentEvent;
    BOOL optionHeld = event && ((event.modifierFlags & NSEventModifierFlagOption) != 0);

    if (optionHeld) {
        DebugMsg("WCStatusBarItem::statusBarButtonClicked: Option key held");
    }

    [debugLoggingMenuItem setMenuShowingExtraOptions:optionHeld];

    if ([WCStatusBarItem buttonAvailable]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        // The button always exists once the status item itself does -- see initWithPanel:...
        // above, which sets statusBarItem.button.target/action unconditionally under the same
        // buttonAvailable check as here.
        NSStatusBarButton* button = BGMNN(statusBarItem.button);
#pragma clang diagnostic pop

        [mainPanel toggleRelativeToStatusItemButton:button];
    }
}

#pragma mark Debug Logging Menu Item

- (void) setDebugLoggingMenuItem:(WCDebugLoggingMenuItem*)menuItem {
    debugLoggingMenuItem = menuItem;
}

@end

#pragma clang assume_nonnull end

