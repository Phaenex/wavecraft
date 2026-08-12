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
//  BGM_ClientsTests.mm
//  BGMDriver
//
//  Copyright © 2016 Kyle Neideck
//

// Unit Include
#include "BGM_Clients.h"

// Local Includes
#include "BGM_TestUtils.h"

// BGMDriver Includes
#include "BGM_Types.h"

// PublicUtility Includes
#include "CACFDictionary.h"


static BGM_TaskQueue taskQueue;

static const AudioServerPlugInClientInfo client1Info = {
    /* mClientID = */ 11,
    /* mProcessID = */ 1181,
    /* mIsNativeEndian = */ true,
    /* mBundleID = */ CFSTR("com.bearisdriving.BGMDriver.ClientOne")
};

static const AudioServerPlugInClientInfo client2Info = {
    /* mClientID = */ 22,
    /* mProcessID = */ 222,
    /* mIsNativeEndian = */ true,
    /* mBundleID = */ CFSTR("com.bearisdriving.BGMDriver.ClientTwo")
};

@interface BGM_ClientsTests : XCTestCase

@end

@implementation BGM_ClientsTests {
    BGM_Clients* clients;
}

- (void)setUp {
    [super setUp];
    
    clients = new BGM_Clients(kAudioObjectUnknown, &taskQueue);
}

- (void)tearDown {
    delete clients;
    
    [super tearDown];
}

- (void)testMusicPlayer {
    // Should be able to set the music player PID before clients have been added
    clients->SetMusicPlayer(441);
    XCTAssertEqual(clients->GetMusicPlayerProcessIDProperty(), 441);
    
    // IsMusicPlayerRT takes a client ID, not a PID
    XCTAssertFalse(clients->IsMusicPlayerRT(441));
    
    // Set the bundle ID
    clients->SetMusicPlayer("com.example.music.player");
    NSString* bundleID = (NSString*)CFBridgingRelease(clients->CopyMusicPlayerBundleIDProperty());
    XCTAssertEqualObjects(bundleID, @"com.example.music.player");
    
    // Setting the bundle ID unsets the PID, and vice versa
    XCTAssertEqual(clients->GetMusicPlayerProcessIDProperty(), 0);
    clients->SetMusicPlayer(2169);
    bundleID = (NSString*)CFBridgingRelease(clients->CopyMusicPlayerBundleIDProperty());
    XCTAssertEqualObjects(bundleID, @"");
    
    // Set client 2's bundle ID as the music player bundle ID
    clients->SetMusicPlayer(client2Info.mBundleID);
    
    // No client can be the music player yet because we haven't added any clients yet
    XCTAssertFalse(clients->IsMusicPlayerRT(client2Info.mClientID));
    
    // When we add client 2 it should become the music player because its bundle ID matches what we set above
    clients->AddClient(&client2Info);
    XCTAssert(clients->IsMusicPlayerRT(client2Info.mClientID));
    XCTAssertFalse(clients->IsMusicPlayerRT(client1Info.mClientID));
    
    // Check the bundle ID property matches client 2's
    CFStringRef bundleIDRef = clients->CopyMusicPlayerBundleIDProperty();
    XCTAssertEqual(bundleIDRef, client2Info.mBundleID);
    CFRelease(bundleIDRef);
    
    // Change the music player to client 1
    clients->AddClient(&client1Info);
    clients->SetMusicPlayer(client1Info.mProcessID);
    
    XCTAssert(clients->IsMusicPlayerRT(client1Info.mClientID));
    XCTAssertFalse(clients->IsMusicPlayerRT(client2Info.mClientID));
    
    // The music player should be unset after removing the music player as a client
    clients->RemoveClient(client1Info.mClientID);
    XCTAssertFalse(clients->IsMusicPlayerRT(client1Info.mClientID));
    
    // ...but the music player PID shouldn't change
    XCTAssertEqual(clients->GetMusicPlayerProcessIDProperty(), client1Info.mProcessID);
}

- (void)testSetMusicPlayerInvalidPID {
    BGMShouldThrow<BGM_InvalidClientPIDException>(self, [=](){
        clients->SetMusicPlayer(-1);
    });

    BGMShouldThrow<BGM_InvalidClientPIDException>(self, [=](){
        clients->SetMusicPlayer(INT_MIN);
    });
}

