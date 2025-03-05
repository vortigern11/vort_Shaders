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

#ifndef V_ENABLE_BLOOM
    #define V_ENABLE_BLOOM 0
#endif

#ifndef V_ENABLE_SHARPEN
    #define V_ENABLE_SHARPEN 0
#endif

#ifndef V_ENABLE_COLOR_GRADING
    #define V_ENABLE_COLOR_GRADING 0
#endif

#ifndef V_ENABLE_PALETTE
    #define V_ENABLE_PALETTE 0
#endif

#if IS_SRGB
    #ifndef V_ENABLE_LUT
        #define V_ENABLE_LUT 0
    #endif
#else
    #undef V_ENABLE_LUT
    #define V_ENABLE_LUT 0
#endif

#if IS_SRGB
    #ifndef V_USE_ACES
        #define V_USE_ACES 0
    #endif
#else
    #undef V_USE_ACES
    #define V_USE_ACES 0
#endif

UI_FLOAT("", UI_Tonemap_Mod, "Tonemap Mod", "Lower values increase the HDR range", 1.001, 1.5, 1.04)

#if V_ENABLE_LUT
    #define CAT_LUT "LUT Settings"

    UI_LIST(CAT_LUT, UI_CC_LUTNum, "LUT Name", "Which LUT to use", " Agfa_Precisa_100\0 Agfa_Ultra_Color_100\0 Agfa_Vista_200\0 Creative_Anime\0 Creative_BleachBypass1\0 Creative_BleachBypass2\0 Creative_BleachBypass3\0 Creative_BleachBypass4\0 Creative_CandleLight\0 Creative_ColorNegative\0 Creative_CrispWarm\0 Creative_CrispWinter\0 Creative_DropBlues\0 Creative_EdgyEmber\0 Creative_FallColors\0 Creative_FoggyNight\0 Creative_FuturisticBleak1\0 Creative_FuturisticBleak2\0 Creative_FuturisticBleak3\0 Creative_FuturisticBleak4\0 Creative_HorrorBlue\0 Creative_LateSunset\0 Creative_Moonlight\0 Creative_NightFromDay\0 Creative_RedBlueYellow\0 Creative_Smokey\0 Creative_SoftWarming\0 Creative_TealMagentaGold\0 Creative_TealOrange\0 Creative_TealOrange1\0 Creative_TealOrange2\0 Creative_TealOrange3\0 Creative_TensionGreen1\0 Creative_TensionGreen2\0 Creative_TensionGreen3\0 Creative_TensionGreen4\0 Fuji_160C\0 Fuji_400H\0 Fuji_800Z\0 Fuji_Astia_100F\0 Fuji_Astia_100_Generic\0 Fuji_FP-100c\0 Fuji_FP-100c_Cool\0 Fuji_FP-100c_Negative\0 Fuji_Provia_100F\0 Fuji_Provia_100_Generic\0 Fuji_Provia_400F\0 Fuji_Provia_400X\0 Fuji_Sensia_100\0 Fuji_Superia_100\0 Fuji_Superia_1600\0 Fuji_Superia_200\0 Fuji_Superia_200_XPRO\0 Fuji_Superia_400\0 Fuji_Superia_800\0 Fuji_Superia_HG_1600\0 Fuji_Superia_Reala_100\0 Fuji_Superia_X-Tra_800\0 Fuji_Velvia_100_Generic\0 Fuji_Velvia_50\0 Kodak_E-100_GX_Ektachrome_100\0 Kodak_Ektachrome_100_VS\0 Kodak_Ektachrome_100_VS_Generic\0 Kodak_Ektar_100\0 Kodak_Elite_100_XPRO\0 Kodak_Elite_Chrome_200\0 Kodak_Elite_Chrome_400\0 Kodak_Elite_Color_200\0 Kodak_Elite_Color_400\0 Kodak_Elite_ExtraColor_100\0 Kodak_Kodachrome_200\0 Kodak_Kodachrome_25\0 Kodak_Kodachrome_64\0 Kodak_Kodachrome_64_Generic\0 Kodak_Portra_160\0 Kodak_Portra_160_NC\0 Kodak_Portra_160_VC\0 Kodak_Portra_400\0 Kodak_Portra_400_NC\0 Kodak_Portra_400_UC\0 Kodak_Portra_400_VC\0 Kodak_Portra_800\0 Kodak_Portra_800_HC\0 Lomography_Redscale_100\0 Lomography_X-Pro_Slide_200\0 Polaroid_669\0 Polaroid_669_Cold\0 Polaroid_690\0 Polaroid_690_Cold\0 Polaroid_690_Warm\0 Polaroid_Polachrome\0 Polaroid_PX-100UV+_Cold\0 Polaroid_PX-100UV+_Warm\0 Polaroid_PX-680\0 Polaroid_PX-680_Cold\0 Polaroid_PX-680_Warm\0 Polaroid_PX-70\0 Polaroid_PX-70_Cold\0 Polaroid_PX-70_Warm\0", 0)
    UI_FLOAT(CAT_LUT, UI_CC_LUTChroma, "LUT Chroma", "Changes the chroma intensity of the LUT", 0.0, 1.0, 1.0)
    UI_FLOAT(CAT_LUT, UI_CC_LUTLuma, "LUT Luma", "Changes the luma intensity of the LUT", 0.0, 1.0, 1.0)
