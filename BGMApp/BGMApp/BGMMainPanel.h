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
//  BGMMainPanel.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  The main dropdown, shown when the user clicks the status bar icon. A custom NSPanel rather than
//  an NSMenu -- see docs/LESSONS.md for why: NSMenu closes itself the instant any click-and-release
//  finishes inside it, even one fully handled by a custom NSMenuItem view's own control (a slider,
//  say), and there's no supported way to stop that at the control level. A real window has no such
//  race, at the cost of having to build click-outside dismissal, key-window handling, and multi-Space
//  behaviour ourselves instead of getting them for free from NSMenu.
//

// Local Includes
#import "BGMMainPanelContentView.h"

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

@interface BGMMainPanel : NSPanel

// mainContentView is a BGMMainPanelContentView added as this panel's content once, at init.
// Callers add/arrange rows within it -- this class only owns the panel's own window-level
// behaviour (showing, hiding, positioning, dismissal), not what's inside it.
@property (nonatomic, readonly) BGMMainPanelContentView* mainContentView;

// Called every time the panel is about to be shown, before it's positioned/ordered front -- the
// equivalent of the old NSMenu-based design's -menuWillOpen:, for content (the routed-app
// indicator, the Auto-pause row's title, etc.) that can go stale while the panel's closed and
// needs refreshing right before it's seen again.
@property (nonatomic, copy, nullable) void (^willShowBlock)(void);

// Shows the panel positioned just below inButton (expected to be the status item's button),
// left-aligned with it, and starts watching for the interactions that should dismiss it (a click
// outside the panel, Escape, or the panel losing key status). No-op if already visible.
- (void) showRelativeToStatusItemButton:(NSStatusBarButton*)inButton;

// Hides the panel and stops watching for dismissal interactions. No-op if already hidden.
- (void) hide;

// Shows the panel if it's currently hidden, hides it if currently visible.
- (void) toggleRelativeToStatusItemButton:(NSStatusBarButton*)inButton;

@end

#pragma clang assume_nonnull end
