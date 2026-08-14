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

// Kept as a constant, rather than read back from self.frameAutosaveName, because
// initWithUserDefaults: deliberately doesn't set that property until *after* the window's
// initial position for this show has already been resolved -- see the comment there.
static NSString* const kFrameAutosaveName = @"WCSetupWindow";

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

        setupContentView = [[WCSetupWindowContentView alloc] initWithFrame:NSZeroRect];
        self.contentView = setupContentView;

        [self buildRows];
        [self sizeToFitContent];

        // Remembers where the user leaves it from here on, like any normal document window --
        // there's no "always reopen in the same spot below some anchor" reason not to, unlike the
        // main panel. Deliberately not set until *after* sizeToFitContent has already resolved
        // the window's initial position: AppKit auto-saves the frame on every move/resize the
        // moment this property is non-nil, and sizeToFitContent's own setContentSize: call is
        // itself a resize. Set this any earlier and that resize would get auto-saved immediately,
        // and setFrameUsingName: (called moments later, in the same method) would then "restore"
        // that exact just-saved, never-actually-positioned frame right back -- which is why an
        // earlier build of this window always landed at frame origin (0, 0) on a genuinely
        // first-ever show, never centered, no matter what centering logic ran afterward.
        self.frameAutosaveName = kFrameAutosaveName;

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

    // Only a previously *saved* position restores -- and even then, only if that saved position
    // is still somewhere a user could actually find it. A frame remembered from a display that's
    // since been disconnected (or moved off every current screen for any other reason) would
    // otherwise silently reopen off-screen, which looks identical to "didn't open at all" --
    // exactly the confusion this window exists to prevent in the first place (see the class
    // header). Uses the constant, not self.frameAutosaveName, because that property isn't set
    // until after this method returns -- see the comment in the initializer.
    BOOL restoredOnScreen = [self setFrameUsingName:kFrameAutosaveName] && [self isOnAnyScreen];
    if (!restoredOnScreen) {
        [self centerOnMainScreen];
    }
}

// Whether any part of the window's current frame actually overlaps a currently connected
// screen's visible area, as opposed to a frame restored from frameAutosaveName that made sense
// on a display configuration that's since changed.
- (BOOL) isOnAnyScreen {
    for (NSScreen* screen in NSScreen.screens) {
        if (NSIntersectsRect(self.frame, screen.visibleFrame)) {
            return YES;
        }
    }

    return NO;
}

// Computes the centered origin directly, rather than calling NSWindow's own -center, purely so
// this is easy to reason about and log if window positioning ever breaks again the way it did
// once already (see the initializer's comment on frameAutosaveName's ordering -- the actual bug
// there was a self-fulfilling "restore" of a never-positioned frame, not anything wrong with
// -center itself, but this stays explicit rather than relying on -center's undocumented behavior
// for a window that's never been on screen yet).
- (void) centerOnMainScreen {
    NSScreen* __nullable screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;

    if (!screen) {
        return;  // No screen at all -- shouldn't happen on a real Mac, nothing we can do anyway.
    }

    NSRect screenFrame = screen.visibleFrame;
    NSRect frame = self.frame;

    NSPoint newOrigin = NSMakePoint(
        screenFrame.origin.x + (NSWidth(screenFrame) - NSWidth(frame)) / 2.0,
        screenFrame.origin.y + (NSHeight(screenFrame) - NSHeight(frame)) / 2.0);
    NSLog(@"DEBUG centerOnMainScreen: setting origin to %@", NSStringFromPoint(newOrigin));

    [self setFrameOrigin:newOrigin];
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
                [self fireMicrophoneAccessGrantedHandlerIfAuthorizedNow];
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

// Custom setter (not just @synthesize) because setting this needs to immediately check whether
// access is already granted -- if it is, the status change that would normally trigger the
// handler (see updateMicrophoneRow) already happened before this was ever set, e.g. because this
// window's already been through Setup in an earlier session, or the user granted access from a
// different build. Without this check, the handler would just sit here armed forever, since
// nothing would ever re-trigger updateMicrophoneRow in that case.
- (void) setMicrophoneAccessGrantedHandler:(void (^__nullable)(void))handler {
    _microphoneAccessGrantedHandler = [handler copy];
    [self fireMicrophoneAccessGrantedHandlerIfAuthorizedNow];
}

- (void) fireMicrophoneAccessGrantedHandlerIfAuthorizedNow {
    if (!_microphoneAccessGrantedHandler) {
        return;
    }

    BOOL authorized;

    if (@available(macOS 10.14, *)) {
        authorized = ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] ==
                          AVAuthorizationStatusAuthorized);
    } else {
        authorized = YES;  // Not required before 10.14 -- nothing to grant.
    }

    if (!authorized) {
        return;
    }

    void (^handler)(void) = _microphoneAccessGrantedHandler;
    _microphoneAccessGrantedHandler = nil;  // Fire exactly once.
    handler();
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
