// tap_poc.mm
//
// Standalone proof-of-concept for per-app output routing (see
// docs/PROCESS-TAP-ROUTING.md). Taps a single app by bundle ID, mutes its
// normal output, wraps the tap in an aggregate device, and reports whether
// real (non-silent) audio frames actually arrive over a run window.
//
// This exists to answer three questions empirically before any UI or
// persistence gets built on top:
//   1. Does AudioHardwareCreateProcessTap succeed for an ad-hoc "Sign to Run
//      Locally" signed build, or does it need a real Developer ID?
//   2. Does macOS prompt for a new TCC permission the first time, and if so
//      which one and where does the user grant it?
//   3. Does muteBehavior = CATapMuted actually silence the target app's
//      normal output while still delivering audio to the tap?
//
// Usage: ./tap_poc <bundle-id> <seconds-to-run>
// Example: ./tap_poc com.apple.Music 8

#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <atomic>
#include <cstdio>

static std::atomic<uint64_t> gFramesSeen{0};
static std::atomic<uint64_t> gNonSilentFrames{0};
static std::atomic<double> gPeakAbsSample{0.0};

static OSStatus TapIOProc(AudioObjectID inDevice,
                           const AudioTimeStamp* inNow,
                           const AudioBufferList* inInputData,
                           const AudioTimeStamp* inInputTime,
                           AudioBufferList* outOutputData,
                           const AudioTimeStamp* inOutputTime,
                           void* inClientData) {
    #pragma unused(inDevice, inNow, inInputTime, outOutputData, inOutputTime, inClientData)

    for (UInt32 buf = 0; buf < inInputData->mNumberBuffers; buf++) {
        const AudioBuffer& b = inInputData->mBuffers[buf];
        UInt32 sampleCount = b.mDataByteSize / sizeof(Float32);
        const Float32* samples = static_cast<const Float32*>(b.mData);

        gFramesSeen += sampleCount;

        for (UInt32 i = 0; i < sampleCount; i++) {
            double v = fabs(static_cast<double>(samples[i]));
            if (v > 0.0001) {
                gNonSilentFrames++;
            }
            double prevPeak = gPeakAbsSample.load();
            if (v > prevPeak) {
                gPeakAbsSample.store(v);
            }
        }
    }

    return noErr;
}

