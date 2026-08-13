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
#import "BGMMainPanelContentView.h"

// PublicUtility Includes
#import "CADebugMacros.h"


static float const   kSlidersSnapWithin          = 5;
static CGFloat const kAppVolumeViewInitialHeight = 20;

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
// BGMAppVolumes::insertRowForApp:... to find the show-more-controls button so its
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

// Deep-copies a view (with its whole subview hierarchy, including custom subclasses) via
// archiving, the standard technique for cloning a view that isn't loaded fresh from a nib each
// time -- NSView itself doesn't conform to NSCopying. Used once per app row, to get a fresh,
// independent copy of the appVolumeView template instead of the same instance being reused (and
// fought over) by every row.
static NSView* __nullable BGM_DeepCopyView(NSView* view) {
    NSError* __nullable archiveError;
    NSData* __nullable data = [NSKeyedArchiver archivedDataWithRootObject:view
                                                     requiringSecureCoding:NO
                                                                     error:&archiveError];

    if (!data) {
        DebugMsg("BGM_DeepCopyView: Failed to archive view: %s",
                 archiveError.description.UTF8String);
        return nil;
    }

    NSError* __nullable unarchiveError;
    NSKeyedUnarchiver* unarchiver =
        [[NSKeyedUnarchiver alloc] initForReadingFromData:BGMNN(data) error:&unarchiveError];

    if (!unarchiver) {
        DebugMsg("BGM_DeepCopyView: Failed to create unarchiver: %s",
                 unarchiveError.description.UTF8String);
        return nil;
    }

    unarchiver.requiresSecureCoding = NO;

    return [unarchiver decodeObjectOfClass:[NSView class] forKey:NSKeyedArchiveRootObjectKey];
}

@implementation BGMAppVolumes {
    BGMAppVolumesController* controller;

    NSStackView* yourAppsStack;
    NSStackView* systemAndOtherAppsStack;
    NSButton* systemAndOtherAppsDisclosureButton;

    NSView* appVolumeView;
    CGFloat appVolumeViewFullHeight;

    // Maps each running app to the row view showing its controls -- the identity-lookup mechanism
    // that replaced scanning NSMenuItem.representedObject across a fixed index range in the old
    // NSMenu-based design. Weak keys: this map shouldn't be what keeps an NSRunningApplication
    // alive past whenever NSWorkspace itself would.
    NSMapTable<NSRunningApplication*, NSView*>* appRowViews;
}

@synthesize outputRoutingController = outputRoutingController;

- (id) initWithController:(BGMAppVolumesController*)inController
             yourAppsStack:(NSStackView*)inYourAppsStack
   systemAndOtherAppsStack:(NSStackView*)inSystemAndOtherAppsStack
          disclosureButton:(NSButton*)inDisclosureButton
             appVolumeView:(NSView*)inView
  outputRoutingController:(BGMAppOutputRoutingController*)inOutputRoutingController {
    if ((self = [super init])) {
        controller = inController;
        yourAppsStack = inYourAppsStack;
        systemAndOtherAppsStack = inSystemAndOtherAppsStack;
        systemAndOtherAppsDisclosureButton = inDisclosureButton;
        appVolumeView = inView;
        appVolumeViewFullHeight = appVolumeView.frame.size.height;
        outputRoutingController = inOutputRoutingController;
        appRowViews = [NSMapTable weakToStrongObjectsMapTable];

        [self updateDisclosureButtonEnabled];
    }

    return self;
}

#pragma mark UI Modifications

