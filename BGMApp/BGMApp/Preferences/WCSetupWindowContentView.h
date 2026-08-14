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
//  WCSetupWindowContentView.h
//  BGMApp
//
//  Copyright © 2026 Wavecraft contributors
//
//  The content of WCSetupWindow -- one row per thing Wavecraft needs from the system, each with
//  a title, a live granted/not-granted status, an explanation of what it's for, and (where there's
//  somewhere useful to send the user) a button that jumps straight to the right System Settings
//  pane. Built programmatically, matching WCMainPanelContentView's convention -- see that file
//  for why this codebase builds panel content in code rather than via XIBs now.
//

// System Includes
#import <Cocoa/Cocoa.h>


#pragma clang assume_nonnull begin

typedef NS_ENUM(NSInteger, BGMSetupRowStatus) {
    // No live status to show -- an informational row, not a permission (e.g. the menu bar
    // visibility tip). Shown with no status badge at all.
    BGMSetupRowStatusNone,
    BGMSetupRowStatusGranted,
    BGMSetupRowStatusNotGranted,
};

// A row that's been added to the content view. Kept around by the caller (WCSetupWindow) just so
// it can update the status badge and wire up the button later -- not meant to be used for anything
// else.
@interface WCSetupWindowRow : NSObject
@property (nonatomic, readonly, nullable) NSButton* button;
@property (nonatomic, readonly) NSTextField* statusLabel;
@end

@interface WCSetupWindowContentView : NSView

// The app icon plus a title/subtitle, at the very top of the window -- establishes this as
// Wavecraft's own window rather than a generic system dialog. Always call this first, before
// addIntroText:/addRowWithTitle:....
- (void) addHeaderWithTitle:(NSString*)title subtitle:(NSString*)subtitle;

// A plain wrapping paragraph at the top of the window, above any rows -- for the one-sentence
// explanation of what this window is, not a row's own explanation of what it needs.
- (void) addIntroText:(NSString*)text;

// Adds a row and returns it so the caller can wire up the button's target/action and update the
// status badge later, as live permission checks come back. buttonTitle may be nil for a row with
// no action (informational rows).
- (WCSetupWindowRow*) addRowWithTitle:(NSString*)title
                                   body:(NSString*)body
                                 status:(BGMSetupRowStatus)status
                            buttonTitle:(NSString* __nullable)buttonTitle;

// Updates a row's status badge in place -- called when a permission's live status changes (e.g.
// after the user comes back from System Settings).
+ (void) setStatus:(BGMSetupRowStatus)status onRow:(WCSetupWindowRow*)row;

// A prominent, right-aligned action button at the very bottom of the window -- a real dialog
// button (rounded bezel, regular size), not one more flat menu-item-style row like the others.
// This is the action that ends the whole flow, so it reads differently on purpose. Always call
// this last, after every row has been added. Also becomes the window's default button (responds
// to Return), matching how a dialog's primary action normally behaves.
- (NSButton*) addDoneButtonWithTitle:(NSString*)title;

@end

#pragma clang assume_nonnull end
