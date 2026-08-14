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
//  WCPreferencesMenu.mm
//  BGMApp
//
//  Copyright © 2016, 2018, 2019 Kyle Neideck
//

// Self Include
#import "WCPreferencesMenu.h"

// Local Includes
#import "WCAutoPauseMusicPrefs.h"
#import "WCAboutPanel.h"
#import "BGM_Types.h"
#import "BGM_Utils.h"

// System Includes
#import <math.h>


NS_ASSUME_NONNULL_BEGIN

// Interface Builder tags
static NSInteger const kPreferencesMenuItemTag = 1;
static NSInteger const kBGMIconMenuItemTag     = 2;
static NSInteger const kVolumeIconMenuItemTag  = 3;
static NSInteger const kAboutPanelMenuItemTag  = 4;

@implementation WCPreferencesMenu {
    // Menu sections/items
    WCAutoPauseMusicPrefs* autoPauseMusicPrefs;
    NSMenuItem* bgmIconMenuItem;
    NSMenuItem* volumeIconMenuItem;

    // The menu item you press to open BGMApp's main menu.
    WCStatusBarItem* statusBarItem;

    // The About Background Music window
    WCAboutPanel* aboutPanel;

    // Delay preferences
    NSMenuItem* pauseDelayMenuItem;
    NSMenuItem* maxUnpauseDelayMenuItem;
    NSSlider* pauseDelaySlider;
    NSSlider* maxUnpauseDelaySlider;
    NSTextField* pauseDelayLabel;
    NSTextField* maxUnpauseDelayLabel;
    WCUserDefaults* userDefaults;

    WCTroubleshootMenu* troubleshootMenu;

    // Hotkey preferences
    WCHotkeys* hotkeys;
    NSMenuItem* hotkeysEnabledMenuItem;
    NSMenuItem* hotkeyStepFineMenuItem;
    NSMenuItem* hotkeyStepNormalMenuItem;
    NSMenuItem* hotkeyStepCoarseMenuItem;
    NSMenuItem* hotkeyBindingsDescriptionMenuItem;
    // One recorder button per BGMHotkeyAction, indexed by the enum's raw value.
    NSMutableArray<WCHotkeyRecorderButton*>* hotkeyRecorderButtons;

    // Do Not Disturb preferences
    WCDoNotDisturb* doNotDisturb;
    NSMenuItem* doNotDisturbEnabledMenuItem;
    NSMenuItem* doNotDisturbPriorityAppMenuItem;
    NSMenu* doNotDisturbPriorityAppSubmenu;
}

- (id) initWithBGMMenu:(NSMenu*)inBGMMenu
          audioDevices:(WCAudioDeviceManager*)inAudioDevices
          musicPlayers:(WCMusicPlayers*)inMusicPlayers
         statusBarItem:(WCStatusBarItem*)inStatusBarItem
            aboutPanel:(NSPanel*)inAboutPanel
 aboutPanelLicenseView:(NSTextView*)inAboutPanelLicenseView
          userDefaults:(WCUserDefaults*)inUserDefaults
