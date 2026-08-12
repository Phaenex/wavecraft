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
//  BGM_DeviceTests.mm
//  BGMDriver
//
//  Copyright © 2016, 2026 Kyle Neideck
//

// Unit Include
#include "BGM_Device.h"

// Local Includes
#include "BGM_TestUtils.h"

// BGMDriver Includes
#include "BGM_Types.h"

// PublicUtility Includes
#include "CAException.h"

// STL Includes
#include <atomic>
#include <stdexcept>
#include <thread>
#include <vector>


// Subclass BGM_Device to add some test-only functions.
class TestBGM_Device
:
    public BGM_Device
{

public:
    TestBGM_Device();
    ~TestBGM_Device() = default;

};

TestBGM_Device::TestBGM_Device()
:
    BGM_Device(kObjectID_Device,
               CFSTR(kDeviceName),
               CFSTR(kBGMDeviceUID),
               CFSTR(kBGMDeviceModelUID),
               kObjectID_Stream_Input,
               kObjectID_Stream_Output,
               kObjectID_Volume_Output_Main,
               kObjectID_Mute_Output_Main)
{
    Activate();
}


@interface BGM_DeviceTests : XCTestCase {
    TestBGM_Device* testDevice;
}

@end


@implementation BGM_DeviceTests

- (void) setUp {
    [super setUp];
    testDevice = new TestBGM_Device();
}

- (void) tearDown {
    delete testDevice;
    [super tearDown];
}

- (void) testDoIOOperation_writeMix_readInput {
    // The number of audio frames to send/receive in the IO operations.
    const int kFrameSize = 512;

    // Choose a sample time that will make the data wrap around to the start of the device's
    // internal ring buffer.
    AudioServerPlugInIOCycleInfo cycleInfo {};
    cycleInfo.mOutputTime.mSampleTime = kLoopbackRingBufferFrameSize - 25.0;

    // Generate the test input data.
    Float32 inputBuffer[kFrameSize * 2];

    for(int i = 0; i < kFrameSize * 2; i++)
    {
        inputBuffer[i] = static_cast<Float32>(i);
    }

    // Send a copy of the input buffer just in case DoIOOperation modifies the data for some reason.
    Float32 inputBufferCopy[kFrameSize * 2];
    memcpy(inputBufferCopy, inputBuffer, sizeof(inputBuffer));

    // Send the input data to the device.
    testDevice->DoIOOperation(/* inStreamObjectID = */ kObjectID_Stream_Output,
                              /* inClientID = */ 0,
                              /* inOperationID = */ kAudioServerPlugInIOOperationWriteMix,
                              /* inIOBufferFrameSize = */ kFrameSize,
                              /* inIOCycleInfo = */ cycleInfo,
                              /* ioMainBuffer = */ inputBuffer,
                              /* ioSecondaryBuffer = */ nullptr);

    // Request data from the same point in time so we get the same data back.
    cycleInfo.mInputTime.mSampleTime = kLoopbackRingBufferFrameSize - 25.0;

    // Read the data back from the device.
    Float32 outputBuffer[kFrameSize * 2];

    testDevice->DoIOOperation(/* inStreamObjectID = */ kObjectID_Stream_Output,
                              /* inClientID = */ 0,
                              /* inOperationID = */ kAudioServerPlugInIOOperationReadInput,
                              /* inIOBufferFrameSize = */ kFrameSize,
                              /* inIOCycleInfo = */ cycleInfo,
                              /* ioMainBuffer = */ outputBuffer,
                              /* ioSecondaryBuffer = */ nullptr);

    // Check the output matches the input.
    for(int i = 0; i < kFrameSize * 2; i++)
    {
        XCTAssertEqual(inputBuffer[i], outputBuffer[i]);
    }
}

