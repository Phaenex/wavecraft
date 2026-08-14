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
//  WCMainPanel.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "WCMainPanel.h"

// Local Includes
#import "WCMainPanelContentView.h"


#pragma clang assume_nonnull begin

// Roughly matches the padding a real NSMenu leaves around its content; not load-bearing, just
// makes the panel not butt directly up against the status bar.
static CGFloat const kGapBelowStatusItem = 4;

@implementation WCMainPanel {
    id __nullable outsideClickMonitor;
    id __nullable keyDownMonitor;

    // Guards against reentrancy: hide calls orderOut:, which itself causes this panel to resign
    // key status, which (without this guard) would call hide again from inside the first call.
    BOOL isHiding;
}

- (instancetype) init {
    // .nonactivatingPanel lets the panel receive mouse/keyboard input without activating this app
    // or stealing frontmost status from whatever app the user was just using -- the same mechanism
    // real menu-bar utilities use for their dropdown panels (see docs/LESSONS.md). .borderless +
    // .fullSizeContentView means we draw 100% of the panel's appearance ourselves, same as an
    // NSMenu's own borderless dropdown.
    NSWindowStyleMask styleMask = (NSWindowStyleMaskBorderless |
                                    NSWindowStyleMaskNonactivatingPanel |
                                    NSWindowStyleMaskFullSizeContentView);

    self = [super initWithContentRect:NSZeroRect
                             styleMask:styleMask
                               backing:NSBackingStoreBuffered
                                 defer:NO];

    if (self) {
        // Above normal app windows, and above the menu bar itself, so it isn't hidden behind
        // whatever the user was last looking at.
        self.level = NSFloatingWindowLevel;

        // Follows the user to whichever Space/full-screen app they're using instead of being
        // stranded on the Space it was opened from, and doesn't count as a separate window when
        // cycling with Cmd-`.
        self.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorIgnoresCycle);

        self.opaque = NO;
        self.backgroundColor = [NSColor clearColor];
        self.hasShadow = YES;
        self.releasedWhenClosed = NO;

        _mainContentView = [[WCMainPanelContentView alloc] initWithFrame:NSZeroRect];
        self.contentView = _mainContentView;
    }

    return self;
}

// Borderless/non-activating panels default to NO here -- without this override, clicks land, but
// keyboard focus, text editing, and a slider's own arrow-key nudging never work, because the
// panel never actually becomes the key window. This is the single most-missed step in every
// reference implementation of this pattern.
- (BOOL) canBecomeKeyWindow {
    return YES;
}

#pragma mark Show / Hide

- (void) showRelativeToStatusItemButton:(NSStatusBarButton*)inButton {
    if (self.visible) {
        return;
    }

    if (self.willShowBlock) {
        self.willShowBlock();
    }

    [self positionBelowStatusItemButton:inButton];

    [self makeKeyAndOrderFront:nil];

    [self startWatchingForDismissal];
}

- (void) hide {
    if (!self.visible || isHiding) {
        return;
    }

    isHiding = YES;

    [self stopWatchingForDismissal];

    [self orderOut:nil];

    isHiding = NO;
}

- (void) toggleRelativeToStatusItemButton:(NSStatusBarButton*)inButton {
    if (self.visible) {
        [self hide];
    } else {
        [self showRelativeToStatusItemButton:inButton];
    }
}

- (void) positionBelowStatusItemButton:(NSStatusBarButton*)inButton {
    NSWindow* __nullable buttonWindow = inButton.window;

    if (!buttonWindow) {
        return;
    }

    NSRect buttonFrameInScreen = [buttonWindow convertRectToScreen:inButton.frame];

    // Rows can have been added/removed, or the "System & Other Apps" disclosure toggled, since the
    // last time this panel was shown -- recompute the (capped) apps-scroll-view height against
    // what's actually there right now before measuring fittingSize, or it'd be sized from stale
    // content.
    [self.mainContentView updateAppsScrollViewHeight];

    // Fit the panel's current content, then position it hanging below the status item, right-
    // aligned with it (matches where an NSMenu opened from the same button would appear).
    NSSize contentSize = self.mainContentView.fittingSize;
    self.contentView.wantsLayer = YES;

    CGFloat panelX = NSMaxX(buttonFrameInScreen) - contentSize.width;
    CGFloat panelY = NSMinY(buttonFrameInScreen) - kGapBelowStatusItem - contentSize.height;

    // Defense in depth beyond the apps-scroll-view cap above: even with that cap, a very small
    // display (or a status item positioned unusually low) could still compute a panelY that puts
    // part of the panel below the visible screen, with no way to scroll to it -- everything below
    // the apps section (Output Device, Preferences, Quit) has no cap of its own. Clamp to the
    // status item's screen's visible frame so the panel's bottom edge never goes further than
    // that, even if it means sitting slightly higher than "immediately below the status item."
    NSScreen* __nullable screen = buttonWindow.screen ?: NSScreen.mainScreen;
    if (screen) {
        CGFloat minY = NSMinY(screen.visibleFrame);
        panelY = MAX(panelY, minY);
    }

    [self setFrame:NSMakeRect(panelX, panelY, contentSize.width, contentSize.height)
            display:YES];
}

#pragma mark Dismissal

// A global monitor observes events delivered to *other* apps -- it can't intercept or cancel
// them, only react, which is exactly what's needed here: close the panel, but don't swallow the
// click so whatever the user actually clicked on still gets it.
- (void) startWatchingForDismissal {
    WCMainPanel* __weak weakSelf = self;

    outsideClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
            (NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown)
                                                                   handler:^(NSEvent* event) {
        #pragma unused (event)
        [weakSelf hide];
    }];

    // A global monitor only sees clicks in *other* apps/windows, so it won't fire for a click on
    // this app's own menu bar icon (clicking the icon again while the panel's open should close
    // it via the button's own click handler, not this monitor) or dialogs this app itself opens.
    // Escape needs its own local monitor since it's not a click.
    keyDownMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                             handler:^NSEvent* __nullable(NSEvent* event) {
        static unsigned short const kEscapeKeyCode = 53;

        if (event.keyCode == kEscapeKeyCode) {
            [weakSelf hide];
            return nil;
        }

        return event;
    }];
}

- (void) stopWatchingForDismissal {
    if (outsideClickMonitor) {
        [NSEvent removeMonitor:(id)outsideClickMonitor];
        outsideClickMonitor = nil;
    }

    if (keyDownMonitor) {
        [NSEvent removeMonitor:(id)keyDownMonitor];
        keyDownMonitor = nil;
    }
}

// The panel losing key status (e.g. the user Cmd-Tabs to another app, or clicks one of this app's
// own other windows) should close it the same as an explicit click outside.
- (void) resignKeyWindow {
    [super resignKeyWindow];

    [self hide];
}

@end

#pragma clang assume_nonnull end
