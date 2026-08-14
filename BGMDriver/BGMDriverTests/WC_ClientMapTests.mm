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
//  WC_ClientMapTests.mm
//  BGMDriver
//
//  Copyright © 2016 Kyle Neideck
//

// Unit Include
#include "WC_ClientMap.h"

// Local Includes
#include "BGM_TestUtils.h"

// BGMDriver Includes
#include "WC_Client.h"
#include "WC_TaskQueue.h"
#include "BGM_Types.h"


static WC_TaskQueue taskQueue;

static const AudioServerPlugInClientInfo client1Info = {
    /* mClientID = */ 1,
    /* mProcessID = */ 2291,
    /* mIsNativeEndian = */ true,
    /* mBundleID = */ CFSTR("com.example.background.music.client.one")
};

static const AudioServerPlugInClientInfo client2Info = {
    /* mClientID = */ 921,
    /* mProcessID = */ 64372,
    /* mIsNativeEndian = */ true,
    /* mBundleID = */ CFSTR("com.example.background.music.client.two")
};

static WC_Client client1(&client1Info);
static WC_Client client2(&client2Info);

@interface WC_ClientMapTests : XCTestCase

@end

@implementation WC_ClientMapTests

- (void)setUp {
    [super setUp];
    
    client1.mRelativeVolume = 0.625;
    client2.mIsMusicPlayer = true;
}

- (void)tearDown {
    [super tearDown];
}

// Asserts that in client the fields that come from AudioServerPlugInClientInfo are equal to the
// corresponding fields in info.
//
// Requires that the mBundleID fields of both are either NULL or have not been released.
+ (void)assertClient:(const WC_Client*)client
      hasInfoEqualTo:(const AudioServerPlugInClientInfo*)info {
    XCTAssertEqual(client->mClientID, info->mClientID);
    XCTAssertEqual(client->mProcessID, info->mProcessID);
    XCTAssertEqual(client->mIsNativeEndian, info->mIsNativeEndian);
    
    if (!client->mBundleID.IsValid() || info->mBundleID == NULL) {
        XCTAssert(!client->mBundleID.IsValid());
        XCTAssert(info->mBundleID == NULL);
    } else {
        XCTAssert(client->mBundleID == info->mBundleID);
    }
}

// Requires that the mBundleID fields of both clients are either NULL or have not been released.
+ (void)assertClient:(const WC_Client*)c1
           isEqualTo:(const WC_Client*)c2 {
    const AudioServerPlugInClientInfo info =
        { c2->mClientID, c2->mProcessID, c2->mIsNativeEndian, c2->mBundleID.GetCFString() };
    
    [WC_ClientMapTests assertClient:c1 hasInfoEqualTo:&info];
    
    XCTAssertEqual(c1->mIsMusicPlayer, c2->mIsMusicPlayer);
    XCTAssertEqual(c1->mRelativeVolume, c2->mRelativeVolume);
}

- (void)testClientConstruction {
    // Check that the WC_Client instances we're testing with match the AudioServerPlugInClientInfos
    // they were constructed from.
    //
    // TODO: This should be in a BGM_ClientTests class rather than here.
    [WC_ClientMapTests assertClient:&client1 hasInfoEqualTo:&client1Info];
    [WC_ClientMapTests assertClient:&client2 hasInfoEqualTo:&client2Info];
}

