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
- add more color stuff like hue shifting
- add more tonemappers
- implement Hald CLUTs
*/

#pragma once
#include "Includes/vort_Defs.fxh"
#include "Includes/vort_HDR_UI.fxh"
#include "Includes/vort_Depth.fxh"
#include "Includes/vort_Filters.fxh"
#include "Includes/vort_LDRTex.fxh"
#include "Includes/vort_HDRTexA.fxh"
#include "Includes/vort_HDRTexB.fxh"
#include "Includes/vort_ExpTex.fxh"
#include "Includes/vort_ACES.fxh"

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

#define USE_ACES IS_SRGB && V_USE_TONEMAP == 1

#if USE_ACES
    #define LINEAR_MIN FLOAT_MIN
    #define LINEAR_MAX FLOAT_MAX
#elif IS_SRGB
    #define LINEAR_MIN 0.0
    #define LINEAR_MAX 1.0
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

#if USE_ACES
    #define TO_LOG_CS(_x) ACEScgToACEScct(_x)
    #define TO_LINEAR_CS(_x) ACEScctToACEScg(_x)
    #define GET_LUMI(_x) RGBToACESLumi(_x)
    #define LINEAR_MID_GRAY 0.18
    #define LOG_MID_GRAY ACES_LOG_MID_GRAY
#else
    #define TO_LOG_CS(_x) LOG2(_x)
    #define TO_LINEAR_CS(_x) exp2(_x)
    #define GET_LUMI(_x) RGBToYCbCrLumi(_x)
    #define LINEAR_MID_GRAY 0.18
    #define LOG_MID_GRAY 0.18
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

float3 LimitColor(float3 c)
{
    return clamp(c, LINEAR_MIN, LINEAR_MAX);
}

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

float3 InverseLottes(float3 c)
{
    float k = max(1.001, UI_CC_LottesMod);
    float3 v = Max3(c.r, c.g, c.b);

    return c * RCP(k - v);
}

#if V_ENABLE_SHARPEN
float3 ApplySharpen(float3 c, sampler samp, float2 uv)
{
    float3 blurred = Filter9Taps(uv, samp, 0);
    float3 sharp = RGBToYCbCrLumi(c - blurred);
    float depth = GetLinearizedDepth(uv);
    float limit = abs(dot(sharp, 0.3333));

    sharp = sharp * UI_CC_SharpenStrength * (1 - depth) * (limit < UI_CC_SharpenLimit);

    if (UI_CC_ShowSharpening) return sharp;

    // apply sharpening and unsharpening
    if(depth < UI_CC_SharpenSwitchPoint)
        c = c + sharp;
    else
        c = lerp(c, blurred, depth * UI_CC_UnsharpenStrength);

    return c;
}
#endif

#if V_ENABLE_COLOR_GRADING
float3 ApplyColorGrading(float3 c)
{
    // white balance
    c = ChangeWhiteBalance(c.rgb, UI_CC_WBTemp, UI_CC_WBTint);
    c = LimitColor(c);

    // color filter
    c *= UI_CC_ColorFilter;
    c = LimitColor(c);

    // contrast in log space
    float contrast = UI_CC_Contrast + 1.0;
    c = TO_LOG_CS(c);
    c = lerp(LOG_MID_GRAY.xxx, c, contrast.xxx);
    c = TO_LINEAR_CS(c);
    c = LimitColor(c);

    // saturation
    float lumi = GET_LUMI(c);
    c = lerp(lumi.xxx, c, UI_CC_Saturation + 1.0);
    c = LimitColor(c);

    // RGB(channel) mixer
    c = float3(
            dot(c.rgb, UI_CC_RGBMixerRed.rgb * 4.0 - 2.0),
            dot(c.rgb, UI_CC_RGBMixerGreen.rgb * 4.0 - 2.0),
            dot(c.rgb, UI_CC_RGBMixerBlue.rgb * 4.0 - 2.0)
            );
    c = LimitColor(c);

    // LGGO in log space
    // My calculations were done in desmos: https://www.desmos.com/calculator/g9nhdxwhqd
    c = TO_LOG_CS(c);

    // affect the color and luminance seperately
    float3 lift = UI_CC_LiftColor - GET_LUMI(UI_CC_LiftColor) + UI_CC_LiftLumi + 0.5;
    float3 gamma = UI_CC_GammaColor - GET_LUMI(UI_CC_GammaColor) + UI_CC_GammaLumi + 0.5;
    float3 gain = UI_CC_GainColor - GET_LUMI(UI_CC_GainColor) + UI_CC_GainLumi + 0.5;
    float3 offset = UI_CC_OffsetColor - GET_LUMI(UI_CC_OffsetColor) + UI_CC_OffsetLumi + 0.5;

    // do the scaling
    lift = 1.0 - exp2((1.0 - 2.0 * lift) * (UI_CC_LiftStrength * 0.5));
    gamma = exp2((1.0 - 2.0 * gamma) * UI_CC_GammaStrength);
    gain = exp2((2.0 * gain - 1.0) * UI_CC_GainStrength);
    offset = (offset - 0.5) * (UI_CC_OffsetStrength * 0.5);

    // apply gamma (it is already inverted)
    c = (c >= 0 && c <= 1.0) ? POW(c, gamma) : c;
    // apply lift
    c = (c <= 1) ? (c * (1.0 - lift) + lift) : c;
    // apply gain
    c = (c >= 0) ? (c * gain) : c;
    // apply offset
    c = c + offset;

    c = TO_LINEAR_CS(c);
    c = LimitColor(c);

    return c;
}
#endif

