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

#if __RESHADE__ > 50902
    #ifndef V_ENABLE_LUT
        #define V_ENABLE_LUT 0
    #endif
#else
    #undef V_ENABLE_LUT
    #define V_ENABLE_LUT 0
#endif

#ifndef V_BLOOM_DEBUG
    #define V_BLOOM_DEBUG 0
#endif

#if V_ENABLE_LUT
    #ifndef V_LUT_FILE
        #define V_LUT_FILE 15
    #endif

    #ifndef V_LUT_SIZE
        #define V_LUT_SIZE 33
    #endif

    #if IS_DX9
        #define V_LOAD_ALL_LUTS 0
    #else
        #ifndef V_LOAD_ALL_LUTS
            #define V_LOAD_ALL_LUTS 0
        #endif
    #endif
#endif

#if IS_SRGB
    #define CAT_TONEMAP "Tonemapping"

    UI_LIST(CAT_TONEMAP, UI_CC_Tonemapper, "Tonemapper", "Which tonemapper to use", "Lottes\0ACES Narkowicz\0", 1)
    UI_FLOAT(CAT_TONEMAP, UI_CC_ManualExp, "Manual Exposure", "Changes the exposure of the scene", -5.0, 5.0, 0.0)
#endif

#if V_ENABLE_BLOOM
    #define CAT_BLOOM "Bloom"

    UI_FLOAT(CAT_BLOOM, UI_Bloom_Intensity, "Bloom Intensity", "Controls the amount of bloom", 0.0, 1.0, 0.08)
    UI_FLOAT(CAT_BLOOM, UI_Bloom_Radius, "Bloom Radius", "Affects the size/scale of the bloom", 0.0, 1.0, 0.8)
    UI_FLOAT(CAT_BLOOM, UI_Bloom_DitherStrength, "Dither Strength", "How much noise to add.", 0.0, 1.0, 0.05)
#endif

#if V_ENABLE_SHARPEN
    #define CAT_SHARP "Sharpen and Far Blur"

    UI_BOOL(CAT_SHARP, UI_CC_ShowSharpening, "Show only Sharpening", "", false)
    UI_FLOAT(CAT_SHARP, UI_CC_SharpenLimit, "Sharpen Limit", "Control which pixel to be sharpened", 0.0, 0.1, 0.02)
    UI_FLOAT(CAT_SHARP, UI_CC_SharpenStrength, "Sharpening Strength", "Controls the shaprening strength.", 0.0, 2.0, 0.75)
    UI_FLOAT(CAT_SHARP, UI_CC_UnsharpenStrength, "Far Blur Strength", "Controls the far blur strength.", 0.0, 1.0, 0.25)
#endif

#if V_ENABLE_LUT
    #define CAT_LUT "LUT Settings"

    #if V_LOAD_ALL_LUTS
        UI_INT(CAT_LUT, UI_CC_LUTName, "LUT Name", "Chooses which LUT filename to use", 1, 40, 1)
    #endif

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

#if V_ENABLE_COLOR_GRADING
    #define CAT_CC "Color Grading"

    UI_FLOAT(CAT_CC, UI_CC_WBTemp, "Temperature", "Changes the white balance temperature.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_WBTint, "Tint", "Changes the white balance tint.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_Contrast, "Contrast", "Changes the contrast of the image", -1.0, 1.0, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_Saturation, "Saturation", "Changes the saturation of all colors", -1.0, 1.0, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_HueShift, "Hue Shift", "Changes the hue of all colors", -0.5, 0.5, 0.0)
    UI_COLOR(CAT_CC, UI_CC_ColorFilter, "Color Filter", "Multiplies every color by this color", 1.0);

    UI_FLOAT(CAT_CC, UI_CC_ShadowsLumi, "Shadows Luminance", "Changes the luminance of the shadows mainly.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_MidtonesLumi, "Midtones Luminance", "Change the luminance of the midtones mainly.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_HighlightsLumi, "Highlights Luminance", "Changes the luminance of the highlights mainly.", -0.5, 0.5, 0.0)
    UI_FLOAT(CAT_CC, UI_CC_OffsetLumi, "Offset Luminance", "Changes the luminance of whole curve.", -0.5, 0.5, 0.0)

    UI_COLOR(CAT_CC, UI_CC_ShadowsColor, "Shadows Color", "Changes the color of the shadows mainly.", 0.5)
    UI_COLOR(CAT_CC, UI_CC_MidtonesColor, "Midtones Color", "Changes the color of the midtones mainly.", 0.5)
    UI_COLOR(CAT_CC, UI_CC_HighlightsColor, "Highlights Color", "Changes the color of the highlights mainly.", 0.5)
    UI_COLOR(CAT_CC, UI_CC_OffsetColor, "Offset Color", "Changes the color of the whole curve.", 0.5)
#endif

UI_HELP(
_vort_HDR_Help_,
"V_ENABLE_BLOOM - 0 or 1\n"
"Toggle the bloom effect.\n"
"\n"
"V_ENABLE_SHARPEN - 0 or 1\n"
"Toggle the sharpening and far blur.\n"
"\n"
"V_ENABLE_LUT - 0 or 1\n"
"Toggle use of 3D .cube LUT\n"
"\n"
"V_ENABLE_PALETTE - 0 or 1\n"
"Toggle color palette generation\n"
"\n"
"V_ENABLE_COLOR_GRADING - 0 or 1\n"
"Toggle all the color grading effects\n"
"\n"
"V_BLOOM_DEBUG - 0 or 1\n"
"Shows 4 bright squares to see the bloom effect and make UI adjustments if you want.\n"
"\n"
"V_LOAD_ALL_LUTS - 0 or 1\n"
"If shown and set to 1, loads all LUTs for you to look at by using the UI\n"
"\n"
"V_HAS_DEPTH - 0 or 1\n"
"Whether the game has depth (2D or 3D game)\n"
"\n"
"V_USE_HW_LIN - 0 or 1\n"
"Toggle hardware linearization (better performance).\n"
"Disable if you have color issues due to some bug (like older REST addon).\n"
)
