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
//  WC_Biquad.h
//  BGMDriver
//
//  Per-app EQ. A single Direct Form I biquad peaking filter, and a fixed
//  10-band chain of them driven by WC_Client's per-app gain settings.
//
//  Coefficients follow Robert Bristow-Johnson's "Audio EQ Cookbook" peaking
//  EQ formula (the same reference the Web Audio API's BiquadFilterNode spec
//  cites). Real-time safe: SetParameters() does the only heap-free trig, and
//  ProcessSample() is pure arithmetic on member state, no locks, no
//  allocation, safe to call from the IO thread.
//

#ifndef BGMDriver__BGM_Biquad
#define BGMDriver__BGM_Biquad

// PublicUtility Includes
#include <CoreAudio/AudioServerPlugIn.h>

// STL Includes
#include <array>
#include <cmath>

class WC_Biquad
{

public:
    // Sets the filter to a peaking EQ with the given center frequency, gain
    // and Q, recalculating the a/b coefficients. Resets the filter's delay
    // state (x1/x2/y1/y2) to silence, since changing the coefficients
    // mid-stream without resetting state can produce an audible click.
    //
    // inCenterFreq and inSampleRate in Hz. inGainDB clamped to
    // [-12.0, 12.0]. inQ must be > 0; 1.0 is a reasonable default bandwidth
    // for a consumer-facing per-band control.
    void SetParameters(double inCenterFreq, double inSampleRate, double inGainDB, double inQ)
    {
        const double clampedGainDB = inGainDB < -12.0 ? -12.0 : (inGainDB > 12.0 ? 12.0 : inGainDB);

        const double A = std::pow(10.0, clampedGainDB / 40.0);
        const double w0 = 2.0 * M_PI * inCenterFreq / inSampleRate;
        const double cosW0 = std::cos(w0);
        const double sinW0 = std::sin(w0);
        const double alpha = sinW0 / (2.0 * inQ);

        const double b0 = 1.0 + alpha * A;
        const double b1 = -2.0 * cosW0;
        const double b2 = 1.0 - alpha * A;
        const double a0 = 1.0 + alpha / A;
        const double a1 = -2.0 * cosW0;
        const double a2 = 1.0 - alpha / A;

        mB0 = static_cast<Float32>(b0 / a0);
        mB1 = static_cast<Float32>(b1 / a0);
        mB2 = static_cast<Float32>(b2 / a0);
        mA1 = static_cast<Float32>(a1 / a0);
        mA2 = static_cast<Float32>(a2 / a0);

        // A gain of (effectively) 0dB means this band is a no-op. Track that
        // separately so ProcessSample can skip the (still correct, but
        // wasteful) filter math for untouched bands -- most apps will have
        // most bands left at 0dB most of the time.
        mIsUnityGain = (clampedGainDB > -0.01) && (clampedGainDB < 0.01);

        for (size_t ch = 0; ch < static_cast<size_t>(kNumChannels); ch++)
        {
            mX1[ch] = 0.0f;
            mX2[ch] = 0.0f;
            mY1[ch] = 0.0f;
            mY2[ch] = 0.0f;
        }
    }

    // Direct Form I: y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
    // inChannel selects which channel's delay state to use (0 = left, 1 = right),
    // so a single WC_Biquad instance can process interleaved stereo without
    // channels bleeding into each other's filter memory.
    inline Float32 ProcessSample(size_t inChannel, Float32 inSample)
    {
        if (mIsUnityGain)
        {
            return inSample;
        }

        const Float32 x0 = inSample;
        const Float32 y0 = mB0 * x0 + mB1 * mX1[inChannel] + mB2 * mX2[inChannel]
                                     - mA1 * mY1[inChannel] - mA2 * mY2[inChannel];

        mX2[inChannel] = mX1[inChannel];
        mX1[inChannel] = x0;
        mY2[inChannel] = mY1[inChannel];
        mY1[inChannel] = y0;

        return y0;
    }

private:
    static constexpr int kNumChannels = 2;

    Float32 mB0 = 1.0f;
    Float32 mB1 = 0.0f;
    Float32 mB2 = 0.0f;
    Float32 mA1 = 0.0f;
    Float32 mA2 = 0.0f;
    bool    mIsUnityGain = true;