preferredOutputDevices:(WCPreferredOutputDevices*)inPreferredOutputDevices
outputRoutingController:(WCAppOutputRoutingController*)inOutputRoutingController
               hotkeys:(WCHotkeys*)inHotkeys
          doNotDisturb:(WCDoNotDisturb*)inDoNotDisturb {
    if ((self = [super init])) {
        NSMenu* prefsMenu = [[inBGMMenu itemWithTag:kPreferencesMenuItemTag] submenu];
        _menu = prefsMenu;

        autoPauseMusicPrefs = [[WCAutoPauseMusicPrefs alloc] initWithPreferencesMenu:prefsMenu
                                                                         audioDevices:inAudioDevices
                                                                         musicPlayers:inMusicPlayers];

        aboutPanel = [[WCAboutPanel alloc] initWithPanel:inAboutPanel licenseView:inAboutPanelLicenseView];

        statusBarItem = inStatusBarItem;

        // Set up the menu items under the "Status Bar Icon" heading.
        bgmIconMenuItem = [prefsMenu itemWithTag:kBGMIconMenuItemTag];
        bgmIconMenuItem.state =
                (statusBarItem.icon == BGMWavecraftStatusBarIcon) ? NSOnState : NSOffState;
        [bgmIconMenuItem setTarget:self];
        [bgmIconMenuItem setAction:@selector(useBGMStatusBarIcon)];

        volumeIconMenuItem = [prefsMenu itemWithTag:kVolumeIconMenuItemTag];
        volumeIconMenuItem.state =
                (statusBarItem.icon == BGMVolumeStatusBarIcon) ? NSOnState : NSOffState;
        [volumeIconMenuItem setTarget:self];
        [volumeIconMenuItem setAction:@selector(useVolumeStatusBarIcon)];

        // Set up the "About Background Music" menu item
        NSMenuItem* aboutMenuItem = [prefsMenu itemWithTag:kAboutPanelMenuItemTag];
        [aboutMenuItem setTarget:aboutPanel];
        [aboutMenuItem setAction:@selector(show)];

        // Set up delay preferences
        userDefaults = inUserDefaults;
        [self setupDelayPreferences:prefsMenu];

        troubleshootMenu =
            [[WCTroubleshootMenu alloc] initWithPreferencesMenu:prefsMenu
                                                     audioDevices:inAudioDevices
                                          preferredOutputDevices:inPreferredOutputDevices
                                         outputRoutingController:inOutputRoutingController
                                                    doNotDisturb:inDoNotDisturb];

        hotkeys = inHotkeys;
        [self setupHotkeysMenu:prefsMenu];

        doNotDisturb = inDoNotDisturb;
        [self setupDoNotDisturbMenu:prefsMenu];
    }

    return self;
}

#pragma mark Hotkeys

- (void) setupHotkeysMenu:(NSMenu*)prefsMenu {
    [prefsMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* header = [[NSMenuItem alloc] initWithTitle:@"Keyboard Shortcuts"
                                                     action:nil
                                              keyEquivalent:@""];
    header.enabled = NO;
    [prefsMenu addItem:header];

    hotkeysEnabledMenuItem = [[NSMenuItem alloc] initWithTitle:@"Enable Keyboard Shortcuts"
                                                         action:@selector(toggleHotkeysEnabled)
                                                  keyEquivalent:@""];
    hotkeysEnabledMenuItem.target = self;
    hotkeysEnabledMenuItem.state = hotkeys.isEnabled ? NSOnState : NSOffState;
    hotkeysEnabledMenuItem.toolTip =
        @"Adjust system or app volume without opening the menu. Needs Accessibility permission.";
    [prefsMenu addItem:hotkeysEnabledMenuItem];

    hotkeyRecorderButtons = [NSMutableArray arrayWithCapacity:(NSUInteger)kBGMHotkeyActionCount];

    for (NSInteger i = kBGMHotkeyActionMinValue; i <= kBGMHotkeyActionMaxValue; i++) {
        BGMHotkeyAction action = (BGMHotkeyAction)i;

        NSMenuItem* rowItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        NSView* row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 22)];

        NSTextField* label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 4, 165, 15)];
        label.stringValue = BGMHotkeyActionDisplayName(action);
        label.editable = NO;
        label.bordered = NO;
        label.backgroundColor = [NSColor clearColor];
        label.font = [NSFont menuFontOfSize:12];
        [row addSubview:label];

        BGMHotkeyBinding binding = [userDefaults hotkeyBindingForAction:action];
        WCHotkeyRecorderButton* recorder =
            [[WCHotkeyRecorderButton alloc] initWithFrame:NSMakeRect(190, 0, 80, 22)
                                                      action:action
                                                    delegate:self];
        [recorder refreshWithBinding:binding];
        [row addSubview:recorder];
        [hotkeyRecorderButtons addObject:recorder];

        rowItem.view = row;
        [prefsMenu addItem:rowItem];
    }

    hotkeyStepFineMenuItem = [[NSMenuItem alloc] initWithTitle:@"Fine Steps"
                                                          action:@selector(useFineStepSize)
                                                   keyEquivalent:@""];
    hotkeyStepFineMenuItem.target = self;
    hotkeyStepFineMenuItem.indentationLevel = 1;
    [prefsMenu addItem:hotkeyStepFineMenuItem];

    hotkeyStepNormalMenuItem = [[NSMenuItem alloc] initWithTitle:@"Normal Steps"
                                                            action:@selector(useNormalStepSize)
                                                     keyEquivalent:@""];
    hotkeyStepNormalMenuItem.target = self;
    hotkeyStepNormalMenuItem.indentationLevel = 1;
    [prefsMenu addItem:hotkeyStepNormalMenuItem];

    hotkeyStepCoarseMenuItem = [[NSMenuItem alloc] initWithTitle:@"Coarse Steps"
                                                            action:@selector(useCoarseStepSize)
                                                     keyEquivalent:@""];
    hotkeyStepCoarseMenuItem.target = self;
    hotkeyStepCoarseMenuItem.indentationLevel = 1;
    [prefsMenu addItem:hotkeyStepCoarseMenuItem];

    hotkeyBindingsDescriptionMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                                    action:nil
                                                             keyEquivalent:@""];
    hotkeyBindingsDescriptionMenuItem.enabled = NO;
    hotkeyBindingsDescriptionMenuItem.indentationLevel = 1;
    [prefsMenu addItem:hotkeyBindingsDescriptionMenuItem];

    [self updateHotkeyMenuItemStates];
}