- (void) testCustomPropertyMusicPlayerBundleID {
    // Convenience wrappers
    auto getBundleID = [&](UInt32 inDataSize = sizeof(CFStringRef)){
        CFStringRef bundleID = nullptr;
        UInt32 outDataSize;
        
        testDevice->GetPropertyData(/* inObjectID = */ kObjectID_Device,
                                    /* inClientPID = */ 3,
                                    /* inAddress = */ kBGMMusicPlayerBundleIDAddress,
                                    /* inQualifierDataSize = */ 0,
                                    /* inQualifierData = */ nullptr,
                                    /* inDataSize = */ inDataSize,
                                    /* outDataSize = */ outDataSize,
                                    /* outData = */ reinterpret_cast<void* __nonnull>(&bundleID));
        
        // This isn't technically required, but we're unlikely to ever want to return any more/less data from GetPropertyData.
        XCTAssertEqual(outDataSize, sizeof(CFStringRef));
        
        return (__bridge_transfer NSString*)bundleID;
    };
    
    auto setBundleID = [&](const CFStringRef* __nullable bundleID, UInt32 dataSize = sizeof(CFStringRef)){
        testDevice->SetPropertyData(/* inObjectID = */ kObjectID_Device,
                                    /* inClientPID = */ 1234,
                                    /* inAddress = */ kBGMMusicPlayerBundleIDAddress,
                                    /* inQualifierDataSize = */ 0,
                                    /* inQualifierData = */ nullptr,
                                    /* inDataSize = */ dataSize,
                                    /* inData = */ reinterpret_cast<const void* __nonnull>(bundleID));
    };
    
    // Should be set to the empty string by default.
    XCTAssertEqualObjects(getBundleID(), @"");
    
    // Should be able to set the property to an arbitrary string. (Purposefully not using CFSTR for this one just in case it
    // makes a difference.)
    CFStringRef newID = CFStringCreateWithCString(kCFAllocatorDefault, "test.bundle.ID", kCFStringEncodingUTF8);
    setBundleID(&newID);
    CFRelease(newID);
    XCTAssertEqualObjects(getBundleID(), @"test.bundle.ID");
    
    // Should be able to set the property back to the empty string.
    newID = CFSTR("");
    setBundleID(&newID);
    XCTAssertEqualObjects(getBundleID(), @"");
    
    // Arguments should be null-checked.
    BGMShouldThrow<std::runtime_error>(self, [&](){
        UInt32 outDataSize;
        testDevice->GetPropertyData(kObjectID_Device, 0, kBGMMusicPlayerBundleIDAddress, 0, nullptr,
                                    sizeof(CFStringRef), outDataSize,
                                    /* outData = */ reinterpret_cast<void* __nonnull>(NULL));
    });
    BGMShouldThrow<std::runtime_error>(self, [&](){
        setBundleID(nullptr);
    });
    
    // Invalid data should be rejected.
    BGMShouldThrow<CAException>(self, [&](){
        setBundleID((CFStringRef*)&kCFNull);
    });
    BGMShouldThrow<CAException>(self, [&](){
        CFStringRef nullRef = nullptr;
        setBundleID(&nullRef);
    });
    BGMShouldThrow<CAException>(self, [&](){
        CFArrayRef array = (__bridge_retained CFArrayRef)@[ @1, @2 ];
        setBundleID((CFStringRef*)&array);
    });
    
    // Should throw if not given enough space for the return data.
    BGMShouldThrow<CAException>(self, [&](){
        getBundleID(/* inDataSize = */ 0);
    });
    
    newID = CFSTR("bundle");
    
    // Passing more data than needed should be fine as long as it starts with a CFStringRef.
    setBundleID(&newID, sizeof(CFStringRef) * 2);
    
    // Should throw if not enough data is passed.
    BGMShouldThrow<CAException>(self, [&](){
        setBundleID(&newID, sizeof(CFStringRef) - 1);
    });
}

