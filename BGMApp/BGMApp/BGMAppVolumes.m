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
//  BGMAppVolumes.m
//  BGMApp
//
//  Copyright © 2016-2020, 2026 Kyle Neideck
//  Copyright © 2017 Andrew Tonner
//  Copyright © 2021 Marcus Wu
//  Copyright © 2022 Jon Egan
//  Copyright © 2026 TwelfthFace
//

// Self Include
#import "BGMAppVolumes.h"

// Local Includes
#import "BGM_Types.h"
#import "BGM_Utils.h"
#import "BGMAppDelegate.h"
#import "BGMAppOutputRoutingController.h"

// PublicUtility Includes
#import "CADebugMacros.h"


static float const     kSlidersSnapWithin          = 5;
static CGFloat const   kAppVolumeViewInitialHeight = 20;
static NSString* const kMoreAppsMenuTitle          = @"More Apps";

// Labels for the EQ band sliders' tooltips/accessibility descriptions. Must be in the same order
// (lowest frequency first) as BGM_AppEQ::kBandCenterFreqs in BGM_Biquad.h -- there's no shared
// source of truth between the driver's C++ constants and this Objective-C UI code, so if the
// driver's bands ever change, these need to be updated to match.
//
// A plain C array rather than an NSArray literal because this file is compiled as Objective-C
// (not Objective-C++), where an @[...] literal isn't a compile-time constant and so can't
// initialize a file-scope static.
static const char* const kEQBandFreqLabels[] = {
    "31 Hz", "62 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"
};
static const NSUInteger kEQBandFreqLabelsCount =
    sizeof(kEQBandFreqLabels) / sizeof(kEQBandFreqLabels[0]);

// Shared by BGMAVM_PanSlider/BGMAVM_EQBandSlider's live-update paths and
// BGMAppVolumes::insertMenuItemForApp:... to find the show-more-controls button so its
// non-default-controls highlight can be kept in sync -- see
// BGMAVM_ShowMoreControlsButton::bgm_syncHighlightForCurrentControls.
static BGMAVM_ShowMoreControlsButton* __nullable BGM_FindShowMoreControlsButton(NSView* siblingContainer) {
    for (NSView* view in siblingContainer.subviews) {
        if ([view isKindOfClass:[BGMAVM_ShowMoreControlsButton class]]) {
            return (BGMAVM_ShowMoreControlsButton*)view;
        }
    }
    return nil;
}

@implementation BGMAppVolumes {
    BGMAppVolumesController* controller;

    NSMenu* bgmMenu;
    NSMenu* moreAppsMenu;
    NSMenuItem* moreAppsMenuItem;

    NSView* appVolumeView;
    CGFloat appVolumeViewFullHeight;

    // The number of menu items this class has added to bgmMenu. Doesn't include the More Apps menu.
    NSInteger numMenuItems;
}

@synthesize outputRoutingController = outputRoutingController;

- (id) initWithController:(BGMAppVolumesController*)inController
                  bgmMenu:(NSMenu*)inMenu
            appVolumeView:(NSView*)inView
  outputRoutingController:(BGMAppOutputRoutingController*)inOutputRoutingController {
    if ((self = [super init])) {
        controller = inController;
        bgmMenu = inMenu;
        moreAppsMenu = [[NSMenu alloc] initWithTitle:kMoreAppsMenuTitle];
        appVolumeView = inView;
        appVolumeViewFullHeight = appVolumeView.frame.size.height;
        numMenuItems = 0;
        outputRoutingController = inOutputRoutingController;

        // Add the More Apps menu to the main menu.
        moreAppsMenuItem =
            [[NSMenuItem alloc] initWithTitle:kMoreAppsMenuTitle action:nil keyEquivalent:@""];
        moreAppsMenuItem.submenu = moreAppsMenu;
        // Starts with nothing in it -- see updateMoreAppsMenuItemEnabled, called every time an app
        // is added to or removed from moreAppsMenu, for why this isn't just hardcoded to NO here.
        moreAppsMenuItem.enabled = NO;

        [bgmMenu insertItem:moreAppsMenuItem atIndex:([self lastMenuItemIndex] + 1)];
        numMenuItems++;

        // Put an empty menu item above the More Apps menu item to fix its top margin.
        NSMenuItem* spacer = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        spacer.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 4)];
        spacer.hidden = YES;  // Tells accessibility clients to ignore this menu item.

        [bgmMenu insertItem:spacer atIndex:[self lastMenuItemIndex]];
        numMenuItems++;
    }
    
    return self;
}

