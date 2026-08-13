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
//  BGMTapRouteTests.mm
//  BGMAppUnitTests
//
//  Deliberately limited to construction/validation only -- see the comment at the bottom of this
//  file for why the real tap/aggregate-device/BGMPlayThrough pipeline can't be exercised inside
//  this XCTest target at all (this target links mocked CAHALAudioDevice/CAHALAudioSystemObject
//  implementations, and BGMPlayThrough depends on the real ones).
//

// Unit Include
#import "BGMTapRoute.h"

// Local Includes
#import "BGM_TestUtils.h"


@interface BGMTapRouteTests : XCTestCase
@end

@implementation BGMTapRouteTests

- (void) testConstructorThrowsForInvalidBundleID {
    CACFString invalidBundleID;  // Default-constructed, no CFStringRef -- !IsValid().

    BGMShouldThrow<CAException>(self, [=]() {
        BGMTapRoute route(invalidBundleID);
        (void)route;
    });
}

- (void) testHasOutputDeviceIsFalseForAnyDeviceBeforeAddOutputDeviceIsCalled {
    // Construction alone (no Start(), no AddOutputDevice()) shouldn't claim any device is one of
    // this route's outputs -- kAudioObjectUnknown is a valid AudioObjectID to wrap even though
    // it's not a real device, which is fine here since this never actually starts the route.
    CACFString bundleID((__bridge_retained CFStringRef)@"com.example.placeholder");
    BGMTapRoute route(bundleID);
    BGMAudioDevice placeholderDevice(kAudioObjectUnknown);

    XCTAssertFalse(route.HasOutputDevice(placeholderDevice));
    XCTAssertTrue(route.GetOutputDevices().empty());
}

// NOTE: There's deliberately no real-device functional test here (there was one; it crashed and
// was removed -- see docs/LESSONS.md for the full story). This whole target links
// Mock_CAHALAudioSystemObject.cpp/Mock_CAHALAudioDevice.cpp in place of the real
// implementations, so ANY CAHALAudioDevice/CAHALAudioSystemObject interaction in this target
// hits the mock layer -- including a real aggregate device's ID, which isn't registered with it.
// BGMTapRoute's actual pipeline depends on BGMPlayThrough, which depends heavily on
// CAHALAudioDevice (GetCurrentVirtualFormats, SetNominalSampleRate, etc.), so there's no way to
// exercise the real integration inside this XCTest target regardless of how the test is written.
// Real verification needs either an out-of-target harness or actual manual use once there's UI
// to trigger it.

@end