float3 ApplyStartProcessing(float3 c)
{
    c = ApplyLinearCurve(c);

#if IS_SRGB
    c = saturate(c);

    #if USE_ACES
        // instead of inversing ACES,
        // use simple Lottes inverse tonemap
        // and convert to AP1(ACEScg)
        c = InverseLottes(c);
        c = RGBToACEScg(c);
    #endif
#endif

    return c;
}

float3 ApplyEndProcessing(float3 c)
{
#if V_SHOW_ONLY_HDR_COLORS
    c = !all(saturate(c - c * c)) ? 1.0 : 0.0;
#elif IS_SRGB
    #if V_USE_AUTO_EXPOSURE
        float avg_for_exp = Sample(sExpTexVort, float2(0.5, 0.5), 8).x;

        c = c >= 0 ? (c * exp2(LOG2(LINEAR_MID_GRAY * RCP(avg_for_exp)))) : c;
        c = LimitColor(c);
    #else
        c = c >= 0 ? c * exp2(UI_CC_ManualExp) : c;
        c = LimitColor(c);
    #endif

    #if USE_ACES
        c = ApplyACESFitted(c);
    #endif

    c = saturate(c);
#endif

    c = ApplyGammaCurve(c);

    return c;
}

/*******************************************************************************
    Shaders
*******************************************************************************/

#if V_USE_AUTO_EXPOSURE
void PS_AutoExposure(PS_ARGS4)
{
    float3 c = Sample(CC_IN_SAMP, i.uv).rgb;
    c = clamp(c, UI_CC_AutoExpMin, UI_CC_AutoExpMax);

    // Min3 works better when there are both very bright
    // and very dark screen areas at the same time
    float avg = Min3(c.r, c.g, c.b);

    o = float4(avg.xxx, UI_CC_AutoExpAdaptTime);
}
#endif

void PS_Start(PS_ARGS4) {
    float3 c = Sample(sLDRTexVort, i.uv).rgb;

    c = ApplyStartProcessing(c);
    o = float4(c, 1);
}

void PS_End(PS_ARGS4)
{
    float3 c = Sample(CC_IN_SAMP, i.uv).rgb;
    c = LimitColor(c);

#if V_ENABLE_SHARPEN
    c = ApplySharpen(c, CC_IN_SAMP, i.uv);
    c = LimitColor(c);
#endif

#if V_ENABLE_COLOR_GRADING
    c = ApplyColorGrading(c);
#endif

    c = ApplyEndProcessing(c);
    o = float4(c, 1);
}

/*******************************************************************************
    Passes
*******************************************************************************/
#define PASS_START \
    pass { VertexShader = PostProcessVS; PixelShader = ColorChanges::PS_Start; RenderTarget = CC_OUT_TEX; }

// Averaging for auto exposure is from author papadanku
#if V_USE_AUTO_EXPOSURE
    #define PASS_END \
        pass { \
            VertexShader = PostProcessVS; \
            PixelShader = ColorChanges::PS_AutoExposure; \
            ClearRenderTargets = false; \
            BlendEnable = true; \
            BlendOp = ADD; \
            SrcBlend = INVSRCALPHA; \
            DestBlend = SRCALPHA; \
            RenderTarget = ExpTexVort; \
        } \
        pass { VertexShader = PostProcessVS; PixelShader = ColorChanges::PS_End; SRGB_WRITE_ENABLE }
#else
    #define PASS_END \
        pass { VertexShader = PostProcessVS; PixelShader = ColorChanges::PS_End; SRGB_WRITE_ENABLE }
#endif

} // namespace end