#pragma mark UI Modifications

- (void) insertMenuItemForApp:(NSRunningApplication*)app
                initialVolume:(int)volume
                   initialPan:(int)pan
           initialEQBandGains:(NSArray<NSNumber*>* __nullable)gainsDB {
    NSMenuItem* appVolItem = [self createBlankAppVolumeMenuItem];

    // Look through the menu item's subviews for the ones we want to set up
    for (NSView* subview in appVolItem.view.subviews) {
        if ([subview conformsToProtocol:@protocol(BGMAppVolumeMenuItemSubview)]) {
            [(NSView<BGMAppVolumeMenuItemSubview>*)subview setUpWithApp:app
                                                                context:self
                                                             controller:controller
                                                               menuItem:appVolItem];
        }
    }

    // Store the NSRunningApplication object with the menu item so when the app closes we can find the item to remove it
    appVolItem.representedObject = app;

    // Set the slider to the volume for this app if we got one from the driver
    [self setVolumeOfMenuItem:appVolItem relativeVolume:volume panPosition:pan];

    if (gainsDB) {
        [self setEQBandGainsOfMenuItem:appVolItem gainsDB:BGMNN(gainsDB)];
    }

    // Now that pan/EQ have their real (possibly restored, non-default) values, sync the
    // show-more-controls button's highlight to match -- has to happen after both calls above, not
    // from BGMAVM_ShowMoreControlsButton::setUpWithApp: itself, since siblings don't have their
    // real values yet at that point in setup.
    [BGM_FindShowMoreControlsButton(appVolItem.view) bgm_syncHighlightForCurrentControls];

    // NSMenuItem didn't implement NSAccessibility before OS X SDK 10.12.
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200  // MAC_OS_X_VERSION_10_12
    if ([appVolItem respondsToSelector:@selector(setAccessibilityTitle:)]) {
        // TODO: This doesn't show up in Accessibility Inspector for me. Not sure why.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        appVolItem.accessibilityTitle = [NSString stringWithFormat:@"%@", [app localizedName]];
#pragma clang diagnostic pop
    }
#endif

    // Add the menu item to its menu.
    if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
        [bgmMenu insertItem:appVolItem atIndex:[self firstMenuItemIndex]];
        numMenuItems++;
    } else if (app.activationPolicy == NSApplicationActivationPolicyAccessory) {
        [moreAppsMenu insertItem:appVolItem atIndex:0];
        [self updateMoreAppsMenuItemEnabled];
    }
}

// "More Apps" only makes sense to click when it actually has something in it -- otherwise it's a
// hoverable/clickable item that opens onto a visibly empty submenu, which happens whenever no
// NSApplicationActivationPolicyAccessory app is currently running (uncommon, but not rare: e.g.
// shortly after boot, or on a system with few background/menu-bar-only apps).
- (void) updateMoreAppsMenuItemEnabled {
    moreAppsMenuItem.enabled = (moreAppsMenu.numberOfItems > 0);
}

- (NSMenuItem*) getMenuItemForApp:(NSRunningApplication*)app {
    NSInteger lastAppVolumeMenuItemIndex = [self lastMenuItemIndex] - 2;

    for (NSInteger i = [self firstMenuItemIndex]; i <= lastAppVolumeMenuItemIndex; i++) {
        NSMenuItem* item = [bgmMenu itemAtIndex:i];
        NSRunningApplication* itemApp = item.representedObject;
        BGMAssert(itemApp, "!itemApp for %s", item.title.UTF8String);

        if ([itemApp isEqual:app]) {
            return item;
        }
    }
    for (NSInteger i = 0; i < [moreAppsMenu numberOfItems]; i++) {
        NSMenuItem* item = [moreAppsMenu itemAtIndex:i];
        NSRunningApplication* itemApp = item.representedObject;
        BGMAssert(itemApp, "!itemApp for %s", item.title.UTF8String);

        if ([itemApp isEqual:app]) {
            return item;
        }
    }

    return nil;
}

