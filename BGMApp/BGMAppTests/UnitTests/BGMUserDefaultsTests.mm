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
//  BGMUserDefaultsTests.mm
//  BGMAppUnitTests
//
//  Copyright © 2026 Wavecraft contributors
//
//  Covers BGMUserDefaults's hotkey-binding storage (BGMHotkeyAction/BGMHotkeyBinding round trips,
//  defaults, clamping) and the BGMHotkeyBinding helper functions. This is plain Foundation/plist
//  logic with no CoreAudio HAL dependency, unlike BGMHotkeys itself (which can't be unit tested --
//  see BGMTapRouteTests.mm's own comment on why -- because it touches real system state:
//  AXIsProcessTrusted(), NSWorkspace.frontmostApplication, and a real global NSEvent monitor).
//  BGMUserDefaults supports this via initWithDefaults:nil, which keeps everything in memory
//  instead of touching the real NSUserDefaults on disk.

// Unit includes
#import "BGMUserDefaults.h"
#import "BGMHotkeys.h"

// System includes
#import <Carbon/Carbon.h>
#import <XCTest/XCTest.h>


@interface BGMUserDefaultsTests : XCTestCase
@end

@implementation BGMUserDefaultsTests {
    BGMUserDefaults* defaults;
}

- (void) setUp {
    [super setUp];
    defaults = [[BGMUserDefaults alloc] initWithDefaults:nil];
}

#pragma mark Hotkey Binding Defaults

- (void) testHotkeyBindingDefaultsMatchOriginalOptionModifierBehavior {
    BGMHotkeyBinding systemUp = [defaults hotkeyBindingForAction:BGMHotkeyActionSystemVolumeUp];
    BGMHotkeyBinding systemDown = [defaults hotkeyBindingForAction:BGMHotkeyActionSystemVolumeDown];
    BGMHotkeyBinding appUp = [defaults hotkeyBindingForAction:BGMHotkeyActionAppVolumeUp];
    BGMHotkeyBinding appDown = [defaults hotkeyBindingForAction:BGMHotkeyActionAppVolumeDown];

    XCTAssertEqual(systemUp.keyCode, (unsigned short)kVK_UpArrow);
    XCTAssertEqual(systemUp.modifierFlags, (NSEventModifierFlags)NSEventModifierFlagOption);

    XCTAssertEqual(systemDown.keyCode, (unsigned short)kVK_DownArrow);
    XCTAssertEqual(systemDown.modifierFlags, (NSEventModifierFlags)NSEventModifierFlagOption);

    XCTAssertEqual(appUp.keyCode, (unsigned short)kVK_UpArrow);
    XCTAssertEqual(appUp.modifierFlags,
                   (NSEventModifierFlags)(NSEventModifierFlagOption | NSEventModifierFlagShift));

    XCTAssertEqual(appDown.keyCode, (unsigned short)kVK_DownArrow);
    XCTAssertEqual(appDown.modifierFlags,
                   (NSEventModifierFlags)(NSEventModifierFlagOption | NSEventModifierFlagShift));

    // None of the built-in defaults should ever present as "unbound" -- a fresh install should
    // always have working shortcuts once enabled, not a blank slate the user has to fill in.
    XCTAssertFalse(BGMHotkeyBindingIsUnbound(systemUp));
    XCTAssertFalse(BGMHotkeyBindingIsUnbound(systemDown));
    XCTAssertFalse(BGMHotkeyBindingIsUnbound(appUp));
    XCTAssertFalse(BGMHotkeyBindingIsUnbound(appDown));
}

#pragma mark Round Trips

- (void) testSetAndGetHotkeyBindingRoundTrips {
    BGMHotkeyBinding custom = { kVK_ANSI_V, NSEventModifierFlagControl | NSEventModifierFlagCommand };

    [defaults setHotkeyBinding:custom forAction:BGMHotkeyActionAppVolumeUp];

    BGMHotkeyBinding readBack = [defaults hotkeyBindingForAction:BGMHotkeyActionAppVolumeUp];

    XCTAssertTrue(BGMHotkeyBindingsEqual(custom, readBack));
}

- (void) testSettingOneActionsBindingDoesNotAffectOthers {
    BGMHotkeyBinding original = [defaults hotkeyBindingForAction:BGMHotkeyActionSystemVolumeDown];

    [defaults setHotkeyBinding:(BGMHotkeyBinding){ kVK_ANSI_A, NSEventModifierFlagCommand }
                      forAction:BGMHotkeyActionSystemVolumeUp];

    BGMHotkeyBinding afterChange =
        [defaults hotkeyBindingForAction:BGMHotkeyActionSystemVolumeDown];

    XCTAssertTrue(BGMHotkeyBindingsEqual(original, afterChange),
                  @"Changing SystemVolumeUp's binding should not change SystemVolumeDown's");
}

