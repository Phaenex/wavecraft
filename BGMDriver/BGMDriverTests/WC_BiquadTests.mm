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
//  WC_BiquadTests.mm
//  BGMDriverTests
//
//  These tests feed a real sine wave through the filter and measure the
//  actual RMS gain, rather than just checking the filter runs -- a biquad
//  with a coefficient sign error still produces *a* number for every input,
//  so "doesn't crash" proves nothing about correctness here.
//

// Unit Include
#include "WC_Biquad.h"

// System Includes
#import <XCTest/XCTest.h>
#include <cmath>
#include <vector>


static const double kSampleRate = 48000.0;

// Runs inNumSamples of a sine wave at inFreqHz through inBiquad (mono, left
// channel only) and returns the ratio of output RMS to input RMS. Skips the
// first kSettleSamples to let the filter's transient response die out --
// judging steady-state gain from samples that include the filter's attack
// would understate or overstate the true gain depending on where the
// measurement window happens to start.
static double MeasureRMSGain(WC_Biquad& inBiquad, double inFreqHz, int inNumSamples)
{
    const int kSettleSamples = 2000;
    double sumInSq = 0.0;
    double sumOutSq = 0.0;
    int measured = 0;

    for (int i = 0; i < inNumSamples; i++)
    {
        Float32 x = static_cast<Float32>(std::sin(2.0 * M_PI * inFreqHz * i / kSampleRate));
        Float32 y = inBiquad.ProcessSample(0, x);

        if (i >= kSettleSamples)
        {
            sumInSq += static_cast<double>(x) * x;
            sumOutSq += static_cast<double>(y) * y;
            measured++;
        }
    }

    double rmsIn = std::sqrt(sumInSq / measured);
    double rmsOut = std::sqrt(sumOutSq / measured);

    return rmsOut / rmsIn;
}

static double RatioToDB(double inRatio)
{
    return 20.0 * std::log10(inRatio);
}

@interface WC_BiquadTests : XCTestCase
@end

@implementation WC_BiquadTests

// At 0dB gain, the filter should be unity -- output should equal input
// exactly, since ProcessSample takes the fast path and skips the filter
// math entirely for a 0dB band.
- (void) testZeroGainIsExactUnity
{
    WC_Biquad biquad;
    biquad.SetParameters(1000.0, kSampleRate, 0.0, 1.0);

    for (int i = 0; i < 100; i++)
    {
        Float32 x = static_cast<Float32>(std::sin(2.0 * M_PI * 1000.0 * i / kSampleRate));
        Float32 y = biquad.ProcessSample(0, x);
        XCTAssertEqual(x, y);
    }
}

// A boost at a band's own center frequency should measure close to the
// requested gain, not just "louder than input".
- (void) testBoostAtCenterFrequencyMatchesRequestedGain
{
    for (double centerFreq : WC_AppEQ::kBandCenterFreqs)
    {
        WC_Biquad biquad;
        biquad.SetParameters(centerFreq, kSampleRate, /* gain dB */ 6.0, 1.0);

        double measuredDB = RatioToDB(MeasureRMSGain(biquad, centerFreq, 8192));

        XCTAssertEqualWithAccuracy(measuredDB, 6.0, 0.5,
                @"Band at %.0f Hz: expected ~+6dB gain at its own center frequency, measured %.2fdB",
                centerFreq, measuredDB);
    }
}

// A cut should measure close to the requested (negative) gain.
- (void) testCutAtCenterFrequencyMatchesRequestedGain
{
    WC_Biquad biquad;
    biquad.SetParameters(1000.0, kSampleRate, /* gain dB */ -9.0, 1.0);

    double measuredDB = RatioToDB(MeasureRMSGain(biquad, 1000.0, 8192));

    XCTAssertEqualWithAccuracy(measuredDB, -9.0, 0.5);
}

// A boost centered far from the test frequency should have little effect --
// this is what actually distinguishes an EQ from a broadband volume
// control, so it's worth testing explicitly rather than assuming the
// filter shape is right just because the center-frequency gain matched.
- (void) testBoostFarFromCenterFrequencyHasLittleEffect
{
    WC_Biquad biquad;
    biquad.SetParameters(60.0, kSampleRate, /* gain dB */ 12.0, 1.0);

    // Test well above the 60Hz band, away from its passband.
    double measuredDB = RatioToDB(MeasureRMSGain(biquad, 12000.0, 8192));

    XCTAssertLessThan(std::fabs(measuredDB), 1.0,
            @"A +12dB boost at 60Hz shouldn't meaningfully affect 12kHz content, measured %.2fdB",
            measuredDB);
}

// Gain is clamped to [-12, 12] -- an out-of-range request shouldn't silently
// apply the extreme, unclamped value.
- (void) testGainIsClampedToPlusMinus12DB
{
    WC_Biquad biquad;
    biquad.SetParameters(1000.0, kSampleRate, /* gain dB */ 40.0, 1.0);

    double measuredDB = RatioToDB(MeasureRMSGain(biquad, 1000.0, 8192));

    XCTAssertEqualWithAccuracy(measuredDB, 12.0, 0.5);
}