- (void) insertRowForApp:(NSRunningApplication*)app
            initialVolume:(int)volume
               initialPan:(int)pan
       initialEQBandGains:(NSArray<NSNumber*>* __nullable)gainsDB {
    NSView* __nullable copiedRowView = BGM_DeepCopyView(appVolumeView);

    if (!copiedRowView) {
        DebugMsg("BGMAppVolumes::insertRowForApp: Failed to copy the app volume row template");
        return;
    }

    NSView* rowView = copiedRowView;

    // Look through the row's subviews for the ones we want to set up.
    for (NSView* subview in rowView.subviews) {
        if ([subview conformsToProtocol:@protocol(BGMAppVolumeMenuItemSubview)]) {
            [(NSView<BGMAppVolumeMenuItemSubview>*)subview setUpWithApp:app
                                                                  context:self
                                                               controller:controller
                                                                  rowView:rowView];
        }
    }

    [appRowViews setObject:rowView forKey:app];

    // Set the slider to the volume for this app if we got one from the driver.
    [self setVolumeOfRow:rowView relativeVolume:volume panPosition:pan];

    if (gainsDB) {
        [self setEQBandGainsOfRow:rowView gainsDB:BGMNN(gainsDB)];
    }

    // Now that pan/EQ have their real (possibly restored, non-default) values, sync the
    // show-more-controls button's highlight to match -- has to happen after both calls above, not
    // from BGMAVM_ShowMoreControlsButton::setUpWithApp: itself, since siblings don't have their
    // real values yet at that point in setup.
    [BGM_FindShowMoreControlsButton(rowView) bgm_syncHighlightForCurrentControls];

    if ([rowView respondsToSelector:@selector(setAccessibilityTitle:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        rowView.accessibilityTitle = [NSString stringWithFormat:@"%@", [app localizedName]];
#pragma clang diagnostic pop
    }

    NSView* row = [BGMMainPanelContentView rowContainerWithControl:rowView height:kBGMMainPanelRowHeight];

    if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
        [yourAppsStack addArrangedSubview:row];
    } else if (app.activationPolicy == NSApplicationActivationPolicyAccessory) {
        [systemAndOtherAppsStack addArrangedSubview:row];
        [self updateDisclosureButtonEnabled];
    }
}

// The "System & Other Apps" disclosure only makes sense to click when it actually has something
// behind it -- otherwise it's a clickable control that opens onto a visibly empty section, which
// happens whenever no NSApplicationActivationPolicyAccessory app is currently running (uncommon,
// but not rare: e.g. shortly after boot, or on a system with few background/menu-bar-only apps).
- (void) updateDisclosureButtonEnabled {
    systemAndOtherAppsDisclosureButton.enabled = (systemAndOtherAppsStack.arrangedSubviews.count > 0);
}

- (NSView* __nullable) getRowViewForApp:(NSRunningApplication*)app {
    return [appRowViews objectForKey:app];
}

- (BGMAppVolumeAndPan) getVolumeAndPanForApp:(NSRunningApplication*)app {
    BGMAppVolumeAndPan result = {
        .volume = -1,
        .pan = kAppPanNoValue
    };

    NSView* __nullable rowView = [self getRowViewForApp:app];

    if (rowView == nil) {
        return result;
    }

    for (NSView* subview in rowView.subviews) {
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
    NSView* __nullable rowView = [self getRowViewForApp:app];

    if (rowView == nil) {
        return;
    }

    for (NSView* subview in rowView.subviews) {
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

- (void) setVolumeOfRow:(NSView*)rowView relativeVolume:(int)volume panPosition:(int)pan {
    for (NSView* subview in rowView.subviews) {
        if (volume != -1 && [subview isKindOfClass:[BGMAVM_VolumeSlider class]]) {
            [(BGMAVM_VolumeSlider*)subview setRelativeVolume:volume];
        }

        if (pan != kAppPanNoValue && [subview isKindOfClass:[BGMAVM_PanSlider class]]) {
            [(BGMAVM_PanSlider*)subview setPanPosition:pan];
        }
    }
}

- (void) setEQBandGainsOfRow:(NSView*)rowView gainsDB:(NSArray<NSNumber*>*)gainsDB {
    for (NSView* subview in rowView.subviews) {
        if ([subview isKindOfClass:[BGMAVM_EQBandSlider class]]) {
            NSInteger band = ((BGMAVM_EQBandSlider*)subview).tag;
            if (band >= 0 && (NSUInteger)band < gainsDB.count) {
                [(BGMAVM_EQBandSlider*)subview setGainDB:gainsDB[(NSUInteger)band].floatValue];
            }
        }
    }
}

- (void) removeRowForApp:(NSRunningApplication*)app {
    NSView* __nullable rowView = [self getRowViewForApp:app];

    if (rowView == nil) {
        return;
    }

    NSView* __nullable row = rowView.superview;
    BOOL wasInSystemAndOtherApps = (row.superview == systemAndOtherAppsStack);

    [row removeFromSuperview];
    [appRowViews removeObjectForKey:app];

    if (wasInSystemAndOtherApps) {
        [self updateDisclosureButtonEnabled];
    }
}

- (void) showHideExtraControls:(BGMAVM_ShowMoreControlsButton*)button {
    // Show or hide an app's extra controls, currently only pan, in its app volume row.

    NSView* rowView = button.cell.representedObject;

    BGMAssert(button, "!button");
    BGMAssert(rowView, "!rowView");

    CGFloat width = rowView.frame.size.width;
#if DEBUG
    CGFloat height = rowView.frame.size.height;
#endif

    // Using this function (instead of just ==) shouldn't be necessary, but just in case.
#if DEBUG
    BOOL(^nearEnough)(CGFloat x, CGFloat y) = ^BOOL(CGFloat x, CGFloat y) {
        return fabs(x - y) < 0.01;  // We don't need much precision.
    };
#endif

    bool allSubviewsShowing = true;
    for (NSView* subview in rowView.subviews) {
        if (subview.hidden) {
            allSubviewsShowing = false;
            break;
        }
    }

    if (allSubviewsShowing) {
        // Hide extra controls.
        DebugMsg("BGMAppVolumes::showHideExtraControls: Hiding extra controls");

        BGMAssert(nearEnough(height, appVolumeViewFullHeight), "Extra controls were already hidden");

        // Make the row shorter to hide the extra controls. Keep the width unchanged.
        rowView.frameSize = NSMakeSize(width, kAppVolumeViewInitialHeight);
        [self updateRowContainerHeight:rowView.superview toMatchRowView:rowView];
        // Turn the button upside down so the arrowhead points down.
        button.frameCenterRotation = 180.0;
        // Move the button up slightly so it aligns with the volume slider.
        [button setFrameOrigin:NSMakePoint(button.frame.origin.x, button.frame.origin.y - 1)];

        // Set the extra controls, and anything else below the fold, to hidden so accessibility
        // clients can skip over them.
        for (NSView* subview in rowView.subviews) {
            CGFloat top = subview.frame.origin.y + subview.frame.size.height;
            if (top <= 0.0) {
                subview.hidden = YES;
            }
        }
    } else {
        // Show extra controls.
        DebugMsg("BGMAppVolumes::showHideExtraControls: Showing extra controls");

        BGMAssert(nearEnough(button.frameCenterRotation, 180.0), "Unexpected button rotation");
        BGMAssert(nearEnough(height, kAppVolumeViewInitialHeight), "Extra controls were already shown");

        // Make the row taller to show the extra controls. Keep the width unchanged.
        rowView.frameSize = NSMakeSize(width, appVolumeViewFullHeight);
        [self updateRowContainerHeight:rowView.superview toMatchRowView:rowView];
        // Turn the button rightside up so the arrowhead points up.
        button.frameCenterRotation = 0.0;
        // Move the button down slightly, back to its original position.
        [button setFrameOrigin:NSMakePoint(button.frame.origin.x, button.frame.origin.y + 1)];

        // Set all of the UI elements in the row to "not hidden" for accessibility clients.
        for (NSView* subview in rowView.subviews) {
            subview.hidden = NO;
        }
    }
}

// rowView's wrapping row container (see BGMMainPanelContentView.rowContainerWithControl:height:)
// has a fixed-height Auto Layout constraint, separate from rowView's own manually-managed
// frameSize -- collapsing/expanding rowView alone would leave the container's height stale (and
// the row's siblings in the stack wouldn't reflow around the new size) unless this constraint is
// updated to match every time.
- (void) updateRowContainerHeight:(NSView* __nullable)rowContainer toMatchRowView:(NSView*)rowView {
    for (NSLayoutConstraint* constraint in rowContainer.constraints) {
        if (constraint.firstAttribute == NSLayoutAttributeHeight) {
            constraint.constant = rowView.frame.size.height;
            return;
        }
    }
}

- (void) refreshRoutedIndicators {
    for (NSRunningApplication* app in appRowViews) {
        NSView* rowView = [appRowViews objectForKey:app];
        NSString* __nullable bundleID = app.bundleIdentifier;
        BOOL isRouted =
            bundleID && [outputRoutingController hasOutputOverrideForBundleID:BGMNN(bundleID)];

        for (NSView* subview in rowView.subviews) {
            if ([subview isKindOfClass:[BGMAVM_AppNameLabel class]]) {
                NSString* name = app.localizedName ? (NSString*)app.localizedName : @"";
                [self setAppNameLabel:(NSTextField*)subview toName:name isRouted:isRouted];
                break;
            }
        }
    }
}

// Sets appTitle's text to name, appending a small icon indicating an active output-route override
// when isRouted is true.
- (void) setAppNameLabel:(NSTextField*)appTitle toName:(NSString*)name isRouted:(BOOL)isRouted {
    if (!isRouted) {
        appTitle.stringValue = name;
        return;
    }

    NSMutableAttributedString* title =
        [[NSMutableAttributedString alloc] initWithString:[name stringByAppendingString:@"  "]];

    if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        NSImage* routedIcon = [NSImage imageWithSystemSymbolName:@"airplayaudio"
                                          accessibilityDescription:@"Output routed to another device"];
#pragma clang diagnostic pop
        NSTextAttachment* attachment = [NSTextAttachment new];
        attachment.image = routedIcon;
        // Sized and nudged to sit on the text baseline instead of towering over lowercase letters
        // the way an unscaled 17pt SF Symbol glyph does next to a system-size menu font.
        attachment.bounds = NSMakeRect(0, -2, 12, 10);
        [title appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    } else {
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:@"↦"]];
    }

    appTitle.attributedStringValue = title;
}

- (void) removeAllAppVolumeRows {
    for (NSView* row in [yourAppsStack.arrangedSubviews copy]) {
        [yourAppsStack removeArrangedSubview:row];
        [row removeFromSuperview];
    }

    for (NSView* row in [systemAndOtherAppsStack.arrangedSubviews copy]) {
        [systemAndOtherAppsStack removeArrangedSubview:row];
        [row removeFromSuperview];
    }

    [appRowViews removeAllObjects];

    [self updateDisclosureButtonEnabled];
}

@end

#pragma mark Custom Classes (IB)

// Custom classes for the UI elements in the app volume rows

@implementation BGMAVM_AppIcon

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
              rowView:(NSView*)rowView {
    #pragma unused (ctx, ctrl, rowView)

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
              rowView:(NSView*)rowView {
    #pragma unused (ctx, ctrl, rowView)

    NSString* name = app.localizedName ? (NSString*)app.localizedName : @"";
    self.stringValue = name;
}

@end

@implementation BGMAVM_ShowMoreControlsButton

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
              rowView:(NSView*)rowView {
    #pragma unused (app, ctrl)

    // Set up the button that show/hide the extra controls (currently only a pan slider) for the app.
    self.cell.representedObject = rowView;
    self.target = ctx;
    self.action = @selector(showHideExtraControls:);

    // The row starts out with the extra controls visible, so we hide them here.
    [ctx showHideExtraControls:self];

    // Not bgm_syncHighlightForCurrentControls here -- at this point in setup, sibling sliders in
    // the same row haven't had their real values written yet (that happens later, in
    // BGMAppVolumes::insertRowForApp:..., after every subview's setUpWithApp: has already run),
    // so every check here would see "all default" regardless of what's actually restored.
    // insertRowForApp:... calls bgm_syncHighlightForCurrentControls itself once real values are
    // in place.

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
              rowView:(NSView*)rowView {
#pragma unused (ctx, rowView)

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

    // Keep the row so we can sync the mute button when the slider changes.
    __weak NSView* rowView;
}

- (void) setUpWithApp:(NSRunningApplication*)app
              context:(BGMAppVolumes*)ctx
           controller:(BGMAppVolumesController*)ctrl
              rowView:(NSView*)inRowView {
    #pragma unused (ctx)

    controller = ctrl;
    rowView = inRowView;

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
    for (NSView* subview in rowView.subviews) {
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
              rowView:(NSView*)rowView {
    #pragma unused (ctx, rowView)

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
              rowView:(NSView*)rowView {
    #pragma unused (ctx, rowView)

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
              rowView:(NSView*)rowView {
    #pragma unused (ctrl, rowView)

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

// NSMenuDelegate. Rebuilds this button's own internal pop-up menu from the currently-connected
// output devices right before it's shown, so it's never stale (a device plugged/unplugged since
// the menu was last opened, or the routing state changing from elsewhere). This is a plain
// NSPopUpButton's own menu, independent of the main panel -- unaffected by this app's move off
// NSMenu for its main dropdown.
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