- (BGMAppVolumeAndPan) getVolumeAndPanForApp:(NSRunningApplication*)app {
    BGMAppVolumeAndPan result = {
        .volume = -1,
        .pan = kAppPanNoValue
    };

    NSMenuItem *item = [self getMenuItemForApp:app];

    if (item == nil) {
        return result;
    }

    for (NSView* subview in item.view.subviews) {
        // Get the volume.
        if ([subview isKindOfClass:[BGMAVM_VolumeSlider class]]) {
            result.volume = [(BGMAVM_VolumeSlider*)subview intValue];
        }

        // Get the pan position.
        if ([subview isKindOfClass:[BGMAVM_PanSlider class]]) {
            result.pan = [(BGMAVM_PanSlider*)subview intValue];
        }
    }

    return result;
}

- (void) setVolumeAndPan:(BGMAppVolumeAndPan)volumeAndPan forApp:(NSRunningApplication*)app {
    NSMenuItem *item = [self getMenuItemForApp:app];

    if (item == nil) {
        return;
    }

    for (NSView* subview in item.view.subviews) {
        // Set the volume.
        if (volumeAndPan.volume != -1 && [subview isKindOfClass:[BGMAVM_VolumeSlider class]]) {
            [(BGMAVM_VolumeSlider*)subview setRelativeVolume:volumeAndPan.volume];
        }

        // Set the pan position.
        if (volumeAndPan.pan != kAppPanNoValue && [subview isKindOfClass:[BGMAVM_PanSlider class]]) {
            [(BGMAVM_PanSlider*)subview setPanPosition:volumeAndPan.pan];
        }
    }

}

// Create a blank menu item to copy as a template.
- (NSMenuItem*) createBlankAppVolumeMenuItem {
    NSMenuItem* menuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    
    menuItem.view = appVolumeView;
    menuItem = [menuItem copy];  // So we can modify a copy of the view, rather than the template itself.
    
    return menuItem;
}

- (void) setVolumeOfMenuItem:(NSMenuItem*)menuItem relativeVolume:(int)volume panPosition:(int)pan {
    // Update the sliders.
    for (NSView* subview in menuItem.view.subviews) {
        // Set the volume.
        if (volume != -1 && [subview isKindOfClass:[BGMAVM_VolumeSlider class]]) {
            [(BGMAVM_VolumeSlider*)subview setRelativeVolume:volume];
        }

        // Set the pan position.
        if (pan != kAppPanNoValue && [subview isKindOfClass:[BGMAVM_PanSlider class]]) {
            [(BGMAVM_PanSlider*)subview setPanPosition:pan];
        }
    }
}

- (void) setEQBandGainsOfMenuItem:(NSMenuItem*)menuItem gainsDB:(NSArray<NSNumber*>*)gainsDB {
    for (NSView* subview in menuItem.view.subviews) {
        if ([subview isKindOfClass:[BGMAVM_EQBandSlider class]]) {
            NSInteger band = ((BGMAVM_EQBandSlider*)subview).tag;
            if (band >= 0 && (NSUInteger)band < gainsDB.count) {
                [(BGMAVM_EQBandSlider*)subview setGainDB:gainsDB[(NSUInteger)band].floatValue];
            }
        }
    }
}

- (NSInteger) firstMenuItemIndex {
    return [self lastMenuItemIndex] - numMenuItems + 1;
}

- (NSInteger) lastMenuItemIndex {
    return [bgmMenu indexOfItemWithTag:kSeparatorBelowVolumesMenuItemTag] - 1;
}

- (void) removeMenuItemForApp:(NSRunningApplication*)app {
    // Subtract two extra positions to skip the More Apps menu and the spacer menu item above it.
    NSInteger lastAppVolumeMenuItemIndex = [self lastMenuItemIndex] - 2;

    // Check each app volume menu item and remove the item that controls the given app.

    // Look through the main menu.
    for (NSInteger i = [self firstMenuItemIndex]; i <= lastAppVolumeMenuItemIndex; i++) {
        NSMenuItem* item = [bgmMenu itemAtIndex:i];
        NSRunningApplication* itemApp = item.representedObject;
        BGMAssert(itemApp, "!itemApp for %s", item.title.UTF8String);

        if ([itemApp isEqual:app]) {
            [bgmMenu removeItem:item];
            numMenuItems--;
            return;
        }
    }

    // Look through the More Apps menu.
    for (NSInteger i = 0; i < [moreAppsMenu numberOfItems]; i++) {
        NSMenuItem* item = [moreAppsMenu itemAtIndex:i];
        NSRunningApplication* itemApp = item.representedObject;
        BGMAssert(itemApp, "!itemApp for %s", item.title.UTF8String);

        if ([itemApp isEqual:app]) {
            [moreAppsMenu removeItem:item];
            [self updateMoreAppsMenuItemEnabled];
            return;
        }
    }
}

