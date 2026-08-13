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
//  BGMSetupWindow.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "BGMSetupWindow.h"

// Local Includes
#import "BGM_Utils.h"

// System Includes
#import <AVFoundation/AVCaptureDevice.h>
#import <ApplicationServices/ApplicationServices.h>


#pragma clang assume_nonnull begin

@implementation BGMSetupWindow {
    BGMSetupWindowContentView* setupContentView;
    BGMUserDefaults* userDefaults;

    BGMSetupWindowRow* microphoneRow;
    BGMSetupWindowRow* accessibilityRow;
}

- (instancetype) initWithUserDefaults:(BGMUserDefaults*)inUserDefaults {
    NSWindowStyleMask styleMask = (NSWindowStyleMaskTitled |
                                    NSWindowStyleMaskClosable |
                                    NSWindowStyleMaskMiniaturizable);

    self = [super initWithContentRect:NSZeroRect
                             styleMask:styleMask
                               backing:NSBackingStoreBuffered
                                 defer:NO];

    if (self) {
        userDefaults = inUserDefaults;

        self.title = @"Wavecraft Setup";
        self.releasedWhenClosed = NO;
        // Remembers where the user leaves it, like any normal document window -- there's no
        // "always reopen in the same spot below some anchor" reason not to, unlike the main panel.
        self.frameAutosaveName = @"BGMSetupWindow";

        setupContentView = [[BGMSetupWindowContentView alloc] initWithFrame:NSZeroRect];
        self.contentView = setupContentView;

        [self buildRows];
        [self sizeToFitContent];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                   selector:@selector(applicationDidBecomeActive:)
                                                       name:NSApplicationDidBecomeActiveNotification
                                                     object:nil];
    }

    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) buildRows {
    [setupContentView addIntroText:
        @"Wavecraft needs a couple of things from macOS to work fully, and one common surprise "
         "isn’t a permission at all. Here’s what each is for."];

    microphoneRow = [setupContentView
        addRowWithTitle:@"Microphone Access (required)"
                     body:@"Wavecraft uses a virtual microphone to capture your system’s audio, "
                           "so it can apply per-app volume, EQ, and output routing. It never "
                           "actually listens to anything — macOS just classifies that virtual "
                           "device as a microphone input."
                   status:BGMSetupRowStatusNotGranted
              buttonTitle:@"Open Privacy Settings"];
    [microphoneRow.button setTarget:self];
    [microphoneRow.button setAction:@selector(openMicrophonePrivacySettings:)];

    accessibilityRow = [setupContentView
        addRowWithTitle:@"Accessibility Access (optional)"
                     body:@"Only needed if you turn on global keyboard shortcuts for volume "
                           "control, in Preferences. macOS requires this for any app that "
                           "listens for keyboard shortcuts while it isn’t the active app."
                   status:BGMSetupRowStatusNotGranted
              buttonTitle:@"Open Privacy Settings"];
    [accessibilityRow.button setTarget:self];
    [accessibilityRow.button setAction:@selector(openAccessibilityPrivacySettings:)];

    [setupContentView
        addRowWithTitle:@"Don’t see the menu bar icon?"
                     body:@"If you use a menu bar organizer (Bartender, Ice, Hidden Bar, and "
                           "similar apps), Wavecraft’s icon may be tucked into a collapsed "
                           "section by default rather than missing — check there, or drag the "
                           "icon into the always-visible area."
                   status:BGMSetupRowStatusNone
              buttonTitle:nil];

    [self refreshPermissionStatuses];
}

- (void) sizeToFitContent {
    NSSize contentSize = setupContentView.fittingSize;
    [self setContentSize:contentSize];

    // Only frameAutosaveName restores a previous position; a first-ever show should still land
    // somewhere reasonable.
    if (![self setFrameUsingName:BGMNN(self.frameAutosaveName)]) {
        [self center];
    }
}

#pragma mark Show

- (void) show {
    [self refreshPermissionStatuses];

    [self setIsVisible:YES];
    [self makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void) showOnFirstLaunchIfNeeded {
    NSString* __nullable currentVersion =
        NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"];

    if (!currentVersion || [userDefaults.lastShownSetupWindowVersion isEqualToString:BGMNN(currentVersion)]) {
        return;
    }

    userDefaults.lastShownSetupWindowVersion = currentVersion;

    [self show];
}

#pragma mark Live status

// Catches the common flow of "click Open Privacy Settings, grant it, alt-tab back to Wavecraft"
// -- macOS doesn't notify apps directly when a permission they don't currently hold is granted,
// but it does tell every app when it becomes active again, which is a reasonable proxy here.
- (void) applicationDidBecomeActive:(NSNotification*)notification {
    #pragma unused (notification)

    if (self.visible) {
        [self refreshPermissionStatuses];
    }
}

- (void) refreshPermissionStatuses {
    [BGMSetupWindowContentView setStatus:[self microphoneStatus] onRow:microphoneRow];
    [BGMSetupWindowContentView setStatus:[self accessibilityStatus] onRow:accessibilityRow];
}

- (BGMSetupRowStatus) microphoneStatus {
    if (@available(macOS 10.14, *)) {
        AVAuthorizationStatus status =
            [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];

        return (status == AVAuthorizationStatusAuthorized) ? BGMSetupRowStatusGranted
                                                             : BGMSetupRowStatusNotGranted;
    }

    // Not required before 10.14.
    return BGMSetupRowStatusGranted;
}

- (BGMSetupRowStatus) accessibilityStatus {
    return AXIsProcessTrusted() ? BGMSetupRowStatusGranted : BGMSetupRowStatusNotGranted;
}

#pragma mark Actions

- (void) openMicrophonePrivacySettings:(id)sender {
    #pragma unused (sender)
    [self openSystemSettingsPane:@"Privacy_Microphone"];
}

- (void) openAccessibilityPrivacySettings:(id)sender {
    #pragma unused (sender)
    [self openSystemSettingsPane:@"Privacy_Accessibility"];
}

// Same x-apple.systempreferences: scheme BGMAppDelegate/BGMTroubleshootMenu already use to deep-
// link into Privacy & Security's sub-panes -- see BGMAppDelegate::openSysPrefsMicrophonePrivacy
// for why this scheme rather than the Scripting Bridge approach used elsewhere in this codebase.
- (void) openSystemSettingsPane:(NSString*)privacyPane {
    NSString* urlString =
        [NSString stringWithFormat:@"x-apple.systempreferences:com.apple.preference.security?%@",
                                    privacyPane];
    NSURL* __nullable url = [NSURL URLWithString:urlString];

    BOOL opened = url && [[NSWorkspace sharedWorkspace] openURL:BGMNN(url)];

    if (!opened) {
        NSLog(@"BGMSetupWindow::openSystemSettingsPane: Failed to open System Settings pane %@",
              privacyPane);
    }
}

@end

#pragma clang assume_nonnull end
