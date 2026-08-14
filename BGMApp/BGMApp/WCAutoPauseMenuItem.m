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
//  WCAutoPauseMenuItem.m
//  BGMApp
//
//  Copyright © 2016, 2019, 2026 Kyle Neideck
//  Copyright © 2016 Tanner Hoke
//

// Self Include
#import "WCAutoPauseMenuItem.h"

// Local Includes
#import "WCAppWatcher.h"


#pragma clang assume_nonnull begin

static NSString* const kButtonTitleFormat = @"Auto-pause %@";
static NSString* const kDisabledLookToolTipFormat = @"%@ doesn't appear to be running.";

// Wait time to update the button's enabled-look after the selected player launches/quits, in
// seconds.
static SInt64 const kButtonUpdateWaitTime = 1;

@implementation WCAutoPauseMenuItem {
    WCUserDefaults* userDefaults;
    NSButton* button;
    WCAutoPauseMusic* autoPauseMusic;
    WCMusicPlayers* musicPlayers;
    WCAppWatcher* appWatcher;
}

- (instancetype) initWithButton:(NSButton*)inButton
                  autoPauseMusic:(WCAutoPauseMusic*)autoPause
                    musicPlayers:(WCMusicPlayers*)players
                    userDefaults:(WCUserDefaults*)defaults {
    if ((self = [super init])) {
        button = inButton;
        autoPauseMusic = autoPause;
        musicPlayers = players;
        userDefaults = defaults;

        // Enable/disable auto-pause to match the user's preferences setting.
        if (userDefaults.autoPauseMusicEnabled) {
            button.state = NSControlStateValueOn;
            [autoPauseMusic enable];
        } else {
            button.state = NSControlStateValueOff;
            [autoPauseMusic disable];
        }

        button.target = self;
        button.action = @selector(toggleAutoPauseMusic);

        [self updateButtonTitle];

        // Avoid retain cycles in case we ever want to destroy instances of this class.
        WCAutoPauseMenuItem* __weak weakSelf = self;

        // Update the button's title/enabled-look when the music player is launched/terminated.
        void (^callback)(void) = ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kButtonUpdateWaitTime * NSEC_PER_SEC),
                           dispatch_get_main_queue(),
                           ^{
                               [weakSelf updateButtonTitle];
                           });
        };

        appWatcher = [[WCAppWatcher alloc] initWithAppLaunched:callback
                                                  appTerminated:callback
                                             isMatchingBundleID:^BOOL(NSString* appBundleID) {
            WCAutoPauseMenuItem* __strong strongSelf = weakSelf;
            NSString* __nullable playerBundleID = strongSelf->musicPlayers.selectedMusicPlayer.bundleID;
            return playerBundleID && [appBundleID isEqualToString:(NSString*)playerBundleID];
        }];
    }

    return self;
}

- (void) toggleAutoPauseMusic {
    if (button.state == NSControlStateValueOn) {
        button.state = NSControlStateValueOff;
        [autoPauseMusic disable];
    } else {
        button.state = NSControlStateValueOn;
        [autoPauseMusic enable];
    }

    userDefaults.autoPauseMusicEnabled = (button.state == NSControlStateValueOn);
}

// Sets the button's title, including the selected music player's name, and gives it a
// disabled-looking (but still clickable) appearance if that player isn't currently running. Not
// actually disabled: someone might want to turn auto-pause off while their player isn't running,
// e.g. right after installing Wavecraft and before they've decided whether they want this feature
// at all.
- (void) updateButtonTitle {
    NSString* musicPlayerName = musicPlayers.selectedMusicPlayer.name;
    button.title = [NSString stringWithFormat:kButtonTitleFormat, musicPlayerName];

    if (musicPlayers.selectedMusicPlayer.running) {
        button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title];
        button.toolTip = nil;
    } else {
        NSDictionary* attributes = @{
            NSFontAttributeName: [NSFont menuFontOfSize:0],
            NSForegroundColorAttributeName: [NSColor disabledControlTextColor],
        };
        button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title
                                                                   attributes:attributes];
        button.toolTip = [NSString stringWithFormat:kDisabledLookToolTipFormat, musicPlayerName];
    }
}

- (void) refreshBeforeShow {
    [self updateButtonTitle];
}

@end

#pragma clang assume_nonnull end