- (void) toggleHotkeysEnabled {
    [hotkeys setEnabled:!hotkeys.isEnabled];
    [self updateHotkeyMenuItemStates];
}

#pragma mark WCHotkeyRecorderButtonDelegate

- (BOOL) hotkeyRecorderButton:(WCHotkeyRecorderButton*)button
          didRecordNewBinding:(BGMHotkeyBinding)binding
                    forAction:(BGMHotkeyAction)action {
    #pragma unused (button)

    for (NSInteger i = kBGMHotkeyActionMinValue; i <= kBGMHotkeyActionMaxValue; i++) {
        BGMHotkeyAction otherAction = (BGMHotkeyAction)i;

        if (otherAction == action) {
            continue;
        }

        BGMHotkeyBinding otherBinding = [userDefaults hotkeyBindingForAction:otherAction];

        if (BGMHotkeyBindingsEqual(binding, otherBinding)) {
            NSAlert* conflict = [NSAlert new];
            conflict.messageText = @"That shortcut is already in use";
            conflict.informativeText =
                [NSString stringWithFormat:
                    @"%@ is already bound to “%@”. Pick a different key, or record a new shortcut "
                     "for “%@” first to free it up.",
                    BGMHotkeyBindingDescription(binding),
                    BGMHotkeyActionDisplayName(otherAction),
                    BGMHotkeyActionDisplayName(otherAction)];
            [conflict addButtonWithTitle:@"OK"];
            [conflict runModal];

            return NO;
        }
    }

    [userDefaults setHotkeyBinding:binding forAction:action];
    [hotkeys bindingsChanged];
    [self updateHotkeyMenuItemStates];

    return YES;
}

- (void) useFineStepSize {
    userDefaults.hotkeyStepSize = BGMHotkeyStepSizeFine;
    [self updateHotkeyMenuItemStates];
}

- (void) useNormalStepSize {
    userDefaults.hotkeyStepSize = BGMHotkeyStepSizeNormal;
    [self updateHotkeyMenuItemStates];
}

- (void) useCoarseStepSize {
    userDefaults.hotkeyStepSize = BGMHotkeyStepSizeCoarse;
    [self updateHotkeyMenuItemStates];
}

