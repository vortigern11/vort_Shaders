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

/*

- MLUT .png and settings generated with: https://github.com/etra0/lutdinho

- add more tonemappers:
    Agx -> https://github.com/MrLixm/AgXc/tree/main/reshade
    Tony McMapface -> https://github.com/h3r2tic/tony-mc-mapface/tree/main

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
#include "Includes/vort_ColorTex.fxh"
#include "Includes/vort_HDRTexA.fxh"
#include "Includes/vort_HDRTexB.fxh"
#include "Includes/vort_Tonemap.fxh"
#include "Includes/vort_OKColors.fxh"
#include "Includes/vort_BlueNoise.fxh"

#if V_USE_ACES
    #include "Includes/vort_ACES.fxh"
#endif

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

#define GET_LUMA(_x) RGBToYCbCrLuma(_x)
#define LOG_MID_GRAY 0.18

#define MLUT_TileSizeXY 33
#define MLUT_TileAmount 33
#define MLUT_LutAmount 99

/*******************************************************************************
    Textures, Samplers
*******************************************************************************/

#if V_ENABLE_LUT
    texture MLUTTexVort <source = "vort_MLUT.png";>
    { Width = MLUT_TileSizeXY * MLUT_TileAmount; Height = MLUT_TileSizeXY * MLUT_LutAmount; TEX_RGBA8 };
    sampler sMLUTTexVort { Texture = MLUTTexVort; };
#endif

/*******************************************************************************
    Functions
*******************************************************************************/

#if V_ENABLE_SHARPEN
float3 ApplySharpen(float3 c, float2 uv)
{
    float3 blurred = 0;
    float3 edges = 0;

    // manual dual kawase filter, because we need edges too
    [loop]for(int j = 0; j < 13; j++)
    {
        float2 offset = Filters::OFFS_DK[j] * BUFFER_PIXEL_SIZE;
        float2 tap_uv = uv + offset;
        float3 tap_color = Sample(CC_IN_SAMP, tap_uv).rgb;

        blurred += Filters::WEIGHTS_DK[j] * tap_color;
        edges += Filters::WEIGHTS_DK[j] * abs(tap_color - c);
    }

    float sharp_amount = 1.0 - saturate(1.0 - 1e-4 * RCP(dot(edges, edges)));
    float3 sharp = GET_LUMA(c - blurred) * sharp_amount * UI_CC_SharpenStrength * (1.0 - GetDepth(uv));

    return UI_CC_ShowSharpening ? sharp : c + sharp;
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

    // RGB(channel) mixer
    c = float3(
        dot(c.rgb, UI_CC_RGBMixerRed.rgb * 4.0 - 2.0),
        dot(c.rgb, UI_CC_RGBMixerGreen.rgb * 4.0 - 2.0),
        dot(c.rgb, UI_CC_RGBMixerBlue.rgb * 4.0 - 2.0)
    );

    // saturation
    float lumi = GET_LUMA(c);
    c = lerp(lumi.xxx, c, UI_CC_Saturation + 1.0);

    // Hue Shift
    float3 hsv = RGBToHSV(c);
    hsv.x = frac(hsv.x + UI_CC_HueShift);
    c = HSVToRGB(hsv);

    // start grading in log space
    c = LOG2(c);

    // contrast in log space
    float contrast = UI_CC_Contrast + 1.0;
    c = lerp(LOG_MID_GRAY.xxx, c, contrast.xxx);

    // end grading in log space
    c = exp2(c);

    // Shadows,Midtones,Highlights,Offset in linear space
    // My calculations were done in desmos: https://www.desmos.com/calculator/vvur0dzia9

    // affect the color and luminance seperately
    float3 shadows = UI_CC_ShadowsColor - GET_LUMA(UI_CC_ShadowsColor) + UI_CC_ShadowsLuma + 0.5;
    float3 midtones = UI_CC_MidtonesColor - GET_LUMA(UI_CC_MidtonesColor) + UI_CC_MidtonesLuma + 0.5;
    float3 highlights = UI_CC_HighlightsColor - GET_LUMA(UI_CC_HighlightsColor) + UI_CC_HighlightsLuma + 0.5;
    float3 offset = UI_CC_OffsetColor - GET_LUMA(UI_CC_OffsetColor) + UI_CC_OffsetLuma + 0.5;

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
    c = (c <= 1.0) ? (c * (1.0 - shadows) + shadows) : c;
    c = (c >= 0.0) ? (c * highlights) : c;
    c = c + offset;
    c = (c >= 0.0 && c <= 1.0) ? POW(c, midtones) : c;

    return c;
}
#endif

#if V_ENABLE_LUT
float3 ApplyLUT(float3 c)
{
    float3 orig_c = c;

    c = LinToSRGB(c);

    float2 lut_ps = rcp(float2(MLUT_TileSizeXY * MLUT_TileAmount, MLUT_TileSizeXY));
    float3 lut_uv = c * (MLUT_TileSizeXY - 1.0);
    float lerpfact = frac(lut_uv.z);

    lut_uv.xy = (lut_uv.xy + 0.5) * lut_ps;
    lut_uv.x = lut_uv.x + (lut_uv.z - lerpfact) * lut_ps.y;
    lut_uv.y = (lut_uv.y / MLUT_LutAmount) + (float(UI_CC_LUTNum) / MLUT_LutAmount);

    c = lerp(
        Sample(sMLUTTexVort, lut_uv.xy).rgb,
        Sample(sMLUTTexVort, float2(lut_uv.x + lut_ps.y, lut_uv.y)).rgb,
        lerpfact
    );

    c = SRGBToLin(c);

    float3 factor = float3(UI_CC_LUTLuma, UI_CC_LUTChroma, UI_CC_LUTChroma);

    orig_c = OKColors::RGBToOKLAB(orig_c);
    c = OKColors::RGBToOKLAB(c);

    c = OKColors::OKLABToRGB(lerp(orig_c, c, factor));

    return c;
}
#endif