- (void) showHideExtraControls:(BGMAVM_ShowMoreControlsButton*)button {
    // Show or hide an app's extra controls, currently only pan, in its App Volumes menu item.
    
    NSMenuItem* menuItem = button.cell.representedObject;
    
    BGMAssert(button, "!button");
    BGMAssert(menuItem, "!menuItem");

    CGFloat width = menuItem.view.frame.size.width;
#if DEBUG
    CGFloat height = menuItem.view.frame.size.height;
#endif

    const char* appName =
        [((NSRunningApplication*)menuItem.representedObject).localizedName UTF8String];

    // Using this function (instead of just ==) shouldn't be necessary, but just in case.
#if DEBUG
    BOOL(^nearEnough)(CGFloat x, CGFloat y) = ^BOOL(CGFloat x, CGFloat y) {
        return fabs(x - y) < 0.01;  // We don't need much precision.
    };
#endif
    
    bool allSubviewsShowing = true;
    for (NSView* subview in menuItem.view.subviews) {
        if (subview.hidden) {
            allSubviewsShowing = false;
            break;
        }
        //DebugMsg("BGMAppVolumes:: subview hash / hidden: (%lu) / (%hhd)", (unsigned long)subview.hash, subview.hidden);
    }

    if (allSubviewsShowing) {
        // Hide extra controls
        DebugMsg("BGMAppVolumes::showHideExtraControls: Hiding extra controls (%s)", appName);
        
        BGMAssert(nearEnough(height, appVolumeViewFullHeight), "Extra controls were already hidden");
        
        // Make the menu item shorter to hide the extra controls. Keep the width unchanged.
        menuItem.view.frameSize = NSMakeSize(width, kAppVolumeViewInitialHeight);
        // Turn the button upside down so the arrowhead points down.
        button.frameCenterRotation = 180.0;
        // Move the button up slightly so it aligns with the volume slider.
        [button setFrameOrigin:NSMakePoint(button.frame.origin.x, button.frame.origin.y - 1)];

        // Set the extra controls, and anything else below the fold, to hidden so accessibility
        // clients can skip over them.
        for (NSView* subview in menuItem.view.subviews) {
            CGFloat top = subview.frame.origin.y + subview.frame.size.height;
            if (top <= 0.0) {
                subview.hidden = YES;
            }
        }
    } else {
        // Show extra controls
        DebugMsg("BGMAppVolumes::showHideExtraControls: Showing extra controls (%s)", appName);
        
        BGMAssert(nearEnough(button.frameCenterRotation, 180.0), "Unexpected button rotation");
        BGMAssert(nearEnough(height, kAppVolumeViewInitialHeight), "Extra controls were already shown");
        
        // Make the menu item taller to show the extra controls. Keep the width unchanged.
        menuItem.view.frameSize = NSMakeSize(width, appVolumeViewFullHeight);
        // Turn the button rightside up so the arrowhead points up.
        button.frameCenterRotation = 0.0;
        // Move the button down slightly, back to its original position.
        [button setFrameOrigin:NSMakePoint(button.frame.origin.x, button.frame.origin.y + 1)];

        // Set all of the UI elements in the menu item to "not hidden" for accessibility clients.
        for (NSView* subview in menuItem.view.subviews) {
            subview.hidden = NO;
        }
    }
}

- (void) removeAllAppVolumeMenuItems {
    // Remove all of the menu items this class adds to the menu except for the last two, which are
    // the More Apps menu item and the invisible spacer above it.
    while (numMenuItems > 2) {
        [bgmMenu removeItemAtIndex:[self firstMenuItemIndex]];
        numMenuItems--;
    }

    // The More Apps menu only contains app volume menu items, so we can just remove everything.
    [moreAppsMenu removeAllItems];
    [self updateMoreAppsMenuItemEnabled];
}