- (void) updateHotkeyMenuItemStates {
    BOOL hotkeysEnabled = hotkeys.isEnabled;

    hotkeysEnabledMenuItem.state = hotkeysEnabled ? NSOnState : NSOffState;

    for (NSInteger i = kBGMHotkeyActionMinValue; i <= kBGMHotkeyActionMaxValue; i++) {
        BGMHotkeyAction action = (BGMHotkeyAction)i;
        WCHotkeyRecorderButton* recorder = hotkeyRecorderButtons[(NSUInteger)i];
        [recorder refreshWithBinding:[userDefaults hotkeyBindingForAction:action]];
        // Grayed out (not just cosmetically -- genuinely unclickable) while shortcuts are off,
        // since recording a binding here has no effect at all until "Enable Keyboard Shortcuts"
        // is checked -- there was previously nothing here to warn a user they'd set up shortcuts
        // that don't do anything yet.
        recorder.enabled = hotkeysEnabled;
    }

    NSInteger stepSize = userDefaults.hotkeyStepSize;
    hotkeyStepFineMenuItem.state = (stepSize == BGMHotkeyStepSizeFine) ? NSOnState : NSOffState;
    hotkeyStepNormalMenuItem.state = (stepSize == BGMHotkeyStepSizeNormal) ? NSOnState : NSOffState;
    hotkeyStepCoarseMenuItem.state = (stepSize == BGMHotkeyStepSizeCoarse) ? NSOnState : NSOffState;
    hotkeyStepFineMenuItem.enabled = hotkeysEnabled;
    hotkeyStepNormalMenuItem.enabled = hotkeysEnabled;
    hotkeyStepCoarseMenuItem.enabled = hotkeysEnabled;

    hotkeyBindingsDescriptionMenuItem.title = [hotkeys currentBindingsDescription];
}

#pragma mark Do Not Disturb