static void PrintOSStatusError(const char* what, OSStatus status) {
    char fourcc[5] = {0};
    UInt32 be = CFSwapInt32HostToBig((UInt32)status);
    memcpy(fourcc, &be, 4);
    bool printable = true;
    for (int i = 0; i < 4; i++) {
        if (fourcc[i] < 32 || fourcc[i] > 126) { printable = false; break; }
    }
    if (printable) {
        fprintf(stderr, "FAIL: %s failed: %d ('%s')\n", what, (int)status, fourcc);
    } else {
        fprintf(stderr, "FAIL: %s failed: %d\n", what, (int)status);
    }
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "Usage: %s <bundle-id | --pid PID> [seconds-to-run=8]\n", argv[0]);
            return 2;
        }

        BOOL usePID = (strcmp(argv[1], "--pid") == 0);
        NSString* bundleID = nil;
        pid_t targetPID = 0;
        int seconds = 8;

        if (usePID) {
            if (argc < 3) {
                fprintf(stderr, "Usage: %s --pid PID [seconds-to-run=8]\n", argv[0]);
                return 2;
            }
            targetPID = (pid_t)atoi(argv[2]);
            seconds = argc >= 4 ? atoi(argv[3]) : 8;
        } else {
            bundleID = [NSString stringWithUTF8String:argv[1]];
            seconds = argc >= 3 ? atoi(argv[2]) : 8;
        }

        printf("== Process Tap proof-of-concept ==\n");
        if (usePID) {
            printf("Target PID: %d\n", (int)targetPID);
        } else {
            printf("Target bundle ID: %s\n", bundleID.UTF8String);
        }
        printf("Run window: %d seconds\n\n", seconds);

        // Step 1: build the tap description.
        CATapDescription* desc = [[CATapDescription alloc] init];

        if (usePID) {
            AudioObjectID processObjectID = kAudioObjectUnknown;
            UInt32 poidSize = sizeof(processObjectID);
            AudioObjectPropertyAddress translateAddr = {
                kAudioHardwarePropertyTranslatePIDToProcessObject,
                kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
            };
            pid_t qualifierPID = targetPID;
            OSStatus tstatus = AudioObjectGetPropertyData(kAudioObjectSystemObject, &translateAddr,
                                                            sizeof(qualifierPID), &qualifierPID,
                                                            &poidSize, &processObjectID);
            if (tstatus != noErr || processObjectID == kAudioObjectUnknown) {
                PrintOSStatusError("TranslatePIDToProcessObject", tstatus);
                fprintf(stderr, "PID %d may not have any active CoreAudio output yet.\n", (int)targetPID);
                return 1;
            }
            printf("PASS: PID %d -> process AudioObjectID %u\n", (int)targetPID, (unsigned)processObjectID);
            desc.processes = @[ @(processObjectID) ];
        } else {
            desc.bundleIDs = @[bundleID];
        }

        desc.exclusive = NO;
        desc.mono = NO;
        desc.mixdown = YES;
        desc.privateTap = YES;
        desc.muteBehavior = CATapMuted;
        desc.name = @"mac-volume-mixer tap-poc";

        AudioObjectID tapID = kAudioObjectUnknown;
        printf("Calling AudioHardwareCreateProcessTap...\n");
        OSStatus status = AudioHardwareCreateProcessTap(desc, &tapID);
        if (status != noErr) {
            PrintOSStatusError("AudioHardwareCreateProcessTap", status);
            fprintf(stderr, "\nIf this is an authorization error, check System Settings ->\n"
                             "Privacy & Security for a new permission category (likely grouped\n"
                             "with Screen & System Audio Recording) and grant it to this binary's\n"
                             "host process, then re-run.\n");
            return 1;
        }
        printf("PASS: tap created, AudioObjectID = %u\n", (unsigned)tapID);

        // Step 2: get the tap's UID (needed to attach it to an aggregate device).
        CFStringRef tapUID = nullptr;
        UInt32 uidSize = sizeof(tapUID);
        AudioObjectPropertyAddress uidAddr = {
            kAudioTapPropertyUID, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
        };
        status = AudioObjectGetPropertyData(tapID, &uidAddr, 0, nullptr, &uidSize, &tapUID);
        if (status != noErr || tapUID == nullptr) {
            PrintOSStatusError("AudioObjectGetPropertyData(kAudioTapPropertyUID)", status);
            AudioHardwareDestroyProcessTap(tapID);
            return 1;
        }
        printf("PASS: tap UID = %s\n", CFStringGetCStringPtr(tapUID, kCFStringEncodingUTF8));

        // Step 3: wrap the tap in a private aggregate device.
        NSDictionary* subTap = @{ @(kAudioSubTapUIDKey) : (__bridge NSString*)tapUID };
        NSDictionary* aggregateDict = @{
            @(kAudioAggregateDeviceNameKey) : @"mac-volume-mixer tap-poc aggregate",
            @(kAudioAggregateDeviceUIDKey) : [[NSUUID UUID] UUIDString],
            @(kAudioAggregateDeviceIsPrivateKey) : @YES,
            @(kAudioAggregateDeviceTapAutoStartKey) : @YES,
            @(kAudioAggregateDeviceTapListKey) : @[ subTap ],
        };

        AudioObjectID aggregateID = kAudioObjectUnknown;
        printf("Calling AudioHardwareCreateAggregateDevice...\n");
        status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)aggregateDict, &aggregateID);
        if (status != noErr) {
            PrintOSStatusError("AudioHardwareCreateAggregateDevice", status);
            CFRelease(tapUID);
            AudioHardwareDestroyProcessTap(tapID);
            return 1;
        }
        printf("PASS: aggregate device created, AudioObjectID = %u\n", (unsigned)aggregateID);

        // Step 4: install an IOProc and run for the window, counting real samples.
        AudioDeviceIOProcID ioProcID = nullptr;
        status = AudioDeviceCreateIOProcID(aggregateID, TapIOProc, nullptr, &ioProcID);
        if (status != noErr) {
            PrintOSStatusError("AudioDeviceCreateIOProcID", status);
        } else {
            status = AudioDeviceStart(aggregateID, ioProcID);
            if (status != noErr) {
                PrintOSStatusError("AudioDeviceStart", status);
            } else {
                printf("PASS: IOProc running. Play audio in the target app now.\n");
                printf("Listening for %d seconds...\n", seconds);
                for (int i = 0; i < seconds; i++) {
                    sleep(1);
                    printf("  t+%ds: frames seen = %llu, non-silent = %llu, peak |sample| = %.5f\n",
                           i + 1,
                           (unsigned long long)gFramesSeen.load(),
                           (unsigned long long)gNonSilentFrames.load(),
                           gPeakAbsSample.load());
                }
                AudioDeviceStop(aggregateID, ioProcID);
            }
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID);
        }

        // Cleanup.
        AudioHardwareDestroyAggregateDevice(aggregateID);
        CFRelease(tapUID);
        AudioHardwareDestroyProcessTap(tapID);

        printf("\n== Result ==\n");
        printf("Total frames seen: %llu\n", (unsigned long long)gFramesSeen.load());
        printf("Non-silent frames: %llu\n", (unsigned long long)gNonSilentFrames.load());
        printf("Peak |sample|: %.5f\n", gPeakAbsSample.load());

        if (gNonSilentFrames.load() > 0) {
            printf("\nPASS: real, non-silent audio was captured from the tap.\n");
            printf("Manually confirm by ear whether the target's normal output was muted during the run.\n");
            return 0;
        } else if (gFramesSeen.load() > 0) {
            printf("\nBORDERLINE: frames arrived but were all silence. Either nothing was\n"
                   "playing in the target app during the run, or the tap is attached but not\n"
                   "receiving real audio. Re-run while actively playing audio in the target app.\n");
            return 1;
        } else {
            printf("\nFAIL: no frames arrived at all. The IOProc likely wasn't actually\n"
                   "running against real hardware I/O, or the tap never attached to a live app.\n");
            return 1;
        }
    }
}
