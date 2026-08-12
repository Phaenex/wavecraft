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
//  BGM_BiquadTests.mm
//  BGMDriverTests
//
//  These tests feed a real sine wave through the filter and measure the
//  actual RMS gain, rather than just checking the filter runs -- a biquad
//  with a coefficient sign error still produces *a* number for every input,
//  so "doesn't crash" proves nothing about correctness here.
//

// Unit Include
#include "BGM_Biquad.h"

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
static double MeasureRMSGain(BGM_Biquad& inBiquad, double inFreqHz, int inNumSamples)
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

@interface BGM_BiquadTests : XCTestCase
@end

@implementation BGM_BiquadTests

// At 0dB gain, the filter should be unity -- output should equal input
// exactly, since ProcessSample takes the fast path and skips the filter
// math entirely for a 0dB band.
- (void) testZeroGainIsExactUnity
{
    BGM_Biquad biquad;
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
    for (double centerFreq : BGM_AppEQ::kBandCenterFreqs)
    {
        BGM_Biquad biquad;
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
    BGM_Biquad biquad;
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
    BGM_Biquad biquad;
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
    BGM_Biquad biquad;
    biquad.SetParameters(1000.0, kSampleRate, /* gain dB */ 40.0, 1.0);

    double measuredDB = RatioToDB(MeasureRMSGain(biquad, 1000.0, 8192));

    XCTAssertEqualWithAccuracy(measuredDB, 12.0, 0.5);
}

// Left and right channels must have independent filter state -- processing
// interleaved stereo through one BGM_Biquad instance must not let one
// channel's delay memory leak into the other's.
- (void) testChannelsHaveIndependentState
{
    BGM_Biquad biquad;
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

// BGM_AppEQ chains 5 bands correctly -- setting one band shouldn't affect
// the others, and a flat (all-zero) EQ should be unity end to end.
- (void) testAppEQAllBandsFlatIsUnity
{
    BGM_AppEQ eq;
    for (int b = 0; b < BGM_AppEQ::kNumBands; b++)
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

@end