#if V_ENABLE_PALETTE
float3 ApplyPalette(float3 c, float2 vpos)
{
    // OKHSV color space info
    // https://bottosson.github.io/posts/colorpicker

    float hue = UI_CPS_HSV.x;
    float sat_base = lerp(0.6, 1.0, UI_CPS_HSV.y);
    float val_base = lerp(0.2, 0.6, UI_CPS_HSV.z);

    static const float contrast = 0.4;
    static const int max_idx = 7;
    static const int mid_idx = 4;
    float3 colors[8];

    // default is analogous
    int hue_switch = 99;
    float hue_offset = 0.0;

    // complementary
    if(UI_CPS_Harmony == 1) { hue_switch = mid_idx; hue_offset = 0.5; }

    // generate the palette
    [unroll]for(int j = 0; j <= max_idx; j++)
    {
        float j_mult = float(j) / float(max_idx);

        // rotate hue depending on harmony
        if(j == hue_switch) hue += hue_offset;

        float3 hsv = float3(
            hue,
            sat_base - contrast * j_mult,
            val_base + contrast * j_mult
        );

        colors[j] = OKColors::OKHSVToRGB(hsv);
    }

    bool c_has_changed = false;

    if(UI_CPS_ShowPalette)
    {
        static const int off = 20;
        static const int2 f = int2(off + 5, off + 5);
        static const int2 palette_area = int2(f.x + 5 + max_idx * (off + 5), f.y + 5);

        bool is_border = all(int2(vpos <= palette_area));

        // black border
        if(is_border) c = 0.0;

        bool is_square = false;

        for(int j = 0; j <= max_idx; j++)
        {
            int2 fs = int2(f.x + j * (off + 5), f.y);
            is_square = all(int2(vpos >= (fs - off) && vpos <= fs));

            if(is_square) { c = colors[j]; break; }
        }

        c_has_changed = is_border || is_square;
    }

    if(!c_has_changed)
    {
        float lumi = RGBToYCbCrLuma(c);
        int idx = lumi * float(max_idx);
        int s_idx = idx < mid_idx ? idx : max_idx - idx;
        float3 shadows_c = colors[s_idx];
        float3 highlights_c = colors[max_idx - s_idx];
        float3 new_c = c;

        new_c = SoftLightBlend(new_c, lerp(shadows_c, (0.5).xxx, lumi));
        new_c = SoftLightBlend(new_c, lerp((0.5).xxx, highlights_c, lumi));

        float3 c_lab = OKColors::RGBToOKLAB(c);
        float3 new_c_lab = OKColors::RGBToOKLAB(new_c);

        c_lab.yz = lerp(c_lab.yz, new_c_lab.yz, UI_CPS_Blend);
        c = OKColors::OKLABToRGB(c_lab);
    }

    return c;
}
#endif

/*******************************************************************************
    Shaders
*******************************************************************************/

void PS_Start(PS_ARGS4) {
    float3 c = SampleLinColor(i.uv);

#if V_ENABLE_LUT
    c = ApplyLUT(c);
#endif

#if V_ENABLE_PALETTE
    c = ApplyPalette(c, i.vpos.xy);
#endif

#if V_USE_ACES
    c = InverseACESFull(c);
#elif IS_SRGB
    c = Tonemap::InverseReinhardMax(c, UI_Tonemap_Mod);
#endif

    o = float4(c, 1);
}

void PS_End(PS_ARGS3)
{
    float3 c = Sample(CC_IN_SAMP, i.uv).rgb;
    float2 range = GetHDRRange();

#if V_USE_ACES
    range.x = FLOAT_MIN;
#endif

    c = clamp(c, range.x, range.y);

#if V_ENABLE_SHARPEN
    c = ApplySharpen(c, i.uv);
    c = clamp(c, range.x, range.y);
#endif

#if V_ENABLE_COLOR_GRADING
    c = ApplyColorGrading(c);
    c = clamp(c, range.x, range.y);
#endif

#if V_USE_ACES
    c = ApplyACESFull(c);
#elif IS_SRGB
    c = Tonemap::ApplyReinhardMax(c, UI_Tonemap_Mod);
#endif

    // dither
    c += (GetR3(GetBlueNoise(i.vpos.xy).rgb, frame_count % 16) - 0.5) * 0.001;

    o = ApplyGammaCurve(c);
}

/*******************************************************************************
    Passes
*******************************************************************************/
#define PASS_START \
    pass { VertexShader = PostProcessVS; PixelShader = ColorChanges::PS_Start; RenderTarget = CC_OUT_TEX; }

#define PASS_END \
    pass { VertexShader = PostProcessVS; PixelShader = ColorChanges::PS_End; }

} // namespace end