- (void) setupDoNotDisturbMenu:(NSMenu*)prefsMenu {
    [prefsMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* header = [[NSMenuItem alloc] initWithTitle:@"Do Not Disturb"
                                                      action:nil
                                               keyEquivalent:@""];
    header.enabled = NO;
    [prefsMenu addItem:header];

    doNotDisturbEnabledMenuItem =
        [[NSMenuItem alloc] initWithTitle:@"Enable Do Not Disturb"
                                    action:@selector(toggleDoNotDisturbEnabled)
                             keyEquivalent:@""];
    doNotDisturbEnabledMenuItem.target = self;
    doNotDisturbEnabledMenuItem.toolTip =
        @"Mutes every other app while it's on, so only the app you pick below stays audible.";
    [prefsMenu addItem:doNotDisturbEnabledMenuItem];

    doNotDisturbPriorityAppSubmenu = [[NSMenu alloc] initWithTitle:@"Priority App"];
    doNotDisturbPriorityAppSubmenu.delegate = self;

    doNotDisturbPriorityAppMenuItem = [[NSMenuItem alloc] initWithTitle:@"Priority App"
                                                                    action:nil
                                                             keyEquivalent:@""];
    doNotDisturbPriorityAppMenuItem.submenu = doNotDisturbPriorityAppSubmenu;
    doNotDisturbPriorityAppMenuItem.indentationLevel = 1;
    [prefsMenu addItem:doNotDisturbPriorityAppMenuItem];

    [self updateDoNotDisturbMenuItemStates];
}

- (void) toggleDoNotDisturbEnabled {
    [doNotDisturb setEnabled:!doNotDisturb.isEnabled];
    [self updateDoNotDisturbMenuItemStates];
}

// NSMenuDelegate. Rebuilds the priority-app list from currently-running apps right before it's
// shown -- same reasoning as WCAppOutputRoutingController::populateMenuForButton:forBundleID:,
// an app can launch or quit between menu opens.
- (void) menuNeedsUpdate:(NSMenu*)menu {
    if (menu != doNotDisturbPriorityAppSubmenu) {
        return;
    }

    [menu removeAllItems];

    NSString* __nullable currentBundleID = doNotDisturb.priorityAppBundleID;

    NSMenuItem* noneItem = [[NSMenuItem alloc] initWithTitle:@"None"
                                                        action:@selector(selectDoNotDisturbPriorityApp:)
                                                 keyEquivalent:@""];
    noneItem.target = self;
    noneItem.state = currentBundleID ? NSOffState : NSOnState;
    [menu addItem:noneItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSArray<NSRunningApplication*>* apps =
        [[NSWorkspace sharedWorkspace].runningApplications
            sortedArrayUsingComparator:^NSComparisonResult(NSRunningApplication* a, NSRunningApplication* b) {
                NSString* nameA = a.localizedName ?: @"";
                NSString* nameB = b.localizedName ?: @"";
                return [nameA localizedCaseInsensitiveCompare:nameB];
            }];

    for (NSRunningApplication* app in apps) {
        NSString* __nullable bundleID = app.bundleIdentifier;
        NSString* __nullable name = app.localizedName;

        if (!bundleID || !name || [BGMNN(bundleID) isEqualToString:@kBGMAppBundleID] ||
            (app.activationPolicy == NSApplicationActivationPolicyProhibited)) {
            // No bundle ID/name, Wavecraft itself, or a background-only process with no UI and
            // (almost always) no audio of its own -- same filtering WCAppVolumesController uses
            // for which apps get their own volume row.
            continue;
        }

        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:BGMNN(name)
                                                        action:@selector(selectDoNotDisturbPriorityApp:)
                                                 keyEquivalent:@""];
        item.target = self;
        item.representedObject = bundleID;
        item.state =
            (currentBundleID && [BGMNN(bundleID) isEqualToString:BGMNN(currentBundleID)]) ?
                NSOnState : NSOffState;
        [menu addItem:item];
    }
}

- (void) selectDoNotDisturbPriorityApp:(NSMenuItem*)sender {
    doNotDisturb.priorityAppBundleID = sender.representedObject;
    [self updateDoNotDisturbMenuItemStates];
}

- (void) updateDoNotDisturbMenuItemStates {
    doNotDisturbEnabledMenuItem.state = doNotDisturb.isEnabled ? NSOnState : NSOffState;

    NSString* __nullable priorityAppBundleID = doNotDisturb.priorityAppBundleID;
    NSString* __nullable priorityAppName = nil;

    if (priorityAppBundleID) {
        NSRunningApplication* __nullable app =
            [NSRunningApplication runningApplicationsWithBundleIdentifier:BGMNN(priorityAppBundleID)]
                .firstObject;
        priorityAppName = app.localizedName ?: priorityAppBundleID;
    }

    doNotDisturbPriorityAppMenuItem.title =
        [NSString stringWithFormat:@"Priority App: %@", priorityAppName ?: @"None"];
}

- (void) setXPCListener:(WCXPCListener*)xpcListener {
    [troubleshootMenu setXPCListener:xpcListener];
}

- (void) useBGMStatusBarIcon {
    // Change the icon.
    statusBarItem.icon = BGMWavecraftStatusBarIcon;

    // Select/deselect the menu items.
    bgmIconMenuItem.state = NSOnState;
    volumeIconMenuItem.state = NSOffState;
}

- (void) useVolumeStatusBarIcon {
    // TODO: Maybe we should show a message that tells the user how to hide the built-in volume
    //       icon. They probably won't want two status bar items that look the same. Or we might be
    //       able to automatically hide the built-in icon while BGMApp is running and show it again
    //       when BGMApp is closed.

    // Change the icon.
    statusBarItem.icon = BGMVolumeStatusBarIcon;

    // Select/deselect the menu items.
    bgmIconMenuItem.state = NSOffState;
    volumeIconMenuItem.state = NSOnState;
}

- (void) setupDelayPreferences:(NSMenu*)prefsMenu {
    // Create delay preference menu items dynamically, inserted right after the Auto-pause
    // player-picker list (which WCAutoPauseMusicPrefs, constructed just before this method runs,
    // has already inserted right after the "Auto-pause" header) instead of appended at the very
    // end of the whole Preferences menu -- this section configures the same feature, so it
    // belongs next to it, not buried after Status Bar Icon/About/Troubleshoot/Keyboard Shortcuts/
    // Do Not Disturb. tag="10" on the separator between "Auto-pause" and "Status Bar Icon" in
    // MainMenu.xib exists specifically to give this method a stable insertion point.
    NSInteger insertIndex = [prefsMenu indexOfItemWithTag:10];

    // Add separator
    [prefsMenu insertItem:[NSMenuItem separatorItem] atIndex:insertIndex];
    insertIndex++;

    // Add "Auto-pause Delays" header
    NSMenuItem* delaysHeader = [[NSMenuItem alloc] initWithTitle:@"Auto-pause Delays" action:nil keyEquivalent:@""];
    delaysHeader.enabled = NO;
    [prefsMenu insertItem:delaysHeader atIndex:insertIndex];
    insertIndex++;

    // Create pause delay menu item with slider
    pauseDelayMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSView* pauseDelayView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 25)];
    
    // Pause delay label
    NSTextField* pauseDelayTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 5, 100, 15)];
    pauseDelayTitleLabel.stringValue = @"Pause Delay:";
    pauseDelayTitleLabel.editable = NO;
    pauseDelayTitleLabel.bordered = NO;
    pauseDelayTitleLabel.backgroundColor = [NSColor clearColor];
    pauseDelayTitleLabel.font = [NSFont menuFontOfSize:13];
    [pauseDelayView addSubview:pauseDelayTitleLabel];
    
    // Pause delay slider
    pauseDelaySlider = [[NSSlider alloc] initWithFrame:NSMakeRect(115, 5, 100, 15)];
    [pauseDelayView addSubview:pauseDelaySlider];
    
    // Pause delay value label
    pauseDelayLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(220, 5, 55, 15)];
    pauseDelayLabel.editable = NO;
    pauseDelayLabel.bordered = NO;
    pauseDelayLabel.backgroundColor = [NSColor clearColor];
    pauseDelayLabel.font = [NSFont menuFontOfSize:11];
    [pauseDelayView addSubview:pauseDelayLabel];
    
    pauseDelayMenuItem.view = pauseDelayView;
    [prefsMenu insertItem:pauseDelayMenuItem atIndex:insertIndex];
    insertIndex++;

    // Create max unpause delay menu item with slider
    maxUnpauseDelayMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSView* maxUnpauseDelayView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 25)];
    
    // Max unpause delay label
    NSTextField* maxUnpauseDelayTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 5, 100, 15)];
    maxUnpauseDelayTitleLabel.stringValue = @"Max Unpause:";
    maxUnpauseDelayTitleLabel.editable = NO;
    maxUnpauseDelayTitleLabel.bordered = NO;
    maxUnpauseDelayTitleLabel.backgroundColor = [NSColor clearColor];
    maxUnpauseDelayTitleLabel.font = [NSFont menuFontOfSize:13];
    [maxUnpauseDelayView addSubview:maxUnpauseDelayTitleLabel];
    
    // Max unpause delay slider
    maxUnpauseDelaySlider = [[NSSlider alloc] initWithFrame:NSMakeRect(115, 5, 100, 15)];
    [maxUnpauseDelayView addSubview:maxUnpauseDelaySlider];
    
    // Max unpause delay value label
    maxUnpauseDelayLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(220, 5, 55, 15)];
    maxUnpauseDelayLabel.editable = NO;
    maxUnpauseDelayLabel.bordered = NO;
    maxUnpauseDelayLabel.backgroundColor = [NSColor clearColor];
    maxUnpauseDelayLabel.font = [NSFont menuFontOfSize:11];
    [maxUnpauseDelayView addSubview:maxUnpauseDelayLabel];
    
    maxUnpauseDelayMenuItem.view = maxUnpauseDelayView;
    [prefsMenu insertItem:maxUnpauseDelayMenuItem atIndex:insertIndex];
    
    // Initialize the delay sliders with current values and targets
    [self initDelaySliders];
}

