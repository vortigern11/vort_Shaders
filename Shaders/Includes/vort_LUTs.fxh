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
#include "Includes/vort_HDR_UI.fxh"

#if V_ENABLE_LUT

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

texture3D CubeTexVort < source = TO_STR(V_LUT_FILE) ".cube"; >
{ Width = V_LUT_SIZE; Height = V_LUT_SIZE; Depth = V_LUT_SIZE; TEX_RGBA32 };
sampler3D sCubeTexVort { Texture = CubeTexVort; };

/*******************************************************************************
    Functions
*******************************************************************************/

float3 ApplyLUT(float3 c)
{
    float3 orig_c = c;

    c = LinToSRGB(c);

    // remap the color depending on the LUT size
    c = (c - 0.5) * ((V_LUT_SIZE - 1.0) / V_LUT_SIZE) + 0.5;

    c = tex3D(sCubeTexVort, c).rgb;

    c = SRGBToLin(c);

    float3 factor = float3(UI_CC_LUTLuma, UI_CC_LUTChroma, UI_CC_LUTChroma);
    orig_c = OKColors::RGBToOKLAB(orig_c); c = OKColors::RGBToOKLAB(c);
    c = OKColors::OKLABToRGB(lerp(orig_c, c, factor));

    return c;
}

#endif // V_ENABLE_LUT
