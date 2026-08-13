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
//  BGMHotkeyRecorderButton.mm
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//

// Self Include
#import "BGMHotkeyRecorderButton.h"

// Local Includes
#import "BGM_Utils.h"

// System Includes
#import <Carbon/Carbon.h>  // For kVK_Escape only.


NS_ASSUME_NONNULL_BEGIN

@interface BGMHotkeyRecorderButton ()
@property (nonatomic, weak) id<BGMHotkeyRecorderButtonDelegate> delegate;
@end

@implementation BGMHotkeyRecorderButton {
    NSString* __nullable titleBeforeRecording;
    id __nullable localMonitor;
}

- (instancetype) initWithFrame:(NSRect)frameRect
                         action:(BGMHotkeyAction)hotkeyAction
                       delegate:(id<BGMHotkeyRecorderButtonDelegate>)delegate {
    if ((self = [super initWithFrame:frameRect])) {
        _hotkeyAction = hotkeyAction;
        _delegate = delegate;

        self.bezelStyle = NSBezelStyleRounded;
        self.font = [NSFont menuFontOfSize:11];
        self.target = self;
        self.action = @selector(startRecording);
    }

    return self;
}

- (void) dealloc {
    [self stopRecording];
}

- (void) refreshWithBinding:(BGMHotkeyBinding)binding {
    // Recording takes priority over an out-of-band refresh -- if this button is mid-recording (a
    // rare race: another button's rebind landed while this one was waiting for a keypress), don't
    // clobber the "Press a key..." title the user is currently looking at.
    if (!localMonitor) {
        self.title = BGMHotkeyBindingDescription(binding);
    }
}

- (void) startRecording {
    if (localMonitor) {
        // Already recording -- treat a second click as "cancel," not "restart," so there's always
        // a way to back out with the mouse alone, not just Escape.
        [self cancelRecording];
        return;
    }

    titleBeforeRecording = self.title;
    self.title = @"Press a key… (Esc to cancel)";

    // A local monitor observes events before AppKit's normal dispatch, including during a menu's
    // own tracking loop -- see this class's header for why that matters here, and why it's still
    // unverified against a real menu.
    localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                           handler:^NSEvent* __nullable(NSEvent* event) {
        return [self handleCandidateKeyEvent:event];
    }];
}

- (void) cancelRecording {
    self.title = titleBeforeRecording ?: BGMHotkeyBindingDescription(kBGMHotkeyBindingUnbound);
    titleBeforeRecording = nil;
    [self stopRecording];
}

- (void) stopRecording {
    if (localMonitor) {
        [NSEvent removeMonitor:BGMNN(localMonitor)];
        localMonitor = nil;
    }
}

// Returns nil to swallow the event (recording handled it -- whether by accepting a new binding or
// cancelling), or the event itself to let it continue on to normal dispatch (shouldn't currently
// happen, since every path below either accepts or cancels, but returning the event rather than
// nil is the safe default for a monitor callback if a future change adds a path that falls
// through without deciding).
- (NSEvent* __nullable) handleCandidateKeyEvent:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;

    if ((event.keyCode == kVK_Escape) && (flags == 0)) {
        [self cancelRecording];
        return nil;
    }

    BGMHotkeyBinding candidate = { event.keyCode, flags };

    [self stopRecording];

    BOOL accepted = [self.delegate hotkeyRecorderButton:self
                                     didRecordNewBinding:candidate
                                               forAction:self.hotkeyAction];

    self.title = accepted ?
        BGMHotkeyBindingDescription(candidate) :
        (titleBeforeRecording ?: BGMHotkeyBindingDescription(kBGMHotkeyBindingUnbound));
    titleBeforeRecording = nil;

    return nil;
}

@end

NS_ASSUME_NONNULL_END