- (void) initDelaySliders {
    // Configure pause delay slider with logarithmic scale (0ms to 10000ms)
    // Slider range 0-100 maps logarithmically to 0-10000ms
    pauseDelaySlider.minValue = 0;
    pauseDelaySlider.maxValue = 100;
    pauseDelaySlider.integerValue = [self msToSliderValue:userDefaults.pauseDelayMS];
    pauseDelaySlider.target = self;
    pauseDelaySlider.action = @selector(pauseDelaySliderChanged:);
    
    // Configure max unpause delay slider with logarithmic scale (0ms to 10000ms)
    // Slider range 0-100 maps logarithmically to 0-10000ms
    maxUnpauseDelaySlider.minValue = 0;
    maxUnpauseDelaySlider.maxValue = 100;
    maxUnpauseDelaySlider.integerValue = [self msToSliderValue:userDefaults.maxUnpauseDelayMS];
    maxUnpauseDelaySlider.target = self;
    maxUnpauseDelaySlider.action = @selector(maxUnpauseDelaySliderChanged:);
    
    // Update labels with current values
    [self updatePauseDelayLabel];
    [self updateMaxUnpauseDelayLabel];
}

- (void) pauseDelaySliderChanged:(NSSlider*)sender {
    NSUInteger delayMS = [self sliderValueToMS:sender.integerValue];
    userDefaults.pauseDelayMS = delayMS;
    [self updatePauseDelayLabel];
}

