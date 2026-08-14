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
//  WCDebugLoggingMenuItem.m
//  BGMApp
//
//  Copyright © 2020, 2026 Kyle Neideck
//

// Self Include
#import "WCDebugLoggingMenuItem.h"

// Local Includes
#import "BGM_Utils.h"
#import "WCAudioDeviceManager.h"
#import "WCBackgroundMusicDevice.h"

// PublicUtility Includes
#import "BGMDebugLogging.h"
#import "CADebugMacros.h"


#pragma clang assume_nonnull begin

@implementation WCDebugLoggingMenuItem {
    NSButton* _button;
    BOOL _menuShowingExtraOptions;
    WCAudioDeviceManager* _audioDevices;
}

- (instancetype) initWithButton:(NSButton*)button
                   audioDevices:(WCAudioDeviceManager*)audioDevices {
    if ((self = [super init])) {
        _button = button;
        _audioDevices = audioDevices;
        _button.state =
                BGMDebugLoggingIsEnabled() ? NSControlStateValueOn : NSControlStateValueOff;

        [self setMenuShowingExtraOptions:NO];

        // Enable/disable debug logging when the button is clicked.
        button.target = self;
        button.action = @selector(toggleDebugLogging);
    }

    return self;
}

- (void) setMenuShowingExtraOptions:(BOOL)showingExtra {
    _menuShowingExtraOptions = showingExtra;

    // The button's own container row (see WCMainPanelContentView's wrapInRowContainer:height:)
    // has to be hidden, not just the button, or NSStackView leaves an empty gap where the row
    // would be instead of collapsing it.
    BOOL hidden = !BGMDebugLoggingIsEnabled() && !showingExtra;
    _button.superview.hidden = hidden;

    DebugMsg("WCDebugLoggingMenuItem::menuShowingExtraOptions: %s the row",
             hidden ? "Hiding" : "Showing");
}

- (void) toggleDebugLogging {
    BGMSetDebugLoggingEnabled(!BGMDebugLoggingIsEnabled());
    _button.state = BGMDebugLoggingIsEnabled() ? NSControlStateValueOn : NSControlStateValueOff;

    // Keep BGMDriver's debug logging in sync with ours.
    BGMLogAndSwallowExceptions("WCDebugLoggingMenuItem::toggleDebugLogging", [&] {
        [_audioDevices bgmDevice].SetDebugLoggingEnabled(BGMDebugLoggingIsEnabled());
    });

    DebugMsg("WCDebugLoggingMenuItem::toggleDebugLogging: Debug logging %s",
             BGMDebugLoggingIsEnabled() ? "enabled" : "disabled");
}

@end

#pragma clang assume_nonnull end