    std::array<Float32, kNumChannels> mX1 { 0.0f, 0.0f };
    std::array<Float32, kNumChannels> mX2 { 0.0f, 0.0f };
    std::array<Float32, kNumChannels> mY1 { 0.0f, 0.0f };
    std::array<Float32, kNumChannels> mY2 { 0.0f, 0.0f };

};

// A fixed 10-band peaking EQ chain, one instance per app. Owned by WC_Device
// (in mClientEQProcessors, keyed by client ID), NOT by WC_Client -- WC_Client
// gets copied by value by the existing per-client access pattern (see
// docs/LESSONS.md), which would silently reset this filter's delay-line state
// on every IO callback if it lived there instead.
// Bands are processed in series, low to high.
class WC_AppEQ
{

public:
    static constexpr int kNumBands = 10;

    // Center frequencies for the 10 bands, Hz -- the standard ISO octave-band graphic-EQ spread
    // (31/62/125/250/500/1k/2k/4k/8k/16k), matching what other per-app EQ tools in this space
    // (SoundSource, Sound Control) also use, rather than an arbitrary custom set. kNumBands and
    // kBGMAppEQNumBands (SharedSource/BGM_Types.h) are two independent constants that have to
    // stay equal by hand -- see the static_assert enforcing that in WC_Device.cpp.
    static constexpr std::array<double, kNumBands> kBandCenterFreqs {
        31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
    };

    // Sets band inBandIndex's gain, in dB, clamped to [-12, 12] by
    // WC_Biquad::SetParameters. inSampleRate should be the device's
    // current sample rate -- callers should re-call this for every band if
    // the device's sample rate changes.
    //
    // Unconditionally resets that band's filter delay-line state (see
    // WC_Biquad::SetParameters), so avoid calling this every IO callback
    // with the same value -- prefer SetAllBandGainsDB, which only touches
    // bands whose target gain actually changed.
    void SetBandGainDB(int inBandIndex, double inGainDB, double inSampleRate)
    {
        if (inBandIndex < 0 || inBandIndex >= kNumBands)
        {
            return;
        }

        // Q = 1.0: a moderate bandwidth appropriate for a small fixed set of
        // bands covering the full audible spectrum without gaps or
        // excessive overlap.
        mBands[static_cast<size_t>(inBandIndex)].SetParameters(
                kBandCenterFreqs[static_cast<size_t>(inBandIndex)], inSampleRate, inGainDB, 1.0);

        mCurrentGainsDB[static_cast<size_t>(inBandIndex)] = static_cast<Float32>(inGainDB);
    }

    // True if any band's target gain differs from what's currently applied -- i.e. whether a
    // SetAllBandGainsDB call with these gains would actually do anything. Callers on the
    // real-time thread should check this before fetching a sample rate that requires taking a
    // lock (e.g. WC_Device::GetSampleRate, which takes mStateMutex) purely to pass into a call
    // that would turn out to be a no-op.
    bool NeedsGainUpdate(const std::array<Float32, kNumBands>& inGainsDB) const
    {
        return mCurrentGainsDB != inGainsDB;
    }

    // Sets all bands' gains at once, but only actually reconfigures (and
    // resets the delay-line state of) bands whose target gain differs from
    // what's currently applied. Real-time safe to call every IO callback:
    // the common case (nothing changed since last call) does no filter
    // resets at all, just kNumBands float comparisons.
    void SetAllBandGainsDB(const std::array<Float32, kNumBands>& inGainsDB, double inSampleRate)
    {
        for (int i = 0; i < kNumBands; i++)
        {
            const size_t idx = static_cast<size_t>(i);

            if (mCurrentGainsDB[idx] != inGainsDB[idx])
            {
                SetBandGainDB(i, inGainsDB[idx], inSampleRate);
            }
        }
    }

    // Applies all bands in series to one interleaved stereo sample pair.
    inline void ProcessStereoSample(Float32& ioLeft, Float32& ioRight)
    {
        for (auto& band : mBands)
        {
            ioLeft = band.ProcessSample(0, ioLeft);
            ioRight = band.ProcessSample(1, ioRight);
        }
    }

private:
    std::array<WC_Biquad, kNumBands> mBands;

    // Tracks what's currently applied to mBands, all zeroed (0dB, unity) to
    // match each WC_Biquad's own default-constructed state. Compared
    // against in SetAllBandGainsDB to avoid unnecessary filter resets.
    std::array<Float32, kNumBands> mCurrentGainsDB {};

};

#endif /* BGMDriver__BGM_Biquad */