- (void) maxUnpauseDelaySliderChanged:(NSSlider*)sender {
    NSUInteger delayMS = [self sliderValueToMS:sender.integerValue];
    userDefaults.maxUnpauseDelayMS = delayMS;
    [self updateMaxUnpauseDelayLabel];
}


- (void) updatePauseDelayLabel {
    NSUInteger delayMS = userDefaults.pauseDelayMS;
    if (delayMS == 0) {
        pauseDelayLabel.stringValue = @"Off";
    } else {
        pauseDelayLabel.stringValue = [NSString stringWithFormat:@"%lums", (unsigned long)delayMS];
    }
}

- (void) updateMaxUnpauseDelayLabel {
    NSUInteger delayMS = userDefaults.maxUnpauseDelayMS;
    if (delayMS == 0) {
        maxUnpauseDelayLabel.stringValue = @"Off";
    } else {
        maxUnpauseDelayLabel.stringValue = [NSString stringWithFormat:@"%lums", (unsigned long)delayMS];
    }
}

// Logarithmic conversion methods for better control at small values
// Maps slider value (0-100) to milliseconds (0-10000) logarithmically
- (NSUInteger) sliderValueToMS:(NSInteger)sliderValue {
    if (sliderValue <= 0) {
        return 0;
    }
    
    // Logarithmic mapping: slider 0-100 -> ms 0-10000
    // Formula: ms = (10^(sliderValue/50) - 1) * (10000/99)
    // This gives finer control at small values and coarser control at large values
    double normalizedSlider = (double)sliderValue / 100.0; // 0-1
    double logValue = pow(10.0, normalizedSlider * 2.0) - 1.0; // 0-99
    NSUInteger ms = (NSUInteger)(logValue * (10000.0 / 99.0));
    
    return MIN(ms, 10000); // Cap at 10000ms
}

// Maps milliseconds (0-10000) to slider value (0-100) logarithmically
- (NSInteger) msToSliderValue:(NSUInteger)ms {
    if (ms == 0) {
        return 0;
    }
    
    // Inverse of the logarithmic mapping
    // Formula: sliderValue = 50 * log10((ms * 99/10000) + 1)
    double normalizedMS = (double)ms / 10000.0; // 0-1
    double logInput = (normalizedMS * 99.0) + 1.0; // 1-100
    double sliderValue = (log10(logInput) / 2.0) * 100.0; // 0-100
    
    return (NSInteger)MIN(MAX(sliderValue, 0), 100);
}

@end

NS_ASSUME_NONNULL_END