// Left and right channels must have independent filter state -- processing
// interleaved stereo through one WC_Biquad instance must not let one
// channel's delay memory leak into the other's.
- (void) testChannelsHaveIndependentState
{
    WC_Biquad biquad;
    biquad.SetParameters(1000.0, kSampleRate, 6.0, 1.0);

    // Drive channel 0 hard for a while, then start channel 1 from silence.
    for (int i = 0; i < 500; i++)
    {
        Float32 x = static_cast<Float32>(std::sin(2.0 * M_PI * 1000.0 * i / kSampleRate));
        biquad.ProcessSample(0, x);
    }

    // Channel 1 has never been fed anything -- its first sample from
    // silence should come back as (near) silence, not carry over channel
    // 0's filter state.
    Float32 y = biquad.ProcessSample(1, 0.0f);
    XCTAssertEqualWithAccuracy(y, 0.0f, 0.0001);
}

// WC_AppEQ chains all its bands correctly -- setting one band shouldn't affect
// the others, and a flat (all-zero) EQ should be unity end to end.
- (void) testAppEQAllBandsFlatIsUnity
{
    WC_AppEQ eq;
    for (int b = 0; b < WC_AppEQ::kNumBands; b++)
    {
        eq.SetBandGainDB(b, 0.0, kSampleRate);
    }

    for (int i = 0; i < 100; i++)
    {
        Float32 l = static_cast<Float32>(std::sin(2.0 * M_PI * 1000.0 * i / kSampleRate));
        Float32 r = static_cast<Float32>(std::sin(2.0 * M_PI * 1000.0 * i / kSampleRate + 0.3));
        Float32 origL = l, origR = r;

        eq.ProcessStereoSample(l, r);

        XCTAssertEqual(l, origL);
        XCTAssertEqual(r, origR);
    }
}

// NeedsGainUpdate is what ApplyClientEQ checks before calling GetSampleRate() (which takes a
// lock) on every real-time audio callback -- see WC_Device::ApplyClientEQ. If this predicate
// were wrong, either the lock would be taken far more often than necessary (a real-time-safety
// regression) or, worse, a genuine gain change would go unnoticed.
- (void) testNeedsGainUpdate
{
    WC_AppEQ eq;

    std::array<Float32, WC_AppEQ::kNumBands> flat {};
    std::array<Float32, WC_AppEQ::kNumBands> boosted {
        3.0f, 0.0f, -2.0f, 0.0f, 5.0f, -4.0f, 0.0f, 6.0f, -1.0f, 2.0f
    };

    // A freshly-constructed WC_AppEQ starts flat, so requesting flat again needs no update...
    XCTAssertFalse(eq.NeedsGainUpdate(flat));
    // ...but requesting a real change does.
    XCTAssert(eq.NeedsGainUpdate(boosted));

    eq.SetAllBandGainsDB(boosted, kSampleRate);

    // After applying, the same gains again need no update...
    XCTAssertFalse(eq.NeedsGainUpdate(boosted));
    // ...but a different set does.
    XCTAssert(eq.NeedsGainUpdate(flat));
}

// The actual correctness property SetAllBandGainsDB exists for: repeatedly calling it with
// unchanged gains (as ApplyClientEQ does every audio callback) must not reset the filter's
// delay-line state. Verified behaviorally, not by inspecting private state: process the same
// continuous signal two ways -- calling SetAllBandGainsDB once vs. calling it redundantly before
// every single sample -- and confirm the outputs are bit-for-bit identical. If the "only touch
// bands that changed" logic were broken and every call reset state regardless, the redundant-call
// version would show discontinuities the single-call version wouldn't, and the two outputs would
// diverge.
- (void) testSetAllBandGainsDBDoesNotResetStateWhenUnchanged
{
    std::array<Float32, WC_AppEQ::kNumBands> gains {
        4.0f, -6.0f, 2.0f, 0.0f, -3.0f, 5.0f, -2.0f, 0.0f, 7.0f, -5.0f
    };
    const int kNumSamples = 2000;

    WC_AppEQ eqCalledOnce;
    eqCalledOnce.SetAllBandGainsDB(gains, kSampleRate);

    WC_AppEQ eqCalledEverySample;
    eqCalledEverySample.SetAllBandGainsDB(gains, kSampleRate);

    for (int i = 0; i < kNumSamples; i++)
    {
        Float32 xL = static_cast<Float32>(std::sin(2.0 * M_PI * 440.0 * i / kSampleRate));
        Float32 xR = static_cast<Float32>(std::sin(2.0 * M_PI * 660.0 * i / kSampleRate));

        Float32 onceL = xL, onceR = xR;
        eqCalledOnce.ProcessStereoSample(onceL, onceR);

        // Redundantly re-request the exact same gains before every sample -- this is exactly
        // what ApplyClientEQ does on every real-time callback.
        eqCalledEverySample.SetAllBandGainsDB(gains, kSampleRate);
        Float32 everyL = xL, everyR = xR;
        eqCalledEverySample.ProcessStereoSample(everyL, everyR);

        XCTAssertEqual(onceL, everyL, @"Diverged at sample %d (left channel) -- redundant "
                "SetAllBandGainsDB calls with unchanged gains must not reset filter state", i);
        XCTAssertEqual(onceR, everyR, @"Diverged at sample %d (right channel)", i);
    }
}

// Note: deliberately not testing "changing one band leaves other bands' state alone" as a
// separate black-box behavioral test. Bands are chained in series, so isolating one band's
// contribution from the combined output without exposing private state isn't something a
// black-box test can do rigorously (an earlier attempt at this compared mismatched targets with
// an arbitrary tolerance -- not real evidence, removed rather than shipped). The property holds
// by construction instead: SetAllBandGainsDB's loop only calls SetBandGainDB(i, ...) -- which
// only ever touches mBands[i] -- for indices whose target actually changed, so it's structurally
// incapable of touching an unchanged band.

@end
