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
//  WCSetupWindow.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "WCSetupWindow.h"

// Local Includes
#import "BGM_Utils.h"

// System Includes
#import <AVFoundation/AVCaptureDevice.h>
#import <ApplicationServices/ApplicationServices.h>


#pragma clang assume_nonnull begin

@implementation WCSetupWindow {
    WCSetupWindowContentView* setupContentView;
    WCUserDefaults* userDefaults;

    WCSetupWindowRow* microphoneRow;
    WCSetupWindowRow* accessibilityRow;
}

- (instancetype) initWithUserDefaults:(WCUserDefaults*)inUserDefaults {
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
        self.frameAutosaveName = @"WCSetupWindow";

        setupContentView = [[WCSetupWindowContentView alloc] initWithFrame:NSZeroRect];
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
    [setupContentView addHeaderWithTitle:@"Welcome to Wavecraft"
                                 subtitle:@"Setup & Permissions"];

    [setupContentView addIntroText:
        @"A couple of things from macOS get Wavecraft fully working, and one common surprise "
         "isn’t a permission at all. Here’s what each is for."];

    microphoneRow = [setupContentView
        addRowWithTitle:@"Microphone Access (required)"
                     body:@"Wavecraft uses a virtual microphone to capture your system’s audio, "
                           "so it can apply per-app volume, EQ, and output routing. It never "
                           "actually listens to anything — macOS just classifies that virtual "
                           "device as a microphone input. Click below and macOS will ask you to "
                           "confirm."
                   status:BGMSetupRowStatusNotGranted
              buttonTitle:@"Grant Access"];
    [microphoneRow.button setTarget:self];
    [microphoneRow.button setAction:@selector(microphoneButtonClicked:)];

    accessibilityRow = [setupContentView
        addRowWithTitle:@"Accessibility Access (optional)"
                     body:@"Only needed if you turn on global keyboard shortcuts for volume "
                           "control, in Preferences. macOS requires this for any app that "
                           "listens for keyboard shortcuts while it isn’t the active app."
                   status:BGMSetupRowStatusNotGranted
              buttonTitle:@"Grant Access"];
    [accessibilityRow.button setTarget:self];
    [accessibilityRow.button setAction:@selector(accessibilityButtonClicked:)];

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

- (BOOL) showOnFirstLaunchIfNeeded {
    NSString* __nullable currentVersion =
        NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"];

    if (!currentVersion || [userDefaults.lastShownSetupWindowVersion isEqualToString:BGMNN(currentVersion)]) {
        return NO;
    }

    userDefaults.lastShownSetupWindowVersion = currentVersion;

    [self show];

    return YES;
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
    [self updateMicrophoneRow];
    [self updateAccessibilityRow];
}

// Unlike Accessibility (a plain trusted/not-trusted bool), Microphone access has a real third
// state: once the system dialog's been answered with "Don't Allow", calling
// requestAccessForMediaType: again doesn't re-show it -- it just calls back immediately with
// granted=NO, silently. So the button has to do a different thing depending on which of the two
// not-granted states it's actually in, or a second click after a denial would look like it did
// nothing at all.
- (void) updateMicrophoneRow {
    // @available's flow analysis doesn't cross a method-call boundary -- a separate
    // "is this available" helper called first wouldn't satisfy the compiler here, every actual
    // AVFoundation call site needs its own guard directly (same trap noted in
    // WCAppDelegate::requestMicrophoneAccess's header comment).
    if (@available(macOS 10.14, *)) {
        AVAuthorizationStatus status =
            [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];

        switch (status) {
            case AVAuthorizationStatusAuthorized:
                [WCSetupWindowContentView setStatus:BGMSetupRowStatusGranted onRow:microphoneRow];
                microphoneRow.button.hidden = YES;
                break;

            case AVAuthorizationStatusNotDetermined:
                [WCSetupWindowContentView setStatus:BGMSetupRowStatusNotGranted
                                                onRow:microphoneRow];
                microphoneRow.button.hidden = NO;
                microphoneRow.button.title = @"Grant Access";
                break;

            case AVAuthorizationStatusDenied:
            case AVAuthorizationStatusRestricted:
            default:
                [WCSetupWindowContentView setStatus:BGMSetupRowStatusNotGranted
                                                onRow:microphoneRow];
                microphoneRow.button.hidden = NO;
                microphoneRow.button.title = @"Open Privacy Settings";
                break;
        }
    } else {
        // Not required before 10.14 -- nothing to grant, nothing to click.
        [WCSetupWindowContentView setStatus:BGMSetupRowStatusGranted onRow:microphoneRow];
        microphoneRow.button.hidden = YES;
    }
}

- (void) updateAccessibilityRow {
    BOOL trusted = AXIsProcessTrusted();

    [WCSetupWindowContentView setStatus:(trusted ? BGMSetupRowStatusGranted
                                                    : BGMSetupRowStatusNotGranted)
                                    onRow:accessibilityRow];
    accessibilityRow.button.hidden = trusted;
    accessibilityRow.button.title = @"Grant Access";
}

#pragma mark Actions

// Requests access directly (macOS's own system dialog) when it's never been asked, or deep-links
// to Settings when it has and was declined -- see updateMicrophoneRow for why those need to be
// different actions, not just different button titles. Only ever reachable via a click on a
// button that updateMicrophoneRow itself only shows/enables on 10.14+, but the compiler's
// availability analysis doesn't see across that method boundary, so this needs its own guard too
// -- see WCAppDelegate::requestMicrophoneAccess's header comment for the same trap.
- (void) microphoneButtonClicked:(id)sender {
    #pragma unused (sender)

    if (@available(macOS 10.14, *)) {
        AVAuthorizationStatus status =
            [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];

        if (status == AVAuthorizationStatusNotDetermined) {
            WCSetupWindow* __weak weakSelf = self;

            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                     completionHandler:^(BOOL granted) {
                #pragma unused (granted)
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf refreshPermissionStatuses];
                });
            }];

            return;
        }
    }

    [self openSystemSettingsPane:@"Privacy_Microphone"];
}

