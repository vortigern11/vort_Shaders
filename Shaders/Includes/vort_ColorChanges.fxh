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

/* TODO:
- add more tonemappers:
    Agx -> https://github.com/MrLixm/AgXc/tree/main/reshade
    Tony McMapface -> https://github.com/h3r2tic/tony-mc-mapface/tree/main

- Move the inverse tonemap, tonemap and color grading to a LUT

- Useful links for applying LUTs:
    https://www.lightillusion.com/what_are_luts.html
    https://lut.tgratzer.com/
    https://github.com/prod80/prod80-ReShade-Repository/blob/master/Shaders/PD80_02_LUT_Creator.fx
    https://github.com/prod80/prod80-ReShade-Repository/blob/master/Shaders/PD80_LUT_v2.fxh
    https://github.com/FransBouma/OtisFX/blob/master/Shaders/MultiLUT.fx

- It is easier to install OCIO latest on Fedora using it's package manager
- OpenColorIO (OCIO) links
    https://opencolorio.readthedocs.io/en/latest/guides/using_ocio/using_ocio.html
    https://opencolorio.readthedocs.io/en/latest/tutorials/baking_luts.html
    https://help.maxon.net/c4d/en-us/Content/_REDSHIFT_/html/Compositing+with+ACES.html
*/

#pragma once
#include "Includes/vort_Defs.fxh"
#include "Includes/vort_HDR_UI.fxh"
#include "Includes/vort_Depth.fxh"
#include "Includes/vort_Filters.fxh"
#include "Includes/vort_LDRTex.fxh"
#include "Includes/vort_HDRTexA.fxh"
#include "Includes/vort_HDRTexB.fxh"
#include "Includes/vort_Tonemap.fxh"

namespace ColorChanges {

/*******************************************************************************
    Globals
*******************************************************************************/

#define CC_OUT_TEX HDRTexVortA

#if V_ENABLE_BLOOM
    #define CC_IN_SAMP sHDRTexVortB
#else
    #define CC_IN_SAMP sHDRTexVortA
#endif

#if IS_SRGB
    #define LINEAR_MIN FLOAT_MIN
    #define LINEAR_MAX FLOAT_MAX
#elif IS_SCRGB
    #define LINEAR_MIN -0.5
    #define LINEAR_MAX (1e4 / V_HDR_WHITE_LVL)
#elif IS_HDR_PQ
    #define LINEAR_MIN 0.0
    #define LINEAR_MAX (1e4 / V_HDR_WHITE_LVL)
#elif IS_HDR_HLG
    #define LINEAR_MIN 0.0
    #define LINEAR_MAX (1e3 / V_HDR_WHITE_LVL)
#else
    #define LINEAR_MIN 0.0
    #define LINEAR_MAX 1.0
#endif

#define TO_LOG_CS(_x) ACEScgToACEScct(_x)
#define TO_LINEAR_CS(_x) ACEScctToACEScg(_x)
#define GET_LUMI(_x) ACESToLumi(_x)
#define LINEAR_MID_GRAY 0.18
#define LOG_MID_GRAY ACES_LOG_MID_GRAY

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

#if V_ENABLE_LUT
    #if !LOAD_ALL_LUTS
        texture3D CubeTexVort < source = TO_STR(V_LUT_FILE) ".cube"; >
        { Width = V_LUT_SIZE; Height = V_LUT_SIZE; Depth = V_LUT_SIZE; TEX_RGBA32 };
        sampler3D sCubeTexVort { Texture = CubeTexVort; };
    #else
        #define MAKE_LUT_TS(x) \
            texture3D CubeTexVort##x < source = TO_STR(x) ".cube"; > \
            { Width = 33; Height = 33; Depth = 33; TEX_RGBA32 }; \
            sampler3D sCubeTexVort##x { Texture = CubeTexVort##x; };

