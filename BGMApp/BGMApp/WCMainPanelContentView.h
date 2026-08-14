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
//  WCMainPanelContentView.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  Everything shown inside WCMainPanel: the Auto-pause row, Volumes section, per-app rows
//  (split into "Your Apps" and a collapsed "System & Other Apps"), Output Device section, and the
//  Preferences/Quit buttons. A plain NSView, not an NSViewController -- this codebase doesn't use
//  view controllers anywhere else, so this matches its existing convention of NSView/NSObject with
//  manual wiring rather than introducing a new pattern.
//
//  This class only builds the static shell (section headers, separators, the stacks that rows get
//  added to). The actual row content -- what's inside volumesStack/yourAppsStack/etc. -- is added
//  by the controller classes that own that content (WCOutputVolumeMenuItem, WCAppVolumesController,
//  WCOutputDeviceMenuSection), the same division of responsibility those classes already had with
//  the old NSMenu.
//

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

// The standard row height most rows in the panel use -- shared so other classes building rows to
// add to this view's stacks (WCAppDelegate, WCOutputDeviceMenuSection) don't each hardcode their
// own copy of the same number.
static CGFloat const kBGMMainPanelRowHeight = 22;

@interface WCMainPanelContentView : NSView

// The top-level vertical stack; sections are arranged subviews of this, top to bottom.
@property (nonatomic, readonly) NSStackView* rowStack;

// A single row, target/action already unset -- the Auto-pause row. WCAutoPauseMenuItem owns its
// title/state/enabled-look; this class only places it.
@property (nonatomic, readonly) NSButton* autoPauseButton;

// Volumes section: WCOutputVolumeMenuItem's and WCSystemSoundsVolume's views are added here, in
// that order.
@property (nonatomic, readonly) NSStackView* volumesStack;

// Per-app rows. yourAppsStack is always visible; systemAndOtherAppsStack starts collapsed
// (hidden) behind systemAndOtherAppsDisclosureButton, which toggles it.
@property (nonatomic, readonly) NSStackView* yourAppsStack;
@property (nonatomic, readonly) NSButton* systemAndOtherAppsDisclosureButton;
@property (nonatomic, readonly) NSStackView* systemAndOtherAppsStack;

// Output Device section: WCOutputDeviceMenuSection's device rows are added here.
@property (nonatomic, readonly) NSStackView* outputDeviceStack;

@property (nonatomic, readonly) NSButton* preferencesButton;
@property (nonatomic, readonly) NSButton* quitButton;

// Hidden unless you hold Option while clicking the status bar icon -- see WCDebugLoggingMenuItem.
@property (nonatomic, readonly) NSButton* debugLoggingButton;

// Recomputes the scrollable apps section's height from its current content (yourAppsStack +
// disclosure button + systemAndOtherAppsStack, whatever's currently visible), capped at a fixed
// maximum -- see the .mm file for why this exists and can't just be a static constraint set up
// once at construction time. Must be called before the panel is shown, any time rows might have
// been added/removed/revealed since the last show (in practice: always, right before showing --
// WCMainPanel does this).
- (void) updateAppsScrollViewHeight;

// Adds a thin horizontal divider as the next arranged subview of rowStack. Exposed so
// WCAppDelegate can lay sections out in the same order the old NSMenu had them, without every
// caller re-implementing "what a separator looks like".
- (void) addSeparator;

// Adds a small, non-interactive section-heading label (matching a disabled NSMenu header's look)
// as the next arranged subview of rowStack.
- (void) addSectionHeaderWithTitle:(NSString*)title;

// Wraps innerView in a fixed-width, fixed-height container with the standard row padding, so
// content built by other classes (e.g. WCOutputDeviceMenuSection's per-device buttons) lines up
// consistently with rows built directly by this class. The returned container, not innerView
// itself, is what should be added as an arranged subview of a stack view.
+ (NSView*) rowContainerWithControl:(NSView*)innerView height:(CGFloat)height;

@end

#pragma clang assume_nonnull end