@end

#pragma mark Custom Classes (IB)

// Custom classes for the UI elements in the app volume menu items

@implementation BGMAVM_AppIcon

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
             menuItem:(NSMenuItem*)menuItem {
    #pragma unused (ctx, ctrl, menuItem)
    
    self.image = app.icon;

    // Remove the icon from the accessibility hierarchy.
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101000  // MAC_OS_X_VERSION_10_10
    if ([self.cell respondsToSelector:@selector(setAccessibilityElement:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.cell.accessibilityElement = NO;
#pragma clang diagnostic pop
    }
#endif
}

@end

@implementation BGMAVM_AppNameLabel

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
             menuItem:(NSMenuItem*)menuItem {
    #pragma unused (ctx, ctrl, menuItem)
    
    NSString* name = app.localizedName ? (NSString*)app.localizedName : @"";
    self.stringValue = name;
}

@end

@implementation BGMAVM_ShowMoreControlsButton

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
             menuItem:(NSMenuItem*)menuItem {
    #pragma unused (app, ctrl)

    // Set up the button that show/hide the extra controls (currently only a pan slider) for the app.
    self.cell.representedObject = menuItem;
    self.target = ctx;
    self.action = @selector(showHideExtraControls:);

    // The menu item starts out with the extra controls visible, so we hide them here.
    [ctx showHideExtraControls:self];

    // Not bgm_syncHighlightForCurrentControls here -- at this point in setup, sibling sliders in
    // the same menu item view haven't had their real values written yet (that happens later, in
    // BGMAppVolumes::insertMenuItemForApp:..., after every subview's setUpWithApp: has already
    // run), so every check here would see "all default" regardless of what's actually restored.
    // insertMenuItemForApp:... calls bgm_syncHighlightForCurrentControls itself once real values
    // are in place.

    // toolTip, not just accessibilityTitle -- this caret is the only way to discover the Pan/EQ/
    // Output Routing controls exist at all, and accessibilityTitle alone only reaches VoiceOver
    // users. A sighted person hovering it should get the same explanation.
    self.toolTip = @"More controls (Pan, EQ, Output Routing)";

    if ([self respondsToSelector:@selector(setAccessibilityTitle:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.accessibilityTitle = @"More options";
#pragma clang diagnostic pop
    }
}

- (void) bgm_syncHighlightForCurrentControls {
    BOOL hasNonDefaultControls = NO;

    for (NSView* view in self.superview.subviews) {
        if ([view isKindOfClass:[BGMAVM_EQBandSlider class]]) {
            if (((NSSlider*)view).floatValue != 0.0f) {
                hasNonDefaultControls = YES;
                break;
            }
        } else if ([view isKindOfClass:[BGMAVM_PanSlider class]]) {
            if (((NSSlider*)view).intValue != kAppPanCenterRawValue) {
                hasNonDefaultControls = YES;
                break;
            }
        }
    }

    if ([self respondsToSelector:@selector(setContentTintColor:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.contentTintColor = hasNonDefaultControls ? [NSColor controlAccentColor] : nil;
#pragma clang diagnostic pop
    }

    self.toolTip = hasNonDefaultControls ?
        @"More controls (Pan, EQ, Output Routing) -- Pan or EQ is set on this app" :
        @"More controls (Pan, EQ, Output Routing)";

    if ([self respondsToSelector:@selector(setAccessibilityTitle:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.accessibilityTitle =
            hasNonDefaultControls ? @"More options (pan or EQ set)" : @"More options";
#pragma clang diagnostic pop
    }
}

@end

@implementation BGMAVM_VolumeMute {
    pid_t appProcessID;
    NSString* __nullable appBundleID;
    BGMAppVolumesController* controller;
}

- (NSString*) lastNonZeroVolumeDefaultsKey {
    if (appBundleID.length > 0) {
        return [NSString stringWithFormat:@"BGMAVM_LastNonZeroVolume_%@", appBundleID];
    }
    return [NSString stringWithFormat:@"BGMAVM_LastNonZeroVolume_pid_%d", appProcessID];
}

- (BOOL) isMuted:(int)value {
    return value <= kAppRelativeVolumeMinRawValue;
}

- (int) defaultRestoreVolume {
    return (int)((kAppRelativeVolumeMaxRawValue + kAppRelativeVolumeMinRawValue) / 2);
}

- (BGMAVM_VolumeSlider* __nullable) findSiblingVolumeSlider {
    for (NSView* view in self.superview.subviews) {
        if ([view isKindOfClass:[BGMAVM_VolumeSlider class]]) {
            return (BGMAVM_VolumeSlider*)view;
        }
    }
    return nil;
}

- (void) updateButtonForVolume:(int)volume {
    BOOL muted = [self isMuted:volume];

    if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        NSString* symbol = muted ? @"speaker.slash.fill" : @"speaker.wave.2.fill";
        NSString* description = muted ? @"Unmute" : @"Mute";
        self.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:description];
#pragma clang diagnostic pop
        self.imagePosition = NSImageOnly;
        self.title = @"";
    } else {
        self.title = muted ? @"Unmute" : @"Mute";
    }
}

- (void) bgm_syncForVolume:(int)volume {
    [self updateButtonForVolume:volume];
}

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
             menuItem:(NSMenuItem*)menuItem {
#pragma unused (ctx, menuItem)

    controller = ctrl;
    appProcessID = app.processIdentifier;
    appBundleID = app.bundleIdentifier;

    self.target = self;
    self.action = @selector(mutePressed:);

    BGMAVM_VolumeSlider* slider = [self findSiblingVolumeSlider];
    int currentVol = slider ? slider.intValue : kAppRelativeVolumeMinRawValue;
    [self updateButtonForVolume:currentVol];
}

- (IBAction) mutePressed:(id)sender {
#pragma unused(sender)

    BGMAVM_VolumeSlider* slider = [self findSiblingVolumeSlider];
    if (!slider) {
        DebugMsg("Mute button: no slider found");
        return;
    }

    int currentVol = slider.intValue;
    BOOL mutedNow = [self isMuted:currentVol];

    if (!mutedNow) {
        // Store last volume
        [[NSUserDefaults standardUserDefaults] setInteger:currentVol
                                                   forKey:[self lastNonZeroVolumeDefaultsKey]];

        [slider setRelativeVolume:kAppRelativeVolumeMinRawValue];
    } else {
        NSInteger last = [[NSUserDefaults standardUserDefaults] integerForKey:[self lastNonZeroVolumeDefaultsKey]];
        int restoreVol = (int)last;

        if (restoreVol <= kAppRelativeVolumeMinRawValue ||
            restoreVol > kAppRelativeVolumeMaxRawValue) {
            restoreVol = [self defaultRestoreVolume];
        }

        [slider setRelativeVolume:restoreVol];
    }

    [controller setVolume:slider.intValue
      forAppWithProcessID:appProcessID
                 bundleID:appBundleID];

    [self updateButtonForVolume:slider.intValue];
}

@end

@implementation BGMAVM_VolumeSlider {
    // Will be set to -1 for apps without a pid
    pid_t appProcessID;
    NSString* __nullable appBundleID;
    BGMAppVolumesController* controller;

    // Keep the menu item so we can sync the mute button when the slider changes.
    __weak NSMenuItem* menuItem;
}

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
             menuItem:(NSMenuItem*)inMenuItem {
    #pragma unused (ctx)
    
    controller = ctrl;
    menuItem = inMenuItem;
    
    self.target = self;
    self.action = @selector(appVolumeChanged);
    
    appProcessID = app.processIdentifier;
    appBundleID = app.bundleIdentifier;
    
    self.maxValue = kAppRelativeVolumeMaxRawValue;
    self.minValue = kAppRelativeVolumeMinRawValue;

    if ([self respondsToSelector:@selector(setAccessibilityTitle:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.accessibilityTitle = [NSString stringWithFormat:@"Volume for %@", [app localizedName]];
#pragma clang diagnostic pop
    }
}

// We have to handle snapping for volume sliders ourselves because adding a tick mark (snap point) in Interface Builder
// changes how the slider looks.
- (void) snap {
    // Snap to the 50% point.
    float midPoint = (float)((self.maxValue + self.minValue) / 2);
    if (self.floatValue > (midPoint - kSlidersSnapWithin) && self.floatValue < (midPoint + kSlidersSnapWithin)) {
        self.floatValue = midPoint;
    }
}

- (void) setRelativeVolume:(int)relativeVolume {
    self.intValue = relativeVolume;
    [self snap];
}

- (void) appVolumeChanged {
    // TODO: This (sending updates to the driver) should probably be rate-limited. It uses a fair bit of CPU for me.
    
    DebugMsg("BGMAppVolumes::appVolumeChanged: App volume for %s (%d) changed to %d",
             appBundleID.UTF8String,
             appProcessID,
             self.intValue);
    
    [self snap];

    // The values from our sliders are in
    // [kAppRelativeVolumeMinRawValue, kAppRelativeVolumeMaxRawValue] already.
    [controller setVolume:self.intValue forAppWithProcessID:appProcessID bundleID:appBundleID];

    // Sync the mute button so it reflects muted/unmuted when the user drags the slider.
    for (NSView* subview in menuItem.view.subviews) {
        if ([subview isKindOfClass:[BGMAVM_VolumeMute class]]) {
            [(BGMAVM_VolumeMute*)subview bgm_syncForVolume:self.intValue];
        }
    }
}

@end

@implementation BGMAVM_PanSlider {
    // Will be set to -1 for apps without a pid
    pid_t appProcessID;
    NSString* __nullable appBundleID;
    BGMAppVolumesController* controller;
}

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
             menuItem:(NSMenuItem*)menuItem {
    #pragma unused (ctx, menuItem)
    
    controller = ctrl;
    
    self.target = self;
    self.action = @selector(appPanPositionChanged);
    
    appProcessID = app.processIdentifier;
    appBundleID = app.bundleIdentifier;
    
    self.minValue = kAppPanLeftRawValue;
    self.maxValue = kAppPanRightRawValue;

    if ([self respondsToSelector:@selector(setAccessibilityTitle:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.accessibilityTitle = [NSString stringWithFormat:@"Pan for %@", [app localizedName]];
#pragma clang diagnostic pop
    }
}

- (void) setPanPosition:(int)panPosition {
    self.intValue = panPosition;
}

- (void) appPanPositionChanged {
    // TODO: This (sending updates to the driver) should probably be rate-limited. It uses a fair bit of CPU for me.
    
    DebugMsg("BGMAppVolumes::appPanPositionChanged: App pan position for %s changed to %d", appBundleID.UTF8String, self.intValue);

    // The values from our sliders are in [kAppPanLeftRawValue, kAppPanRightRawValue] already.
    [controller setPanPosition:self.intValue forAppWithProcessID:appProcessID bundleID:appBundleID];

    [BGM_FindShowMoreControlsButton(self.superview) bgm_syncHighlightForCurrentControls];
}

@end

@implementation BGMAVM_EQBandSlider {
    pid_t appProcessID;
    NSString* __nullable appBundleID;
    BGMAppVolumesController* controller;
}

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
             menuItem:(NSMenuItem*)menuItem {
    #pragma unused (ctx, menuItem)

    controller = ctrl;

    self.target = self;
    self.action = @selector(appEQGainChanged);

    appProcessID = app.processIdentifier;
    appBundleID = app.bundleIdentifier;

    self.minValue = kBGMAppEQMinGainDB;
    self.maxValue = kBGMAppEQMaxGainDB;

    NSString* freqLabel =
        (self.tag >= 0 && (NSUInteger)self.tag < kEQBandFreqLabelsCount) ?
            @(kEQBandFreqLabels[(NSUInteger)self.tag]) : @"";

    self.toolTip = [NSString stringWithFormat:@"%@ EQ gain for %@", freqLabel, [app localizedName]];

    if ([self respondsToSelector:@selector(setAccessibilityTitle:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.accessibilityTitle = self.toolTip;
#pragma clang diagnostic pop
    }
}

- (void) setGainDB:(float)gainDB {
    self.floatValue = gainDB;
}

// Returns this slider's siblings (including itself), sorted by band index (their IB "tag"), so
// callers always send the driver a complete, correctly-ordered set of band gains.
- (NSArray<BGMAVM_EQBandSlider*>*) siblingBandSlidersIncludingSelf {
    NSMutableArray<BGMAVM_EQBandSlider*>* sliders = [NSMutableArray new];

    for (NSView* view in self.superview.subviews) {
        if ([view isKindOfClass:[BGMAVM_EQBandSlider class]]) {
            [sliders addObject:(BGMAVM_EQBandSlider*)view];
        }
    }

    [sliders sortUsingComparator:^NSComparisonResult(BGMAVM_EQBandSlider* a, BGMAVM_EQBandSlider* b) {
        return [@(a.tag) compare:@(b.tag)];
    }];

    return sliders;
}

- (void) appEQGainChanged {
    NSArray<BGMAVM_EQBandSlider*>* sliders = [self siblingBandSlidersIncludingSelf];

    if (sliders.count != kBGMAppEQNumBands) {
        DebugMsg("BGMAppVolumes::appEQGainChanged: Expected %d EQ band sliders, found %lu",
                 kBGMAppEQNumBands,
                 (unsigned long)sliders.count);
        return;
    }

    NSMutableArray<NSNumber*>* gainsDB = [NSMutableArray arrayWithCapacity:sliders.count];
    for (BGMAVM_EQBandSlider* slider in sliders) {
        [gainsDB addObject:@(slider.floatValue)];
    }

    DebugMsg("BGMAppVolumes::appEQGainChanged: EQ gains for %s (%d) changed to %s",
             appBundleID.UTF8String,
             appProcessID,
             gainsDB.description.UTF8String);

    [controller setEQBandGains:gainsDB forAppWithProcessID:appProcessID bundleID:appBundleID];

    [BGM_FindShowMoreControlsButton(self.superview) bgm_syncHighlightForCurrentControls];
}

@end

@implementation BGMAVM_OutputRouteButton {
    NSString* __nullable appBundleID;
    NSString* __nullable appName;
    BGMAppOutputRoutingController* routingController;
}

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
             menuItem:(NSMenuItem*)menuItem {
    #pragma unused (ctrl, menuItem)

    appBundleID = app.bundleIdentifier;
    appName = app.localizedName;
    routingController = ctx.outputRoutingController;

    self.target = self;
    self.action = @selector(deviceSelected);
    self.menu.delegate = self;
    self.pullsDown = NO;

    NSString* toolTip;

    // Per-app output routing needs macOS 26+ (BGMTapRoute.mm gates on
    // CATapDescription.processRestoreEnabled) -- without this check, the pop-up looked identical
    // and fully usable on any older system, and only failed with an alert *after* the user had
    // already picked a device, with no earlier hint it was never going to work on their Mac.
    if (@available(macOS 26.0, *)) {
        self.enabled = YES;
        toolTip = [NSString stringWithFormat:@"Route %@'s audio to a different output device -- "
                                               "click more than one to play through all of them "
                                               "at once",
                                              appName ? appName : @"this app"];
    } else {
        self.enabled = NO;
        toolTip = @"Per-app output routing needs macOS 26 or later.";
    }

    self.toolTip = toolTip;

    if ([self respondsToSelector:@selector(setAccessibilityTitle:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.accessibilityTitle = toolTip;
#pragma clang diagnostic pop
    }
}

// NSMenuDelegate. Rebuilds this button's menu from the currently-connected output devices right
// before it's shown, so it's never stale (a device plugged/unplugged since the menu was last
// opened, or the routing state changing from elsewhere).
- (void) menuNeedsUpdate:(NSMenu*)menu {
    #pragma unused (menu)

    if (appBundleID) {
        [routingController populateMenuForButton:self forBundleID:BGMNN(appBundleID)];
    }
}

- (void) deviceSelected {
    if (!appBundleID) {
        return;
    }

    // The "Default" item has no representedObject; every other item's is the device's UID -- see
    // BGMAppOutputRoutingController::populateMenuForButton:forBundleID:. Clicking "Default" clears
    // every target device at once; clicking a device toggles just that one in or out of the set,
    // leaving any others already selected alone -- so routing to more than one device at a time is
    // a few clicks (reopening the pop-up and picking another device each time), not a single
    // multi-select gesture.
    NSString* __nullable deviceUID = self.selectedItem.representedObject;

    if (deviceUID) {
        [routingController userToggledDeviceUID:BGMNN(deviceUID)
                              forAppWithBundleID:BGMNN(appBundleID)
                                         appName:appName];
    } else {
        [routingController userSelectedDefaultForAppWithBundleID:BGMNN(appBundleID)
                                                           appName:appName];
    }
}

@end

