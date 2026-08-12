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
//  BGM_Biquad.cpp
//  BGMDriver
//
//  This project targets c++0x (C++11), not C++17, so `static constexpr`
//  class data members aren't implicitly inline here and still need an
//  out-of-class definition for anything that ODR-uses them (e.g. binding a
//  reference, iterating with a range-based for loop) -- otherwise the
//  linker can't find a symbol for it. See BGM_AppEQ::kBandCenterFreqs's use
//  in BGM_BiquadTests.mm.
//

// Unit Include
#include "BGM_Biquad.h"

constexpr std::array<double, BGM_AppEQ::kNumBands> BGM_AppEQ::kBandCenterFreqs;