// AXIsProcessTrustedWithOptions (with the prompt option) is the single call that handles both
// "never asked" (adds Wavecraft to the list and shows the system prompt) and "already asked"
// (just re-opens System Settings to the same place) -- no separate deep-link path needed, unlike
// Microphone. Same call WCHotkeys::setEnabled: already uses for the same permission.
- (void) accessibilityButtonClicked:(id)sender {
    #pragma unused (sender)

    NSDictionary* options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    // AXIsProcessTrustedWithOptions returns immediately, before the user's actually granted
    // anything in the window it just opened -- give it a moment before re-checking.
    // applicationDidBecomeActive: below also catches it whenever they actually switch back here.
    WCSetupWindow* __weak weakSelf = self;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{
        [weakSelf refreshPermissionStatuses];
    });
}

// Same x-apple.systempreferences: scheme WCAppDelegate/WCTroubleshootMenu already use to deep-
// link into Privacy & Security's sub-panes -- see WCAppDelegate::openSysPrefsMicrophonePrivacy
// for why this scheme rather than the Scripting Bridge approach used elsewhere in this codebase.
- (void) openSystemSettingsPane:(NSString*)privacyPane {
    NSString* urlString =
        [NSString stringWithFormat:@"x-apple.systempreferences:com.apple.preference.security?%@",
                                    privacyPane];
    NSURL* __nullable url = [NSURL URLWithString:urlString];

    BOOL opened = url && [[NSWorkspace sharedWorkspace] openURL:BGMNN(url)];

    if (!opened) {
        NSLog(@"WCSetupWindow::openSystemSettingsPane: Failed to open System Settings pane %@",
              privacyPane);
    }
}

@end

#pragma clang assume_nonnull end
