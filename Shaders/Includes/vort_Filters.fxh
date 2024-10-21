/*******************************************************************************
    Author: Vortigern

    License: MIT, Copyright (c) 2023 Vortigern

    MIT License

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*******************************************************************************/

#pragma once
#include "Includes/vort_Defs.fxh"

namespace Filters {

/*******************************************************************************
    Globals
*******************************************************************************/

// dual kawase filter
static const int2 OFFS_DK[13] = {
    int2(-2,-2), int2(0,-2), int2(2,-2),
    int2(-1,-1), int2(1,-1),
    int2(-2, 0), int2(0, 0), int2(2, 0),
    int2(-1, 1), int2(1, 1),
    int2(-2, 2), int2(0, 2), int2(2, 2)
};

static const float WEIGHTS_DK[13] = {
    0.03125, 0.0625, 0.03125,
    0.125, 0.125,
    0.06250, 0.1250, 0.06250,
    0.125, 0.125,
    0.03125, 0.0625, 0.03125
};

// tent filter
static const int2 OFFS_TENT[9] = {
    int2(-1.0,-1.0), int2(0.0,-1.0), int2(1.0,-1.0),
    int2(-1.0, 0.0), int2(0.0, 0.0), int2(1.0, 0.0),
    int2(-1.0, 1.0), int2(0.0, 1.0), int2(1.0, 1.0)
};

static const float WEIGHTS_TENT[9] = {
    0.0625, 0.1250, 0.0625,
    0.1250, 0.2500, 0.1250,
    0.0625, 0.1250, 0.0625
};

// wronski filter
static const float2 OFFS_W[8] = {
    float2(-0.7577, -0.7577), float2(0.7577, -0.7577),
    float2(0.7577, 0.7577), float2(-0.7577, 0.7577),
    float2(2.907, 0), float2(-2.907, 0),
    float2(0, 2.907), float2(0, -2.907)
};

static const float WEIGHTS_W[8] = {
    0.37487566, 0.37487566,
    0.37487566, 0.37487566,
    -0.12487566, -0.12487566,
    -0.12487566, -0.12487566
};

/*******************************************************************************
    Functions
*******************************************************************************/

/*
 *   13 tap dual kawase filter
 *
 *   Coords       Weights
 *   a - b - c    1 - 2 - 1
 *   - d - e -    - 4 - 4 -
 *   f - g - h    2 - 4 - 2
 *   - i - j -    - 4 - 4 -
 *   k - l - m    1 - 2 - 1
 *
 *                0.03125
 */

float4 DualKawase(sampler samp, float2 uv, int mip)
{
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(mip);
    float4 color = 0;

    [loop]for(int j = 0; j < 13; j++)
    {
        float2 offset = OFFS_DK[j] * texelsize;
        float2 tap_uv = uv + offset;

        // repeat
        /* tap_uv = saturate(tap_uv); */

        // mirror
        tap_uv = (tap_uv < 0 || tap_uv > 1) ? (uv - offset) : tap_uv;

        color += WEIGHTS_DK[j] * Sample(samp, tap_uv);
    }

    return color;
}

/*
 *   9-tap tent filter
 *
 *   Coords   Weights
 *   a b c    1 2 1
 *   d e f    2 4 2
 *   g h i    1 2 1
 *
 *            0.0625
 */

float4 Tent(sampler samp, float2 uv, int mip)
{
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(mip);
    float4 color = 0;

    [loop]for(int j = 0; j < 9; j++)
    {
        float2 offset = OFFS_TENT[j] * texelsize;
        float2 tap_uv = uv + offset;

        // repeat
        /* tap_uv = saturate(tap_uv); */

        // mirror
        tap_uv = (tap_uv < 0 || tap_uv > 1) ? (uv - offset) : tap_uv;

        color += WEIGHTS_TENT[j] * Sample(samp, tap_uv);
    }

    return color;
}

/*
 * 8-tap Wronski filter
 *
 * https://www.shadertoy.com/view/fsjBWm
 */

float4 Wronski(sampler samp, float2 uv, int mip)
{
    float2 texelsize = BUFFER_PIXEL_SIZE * exp2(mip);
    float4 color = 0;

    [loop]for(int j = 0; j < 8; j++)
    {
        float2 offset = OFFS_W[j] * texelsize;
        float2 tap_uv = uv + offset;

        // repeat
        /* tap_uv = saturate(tap_uv); */

        // mirror
        tap_uv = (tap_uv < 0 || tap_uv > 1) ? (uv - offset) : tap_uv;

        color += WEIGHTS_W[j] * Sample(samp, tap_uv);
    }

    return color;
}

} // namespace end
