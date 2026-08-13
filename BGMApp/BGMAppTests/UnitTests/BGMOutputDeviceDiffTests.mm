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
//  BGMOutputDeviceDiffTests.mm
//  BGMAppUnitTests
//
//  Copyright © 2026 Wavecraft contributors
//
//  Unlike BGMTapRouteTests.mm (deliberately limited to construction/validation only -- see its own
//  comment for why the real tap/BGMPlayThrough pipeline can't be exercised in this mocked target),
//  BGMComputeOutputDeviceDiff is pure set-difference logic with no CoreAudio HAL dependency at
//  all, so it gets full behavioral coverage here.
//

// Unit Include
#import "BGMOutputDeviceDiff.h"

// STL Includes
#import <algorithm>

// System Includes
#import <XCTest/XCTest.h>


static const AudioObjectID kDeviceA = 1;
static const AudioObjectID kDeviceB = 2;
static const AudioObjectID kDeviceC = 3;

@interface BGMOutputDeviceDiffTests : XCTestCase
@end

@implementation BGMOutputDeviceDiffTests

// AudioObjectID (a plain UInt32) is fine for XCTAssertEqual on its own, but XCTest's failure-
// description machinery doesn't have an overload for std::vector -- comparing element by element
// (rather than handing the whole vector to XCTAssertEqual) keeps this portable and gives a useful
// failure message naming the exact index and value that didn't match.
- (void) assertDeviceList:(const std::vector<AudioObjectID>&)actual
      matchesExpectedList:(const std::vector<AudioObjectID>&)expected
                    label:(NSString*)label {
    XCTAssertEqual(actual.size(), expected.size(), @"%@: size mismatch", label);

    for (size_t i = 0; i < std::min(actual.size(), expected.size()); i++) {
        XCTAssertEqual(actual[i], expected[i], @"%@: mismatch at index %zu", label, i);
    }
}

- (void) assertDiffWithCurrent:(std::vector<AudioObjectID>)current
                        desired:(std::vector<AudioObjectID>)desired
              expectedToRemove:(std::vector<AudioObjectID>)expectedToRemove
                 expectedToAdd:(std::vector<AudioObjectID>)expectedToAdd {
    BGMOutputDeviceDiff diff = BGMComputeOutputDeviceDiff(current, desired);

    [self assertDeviceList:diff.toRemove matchesExpectedList:expectedToRemove label:@"toRemove"];
    [self assertDeviceList:diff.toAdd matchesExpectedList:expectedToAdd label:@"toAdd"];
}

- (void) testEmptyCurrentAndDesiredProducesNoChanges {
    [self assertDiffWithCurrent:{} desired:{} expectedToRemove:{} expectedToAdd:{}];
}

- (void) testAddingToEmptyCurrentQueuesEveryDesiredDeviceAsToAdd {
    [self assertDiffWithCurrent:{}
                         desired:{kDeviceA, kDeviceB}
                expectedToRemove:{}
                   expectedToAdd:{kDeviceA, kDeviceB}];
}

- (void) testClearingToEmptyDesiredQueuesEveryCurrentDeviceAsToRemove {
    [self assertDiffWithCurrent:{kDeviceA, kDeviceB}
                         desired:{}
                expectedToRemove:{kDeviceA, kDeviceB}
                   expectedToAdd:{}];
}

- (void) testIdenticalCurrentAndDesiredProducesNoChanges {
    [self assertDiffWithCurrent:{kDeviceA, kDeviceB}
                         desired:{kDeviceA, kDeviceB}
                expectedToRemove:{}
                   expectedToAdd:{}];
}

// The behavior this whole extraction exists to guarantee: switching from {A, B} to {A, C} touches
// only B and C. A must never appear in either list -- BGMAppOutputRoutingController relies on that
// to avoid tearing down and immediately recreating an output that didn't actually change.
- (void) testSwitchingOneDeviceLeavesTheUnchangedDeviceOutOfBothLists {
    [self assertDiffWithCurrent:{kDeviceA, kDeviceB}
                         desired:{kDeviceA, kDeviceC}
                expectedToRemove:{kDeviceB}
                   expectedToAdd:{kDeviceC}];
}

- (void) testResultOrderMatchesInputOrder {
    [self assertDiffWithCurrent:{kDeviceC, kDeviceB}
                         desired:{kDeviceA, kDeviceC}
                expectedToRemove:{kDeviceB}
                   expectedToAdd:{kDeviceA}];
}

- (void) testDuplicatesInCurrentDontProduceDuplicatesInToRemove {
    [self assertDiffWithCurrent:{kDeviceA, kDeviceA, kDeviceB}
                         desired:{}
                expectedToRemove:{kDeviceA, kDeviceB}
                   expectedToAdd:{}];
}

- (void) testDuplicatesInDesiredDontProduceDuplicatesInToAdd {
    [self assertDiffWithCurrent:{}
                         desired:{kDeviceA, kDeviceA, kDeviceB}
                expectedToRemove:{}
                   expectedToAdd:{kDeviceA, kDeviceB}];
}

@end