- (void) testOverwritingABindingReplacesTheStoredValue {
    [defaults setHotkeyBinding:(BGMHotkeyBinding){ kVK_ANSI_A, NSEventModifierFlagCommand }
                      forAction:BGMHotkeyActionAppVolumeDown];
    [defaults setHotkeyBinding:(BGMHotkeyBinding){ kVK_ANSI_B, NSEventModifierFlagShift }
                      forAction:BGMHotkeyActionAppVolumeDown];

    BGMHotkeyBinding finalBinding = [defaults hotkeyBindingForAction:BGMHotkeyActionAppVolumeDown];

    XCTAssertEqual(finalBinding.keyCode, (unsigned short)kVK_ANSI_B);
    XCTAssertEqual(finalBinding.modifierFlags, (NSEventModifierFlags)NSEventModifierFlagShift);
}

#pragma mark BGMHotkeyBinding Helper Functions

- (void) testBGMHotkeyBindingIsUnbound {
    XCTAssertTrue(BGMHotkeyBindingIsUnbound(kBGMHotkeyBindingUnbound));
    XCTAssertFalse(BGMHotkeyBindingIsUnbound(((BGMHotkeyBinding){ kVK_ANSI_A, 0 })));
    // keyCode 0 is a real key (kVK_ANSI_A), not the unbound sentinel -- must not be conflated.
    XCTAssertFalse(BGMHotkeyBindingIsUnbound(((BGMHotkeyBinding){ 0, 0 })));
}

- (void) testBGMHotkeyBindingsEqualComparesBothFields {
    BGMHotkeyBinding a = { kVK_ANSI_A, NSEventModifierFlagShift };
    BGMHotkeyBinding sameKeyDifferentModifier = { kVK_ANSI_A, NSEventModifierFlagOption };
    BGMHotkeyBinding differentKeySameModifier = { kVK_ANSI_B, NSEventModifierFlagShift };
    BGMHotkeyBinding identical = { kVK_ANSI_A, NSEventModifierFlagShift };

    XCTAssertTrue(BGMHotkeyBindingsEqual(a, identical));
    XCTAssertFalse(BGMHotkeyBindingsEqual(a, sameKeyDifferentModifier));
    XCTAssertFalse(BGMHotkeyBindingsEqual(a, differentKeySameModifier));
}

- (void) testBGMHotkeyBindingDescriptionForUnbound {
    XCTAssertEqualObjects(BGMHotkeyBindingDescription(kBGMHotkeyBindingUnbound), @"Click to Record");
}

- (void) testBGMHotkeyBindingDescriptionOrdersModifiersConsistently {
    // Fixed order (Control, Option, Shift, Command) regardless of the order the flags are OR'd
    // together in -- so the same binding always renders identically, matching how macOS itself
    // always shows modifier symbols in a fixed order in its own menus.
    BGMHotkeyBinding binding = {
        kVK_UpArrow,
        NSEventModifierFlagShift | NSEventModifierFlagCommand | NSEventModifierFlagOption
    };

    XCTAssertEqualObjects(BGMHotkeyBindingDescription(binding), @"⌥⇧⌘↑");
}

- (void) testBGMHotkeyActionDisplayNamesAreAllDistinct {
    NSMutableSet<NSString*>* names = [NSMutableSet new];

    for (NSInteger i = kBGMHotkeyActionMinValue; i <= kBGMHotkeyActionMaxValue; i++) {
        NSString* name = BGMHotkeyActionDisplayName((BGMHotkeyAction)i);
        XCTAssertFalse([names containsObject:name],
                        @"Duplicate display name would make the Preferences menu ambiguous: %@",
                        name);
        [names addObject:name];
    }

    XCTAssertEqual(names.count, (NSUInteger)kBGMHotkeyActionCount);
}

#pragma mark Step Size Clamping (regression coverage for a previously-fixed bug)

- (void) testHotkeyStepSizeClampsOutOfRangeStoredValue {
    // setHotkeyStepSize: itself does no validation (matching a real corrupted/hand-edited defaults
    // plist, which could equally contain any NSInteger) -- the clamp is the getter's job.
    [defaults setHotkeyStepSize:(BGMHotkeyStepSizeCoarse + 5)];

    XCTAssertEqual([defaults hotkeyStepSize], BGMHotkeyStepSizeNormal,
                    @"An out-of-range stored step size should clamp back to the default, not "
                     "propagate an invalid enum value to callers that index arrays with it");
}

@end