        MAKE_LUT_TS(1)
        MAKE_LUT_TS(2)
        MAKE_LUT_TS(3)
        MAKE_LUT_TS(4)
        MAKE_LUT_TS(5)
        MAKE_LUT_TS(6)
        MAKE_LUT_TS(7)
        MAKE_LUT_TS(8)
        MAKE_LUT_TS(9)
        MAKE_LUT_TS(10)
        MAKE_LUT_TS(11)
        MAKE_LUT_TS(12)
        MAKE_LUT_TS(13)
        MAKE_LUT_TS(14)
        MAKE_LUT_TS(15)
        MAKE_LUT_TS(16)
        MAKE_LUT_TS(17)
        MAKE_LUT_TS(18)
        MAKE_LUT_TS(19)
        MAKE_LUT_TS(20)
        MAKE_LUT_TS(21)
        MAKE_LUT_TS(22)
        MAKE_LUT_TS(23)
        MAKE_LUT_TS(24)
        MAKE_LUT_TS(25)
        MAKE_LUT_TS(26)
        MAKE_LUT_TS(27)
        MAKE_LUT_TS(28)
        MAKE_LUT_TS(29)
        MAKE_LUT_TS(30)
        MAKE_LUT_TS(31)
        MAKE_LUT_TS(32)
        MAKE_LUT_TS(33)
        MAKE_LUT_TS(34)
        MAKE_LUT_TS(35)
        MAKE_LUT_TS(36)
        MAKE_LUT_TS(37)
        MAKE_LUT_TS(38)
        MAKE_LUT_TS(39)
        MAKE_LUT_TS(40)
    #endif
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

#if V_ENABLE_SHARPEN
float3 ApplySharpen(float3 c, sampler samp, float2 uv)
{
    float3 blurred = Filter9Taps(uv, samp, 0);
    float3 sharp = GET_LUMI(c - blurred);
    float depth = GetLinearizedDepth(uv);
    float limit = abs(dot(sharp, 0.3333));

    sharp = sharp * UI_CC_SharpenStrength * (1 - depth) * (limit < UI_CC_SharpenLimit);

    if (UI_CC_ShowSharpening) return sharp;

    // apply sharpening and unsharpening
    c = depth < UI_CC_SharpenSwitchPoint ? c + sharp : lerp(c, blurred, depth * UI_CC_UnsharpenStrength);

    return c;
}
#endif

#if V_ENABLE_COLOR_GRADING
float3 ChangeWhiteBalance(float3 col, float temp, float tint) {
    static const float3x3 LIN_2_LMS_MAT = float3x3(
        3.90405e-1, 5.49941e-1, 8.92632e-3,
        7.08416e-2, 9.63172e-1, 1.35775e-3,
        2.31082e-2, 1.28021e-1, 9.36245e-1
    );

    float3 lms = mul(LIN_2_LMS_MAT, col);

    temp /= 0.6;
    tint /= 0.6;

    float x = 0.31271 - temp * (temp < 0 ? 0.1 : 0.05);
    float y = 2.87 * x - 3 * x * x - 0.27509507 + tint * 0.05;

    float X = x / y;
    float Z = (1 - x - y) / y;

    static const float3 w1 = float3(0.949237, 1.03542, 1.08728);

    float3 w2 = float3(
         0.7328 * X + 0.4296 - 0.1624 * Z,
        -0.7036 * X + 1.6975 + 0.0061 * Z,
         0.0030 * X + 0.0136 + 0.9834 * Z
    );

    lms *= w1 / w2;

    static const float3x3 LMS_2_LIN_MAT = float3x3(
         2.85847e+0, -1.62879e+0, -2.48910e-2,
        -2.10182e-1,  1.15820e+0,  3.24281e-4,
        -4.18120e-2, -1.18169e-1,  1.06867e+0
    );

    return mul(LMS_2_LIN_MAT, lms);
}

float3 ApplyColorGrading(float3 c)
{
    // white balance
    c = ChangeWhiteBalance(c.rgb, UI_CC_WBTemp, UI_CC_WBTint);

    // color filter
    c *= UI_CC_ColorFilter;

    // saturation
    float lumi = GET_LUMI(c);
    c = lerp(lumi.xxx, c, UI_CC_Saturation + 1.0);

    // RGB(channel) mixer
    c = float3(
        dot(c.rgb, UI_CC_RGBMixerRed.rgb * 4.0 - 2.0),
        dot(c.rgb, UI_CC_RGBMixerGreen.rgb * 4.0 - 2.0),
        dot(c.rgb, UI_CC_RGBMixerBlue.rgb * 4.0 - 2.0)
    );

    // Hue Shift
    float3 hsv = RGBToHSV(c);
    hsv.x = frac(hsv.x + UI_CC_HueShift);
    c = HSVToRGB(hsv);

    // start grading in log space
    c = TO_LOG_CS(c);

    // contrast in log space
    float contrast = UI_CC_Contrast + 1.0;
    c = lerp(LOG_MID_GRAY.xxx, c, contrast.xxx);

    // Shadows,Midtones,Highlights,Offset in log space
    // My calculations were done in desmos: https://www.desmos.com/calculator/vvur0dzia9

    // affect the color and luminance seperately
    float3 shadows = UI_CC_ShadowsColor - GET_LUMI(UI_CC_ShadowsColor) + UI_CC_ShadowsLumi + 0.5;
    float3 midtones = UI_CC_MidtonesColor - GET_LUMI(UI_CC_MidtonesColor) + UI_CC_MidtonesLumi + 0.5;
    float3 highlights = UI_CC_HighlightsColor - GET_LUMI(UI_CC_HighlightsColor) + UI_CC_HighlightsLumi + 0.5;
    float3 offset = UI_CC_OffsetColor - GET_LUMI(UI_CC_OffsetColor) + UI_CC_OffsetLumi + 0.5;

    static const float shadows_str = 0.5;
    static const float midtones_str = 1.0;
    static const float highlights_str = 1.0;
    static const float offset_str = 0.5;

    // do the scaling
    shadows = 1.0 - exp2((1.0 - 2.0 * shadows) * shadows_str);
    midtones = exp2((1.0 - 2.0 * midtones) * midtones_str);
    highlights = exp2((2.0 * highlights - 1.0) * highlights_str);
    offset = (offset - 0.5) * offset_str;

    // apply shadows, highlights, offset, midtones
    c = (c <= 1) ? (c * (1.0 - shadows) + shadows) : c;
    c = (c >= 0) ? (c * highlights) : c;
    c = c + offset;
    c = (c >= 0 && c <= 1.0) ? POW(c, midtones) : c;

    // end grading in log space
    c = TO_LINEAR_CS(c);

    return c;
}
#endif

#if V_ENABLE_LUT
float3 ApplyLUT(float3 c)
{
    float3 orig_c = c;

#if HW_LIN_IS_USED
    c = LinToSRGB(c);
#endif

#if !LOAD_ALL_LUTS
    c = tex3D(sCubeTexVort, c).rgb;
#else
    switch(UI_CC_LUTName)
    {
        case  1: c = tex3D(sCubeTexVort1,  c).rgb; break;
        case  2: c = tex3D(sCubeTexVort2,  c).rgb; break;
        case  3: c = tex3D(sCubeTexVort3,  c).rgb; break;
        case  4: c = tex3D(sCubeTexVort4,  c).rgb; break;
        case  5: c = tex3D(sCubeTexVort5,  c).rgb; break;
        case  6: c = tex3D(sCubeTexVort6,  c).rgb; break;
        case  7: c = tex3D(sCubeTexVort7,  c).rgb; break;
        case  8: c = tex3D(sCubeTexVort8,  c).rgb; break;
        case  9: c = tex3D(sCubeTexVort9,  c).rgb; break;
        case 10: c = tex3D(sCubeTexVort10, c).rgb; break;
        case 11: c = tex3D(sCubeTexVort11, c).rgb; break;
        case 12: c = tex3D(sCubeTexVort12, c).rgb; break;
        case 13: c = tex3D(sCubeTexVort13, c).rgb; break;
        case 14: c = tex3D(sCubeTexVort14, c).rgb; break;
        case 15: c = tex3D(sCubeTexVort15, c).rgb; break;
        case 16: c = tex3D(sCubeTexVort16, c).rgb; break;
        case 17: c = tex3D(sCubeTexVort17, c).rgb; break;
        case 18: c = tex3D(sCubeTexVort18, c).rgb; break;
        case 19: c = tex3D(sCubeTexVort19, c).rgb; break;
        case 20: c = tex3D(sCubeTexVort20, c).rgb; break;
        case 21: c = tex3D(sCubeTexVort21, c).rgb; break;
        case 22: c = tex3D(sCubeTexVort22, c).rgb; break;
        case 23: c = tex3D(sCubeTexVort23, c).rgb; break;
        case 24: c = tex3D(sCubeTexVort24, c).rgb; break;
        case 25: c = tex3D(sCubeTexVort25, c).rgb; break;
        case 26: c = tex3D(sCubeTexVort26, c).rgb; break;
        case 27: c = tex3D(sCubeTexVort27, c).rgb; break;
        case 28: c = tex3D(sCubeTexVort28, c).rgb; break;
        case 29: c = tex3D(sCubeTexVort29, c).rgb; break;
        case 30: c = tex3D(sCubeTexVort30, c).rgb; break;
        case 31: c = tex3D(sCubeTexVort31, c).rgb; break;
        case 32: c = tex3D(sCubeTexVort32, c).rgb; break;
        case 33: c = tex3D(sCubeTexVort33, c).rgb; break;
        case 34: c = tex3D(sCubeTexVort34, c).rgb; break;
        case 35: c = tex3D(sCubeTexVort35, c).rgb; break;
        case 36: c = tex3D(sCubeTexVort36, c).rgb; break;
        case 37: c = tex3D(sCubeTexVort37, c).rgb; break;
        case 38: c = tex3D(sCubeTexVort38, c).rgb; break;
        case 39: c = tex3D(sCubeTexVort39, c).rgb; break;
        case 40: c = tex3D(sCubeTexVort40, c).rgb; break;
    }
#endif

    // texture filtering isn't perfect yet, hence the addition
    c += 0.005;

#if HW_LIN_IS_USED
    c = SRGBToLin(c);
#endif

    orig_c = RGBToOKLAB(orig_c); c = RGBToOKLAB(c);
    c.x = lerp(orig_c.x, c.x, UI_CC_LUTLuma);
    c.yz = lerp(orig_c.yz, c.yz, UI_CC_LUTChroma);

    return OKLABToRGB(c);
}
#endif

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Start(PS_ARGS4) {
    float3 c = Sample(sLDRTexVort, i.uv).rgb;

#if V_ENABLE_LUT
    // input must be sRGB
    c = ApplyLUT(c);
#endif

    c = ApplyLinearCurve(c);

#if IS_SRGB
    c = saturate(c);

    if(UI_CC_Tonemapper == 0)
        c = InverseLottes(c);
    else
        c = InverseACESNarkowicz(c);
#endif

    o = float4(c, 1);
}

void PS_End(PS_ARGS3)
{
    float3 c = Sample(CC_IN_SAMP, i.uv).rgb;

#if V_ENABLE_SHARPEN && V_HAS_DEPTH
    c = ApplySharpen(c, CC_IN_SAMP, i.uv);
#endif

#if V_ENABLE_COLOR_GRADING
    c = ApplyColorGrading(c);
#endif

#if V_SHOW_ONLY_HDR_COLORS
    c = !all(saturate(c - c * c)) ? 1.0 : 0.0;
#elif IS_SRGB
    // exposure before tonemap
    c = c >= 0 ? c * exp2(UI_CC_ManualExp) : c;

    // clamp before tonemapping
    c = clamp(c, LINEAR_MIN, LINEAR_MAX);

    if(UI_CC_Tonemapper == 0)
        c = ApplyLottes(c);
    else
        c = ApplyACESNarkowicz(c);

    c = saturate(c);
#endif

    o = ApplyGammaCurve(c);
}

/*******************************************************************************
    Passes
*******************************************************************************/
#define PASS_START \
    pass { VertexShader = PostProcessVS; PixelShader = ColorChanges::PS_Start; RenderTarget = CC_OUT_TEX; }

#define PASS_END \
    pass { VertexShader = PostProcessVS; PixelShader = ColorChanges::PS_End; SRGB_WRITE_ENABLE }

} // namespace end