- (void) testCustomPropertyInfoListSizeMatchesActualEntryCount {
    // Regression test for a real bug found on this fork's first install: Device_GetPropertyData
    // for kAudioObjectPropertyCustomPropertyInfoList grew to include
    // kAudioDeviceCustomPropertyAppEQ as an 8th entry, but Device_GetPropertyDataSize for the same
    // selector was left declaring 7. A well-behaved HAL client sizes its buffer from the size
    // query, and Device_GetPropertyData's own clamp ("theNumberItemsToFetch =
    // inDataSize / sizeof(...)") silently agrees with that undersized buffer -- so the mismatch
    // doesn't fail loudly, it just makes the 8th (and any later) custom property invisible to
    // property discovery. AudioObjectGetPropertyData for kAudioDeviceCustomPropertyAppEQ then
    // fails with kAudioHardwareUnknownPropertyError ('who?') for any real HAL client, even though
    // Device_GetPropertyData itself handles that selector correctly -- confirmed by reproducing
    // the crash this caused in BGMApp and tracing it back to this exact mismatch.
    AudioObjectPropertyAddress infoListAddress = {
        kAudioObjectPropertyCustomPropertyInfoList,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 declaredSize = testDevice->GetPropertyDataSize(kObjectID_Device, 0, infoListAddress,
                                                           0, nullptr);

    // Ask for far more entries than we expect, so Device_GetPropertyData's own internal clamp
    // can't hide an undercount from us the way it would if we naively reused declaredSize as the
    // buffer size for both calls.
    const UInt32 kGenerousCount = 32;
    AudioServerPlugInCustomPropertyInfo buffer[kGenerousCount];
    UInt32 actualSize;

    testDevice->GetPropertyData(kObjectID_Device, 0, infoListAddress, 0, nullptr, sizeof(buffer),
                                actualSize, buffer);

    XCTAssertEqual(declaredSize, actualSize,
                    @"GetPropertyDataSize's declared byte count for the custom property info list "
                     "must match how many bytes GetPropertyData actually fills in, or a caller "
                     "that sizes its buffer from the size query silently truncates the list");

    UInt32 numEntries = actualSize / static_cast<UInt32>(sizeof(AudioServerPlugInCustomPropertyInfo));
    NSMutableSet<NSNumber*>* selectors = [NSMutableSet new];
    for (UInt32 i = 0; i < numEntries; i++) {
        [selectors addObject:@(buffer[i].mSelector)];
    }

    // Every custom property this device implements (see Device_HasProperty) must be discoverable
    // here, or AudioObjectGetPropertyData fails for it from any real HAL client.
    NSArray<NSNumber*>* expectedSelectors = @[
        @(kAudioDeviceCustomPropertyAppVolumes),
        @(kAudioDeviceCustomPropertyMusicPlayerProcessID),
        @(kAudioDeviceCustomPropertyMusicPlayerBundleID),
        @(kAudioDeviceCustomPropertyDeviceIsRunningSomewhereOtherThanBGMApp),
        @(kAudioDeviceCustomPropertyDeviceAudibleState),
        @(kAudioDeviceCustomPropertyEnabledOutputControls),
        @(kAudioDeviceCustomPropertyDebugLoggingEnabled),
        @(kAudioDeviceCustomPropertyAppEQ),
    ];

    for (NSNumber* selector in expectedSelectors) {
        XCTAssertTrue([selectors containsObject:selector],
                      @"Custom property selector %@ is missing from "
                       "kAudioObjectPropertyCustomPropertyInfoList", selector);
    }
}

- (void) testConcurrentAddRemoveClientDuringProcessOutputDoesNotCorruptEQProcessorMap {
    // Regression test for a real data race found in this fork: DoIOOperation's ProcessOutput case
    // used to call ApplyClientEQ/ApplyClientRelativeVolume *after* the CAMutex::Locker guarding
    // mIOMutex had already gone out of scope, so ApplyClientEQ's mClientEQProcessors.find() ran
    // completely unsynchronized against AddClient/RemoveClient inserting/erasing from the same
    // std::map on a different thread -- exactly the kind of concurrent mutation that corrupts a
    // std::map's internal tree. See docs/LESSONS.md.
    //
    // This can't *prove* the race is fixed the way a Thread Sanitizer run could (this project
    // doesn't have a TSan build variant configured, and can't easily add one since the existing
    // Debug/test config already links ASan+UBSan, which TSan can't run alongside) -- it's a
    // best-effort exerciser, not a formal proof. But it's not just theoretical: reverting the fix
    // (putting ApplyClientEQ/ApplyClientRelativeVolume back outside theIOLocker's scope) and
    // running this test reproduced a real SIGABRT crash 3/3 times, every time in well under a
    // second; running it 3/3 times against the actual fix passed clean every time. That's the
    // verification this test is checked in for -- it isn't a synthetic worst case, it reliably
    // reproduced the exact crash this fork hit in real use.

    // A client that stays registered for the whole test, so the IO threads always have something
    // real to look up in mClientEQProcessors.
    AudioServerPlugInClientInfo stableClientInfo {};
    stableClientInfo.mClientID = 100;
    stableClientInfo.mProcessID = 100;
    stableClientInfo.mIsNativeEndian = true;
    stableClientInfo.mBundleID = CFSTR("test.stable.client");
    testDevice->AddClient(&stableClientInfo);

    std::atomic<bool> stop { false };
    std::atomic<bool> ioThreadThrew { false };

    // Several reader threads, all repeatedly running the real-time ProcessOutput path for the
    // stable client -- this is what calls ApplyClientEQ's mClientEQProcessors.find(). More
    // concurrent readers means more chances to land inside a churn thread's insert/erase.
    const int kReaderThreadCount = 4;
    std::vector<std::thread> readerThreads;

    for (int t = 0; t < kReaderThreadCount; t++) {
        readerThreads.emplace_back([&]{
            const UInt32 kFrameSize = 64;
            Float32 buffer[kFrameSize * 2] = {};
            AudioServerPlugInIOCycleInfo cycleInfo {};

            try {
                while (!stop.load(std::memory_order_relaxed)) {
                    testDevice->DoIOOperation(
                        /* inStreamObjectID = */ kObjectID_Stream_Output,
                        /* inClientID = */ stableClientInfo.mClientID,
                        /* inOperationID = */ kAudioServerPlugInIOOperationProcessOutput,
                        /* inIOBufferFrameSize = */ kFrameSize,
                        /* inIOCycleInfo = */ cycleInfo,
                        /* ioMainBuffer = */ buffer,
                        /* ioSecondaryBuffer = */ nullptr);
                }
            } catch (...) {
                ioThreadThrew.store(true, std::memory_order_relaxed);
            }
        });
    }

    // Several churn threads, each repeatedly adding/removing clients with their own range of
    // distinct IDs -- distinct keys (rather than one ID repeatedly re-inserted) force more actual
    // tree rebalancing in mClientEQProcessors's underlying std::map, which is what an unsynchronized
    // concurrent find() is unsafe against.
    const int kChurnThreadCount = 4;
    const int kIterationsPerChurnThread = 5000;
    std::vector<std::thread> churnThreads;

    for (int t = 0; t < kChurnThreadCount; t++) {
        churnThreads.emplace_back([&, t]{
            for (int i = 0; i < kIterationsPerChurnThread; i++) {
                AudioServerPlugInClientInfo churnClientInfo {};
                churnClientInfo.mClientID = static_cast<UInt32>(1000 + (t * kIterationsPerChurnThread) + i);
                churnClientInfo.mProcessID = static_cast<pid_t>(churnClientInfo.mClientID);
                churnClientInfo.mIsNativeEndian = true;
                churnClientInfo.mBundleID = CFSTR("test.churn.client");

                testDevice->AddClient(&churnClientInfo);
                testDevice->RemoveClient(&churnClientInfo);
            }
        });
    }

    for (auto& churnThread : churnThreads) {
        churnThread.join();
    }

    stop.store(true, std::memory_order_relaxed);

    for (auto& readerThread : readerThreads) {
        readerThread.join();
    }

    XCTAssertFalse(ioThreadThrew.load(),
                    @"DoIOOperation threw on a reader thread during concurrent AddClient/RemoveClient");

    testDevice->RemoveClient(&stableClientInfo);
}

// TODO: Performance tests?
- (void) testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end