- (void)testClientEQGainsDefaultToFlat {
    clients->AddClient(&client1Info);

    std::array<Float32, BGM_AppEQ::kNumBands> gains = clients->GetClientEQBandGainsRT(client1Info.mClientID);

    for (Float32 gain : gains) {
        XCTAssertEqual(gain, 0.0f);
    }

    // A client nobody's set anything for shouldn't show up in the property's array at all --
    // matches AppVolumes' "only apps with non-default values" convention.
    CACFArray appEQ = clients->CopyClientEQGainsAsAppEQ();
    XCTAssertEqual(appEQ.GetNumberItems(), (UInt32)0);
}

- (void)testSetClientsEQByBundleIDRoundTrips {
    clients->AddClient(&client1Info);

    CACFArray bandGains(false);
    for (int i = 0; i < BGM_AppEQ::kNumBands; i++) {
        bandGains.AppendFloat64(i == 1 ? 6.0 : -3.0);
    }

    CACFDictionary appEQEntry(false);
    appEQEntry.AddString(CFSTR(kBGMAppEQKey_BundleID), client1Info.mBundleID);
    appEQEntry.AddArray(CFSTR(kBGMAppEQKey_BandGains), bandGains.GetCFArray());

    CACFArray appEQ(false);
    appEQ.AppendDictionary(appEQEntry.GetDict());

    bool didChange = clients->SetClientsEQ(appEQ);
    XCTAssert(didChange);

    std::array<Float32, BGM_AppEQ::kNumBands> gains = clients->GetClientEQBandGainsRT(client1Info.mClientID);
    for (int i = 0; i < BGM_AppEQ::kNumBands; i++) {
        XCTAssertEqualWithAccuracy(gains[static_cast<size_t>(i)], i == 1 ? 6.0f : -3.0f, 0.001f);
    }

    // Setting the exact same gains again still reports "changed" -- matches
    // SetClientsRelativeVolume's existing convention of reporting true whenever a matching
    // client was found, not when the value actually differs from before.
    bool didChangeAgain = clients->SetClientsEQ(appEQ);
    XCTAssert(didChangeAgain);

    // The client should now show up in the property's array, with the gains we set.
    CACFArray appEQArray = clients->CopyClientEQGainsAsAppEQ();
    XCTAssertEqual(appEQArray.GetNumberItems(), (UInt32)1);
}

- (void)testSetClientsEQByPIDRoundTrips {
    clients->AddClient(&client2Info);

    CACFArray bandGains(false);
    for (int i = 0; i < BGM_AppEQ::kNumBands; i++) {
        bandGains.AppendFloat64(2.5);
    }

    CACFDictionary appEQEntry(false);
    appEQEntry.AddSInt32(CFSTR(kBGMAppEQKey_ProcessID), client2Info.mProcessID);
    appEQEntry.AddArray(CFSTR(kBGMAppEQKey_BandGains), bandGains.GetCFArray());

    CACFArray appEQ(false);
    appEQ.AppendDictionary(appEQEntry.GetDict());

    XCTAssert(clients->SetClientsEQ(appEQ));

    std::array<Float32, BGM_AppEQ::kNumBands> gains = clients->GetClientEQBandGainsRT(client2Info.mClientID);
    for (Float32 gain : gains) {
        XCTAssertEqualWithAccuracy(gain, 2.5f, 0.001f);
    }
}

- (void)testSetClientsEQClampsOutOfRangeGains {
    clients->AddClient(&client1Info);

    CACFArray bandGains(false);
    bandGains.AppendFloat64(999.0);   // way above kBGMAppEQMaxGainDB
    bandGains.AppendFloat64(-999.0);  // way below kBGMAppEQMinGainDB
    for (int i = 2; i < BGM_AppEQ::kNumBands; i++) {
        bandGains.AppendFloat64(0.0);
    }

    CACFDictionary appEQEntry(false);
    appEQEntry.AddString(CFSTR(kBGMAppEQKey_BundleID), client1Info.mBundleID);
    appEQEntry.AddArray(CFSTR(kBGMAppEQKey_BandGains), bandGains.GetCFArray());

    CACFArray appEQ(false);
    appEQ.AppendDictionary(appEQEntry.GetDict());

    clients->SetClientsEQ(appEQ);

    std::array<Float32, BGM_AppEQ::kNumBands> gains = clients->GetClientEQBandGainsRT(client1Info.mClientID);
    XCTAssertEqualWithAccuracy(gains[0], static_cast<Float32>(kBGMAppEQMaxGainDB), 0.001f);
    XCTAssertEqualWithAccuracy(gains[1], static_cast<Float32>(kBGMAppEQMinGainDB), 0.001f);
}

@end

