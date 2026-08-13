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
//  BGMHotkeyRecorderButton.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  A button for one row of Preferences > Keyboard Shortcuts. Click it, then press any key
//  (with optional modifiers held) to bind that combination to this button's action -- replaces
//  the old fixed Option/Control preset with a real per-action recorder, the way most macOS apps
//  with rebindable shortcuts work.
//
//  UNTESTED against a live running menu: this installs a local NSEvent monitor while the
//  Preferences menu is still open and tracking, which is the documented-correct way to observe
//  events during a modal-like tracking session (Apple describes local monitors as running before
//  normal dispatch, which is why things like Escape-to-cancel-a-drag work during menu tracking) --
//  but NSMenu is also known to intercept some keys (arrows, Return, Escape, letters for
//  type-ahead) for its own navigation, and there's no way to confirm from a non-interactive
//  environment whether this monitor actually receives the keydown before or after that happens.
//  See TODO.md/docs/QA-PLAN.md for what a real test needs to confirm.
//

// Local Includes
#import "BGMHotkeys.h"

// System Includes
#import <Cocoa/Cocoa.h>


NS_ASSUME_NONNULL_BEGIN

@class BGMHotkeyRecorderButton;

@protocol BGMHotkeyRecorderButtonDelegate <NSObject>

// Called synchronously the moment a key is captured, before the button updates its own title.
// Return YES to accept and persist the binding (the button then shows it); return NO to reject it
// (the button reverts to its previous title) -- e.g. because it's already bound to a different
// action. The delegate, not this button, is responsible for explaining a rejection to the user
// (an alert, since there's nowhere else in a menu item's row to show an error).
- (BOOL) hotkeyRecorderButton:(BGMHotkeyRecorderButton*)button
          didRecordNewBinding:(BGMHotkeyBinding)binding
                    forAction:(BGMHotkeyAction)action;

@end

@interface BGMHotkeyRecorderButton : NSButton

- (instancetype) initWithFrame:(NSRect)frameRect
                         action:(BGMHotkeyAction)hotkeyAction
                       delegate:(id<BGMHotkeyRecorderButtonDelegate>)delegate;

@property (nonatomic, readonly) BGMHotkeyAction hotkeyAction;

// Updates the button's title to describe the given binding, without entering recording mode.
// Call this any time the underlying stored binding changes for a reason other than this button's
// own recording (e.g. on first setup, or after another action's rebind invalidated this one).
- (void) refreshWithBinding:(BGMHotkeyBinding)binding;

@end

NS_ASSUME_NONNULL_END