- (void)testAddRemoveClient {
    WC_ClientMap clientMap(&taskQueue);
    
    // Add a client
    clientMap.AddClient(client1);
    
    // Get the client back out of the map
    WC_Client retrievedClient;
    bool didGetClient = clientMap.GetClientNonRT(client1.mClientID, &retrievedClient);
    XCTAssert(didGetClient);
    
    // Compare the client we added to the one we got back
    [WC_ClientMapTests assertClient:&retrievedClient isEqualTo:&client1];
    [WC_ClientMapTests assertClient:&retrievedClient hasInfoEqualTo:&client1Info];
    
    // A client to use as the out argument for GetClientNonRT when we don't expect to get a client back
    WC_Client notRetrievedClient(&client2Info);
    notRetrievedClient.mRelativeVolume = 3.5;
    
    // A known-good copy to check against
    WC_Client notRetrievedClientCopy(notRetrievedClient);
    
    // Try getting a client that we never added
    didGetClient = clientMap.GetClientNonRT(/* inClientID = */ 12345, &retrievedClient);
    XCTAssertFalse(didGetClient);
    [WC_ClientMapTests assertClient:&notRetrievedClient isEqualTo:&notRetrievedClientCopy];
    
    // Remove the client
    WC_Client removedClient = clientMap.RemoveClient(client1.mClientID);
    
    // Check that the client RemoveClient says we removed matches the one we added in the first place
    [WC_ClientMapTests assertClient:&removedClient isEqualTo:&client1];
    
    // We shouldn't be able to get the client after we've removed it
    didGetClient = clientMap.GetClientNonRT(client1Info.mClientID, &notRetrievedClient);
    XCTAssertFalse(didGetClient);
    
    // Calling GetClientNonRT should have left notRetrievedClient unchanged
    [WC_ClientMapTests assertClient:&notRetrievedClient isEqualTo:&notRetrievedClientCopy];
    
    // Check against hardcoded values as well just in case there's a problem with WC_Client's copy constructor
    XCTAssertEqual(notRetrievedClient.mRelativeVolume, 3.5);
}

- (void)testAddRemoveMultipleClients {
    WC_ClientMap clientMap(&taskQueue);
    
    // Add the clients
    clientMap.AddClient(client1);
    clientMap.AddClient(client2);
    
    // Get both clients from the map and check they match what we added
    {
        WC_Client retrievedClient1, retrievedClient2;
        bool didGetClient = clientMap.GetClientNonRT(client1Info.mClientID, &retrievedClient1);
        XCTAssert(didGetClient);
        [WC_ClientMapTests assertClient:&retrievedClient1 isEqualTo:&client1];
        
        didGetClient = clientMap.GetClientNonRT(client2Info.mClientID, &retrievedClient2);
        XCTAssert(didGetClient);
        [WC_ClientMapTests assertClient:&retrievedClient2 isEqualTo:&client2];
    }
    
    // Remove one and check we can still get the other
    clientMap.RemoveClient(client1Info.mClientID);
    
    {
        WC_Client retrievedClient2;
        bool didGetClient = clientMap.GetClientNonRT(client2Info.mClientID, &retrievedClient2);
        XCTAssert(didGetClient);
        [WC_ClientMapTests assertClient:&retrievedClient2 isEqualTo:&client2];
    }
    
    // Remove the other
    WC_Client removedClient = clientMap.RemoveClient(client2Info.mClientID);
    [WC_ClientMapTests assertClient:&removedClient isEqualTo:&client2];
    
    // Check that we can't get either client from the map anymore
    const AudioServerPlugInClientInfo notRetrievedClientInfo = { 5, 10, true, CFSTR("not.retrieved.client") };
    WC_Client notRetrievedClient(&notRetrievedClientInfo);
    
    bool didGetClient = clientMap.GetClientNonRT(client1Info.mClientID, &notRetrievedClient);
    XCTAssertFalse(didGetClient);
    [WC_ClientMapTests assertClient:&notRetrievedClient hasInfoEqualTo:&notRetrievedClientInfo];
    
    didGetClient = clientMap.GetClientNonRT(client2Info.mClientID, &notRetrievedClient);
    XCTAssertFalse(didGetClient);
    [WC_ClientMapTests assertClient:&notRetrievedClient hasInfoEqualTo:&notRetrievedClientInfo];
}

- (void)testAddClientSeveralTimes {
    WC_ClientMap clientMap(&taskQueue);
    
    // Adding a client once should work
    clientMap.AddClient(client2);
    
    // Adding a different client should work
    clientMap.AddClient(client1);
    
    // Adding the same client twice should fail
    BGMShouldThrow<WC_InvalidClientException>(self, [&](){
        clientMap.AddClient(client2);
    });
    
    // Adding the other client again should fail too
    BGMShouldThrow<WC_InvalidClientException>(self, [&](){
        clientMap.AddClient(client1);
    });
}

@end