#endif

#if V_ENABLE_PALETTE
    #define CAT_CPS "Color Palette Swap"

    UI_BOOL(CAT_CPS, UI_CPS_ShowPalette, "Show Palette", "Shows the color at the top left corner", false)
    UI_FLOAT3(CAT_CPS, UI_CPS_HSV, "Base HSV", "The base hue, saturation and value", 0.0, 1.0, 0.5)
    UI_LIST(CAT_CPS, UI_CPS_Harmony, "Color Harmony", "Which harmony to use", "Analogous\0Complementary\0", 1)
    UI_FLOAT(CAT_CPS, UI_CPS_Blend, "Blend Amount", "How much to blend the palette with the image", 0.0, 2.0, 1.0)
#endif

#if V_ENABLE_BLOOM
    #define CAT_BLOOM "Bloom"

    UI_FLOAT(CAT_BLOOM, UI_Bloom_Intensity, "Bloom Intensity", "Controls the amount of bloom", 0.0, 1.0, 0.02)
    UI_FLOAT(CAT_BLOOM, UI_Bloom_Radius, "Bloom Radius", "Affects the size/scale of the bloom", 0.0, 1.0, 0.8)
#endif

#if V_ENABLE_SHARPEN
    #define CAT_SHARP "Sharpening"

    UI_BOOL(CAT_SHARP, UI_CC_ShowSharpening, "Show only Sharpening", "", false)
    UI_FLOAT(CAT_SHARP, UI_CC_SharpenStrength, "Sharpening Strength", "Controls the shaprening strength.", 0.0, 2.0, 1.0)
#endif

#if V_ENABLE_COLOR_GRADING
    #define CAT_CC "Color Grading"

    UI_FLOAT(CAT_CC, UI_CC_WBTemp, "Temperature", "Changes the white balance temperature.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_WBTint, "Tint", "Changes the white balance tint.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_Contrast, "Contrast", "Changes the contrast of the image", -1.0, 1.0, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_Saturation, "Saturation", "Changes the saturation of all colors", -1.0, 1.0, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_HueShift, "Hue Shift", "Changes the hue of all colors", -0.5, 0.5, 0.0)
    UI_COLOR(CAT_CC, UI_CC_ColorFilter, "Color Filter", "Multiplies every color by this color", 1.0);
    UI_COLOR(CAT_CC, UI_CC_RGBMixerRed, "RGB Mixer Red", "Modifies the reds", float3(0.75, 0.5, 0.5))
    UI_COLOR(CAT_CC, UI_CC_RGBMixerGreen, "RGB Mixer Green", "Modifies the greens", float3(0.5, 0.75, 0.5))
    UI_COLOR(CAT_CC, UI_CC_RGBMixerBlue, "RGB Mixer Blue", "Modifies the blues", float3(0.5, 0.5, 0.75))

    UI_FLOAT(CAT_CC, UI_CC_ShadowsLuma, "Shadows Luma", "Changes the luma of the shadows mainly.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_MidtonesLuma, "Midtones Luma", "Change the luma of the midtones mainly.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_HighlightsLuma, "Highlights Luma", "Changes the luma of the highlights mainly.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_OffsetLuma, "Offset Luma", "Changes the luma of whole curve.", -0.5, 0.5, 0.0)

    UI_COLOR(CAT_CC, UI_CC_ShadowsColor, "Shadows Color", "Changes the color of the shadows mainly.", 0.5)
    UI_COLOR(CAT_CC, UI_CC_MidtonesColor, "Midtones Color", "Changes the color of the midtones mainly.", 0.5)
    UI_COLOR(CAT_CC, UI_CC_HighlightsColor, "Highlights Color", "Changes the color of the highlights mainly.", 0.5)
    UI_COLOR(CAT_CC, UI_CC_OffsetColor, "Offset Color", "Changes the color of the whole curve.", 0.5)
#endif

UI_HELP(
_vort_HDR_Help_,
"V_ENABLE_BLOOM - 0 or 1\n"
"Toggle the bloom effect. Set to 9 to debug.\n"
"\n"
"V_ENABLE_SHARPEN - 0 or 1\n"
"Toggle the sharpening and far blur.\n"
"\n"
"V_ENABLE_LUT - 0 or 1\n"
"Toggle use of LUTs\n"
"\n"
"V_ENABLE_PALETTE - 0 or 1\n"
"Toggle color palette generation\n"
"\n"
"V_ENABLE_COLOR_GRADING - 0 or 1\n"
"Toggle all the color grading effects\n"
"\n"
"V_USE_ACES - 0 or 1\n"
"Whether to use the full ACES tonemapper (very high performance cost)\n"
)
