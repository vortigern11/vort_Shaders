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

// Tonemapping graph at https://www.desmos.com/calculator/zzyoklvamb
// Averaging for auto exposure is from author papadanku

#pragma once
#include "Includes/vort_Defs.fxh"
#include "Includes/vort_HDR_UI.fxh"
#include "Includes/vort_Depth.fxh"
#include "Includes/vort_Filters.fxh"
#include "Includes/vort_LDRTex.fxh"
#include "Includes/vort_HDRTexA.fxh"
#include "Includes/vort_HDRTexB.fxh"
#include "Includes/vort_ExpTex.fxh"

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

static const float3x3 BT709_TO_AP1 = float3x3(0.6130973, 0.3395229, 0.0473793, 0.0701942, 0.9163556, 0.0134526, 0.0206156, 0.1095698, 0.8698151);
static const float3x3 AP1_TO_RRT_SAT = float3x3(0.9708890, 0.0269633, 0.00214758, 0.0108892, 0.9869630, 0.00214758, 0.0108892, 0.0269633, 0.96214800);
static const float3x3 ODT_SAT_TO_BT709 = float3x3(1.60475, -0.53108, -0.07367, -0.10208,  1.10813, -0.00605, -0.00327, -0.07276,  1.07602);

/*******************************************************************************
    Functions
*******************************************************************************/

float3 LimitColor(float3 c)
{
#if IS_SRGB
    // don't clamp ACES
    c = UI_CC_Tonemapper == 1 ? c : max(0.0, c);
#elif IS_SCRGB
    c = clamp(c, -0.5, 1e4 / V_HDR_WHITE_LVL);
#elif IS_HDR_PQ
    c = clamp(c, 0.0, 1e4 / V_HDR_WHITE_LVL);
#elif IS_HDR_HLG
    c = clamp(c, 0.0, 1e3 / V_HDR_WHITE_LVL);
#endif

    return c;
}

#if IS_SRGB
float3 InverseLottes(float3 c)
{
    float k = max(1.001, UI_CC_LottesMod);
    float3 v = Max3(c.r, c.g, c.b);

    return c * RCP(k - v);
}

float3 ApplyLottes(float3 c)
{
    float k = max(1.001, UI_CC_LottesMod);
    float3 v = Max3(c.r, c.g, c.b);

    return k * c * RCP(1.0 + v);
}

float3 InverseACESHill(float3 c)
{
    // LDR to HDR
    c = InverseLottes(c);

    // RGB(BT709) to ACEScg(AP1)
    c = mul(BT709_TO_AP1, c);

    return c;
}

float3 ApplyACESHill(float3 c)
{
    // apply RRT_SAT
    c = mul(AP1_TO_RRT_SAT, c);

    // apply RRT and ODT
    c = (c * (c + 0.0245786) - 0.000090537) * RCP(c * (0.983729 * c + 0.4329510) + 0.238081);

    // apply ODT_SAT -> XYZ -> D60_TO_D65 -> BT709
    c = mul(ODT_SAT_TO_BT709, c);

    return c;
}

float3 ACEScgToACEScct(float3 c)
{
    return c < 0.0078125 ? (10.5402377 * c + 0.0729055) : ((LOG2(c) + 9.72) / 17.52);
}

float3 ACEScctToACEScg(float3 c)
{
    return c > 0.1552511 ? exp2(c * 17.52 - 9.72) : ((c - 0.0729055) / 10.5402377);
}

#endif


#if V_ENABLE_SHARPEN
float3 ApplySharpen(float3 c, sampler samp, float2 uv)
{
    float3 blurred = Filter13Taps(uv, samp, 0);
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

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Begin(PS_ARGS4) {
    float3 c = Sample(sLDRTexVort, i.uv).rgb;

    c = ApplyLinearCurve(c);

#if IS_SRGB
    c = saturate(c);

    switch (UI_CC_Tonemapper)
    {
        case 0: c = InverseLottes(c); break;
        case 1: c = InverseACESHill(c); break;
    }
#endif

    o = float4(c, 1);
}

#if V_USE_AUTO_EXPOSURE
void PS_AutoExposure(PS_ARGS4)
{
    float3 c = Sample(CC_IN_SAMP, i.uv).rgb;
    float3 avg = Max3(c.r, c.g, c.b).xxx;

    o = float4(max(UI_CC_AutoExpMinAvg, avg), UI_CC_AutoExpAdaptTime);
}
#endif

void PS_End(PS_ARGS4)
{
    float3 c = Sample(CC_IN_SAMP, i.uv).rgb;
    c = LimitColor(c);

#if V_ENABLE_SHARPEN
    c = ApplySharpen(c, CC_IN_SAMP, i.uv);
    c = LimitColor(c);
#endif

#if IS_SRGB && UI_CC_Tonemapper == 1
    // convert to ACEScct before color grading
    c = ACEScgToACEScct(c);
#endif

    // exposure
#if V_USE_AUTO_EXPOSURE
    float avg_for_exp = Sample(sExpTexVort, i.uv, 8).x;

    // https://knarkowicz.wordpress.com/2016/01/09/automatic-exposure
    c *= exp2(LOG2(0.18 * RCP(avg_for_exp)) + UI_CC_ManualExp);
#else
    c *= exp2(UI_CC_ManualExp);
#endif
    c = LimitColor(c);

#if V_ENABLE_COLOR_GRADING
    // white balance
    c = ChangeWhiteBalance(c.rgb, UI_CC_WBTemp, UI_CC_WBTint);
    c = LimitColor(c);

    // saturation
    c = lerp(RGBToYCbCrLumi(c), c, UI_CC_Saturation + 1.0);
    c = LimitColor(c);

    // contrast
    c = sign(c) * exp2(lerp(0.18, LOG2(c), UI_CC_Contrast + 1.0));
    c = LimitColor(c);

    // lift(shadows), gamma(midtones), gain(highlights)
    float avg_lift = dot(UI_CC_Lift, 0.3333);
    float avg_gamma = dot(UI_CC_Gamma, 0.3333);
    float avg_gain = dot(UI_CC_Gain, 0.3333);

    // luminance offsets can be added, but who would need them?
    float3 lift = UI_CC_Lift - avg_lift;
    float3 gamma = UI_CC_Gamma - avg_gamma + 0.5;
    float3 gain = UI_CC_Gain - avg_gain + 1.0;
    float3 inv_gamma = LOG(gamma) * RCP(LOG((0.5 - lift) * RCP(gain - lift)));

    c = sign(c) * POW(c * gain + lift, inv_gamma);
    c = LimitColor(c);
#endif

#if IS_SRGB && UI_CC_Tonemapper == 1
    // convert to ACEScg after color grading
    c = ACEScctToACEScg(c);
#endif

#if IS_SRGB && V_SHOW_ONLY_HDR_COLORS
    c = !all(saturate(c - c * c)) ? 0.5 : 0;
#elif IS_SRGB
    switch (UI_CC_Tonemapper)
    {
        case 0: c = ApplyLottes(c); break;
        case 1: c = ApplyACESHill(c); break;
    }
    c = saturate(c);
#endif

    c = ApplyLogarithmicCurve(c);
    o = float4(c, 1);
}

/*******************************************************************************
    Passes
*******************************************************************************/
#define PASS_START \
    pass { VertexShader = PostProcessVS; PixelShader = ColorChanges::PS_Begin; RenderTarget = CC_OUT_TEX; }

#if V_USE_AUTO_EXPOSURE
    #define PASS_END \
        pass { \
            VertexShader = PostProcessVS; \
            PixelShader = ColorChanges::PS_AutoExposure; \
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
